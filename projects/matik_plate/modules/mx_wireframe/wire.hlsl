// mx_wireframe / wire.hlsl — the molecular masses, drawn as opaque black solids with white
// mesh lines, exactly the way the reference's structures read.
//
// Hardware rasterization, not raymarching: a 300-node field is 600 primitives, and an SDF
// distance evaluation over that many primitives per step per pixel is hopeless. Vertex
// pulling builds a UV sphere per node and a tapered tube per bond straight from the record
// buffer, and the shared depth buffer does the occlusion for free.
//
// The mesh lines come from the generated (u,v) parameters, NOT from atan2 of the normal.
// Deriving longitude from the normal puts a seam down every sphere where the derivative used
// for line width explodes; the generated parameters are continuous across the wrap.
//
// Camera: Sentinel's internal camera, per knowledge/internal-camera-template.md. Every vertex
// goes through the injected _ViewProjMatrix and every rim term uses the injected _CameraPos.

struct MolNode
{
    float3 pos; float radius; float parent; float xlink;
    float cluster; float depth; float seed; float phase; float kind; float active;
};

// _Data0 = the Nodes buffer published by MX_Organism.

#define SPH_S     10u
#define SPH_L     16u
#define SPH_V     (SPH_S * SPH_L * 6u)   // 960
#define TUB_L     16u
#define TUB_V     (TUB_L * 6u)           // 96
#define PER_NODE  (SPH_V + TUB_V)        // 1056

static const uint2 QC[6] = {
    uint2(0u, 0u), uint2(1u, 0u), uint2(0u, 1u),
    uint2(1u, 0u), uint2(1u, 1u), uint2(0u, 1u)
};

struct VS_OUTPUT
{
    float4 Position : SV_POSITION;
    float3 Normal   : NORMAL;
    float3 WorldPos : TEXCOORD0;
    float4 Meta     : TEXCOORD1;   // x=u, y=v, z=isTube, w=cluster depth
};

VS_OUTPUT degenerate()
{
    VS_OUTPUT o;
    o.Position = float4(0.0, 0.0, -999.0, 1.0);
    o.Normal = float3(0.0, 1.0, 0.0);
    o.WorldPos = float3(0.0, 0.0, 0.0);
    o.Meta = float4(0.0, 0.0, 0.0, 0.0);
    return o;
}

VS_OUTPUT VSMain(uint vid : SV_VertexID)
{
    uint ni = vid / PER_NODE;
    uint lv = vid % PER_NODE;

    MolNode n = _Data0[ni];
    if (n.active < 0.5) return degenerate();

    VS_OUTPUT o;
    float3 wp;
    float3 nrm;
    float2 uvp;
    float isTube;

    if (lv < SPH_V)
    {
        uint qi = lv / 6u;
        uint vi = lv % 6u;
        uint st = qi / SPH_L;
        uint sl = qi % SPH_L;
        uint2 c = QC[vi];

        float u = (float)(sl + c.x) / (float)SPH_L;    // longitude 0..1
        float v = (float)(st + c.y) / (float)SPH_S;    // latitude 0..1
        float theta = u * 6.2831853;
        float phi   = v * 3.14159265;

        nrm = float3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta));
        wp  = n.pos + nrm * n.radius;
        uvp = float2(u, v);
        isTube = 0.0;
    }
    else
    {
        if (n.parent < 0.0) return degenerate();
        MolNode p = _Data0[(uint)n.parent];
        if (p.active < 0.5) return degenerate();

        uint lt = lv - SPH_V;
        uint qi = lt / 6u;
        uint vi = lt % 6u;
        uint2 c = QC[vi];

        float3 a = p.pos, b = n.pos;
        float3 ax = b - a;
        float alen = length(ax);
        if (alen < 1e-5) return degenerate();
        ax /= alen;

        float3 up = (abs(ax.y) < 0.9) ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
        float3 t1 = normalize(cross(up, ax));
        float3 t2 = cross(ax, t1);

        float u = (float)(qi + c.x) / (float)TUB_L;    // around the tube 0..1
        float v = (float)c.y;                          // along the tube 0..1
        float ang = u * 6.2831853;

        float3 radial = cos(ang) * t1 + sin(ang) * t2;
        float rr = lerp(p.radius, n.radius, v) * tube_ratio;

        nrm = radial;
        wp  = lerp(a, b, v) + radial * rr;
        uvp = float2(u, v);
        isTube = 1.0;
    }

    o.Position = mul(_ViewProjMatrix, float4(wp, 1.0));
    o.Normal   = nrm;
    o.WorldPos = wp;
    o.Meta     = float4(uvp, isTube, n.depth);
    return o;
}

// One family of mesh lines. `px` is one pixel expressed in the same units as x, so line
// weight stays constant on screen no matter how big the sphere is.
float gridLine(float x, float count, float px)
{
    if (count < 0.5) return 0.0;
    float f = frac(x * count);
    float d = min(f, 1.0 - f) / count;
    return 1.0 - smoothstep(px * 0.35, px * 1.05, d);
}

float4 PSMain(VS_OUTPUT In) : SV_TARGET
{
    float3 nrm  = normalize(In.Normal);
    float3 vdir = normalize(In.WorldPos - _CameraPos);
    float rim = 1.0 - abs(dot(nrm, vdir));

    float u = In.Meta.x;
    float v = In.Meta.y;
    bool isTube = In.Meta.z > 0.5;

    float pu = fwidth(u) * line_width;
    float pv = fwidth(v) * line_width;

    float g = 0.0;
    if (isTube)
    {
        g = max(gridLine(u, (float)tube_ribs, pu), gridLine(v, (float)tube_rings, pv));
    }
    else
    {
        int style = (int)wire_style;
        if (style == 1)                                   // Contour Bands
            g = gridLine(v, (float)lat_lines, pv);
        else if (style == 2)                              // Hatch Shell
        {
            float d1 = u + v, d2 = u - v;
            float pd = (pu + pv) * 0.5;
            g = max(gridLine(d1, (float)lon_lines, pd), gridLine(d2, (float)lon_lines, pd));
        }
        else if (style == 3)                              // Ribbon Cage
            g = gridLine(u, (float)lon_lines, pu);
        else                                              // Lat-Long mesh
            g = max(gridLine(u, (float)lon_lines, pu), gridLine(v, (float)lat_lines, pv));
    }

    float sil = smoothstep(1.0 - rim_width, 1.0, rim);
    float ink = saturate(max(g * line_gain, sil));

    // Distance shading keeps the field from flattening into one uniform tangle.
    float dist = length(In.WorldPos - _CameraPos);
    float fade = lerp(1.0, saturate(1.0 - (dist - 1.6) * depth_fade), depth_fade > 0.0 ? 1.0 : 0.0);
    fade = clamp(fade, 0.25, 1.0);

    float3 col = lerp(float3(fill_level, fill_level, fill_level), float3(1.0, 1.0, 1.0) * ink_gain, ink);
    col *= fade;
    return float4(col, 1.0);
}
