// Guest faces: each guest type's emitting faces, one quad per face, shaded per pixel as the fixture engine shades them.
// Each emitter on the face finds the cell under the pixel from its layout (grid, line, ring, single) and draw shape
// (cell, disc, bands, dots) and lights it with that cell's radiance (vis_gframe) times its documented
// luminance, emitter_gain linear units per 100 kcd/m2. LED cells dim off axis with their cos^m distribution down to
// the glow of their optics; a beam lens flares from inside its beam. Emitters sharing a face are painted largest lit
// area first. Unlit cells keep the look of LED dies and lenses.
#include "taa.hlsli"
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"
#include "guests.hlsli"

#define LENS_GLOW 0.01    // FE_Renderer's lens_glow and led_glow defaults
#define LED_GLOW 0.02

struct VOut
{
    float4 Position : SV_POSITION;
    float3 world : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float2 uv : TEXCOORD2;                    // face-local metres along right / up
    nointerpolation uint3 id : TEXCOORD3;     // guest, global face index, type
};

VOut VSMain(uint vid : SV_VertexID)
{
    VOut o = (VOut)0;
    o.Position = float4(0, 0, -1, 1);
    uint g = vid / (6u * FR_MAX_FACES);
    uint f = (vid / 6u) % FR_MAX_FACES, k = vid % 6u;
    FePose pose;
    if (!guestPose(g, pose)) return o;
    uint type = (uint)(pose.pt.w + 0.5);
    uint4 geo = FE_TYPE_GEO_AT(type);
    if (f >= geo.w) return o;
    uint face = geo.z + f;
    float4 c = FE_FACE_G_AT(face * 4u), nr = FE_FACE_G_AT(face * 4u + 1u), rt = FE_FACE_G_AT(face * 4u + 2u);
    float3 up = FE_FACE_G_AT(face * 4u + 3u).xyz;
    float2 corner = float2((k == 1u || k == 4u || k == 5u) ? 1.0 : -1.0, (k == 2u || k == 3u || k == 5u) ? 1.0 : -1.0);
    float2 uv = corner * float2(nr.w, rt.w);
    float3 p = c.xyz + rt.xyz * uv.x + up * uv.y + nr.xyz * 0.0008;
    uint space = (uint)(c.w + 0.5);
    p = fePosePoint(type, space, p, pose.pt.x, pose.pt.y);
    float3 n = fePoseVector(space, nr.xyz, pose.pt.x, pose.pt.y);
    o.world = feToWorld(pose, p);
    o.normal = feRotate(pose, n);
    o.uv = uv;
    o.id = uint3(g, face, type);
    o.Position = taaClip(o.world);
    return o;
}

// Antialiased inside test for a signed distance in metres.
float cover(float d, float px) { return 1.0 - smoothstep(-px, px, d); }

float sdBox2(float2 p, float2 b) { float2 q = abs(p) - b; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0); }

// Coverage of emitter e at face-local uv (0 when it is not on this face), the cell under the pixel and its draw shape;
// rr is the radius within a disc or dot, 1 at its rim. FE_Renderer's faces.hlsl, unchanged.
float emitterCover(uint type, uint e, uint face, float2 uv, float px, out uint cell, out uint shape, out float rr)
{
    cell = 0u;
    shape = 0u;
    rr = 0.0;
    uint me = feMaxEmitters();
    float4 d0 = FE_DRAW_AT((type * me + e) * 3u);
    float4 d1 = FE_DRAW_AT((type * me + e) * 3u + 1u);
    float4 d2 = FE_DRAW_AT((type * me + e) * 3u + 2u);
    if (d0.x < -0.5 || (uint)(d1.w + 0.5) != face) return 0.0;
    uint4 em = FE_EMITTER_AT(type * me + e);
    uint layout = em.z & 255u, cols = (em.z >> 8) & 255u, rows = (em.z >> 16) & 255u;
    shape = (uint)(d0.x + 0.5);
    if (shape == 3u && layout == FE_LAYOUT_LINE && em.w > 0u)
    {
        float4 fc = FE_FACE_G_AT(face * 4u);
        float3 frt = FE_FACE_G_AT(face * 4u + 2u).xyz, fup = FE_FACE_G_AT(face * 4u + 3u).xyz;
        uint first = FE_CELL_BASE_AT(type * me + e);
        float best = 1e9;
        [loop] for (uint c = 0u; c < em.w; c++)
        {
            float3 d = feCellPos(type, first + c).xyz - fc.xyz;
            float dist = length(uv - float2(dot(d, frt), dot(d, fup)));
            cell = dist < best ? c : cell;
            best = min(best, dist);
        }
        float rad = 0.5 * d0.y;
        rr = best / max(rad, 1e-5);
        return cover(best - rad, px);
    }
    if (layout == FE_LAYOUT_RING)
    {
        float stepDeg = 360.0 / (float)max(cols, 1u);
        float phi = degrees(atan2(uv.x, uv.y));
        float k = round((phi - d0.w) / stepDeg);
        cell = (uint)(k - floor(k / (float)cols) * (float)cols);
        float ang = radians(d0.w + k * stepDeg);
        float2 at = float2(sin(ang), cos(ang)) * 0.5 * d1.z;
        rr = length(uv - at) / max(0.5 * d0.y, 1e-5);
        return cover(length(uv - at) - 0.5 * d0.y, px);
    }
    float aw = d1.x, ah = d1.y;
    float cw = aw / (float)max(cols, 1u), ch = ah / (float)max(rows, 1u);
    float2 q = float2(uv.x + 0.5 * aw, 0.5 * ah - uv.y);
    int c = (int)floor(q.x / cw), r = (int)floor(q.y / ch);
    if (c < 0 || r < 0 || c >= (int)cols || r >= (int)rows) return 0.0;
    cell = (uint)r * cols + (uint)c;
    float2 local = q - (float2(c, r) + 0.5) * float2(cw, ch);
    if (shape == 1u)
    {
        rr = length(local) / max(0.5 * d0.y, 1e-5);
        return cover(length(local) - 0.5 * d0.y, px);
    }
    if (shape == 2u)
    {
        float bx = abs(local.x) - (0.5 * cw - d0.z);
        float b0 = max(bx, max(d2.x - uv.y, uv.y - d2.y));
        float b1 = (d2.z != d2.w) ? max(bx, max(d2.z - uv.y, uv.y - d2.w)) : 1.0;
        return cover(min(b0, b1), px);
    }
    return cover(sdBox2(local, float2(0.5 * cw - d0.z, 0.5 * ch - d0.z)), px);
}

float4 PSMain(VOut i) : SV_TARGET0
{
    uint g = i.id.x, face = i.id.y, type = i.id.z;
    uint me = feMaxEmitters();
    float px = max(length(fwidth(i.uv)), 1e-5);
    float3 n = normalize(i.normal);
    float3 v = normalize(_CameraPos - i.world);
    float3 key = normalize(float3(-.5, .8, -.6));
    float spec = pow(saturate(dot(reflect(-v, n), key)), 60.0) * 0.05 * worklight;
    float3 col = float3(0.004, 0.004, 0.0045) * worklight + spec;   // dark glass between cells
    float cv = abs(dot(n, v));
    float area[FE_EMITTERS_CAP];
    [unroll] for (uint q = 0u; q < FE_EMITTERS_CAP; q++)
        area[q] = q < me ? FE_EMITTER_LUM_AT(type * me + q).w * (float)FE_EMITTER_AT(type * me + q).w : -1.0;
    [loop] for (uint r = 0u; r < me; r++)
    {
        // The r-th emitter by lit area, largest first.
        uint e = 0u;
        [loop] for (uint ci = 0u; ci < me; ci++)
        {
            uint ahead = 0u;
            [loop] for (uint oi = 0u; oi < me; oi++)
                ahead += (area[oi] > area[ci] || (area[oi] == area[ci] && oi < ci)) ? 1u : 0u;
            e = ahead == r ? ci : e;
        }
        uint cell, shape;
        float rr;
        float m = emitterCover(type, e, face, i.uv, px, cell, shape, rr);
        if (m > 0.0)
        {
            uint ei = type * me + e;
            float3 rad = guestCell(g, FE_CELL_BASE_AT(ei) + cell);
            float4 lum = FE_EMITTER_LUM_AT(ei);
            float view;
            if (lum.z > 0.5)
            {
                float c = max(cv, 1e-3);
                float off = sqrt(max(1.0 - c * c, 0.0)) / c / max(lum.y, 1e-4);
                view = LENS_GLOW + (1.0 - LENS_GLOW) * exp(-0.69314718 * off * off);
                view *= (0.6 + 2.0 * exp(-12.0 * rr * rr)) / 0.767;
            }
            else
                view = cv > 0.0 ? max(pow(cv, lum.y), LED_GLOW) : 0.0;
            float3 lit = min(rad * lum.x * view * emitter_gain * 1e-5, 4000.0);
            float3 dark = (shape == 1u) ? float3(0.010, 0.011, 0.012) * worklight + spec * 2.0 : float3(0.014, 0.013, 0.012) * worklight;
            col = lerp(col, dark + lit, m);
        }
    }
    return float4(col, length(i.world - _CameraPos));
}
