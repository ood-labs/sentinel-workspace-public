// ---------------------------------------------------------------------------
// CLOTH LAB - surface draw pass.
//
// Hardware rasterisation by vertex pulling: no vertex buffer, each vertex id
// resolves to a surface sample and reads the solved particles directly.
//
// The 64x32 simulation grid is too coarse to rasterise directly - its silhouette
// reads as a polygon. So the render grid is subdivided SUB times per sim cell
// and every sample is evaluated on a Catmull-Rom bicubic patch through the sim
// particles. The patch interpolates the particles exactly and is C1 across cell
// boundaries, so there are no cracks and the sim itself stays cheap. Normals
// come from the patch's analytic tangents rather than from finite differences,
// reusing the same 16 control points.
//
// This is the standard split in production cloth: simulate coarse, render fine.
// ---------------------------------------------------------------------------

#include "cloth_common.hlsli"
#include "../_shared/surface/bicubic.hlsli"

StructuredBuffer<ClothPoint>    Points : register(t0);
StructuredBuffer<InteractState> Touch  : register(t1);

struct VS_OUTPUT
{
    float4 Position : SV_POSITION;
    float3 Normal   : NORMAL;
    float3 World    : TEXCOORD0;
    float2 Uv       : TEXCOORD1;
    float3 Meta     : TEXCOORD2;   // x strain, y tear heat, z 1=backdrop 2=collider
    float3 Brush    : TEXCOORD3;   // x rest distance to brush, y radius, z pin weight
};

// ---------------------------------------------------------------------------
// vertex id layout
// ---------------------------------------------------------------------------
#define BACKDROP_VERTS 6u
#define SUB            3u
#define SUB_W          ((GRID_W - 1u) * SUB)
#define SUB_H          ((GRID_H - 1u) * SUB)
#define CLOTH_VERTS    (SUB_W * SUB_H * 6u)
#define SPHERE_BASE    (BACKDROP_VERTS + CLOTH_VERTS)
#define SEG_U          24u
#define SEG_V          12u
#define SPHERE_VERTS   (SEG_U * SEG_V * 6u)

static const float2 BACKDROP_NDC[6] =
{
    float2(-1.0, -1.0), float2(-1.0, 1.0), float2(1.0, 1.0),
    float2(-1.0, -1.0), float2(1.0, 1.0), float2(1.0, -1.0)
};

static const uint2 QUAD_CORNER[6] =
{
    uint2(0u, 0u), uint2(1u, 0u), uint2(1u, 1u),
    uint2(0u, 0u), uint2(1u, 1u), uint2(0u, 1u)
};

float3 colliderCenterVS(uint s)
{
    if (s == 0u) return sphere_a_pos;
    if (s == 1u) return sphere_b_pos;
    return sphere_c_pos;
}

float colliderRadiusVS(uint s)
{
    if (s == 0u) return sphere_a_radius;
    if (s == 1u) return sphere_b_radius;
    return sphere_c_radius;
}

// ---------------------------------------------------------------------------
// Surface evaluation. The Catmull-Rom basis, tangents and normal come from
// _shared/surface/bicubic.hlsli; this only gathers the control points.
// ---------------------------------------------------------------------------
uint ctrlIndex(int cx, int cy)
{
    uint x = (uint)clamp(cx, 0, (int)GRID_W - 1);
    uint y = (uint)clamp(cy, 0, (int)GRID_H - 1);
    return clothIndex(x, y);
}

void evalPatch(int cx, int cy, float tu, float tv, out float3 pos, out float3 nrm)
{
    float3 c[16];
    [unroll]
    for (int j = 0; j < 4; ++j)
    {
        [unroll]
        for (int i = 0; i < 4; ++i)
            c[j * 4 + i] = Points[ctrlIndex(cx - 1 + i, cy - 1 + j)].position;
    }
    srf_bicubic_normal(c, tu, tv, pos, nrm);
}

// Decided per TRIANGLE, not per quad: killing a whole quad when any of its five
// edges tore doubles the effective hole size and reads as blocky chunks.
bool triangleAlive(uint qx, uint qy, uint corner)
{
    uint tl = clothIndex(qx, qy);
    uint tr = clothIndex(qx + 1u, qy);
    uint bl = clothIndex(qx, qy + 1u);

    uint ftl = Points[tl].flags;
    if ((ftl & CF_INIT) == 0u) return false;
    if ((ftl & CF_BROKEN_D) != 0u) return false;

    if (corner < 3u)
    {
        if ((ftl & CF_BROKEN_H) != 0u) return false;
        if ((Points[tr].flags & CF_BROKEN_V) != 0u) return false;
    }
    else
    {
        if ((ftl & CF_BROKEN_V) != 0u) return false;
        if ((Points[bl].flags & CF_BROKEN_H) != 0u) return false;
    }
    return true;
}

float2 bilerpMeta(uint cx, uint cy, float tu, float tv)
{
    ClothPoint a = Points[clothIndex(cx, cy)];
    ClothPoint b = Points[clothIndex(min(cx + 1u, GRID_W - 1u), cy)];
    ClothPoint c = Points[clothIndex(cx, min(cy + 1u, GRID_H - 1u))];
    ClothPoint d = Points[clothIndex(min(cx + 1u, GRID_W - 1u), min(cy + 1u, GRID_H - 1u))];

    float2 top = lerp(float2(a.strain, a.tearHeat), float2(b.strain, b.tearHeat), tu);
    float2 bot = lerp(float2(c.strain, c.tearHeat), float2(d.strain, d.tearHeat), tu);
    return lerp(top, bot, tv);
}

float bilerpPin(uint cx, uint cy, float tu, float tv)
{
    float a = (Points[clothIndex(cx, cy)].invMass <= 0.0) ? 1.0 : 0.0;
    float b = (Points[clothIndex(min(cx + 1u, GRID_W - 1u), cy)].invMass <= 0.0) ? 1.0 : 0.0;
    float c = (Points[clothIndex(cx, min(cy + 1u, GRID_H - 1u))].invMass <= 0.0) ? 1.0 : 0.0;
    float d = (Points[clothIndex(min(cx + 1u, GRID_W - 1u), min(cy + 1u, GRID_H - 1u))].invMass <= 0.0) ? 1.0 : 0.0;
    return lerp(lerp(a, b, tu), lerp(c, d, tu), tv);
}

// ---------------------------------------------------------------------------

VS_OUTPUT VSMain(uint vid : SV_VertexID)
{
    VS_OUTPUT o;

    // --- backdrop ---------------------------------------------------------
    if (vid < BACKDROP_VERTS)
    {
        float2 ndc = BACKDROP_NDC[vid];
        o.Position = float4(ndc, 0.99999, 1.0);   // inside the far plane
        o.Normal = float3(0.0, 0.0, 1.0);
        o.World = 0.0;
        o.Uv = ndc * 0.5 + 0.5;
        o.Meta = float3(0.0, 0.0, 1.0);
        o.Brush = float3(1e6, 0.0, 0.0);
        return o;
    }

    // --- collider spheres -------------------------------------------------
    if (vid >= SPHERE_BASE)
    {
        uint local = vid - SPHERE_BASE;
        uint si = local / SPHERE_VERTS;
        uint sv = local % SPHERE_VERTS;

        if ((int)si >= collider_count)
        {
            o.Position = float4(0.0, 0.0, -999.0, 1.0);
            o.Normal = float3(0.0, 0.0, 1.0);
            o.World = 0.0; o.Uv = 0.0;
            o.Meta = float3(0.0, 0.0, 0.0);
            o.Brush = float3(1e6, 0.0, 0.0);
            return o;
        }

        uint2 sc = QUAD_CORNER[sv % 6u];
        uint cell = sv / 6u;
        float fu = (float)((cell % SEG_U) + sc.x) / (float)SEG_U;
        float fv = (float)((cell / SEG_U) + sc.y) / (float)SEG_V;

        float theta = fu * 6.2831853;
        float phi = fv * 3.14159265;
        float3 nrm = float3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta));
        float3 wp = colliderCenterVS(si) + nrm * colliderRadiusVS(si);

        o.World = wp;
        o.Position = mul(_ViewProjMatrix, float4(wp, 1.0));
        o.Normal = nrm;
        o.Uv = float2(fu, fv);
        o.Meta = float3(0.0, 0.0, 2.0);
        o.Brush = float3(1e6, 0.0, 0.0);
        return o;
    }

    // --- cloth surface ----------------------------------------------------
    uint quad = (vid - BACKDROP_VERTS) / 6u;
    uint corner = (vid - BACKDROP_VERTS) % 6u;

    uint gx = quad % SUB_W;
    uint gy = quad / SUB_W;
    uint cx = gx / SUB;
    uint sx = gx % SUB;
    uint cy = gy / SUB;
    uint sy = gy % SUB;

    // Which half of the sim cell this sub-triangle sits in, decided from the
    // sub-quad centre so all three corners of a triangle agree (per-corner
    // evaluation would disagree across the diagonal and open cracks).
    float centreU = ((float)sx + 0.5) / (float)SUB;
    float centreV = ((float)sy + 0.5) / (float)SUB;
    uint side = (centreU + centreV < 1.0) ? 0u : 3u;

    if (!triangleAlive(cx, cy, side))
    {
        o.Position = float4(0.0, 0.0, -999.0, 1.0);
        o.Normal = float3(0.0, 0.0, 1.0);
        o.World = 0.0; o.Uv = 0.0;
        o.Meta = float3(0.0, 0.0, 0.0);
        o.Brush = float3(1e6, 0.0, 0.0);
        return o;
    }

    uint2 c = QUAD_CORNER[corner];
    float tu = (float)(sx + c.x) / (float)SUB;
    float tv = (float)(sy + c.y) / (float)SUB;

    float3 pos, nrm;
    evalPatch((int)cx, (int)cy, tu, tv, pos, nrm);

    o.World = pos;
    o.Position = mul(_ViewProjMatrix, float4(pos, 1.0));
    o.Normal = nrm;
    o.Uv = float2(((float)cx + tu) / (float)(GRID_W - 1u),
                  ((float)cy + tv) / (float)(GRID_H - 1u));

    float2 meta = bilerpMeta(cx, cy, tu, tv);
    o.Meta = float3(meta.x, meta.y, 0.0);

    // Brush cursor in rest space, so the ring tracks the fabric through folds
    // instead of sliding across the screen.
    InteractState st = Touch[0];
    int hover = (st.active > 0.5) ? (int)st.index : (int)st.hover;
    float restD = 1e6;
    if (hover >= 0)
    {
        float2 t = o.Uv;
        float3 restHere = float3((t.x - 0.5) * cloth_width, -t.y * cloth_height, 0.0);
        if (spawn_plane != 0)
            restHere = float3((t.x - 0.5) * cloth_width, spawn_height, (t.y - 0.5) * cloth_height);
        restD = length(restHere - restPosition((uint)hover));
    }
    o.Brush = float3(restD, (hover >= 0) ? st.radius : 0.0,
                     bilerpPin(cx, cy, tu, tv));
    return o;
}

// ---------------------------------------------------------------------------

float3 toneMap(float3 c)
{
    c *= exposure;
    return c / (1.0 + c);
}

// Gentle corner falloff so the sheet sits in the frame rather than floating in a
// uniform field. Uses real pixel coordinates, so it is resolution independent.
float vignette(float4 svpos)
{
    float2 p = (svpos.xy / _Resolution.xy) * 2.0 - 1.0;
    p.x *= _Resolution.x / _Resolution.y;
    return lerp(1.0, saturate(1.0 - 0.13 * dot(p, p)), vignette_amount);
}

float4 PSMain(VS_OUTPUT In, bool frontFace : SV_IsFrontFace) : SV_TARGET
{
    // Collider (2.0) tested BEFORE backdrop (1.0): a plain `> 0.5` ordering
    // catches colliders first and shades them as backdrop gradient.
    if (In.Meta.z > 1.5)
    {
        float3 n = normalize(In.Normal);
        float3 vd = normalize(_CameraPos - In.World);
        float lam = saturate(dot(n, normalize(float3(-0.45, 0.78, 0.62))));
        float edge = pow(1.0 - saturate(dot(n, vd)), 2.5);
        float3 c = float3(0.10, 0.105, 0.115) * (0.35 + lam * 0.8);
        c += float3(0.55, 0.56, 0.58) * smoothstep(0.55, 0.95, edge);
        c = toneMap(c);
        return float4(pow(saturate(c), 1.0 / 2.2) * vignette(In.Position), 1.0);
    }

    if (In.Meta.z > 0.5)
    {
        // Near-black field. The earlier values looked mid-grey once gamma was
        // applied, which fought the "black field" the instrument look wants.
        float v = In.Uv.y;
        float3 bg = lerp(float3(0.0035, 0.0038, 0.0045), float3(0.020, 0.021, 0.024), v);
        return float4(pow(saturate(bg), 1.0 / 2.2) * vignette(In.Position), 1.0);
    }

    float3 n = normalize(In.Normal);
    float3 viewDir = normalize(_CameraPos - In.World);
    bool backSide = dot(n, viewDir) < 0.0;
    if (backSide) n = -n;   // two-sided: always light the visible face

    const float3 keyDir  = normalize(float3(-0.45, 0.78, 0.62));
    const float3 fillDir = normalize(float3(0.72, 0.15, 0.38));

    // Wrapped diffuse rather than plain Lambert: cloth is thin and scatters, so
    // the terminator should be soft instead of a hard edge at 90 degrees.
    // Wrap kept tight (0.15): at 0.32 the terminator got so soft the whole sheet
    // read as evenly lit and the folds stopped having any shape.
    float key  = saturate((dot(n, keyDir) + 0.15) / 1.15);
    key = key * key;   // slight gamma on the key for more shaping in the falloff
    float fill = saturate(dot(n, fillDir)) * 0.5 + 0.5;

    // Hemisphere ambient so up-facing folds pick up a touch more light than
    // down-facing ones, which is most of what makes drapery read as volume.
    float3 ambient = lerp(float3(0.055, 0.058, 0.065),
                          float3(0.16, 0.165, 0.175),
                          saturate(0.5 + 0.5 * n.y)) * (ambient_level / 0.10);

    // Crease darkening from the screen-space rate of change of the normal. Free
    // (no extra sampling) and it lands exactly where folds pinch.
    float crease = saturate(length(fwidth(In.Normal)) * crease_gain);

    float3 halfV = normalize(keyDir + viewDir);
    float sheen = pow(saturate(dot(n, halfV)), 60.0) * specular_sheen;

    float3 ink = base_ink;
    if (backSide) ink *= 0.66;   // reverse face a step darker so folds separate

    float3 col = ink * (key * key_intensity + fill * fill_intensity);
    col += ink * ambient;
    col += ink * sheen;
    col *= 1.0 - crease * 0.55;

    // Warm accent is spent only where strain approaches the tear threshold, and
    // on tear edges while they are still fresh.
    float strain = saturate(In.Meta.x / max(strain_range, 1e-4));
    col = lerp(col, accent_color, saturate(strain * strain * strain_accent));
    float rim = pow(1.0 - saturate(dot(n, viewDir)), 6.0);
    col += accent_color * rim * rim_intensity * 0.25;
    col += accent_color * saturate(In.Meta.y) * 1.4;

    col = toneMap(col);
    col = pow(saturate(col), 1.0 / 2.2);

    // ---- instrument overlays, drawn after grade so they stay crisp ---------
    if (weave_lines > 0.0)
    {
        // Thin contour lines along the weave, in rest space, revealing how the
        // surface is actually deforming.
        float2 g = In.Uv * float2(weave_density, weave_density * 0.5);
        float2 f = abs(frac(g) - 0.5) / max(fwidth(g), 1e-6);
        float ln = 1.0 - saturate(min(f.x, f.y) - 0.5);
        col += float3(1.0, 1.0, 1.0) * ln * weave_lines * 0.16;
    }

    // Registration line along the anchored edge.
    float pinW = In.Brush.z;
    float pinEdge = 1.0 - smoothstep(0.0, fwidth(pinW) * 1.5 + 1e-6, abs(pinW - 0.5));
    col += float3(0.85, 0.87, 0.9) * pinEdge * 0.5;

    // Brush cursor.
    if (In.Brush.y > 0.0)
    {
        float d = In.Brush.x;
        float r = In.Brush.y;
        float w = fwidth(d) * 1.5 + 1e-6;
        float ring = 1.0 - smoothstep(0.0, w, abs(d - r));
        col = lerp(col, float3(1.0, 1.0, 1.0), ring * 0.75);
        col += float3(0.10, 0.10, 0.11) * (1.0 - smoothstep(0.0, r, d)) * 0.30;
    }

    return float4(col * vignette(In.Position), 1.0);
}
