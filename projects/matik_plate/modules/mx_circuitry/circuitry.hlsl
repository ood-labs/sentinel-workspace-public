// mx_circuitry / circuitry.hlsl — the plate's connective tissue: frame, registration marks,
// edge rails, scattered micro-marks and leader hairlines.
//
// This is what makes the reference feel dense rather than like panels floating on black.
//
// Marks are placed on a jittered lattice, not from a record list, because they are texture
// rather than content — there is nothing downstream that needs to address an individual
// mark. They are drawn freely everywhere; MX_Composite knocks them out under panels using
// the same Plate records, so panel coverage still has exactly one authority.
//
// Cost discipline: the anchor-proximity test that thins marks over the organisms runs ONCE
// per pixel, not once per lattice candidate. Per-candidate it would be 9x the work for a
// difference smaller than the lattice jitter.
#include "../_shared/plate.hlsli"
#include "../_shared/microfont.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
// _Data0 = Plate records from MX_Console.

float markShape(int t, float2 p, float s, float px, float lw)
{
    float ink = 0.0;
    if (t == 0)      ink = pStroke(pCircle(p, s), lw, px);
    else if (t == 1) ink = pFill(pCircle(p, s * 0.62), px);
    else if (t == 2) ink = pStroke(pBox(p, float2(s, s) * 0.78), lw, px);
    else if (t == 3) ink = pFill(pBox(p, float2(s, s) * 0.52), px);
    else if (t == 4) ink = pStroke(pBox(pRot(p, 0.7854), float2(s, s) * 0.62), lw, px);
    else if (t == 5)
    {
        ink = pStroke(pSeg(p, float2(-s, -s) * 0.7, float2(s, s) * 0.7), lw, px);
        ink = max(ink, pStroke(pSeg(p, float2(-s, s) * 0.7, float2(s, -s) * 0.7), lw, px));
    }
    else if (t == 6)
    {
        float2 a = float2(0.0, -s), b = float2(s * 0.87, s * 0.5), c = float2(-s * 0.87, s * 0.5);
        ink = pStroke(pSeg(p, a, b), lw, px);
        ink = max(ink, pStroke(pSeg(p, b, c), lw, px));
        ink = max(ink, pStroke(pSeg(p, c, a), lw, px));
    }
    else if (t == 7)
    {
        // hexagon
        float d = 1e9;
        for (int i = 0; i < 6; i++)
        {
            float a0 = 1.0472 * (float)i, a1 = 1.0472 * (float)(i + 1);
            d = min(d, pSeg(p, float2(cos(a0), sin(a0)) * s, float2(cos(a1), sin(a1)) * s));
        }
        ink = pStroke(d, lw, px);
    }
    else if (t == 8)
    {
        ink = pStroke(p.x, lw, px) * step(abs(p.y), s);
        ink = max(ink, pStroke(p.y, lw, px) * step(abs(p.x), s));
    }
    else if (t == 9) ink = pStroke(p.y, lw, px) * step(abs(p.x), s);
    else if (t == 10)
    {
        ink = pStroke(pSeg(p, float2(-s * 0.7, -s * 0.6), float2(0.0, 0.0)), lw, px);
        ink = max(ink, pStroke(pSeg(p, float2(0.0, 0.0), float2(-s * 0.7, s * 0.6)), lw, px));
    }
    else if (t == 11)
    {
        ink = pStroke(pBox(p, float2(s, s) * 0.8), lw, px);
        ink = max(ink, pStroke(pSeg(p, float2(-s, -s) * 0.8, float2(s, s) * 0.8), lw, px));
        ink = max(ink, pStroke(pSeg(p, float2(-s, s) * 0.8, float2(s, -s) * 0.8), lw, px));
    }
    else
    {
        ink = pStroke(pCircle(p, s), lw, px);
        ink = max(ink, pStroke(pCircle(p, s * 0.48), lw, px));
    }
    return ink;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pix = DTid.xy;
    if (pix.x >= (uint)_Resolution.x || pix.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pix + 0.5) / _Resolution.xy;
    float px = 1.0 / _Resolution.x;
    float lw = px * line_weight * 0.5;
    float t = _Time * anim_rate;

    float ink = 0.0;
    float2 c = uv - 0.5;
    float half = 0.5 - frame_inset;

    // ---- plate frame and corner registration brackets
    ink = max(ink, pStroke(pBox(c, float2(half, half)), lw, px));
    {
        float armL = 0.045, off = frame_inset * 0.45;
        for (int sx = -1; sx <= 1; sx += 2)
        for (int sy = -1; sy <= 1; sy += 2)
        {
            float2 k = float2((float)sx, (float)sy);
            float2 corner = k * (half + off);
            ink = max(ink, pStroke(pSeg(c, corner, corner - float2(k.x * armL, 0.0)), lw, px));
            ink = max(ink, pStroke(pSeg(c, corner, corner - float2(0.0, k.y * armL)), lw, px));
        }
    }

    // ---- edge rails: bead row along the top, tick rails on the other three edges
    {
        float railOff = frame_inset * 0.52;
        float pitch = 1.0 / max(rail_count, 4.0);

        float yTop = -half - railOff;
        float lx = frac(c.x / pitch + 0.5) - 0.5;
        float beadR = min(pitch * 0.22, railOff * 0.55);
        float bead = pStroke(pCircle(float2(lx * pitch, c.y - yTop), beadR), lw, px);
        // a slow index sweep fills one bead at a time — a real position readout, not a blink
        float idx = floor(c.x / pitch + 0.5);
        float head = floor(frac(t * 0.06) * rail_count) - rail_count * 0.5;
        bead = max(bead, pFill(pCircle(float2(lx * pitch, c.y - yTop), beadR * 0.55), px)
                         * step(abs(idx - head), 0.5));
        ink = max(ink, bead * step(abs(c.x), half) * rail_amount);

        float yBot = half + railOff;
        float tickH = railOff * (0.35 + 0.45 * step(0.5, frac(idx * 0.25)));
        ink = max(ink, pStroke(lx * pitch, lw, px) * step(abs(c.y - yBot), tickH)
                       * step(abs(c.x), half) * rail_amount);

        float ly = frac(c.y / pitch + 0.5) - 0.5;
        float sideIdx = floor(c.y / pitch + 0.5);
        float sideOn = step(0.45, frac(sideIdx * 0.37 + 0.13));
        for (int s2 = -1; s2 <= 1; s2 += 2)
            ink = max(ink, pFill(pCircle(float2(c.x - (float)s2 * (half + railOff), ly * pitch),
                                         beadR * 0.42), px)
                           * step(abs(c.y), half) * sideOn * rail_amount);
    }

    // ---- how crowded the organisms are here: thin the scatter over them so the wireframes
    //      still read, without erasing the marks entirely (the reference overlaps them too)
    float organism = 0.0;
    for (uint a = 0u; a < 8u; a++)
    {
        PlateRec an = _Data0[PLATE_ANCHOR_0 + a];
        if (!(an.role > 0.5 && an.role < 1.5 && an.active > 0.5)) continue;
        organism = max(organism, 1.0 - smoothstep(an.size.x * 0.55, an.size.x * 1.05,
                                                  length(uv - an.pos)));
    }
    float density = mark_density * lerp(1.0, 1.0 - organism_clear, organism);

    // ---- jittered micro-mark lattice
    {
        float pitch = 1.0 / max(lattice_n, 6.0);
        int2 base = (int2)floor(uv / pitch);
        for (int dy = -1; dy <= 1; dy++)
        for (int dx = -1; dx <= 1; dx++)
        {
            int2 cid = base + int2(dx, dy);
            float2 fid = (float2)cid;
            float2 h = mxHash22(fid + seed * 3.7);
            if (mxHash21(fid * 1.71 + seed * 5.3) > density) continue;

            float2 cp = ((float2)cid + 0.5 + (h - 0.5) * 0.78) * pitch;
            if (abs(cp.x - 0.5) > half - 0.004 || abs(cp.y - 0.5) > half - 0.004) continue;

            float2 p = uv - cp;
            float hs = mxHash21(fid * 2.13 + seed);
            float s = pitch * lerp(0.10, 0.30, hs);
            int ty = (int)(mxHash21(fid * 3.31 + seed * 1.9) * 12.999);

            float m = markShape(ty, p, s, px, lw);

            // leader hairline with a dot terminator, capped inside one lattice pitch so the
            // 3x3 neighbourhood search stays sufficient
            float hl = mxHash21(fid * 4.77 + seed * 2.5);
            if (hl < leader_amount)
            {
                float ang = floor(mxHash21(fid * 5.19 + seed) * 4.0) * 1.5707963;
                float len = pitch * lerp(0.45, 0.88, mxHash21(fid * 6.03 + seed));
                float2 e = float2(cos(ang), sin(ang)) * len;
                m = max(m, pStroke(pSeg(p, float2(0.0, 0.0), e), lw * 0.8, px));
                m = max(m, pFill(pCircle(p - e, px * 1.6), px));
            }
            ink = max(ink, m);
        }
    }

    ink = saturate(ink) * ink_level;
    OutputUAV[pix] = float4(ink, ink, ink, 1.0);
}
