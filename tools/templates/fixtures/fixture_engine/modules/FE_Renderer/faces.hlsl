// Emitting faces: one quad per type face, shaded per pixel. Each emitter that lives on the face finds the
// cell under the pixel from its layout (grid, line, ring, single) and draw shape (cell, disc, bands, dots), an
// irregular cell set at its cells' GDTF positions, and
// lights it with that cell's output from the prep pass times its documented luminance (FE_EMITTER_LUM, peak
// intensity over lit area), so a strobe zone outshines a bar pixel as the data sheets say. LED cells
// dim off axis with their cos^m distribution down to the glow of their optics (led_glow); a beam lens is a flare from
// inside its beam and the glow of its optics (lens_glow) from anywhere else. Emitters sharing a face are painted
// largest lit area first. Unlit cells keep the look of LED dies and lenses.
#define GDTF_RENDER _Data2
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"

StructuredBuffer<float4> Frame : register(t0);

#define FACES_PER_INSTANCE FR_MAX_FACES

struct VOut
{
    float4 Position : SV_POSITION;
    float3 world : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float2 uv : TEXCOORD2;                    // face-local metres along right / up
    nointerpolation uint2 id : TEXCOORD3;     // instance, global face index
};

VOut VSMain(uint vid : SV_VertexID)
{
    VOut o = (VOut)0;
    o.Position = float4(0, 0, -1, 1);
    uint inst = vid / (6u * FACES_PER_INSTANCE);
    uint f = (vid / 6u) % FACES_PER_INSTANCE, k = vid % 6u;
    if (inst >= FE_N_MAX) return o;
    FePose pose;
    FE_LOAD_POSE(Frame, inst, pose);
    if (pose.pt.z < 0.5) return o;
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
    o.id = uint2(inst, face);
    o.Position = mul(_ViewProjMatrix, float4(feView(o.world), 1.0));
    return o;
}

// Antialiased inside test for a signed distance in metres.
float cover(float d, float px) { return 1.0 - smoothstep(-px, px, d); }

float sdBox2(float2 p, float2 b) { float2 q = abs(p) - b; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0); }

// Coverage of emitter e of this type at face-local uv (0 when the emitter is not on this face), and the
// cell index and draw shape under the pixel; rr is the radius within a disc or dot, 1 at its rim.
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
        // An irregular cell set (packed as a line of dots): the nearest cell, each projected onto the face from its
        // GDTF position. Grids, lines and rings place their cells where the GDTF puts them (the plan derives the
        // layout from those positions), so they keep the layout placement.
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
        float phi = degrees(atan2(uv.x, uv.y));             // clockwise from up toward right
        float k = round((phi - d0.w) / stepDeg);
        cell = (uint)(k - floor(k / (float)cols) * (float)cols);
        float ang = radians(d0.w + k * stepDeg);
        float2 at = float2(sin(ang), cos(ang)) * 0.5 * d1.z;
        rr = length(uv - at) / max(0.5 * d0.y, 1e-5);
        return cover(length(uv - at) - 0.5 * d0.y, px);
    }
    float aw = d1.x, ah = d1.y;
    float cw = aw / (float)max(cols, 1u), ch = ah / (float)max(rows, 1u);
    float2 q = float2(uv.x + 0.5 * aw, 0.5 * ah - uv.y);     // from the top-left, y down
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

float4 PSMain(VOut i) : SV_TARGET
{
    uint inst = i.id.x, face = i.id.y;
    uint b = inst * FE_FRAME_STRIDE;
    float4 pt = Frame[b + 3u];
    uint type = (uint)(pt.w + 0.5);
    uint me = feMaxEmitters();
    float px = max(length(fwidth(i.uv)), 1e-5);
    float3 camW = feView(_CameraPos);
    float3 n = normalize(i.normal);
    float3 v = normalize(camW - i.world);
    float3 key = normalize(float3(0.3, 0.6, 0.75));
    float spec = pow(saturate(dot(reflect(-v, n), key)), 60.0) * 0.05 * worklight;
    float3 col = float3(0.004, 0.004, 0.0045) * worklight + spec;   // dark glass between cells
    float cv = dot(n, v);
    // Emitters sharing a face are painted largest lit area first, so smaller elements sit in front of a larger field
    // (a lens's ring dots, a strobe's beam lenses, a halo over its glow strip); equal areas keep their order.
    float area[FE_EMITTERS_CAP];
    [unroll] for (uint q = 0u; q < FE_EMITTERS_CAP; q++)
        area[q] = q < me ? FE_EMITTER_LUM_AT(type * me + q).w * (float)FE_EMITTER_AT(type * me + q).w : -1.0;
    [loop] for (uint r = 0u; r < me; r++)
    {
        // The r-th emitter in that order: the one with r emitters ahead of it.
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
            float3 rad = Frame[b + FE_FRAME_EMIT + FE_CELL_BASE_AT(ei) + cell].rgb;
            float4 lum = FE_EMITTER_LUM_AT(ei);
            // How bright the cell looks from here, as a fraction of its documented luminance at full.
            float view;
            if (lum.z > 0.5)
            {
                // A beam lens shows its full luminance only from inside the beam (a flare when the beam meets
                // the camera); from anywhere else, the glow of the optics (lens_glow), hottest at the centre.
                float c = max(cv, 1e-3);
                float off = sqrt(max(1.0 - c * c, 0.0)) / c / max(lum.y, 1e-4);
                view = lens_glow + (1.0 - lens_glow) * exp(-0.69314718 * off * off);
                view *= (0.6 + 2.0 * exp(-12.0 * rr * rr)) / 0.767;
            }
            else
            {
                // An LED's cos^m intensity over its cos-foreshortened area; off axis its optics still glow (led_glow).
                view = cv > 0.0 ? max(pow(cv, lum.y), led_glow) : 0.0;
            }
            // One photometric scale for every face: emitter_gain linear units per 100 kcd/m2.
            float3 lit = min(rad * lum.x * view * emitter_gain * 1e-5, 4000.0);
            float3 dark = (shape == 1u) ? float3(0.010, 0.011, 0.012) * worklight + spec * 2.0 : float3(0.014, 0.013, 0.012) * worklight;
            col = lerp(col, dark + lit, m);
        }
    }
    return float4(col, length(feView(i.world) - _CameraPos));
}
