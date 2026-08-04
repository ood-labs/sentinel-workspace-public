// mx_console / canvas.hlsl — the editor surface AND this node's honest preview.
//
// It draws the plan it is publishing: every instrument cell as an outlined slot carrying a
// miniature of the instrument it will become, every organism anchor as its reserve disc and
// growth ring, the live selection, and live counts read out of the header record. Nothing
// here is decorative: if a record moves, changes kind, or dies, this picture changes.
//
// Square canvas, generator resolution: plate space == uv == viewport pointer space, so the
// handle you see is exactly the handle you pick.
#include "../_shared/plate.hlsli"
#include "../_shared/microfont.hlsli"
#include "../_shared/plan_theme.hlsli"

StructuredBuffer<PlateRec> Plate : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// INSTRUMENT PALETTE — see plan_theme.hlsli. Mostly monochrome; hue only where it informs.
static const float3 INK    = PT_INK;
static const float3 DIM    = PT_DIM;
static const float3 ACCENT = PT_ACCENT;   // RESERVED: selection & live handle
// role identity: organism anchors vs instrument cells — a closed two-member set, so hue earns it
static const float3 ORGAN  = PT_ID_A;

float txt(float2 p, float2 org, float gh, uint2 packed, uint count)
{
    float gw = gh * 0.72;
    float2 lp = (p - org) / float2(gw * (float)count, gh);
    return mf_text(lp, packed, count);
}
float txtn(float2 p, float2 org, float gh, uint v, uint digits)
{
    float gw = gh * 0.72;
    float2 lp = (p - org) / float2(gw * (float)digits, gh);
    return mf_num(lp, v, digits);
}

// Miniature of what each cell kind will render as. Deliberately schematic — the console is
// a plan, not the program. q is cell-local in [-1,1], px is a pixel in the same units.
float kindIcon(int k, float2 q, float px)
{
    float a = 0.0;
    float w = px * 1.2;
    if (k == K_GRID)
    {
        for (int i = -1; i <= 1; i++)
        {
            a = max(a, pStroke(q.x - (float)i * 0.5, w, px) * step(abs(q.y), 0.85));
            a = max(a, pStroke(q.y - (float)i * 0.5, w, px) * step(abs(q.x), 0.85));
        }
    }
    else if (k == K_CHECKER)
    {
        float2 c = floor((q * 0.5 + 0.5) * 4.0);
        a = step(abs(q.x), 0.9) * step(abs(q.y), 0.9) * (fmod(c.x + c.y, 2.0) < 0.5 ? 0.9 : 0.12);
    }
    else if (k == K_DOTS)
    {
        float2 g = frac((q * 0.5 + 0.5) * 4.0) - 0.5;
        a = pFill(length(g) - 0.18, 0.5) * step(abs(q.x), 0.92) * step(abs(q.y), 0.92);
    }
    else if (k == K_RAIL)
    {
        a = pStroke(q.y, w, px) * step(abs(q.x), 0.9);
        for (int i = -1; i <= 1; i++) a = max(a, pStroke(pCircle(q - float2((float)i * 0.55, 0.0), 0.20), w, px));
    }
    else if (k == K_DASH)
    {
        float s = frac(q.x * 2.4);
        a = step(abs(q.y), 0.22) * step(abs(q.x), 0.9) * step(s, 0.55);
    }
    else if (k == K_HALFTONE)
    {
        a = step(abs(q.x), 0.9) * step(abs(q.y), 0.6) * saturate(q.x * 0.5 + 0.5);
    }
    else if (k == K_DIAL)
    {
        a = pStroke(pCircle(q, 0.72), w, px);
        a = max(a, pStroke(pSeg(q, float2(0, 0), float2(0.45, -0.45)), w, px));
    }
    else if (k == K_DATA)
    {
        float2 c = floor((q * 0.5 + 0.5) * 5.0);
        a = step(abs(q.x), 0.9) * step(abs(q.y), 0.9) * step(0.45, mxHash21(c + 3.1));
    }
    else if (k == K_CHEVRON)
    {
        float s = frac(q.x * 3.0 + q.y * 0.5);
        a = step(abs(q.y), 0.45) * step(abs(q.x), 0.9) * step(0.45, s) * step(s, 0.85);
    }
    else if (k == K_BARS)
    {
        float bx = floor((q.x * 0.5 + 0.5) * 5.0);
        float h = 0.25 + 0.65 * mxHash21(float2(bx, 2.0));
        a = step(frac((q.x * 0.5 + 0.5) * 5.0), 0.65) * step(abs(q.x), 0.9) * step(-q.y, h * 2.0 - 1.0) * step(q.y, 0.85);
    }
    else if (k == K_CONE)
    {
        a = pStroke(pSeg(q, float2(-0.30, -0.7), float2(-0.75, 0.7)), w, px);
        a = max(a, pStroke(pSeg(q, float2(0.30, -0.7), float2(0.75, 0.7)), w, px));
        a = max(a, pStroke(pCircle(float2(q.x / 0.30, (q.y + 0.7) / 0.14), 1.0) * 0.30, w, px));
        a = max(a, pStroke(pCircle(float2(q.x / 0.75, (q.y - 0.7) / 0.22), 1.0) * 0.75, w, px));
    }
    else if (k == K_GLYPH)
    {
        a = mf_text((q * float2(0.5, 0.5) + 0.5) * float2(1.0, 1.0), uint2(mf_pack1(10u, 11u, 12u, 0u, 0u), 0u), 3u);
    }
    else if (k == K_TARGET)
    {
        a = pStroke(pCircle(q, 0.75), w, px);
        a = max(a, pStroke(pCircle(q, 0.38), w, px));
        a = max(a, pStroke(q.x, w, px) * step(abs(q.y), 0.95));
        a = max(a, pStroke(q.y, w, px) * step(abs(q.x), 0.95));
    }
    else if (k == K_WAVE)
    {
        a = pStroke(q.y - sin(q.x * 6.0) * 0.45, w * 1.4, px) * step(abs(q.x), 0.9);
    }
    else if (k == K_SPIRAL)
    {
        for (int i = 1; i <= 3; i++) a = max(a, pStroke(pCircle(q - float2(0.06 * (float)i, 0.0), 0.22 * (float)i), w, px));
    }
    else // K_KEYS
    {
        float s = frac((q.x * 0.5 + 0.5) * 5.0);
        a = step(abs(q.y), 0.7) * step(abs(q.x), 0.9) * step(0.18, s) * step(s, 0.86);
    }
    return saturate(a);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float pxs = 1.0 / _Resolution.x;

    float3 col = PT_FIELD;

    // reference lattice — the plan is spatial, so give the eye a ruler
    float gl = min(abs(frac(uv.x * 12.0) - 0.5), abs(frac(uv.y * 12.0) - 0.5));
    col += PT_GRID * 0.55 * (1.0 - smoothstep(0.0, 0.03, gl));

    PlateRec hdr = Plate[PLATE_HEADER];

    // ---- organism anchors first: they are the negative space the cells respect
    for (uint a = 0u; a < 8u; a++)
    {
        PlateRec r = Plate[PLATE_ANCHOR_0 + a];
        if (r.active < 0.5) continue;
        float2 q = uv - r.pos;
        float d = length(q);
        float ang = atan2(q.y, q.x);

        col += ORGAN * 0.055 * pFill(d - r.size.x, pxs * 2.0);                       // reserve field
        col += ORGAN * 0.85 * pDash(d - r.size.x, pxs * 0.9, pxs, ang * r.size.x, 0.010, 0.55);
        col += ORGAN * 0.55 * pStroke(d - r.size.y * 0.075, pxs * 0.9, pxs);          // growth ring
        col += ORGAN * pFill(d - pxs * 2.5, pxs);                                     // core

        // growth kind: C chain / D dendrite / B burst, plus the anchor index
        uint gk = (uint)(r.kind + 0.5);
        uint letter = (gk == 0u) ? 12u : (gk == 1u ? 13u : 11u);
        float lab = txt(uv, r.pos + float2(pxs * 6.0, -pxs * 16.0), 0.014,
                        uint2(mf_pack1(letter, MF_DASH, 0u, 0u, 0u), 0u), 2u);
        lab = max(lab, txtn(uv, r.pos + float2(pxs * 30.0, -pxs * 16.0), 0.014, a, 1u));
        col = lerp(col, ORGAN, lab * 0.9);
    }

    // ---- instrument cells
    for (uint i = 0u; i < PLATE_CELLS; i++)
    {
        PlateRec r = Plate[i];
        if (r.role > 0.5) continue;
        if (r.size.x <= 0.0 || r.size.y <= 0.0) continue;
        float2 q = uv - r.pos;
        float d = pBox(q, r.size);
        bool selected = pFlag(r, F_SELECTED);

        if (r.active < 0.5)
        {
            // dead slot: dashed ghost so the layout's rhythm stays readable
            float t = (abs(q.x) > abs(q.y)) ? q.x : q.y;
            col += DIM * 0.55 * pDash(d, pxs * 0.7, pxs, t, 0.011, 0.5);
        }
        else
        {
            float wgt = lerp(0.8, 1.6, r.tone);
            col += INK * (0.45 + 0.5 * r.tone) * pStroke(d, pxs * wgt, pxs);
            col += INK * 0.035 * pFill(d, pxs);

            float side = min(r.size.x, r.size.y);
            float2 ql = q / max(side * 0.72, 1e-5);
            float icon = kindIcon((int)(r.kind + 0.5), ql, pxs / max(side * 0.72, 1e-5));
            col += INK * 0.65 * icon * step(max(abs(q.x) - r.size.x, abs(q.y) - r.size.y), 0.0);

            // kind id in the corner — a real field of the record, not a caption
            float lab = txtn(uv, r.pos - r.size + float2(pxs * 3.0, pxs * 3.0), 0.011, (uint)(r.kind + 0.5), 2u);
            col = lerp(col, INK * 0.75, lab * 0.85);
        }

        if (selected)
        {
            col = lerp(col, ACCENT, pStroke(d, pxs * 1.8, pxs));
            float2 e = r.size + pxs * 5.0;
            float hnd = 0.0;
            for (int sx = -1; sx <= 1; sx += 2)
            for (int sy = -1; sy <= 1; sy += 2)
                hnd = max(hnd, pFill(pBox(q - float2(sx * e.x, sy * e.y), pxs * 3.0), pxs));
            col = lerp(col, ACCENT, hnd);
        }
    }

    // selected anchor highlight (anchors are indexed after the cells)
    for (uint a2 = 0u; a2 < 8u; a2++)
    {
        PlateRec r = Plate[PLATE_ANCHOR_0 + a2];
        if (r.active < 0.5 || !pFlag(r, F_SELECTED)) continue;
        float d = length(uv - r.pos);
        col = lerp(col, ACCENT, pStroke(d - r.size.x, pxs * 1.6, pxs));
        col = lerp(col, ACCENT, pFill(d - pxs * 4.0, pxs));
    }

    // ---- readout: header strip, all values live off the header record
    float bar = step(uv.y, 0.042);
    col *= lerp(1.0, 0.18, bar);
    col += INK * 0.10 * (1.0 - smoothstep(0.0, pxs * 1.5, abs(uv.y - 0.042)));

    float hud = 0.0;
    // "CONSOLE"
    hud = max(hud, txt(uv, float2(0.014, 0.013), 0.016,
              uint2(mf_pack1(12u, 24u, 23u, 28u, 24u), mf_pack1(21u, 14u, 0u, 0u, 0u)), 7u));
    // "CELLS" nn
    hud = max(hud, txt(uv, float2(0.150, 0.013), 0.016,
              uint2(mf_pack1(12u, 14u, 21u, 21u, 28u), 0u), 5u));
    hud = max(hud, txtn(uv, float2(0.212, 0.013), 0.016, (uint)hdr.grp, 2u));
    // "ANCH" n
    hud = max(hud, txt(uv, float2(0.262, 0.013), 0.016,
              uint2(mf_pack1(10u, 23u, 12u, 17u, 0u), 0u), 4u));
    hud = max(hud, txtn(uv, float2(0.312, 0.013), 0.016, (uint)hdr.phase, 1u));
    // "SEL" nnn
    hud = max(hud, txt(uv, float2(0.350, 0.013), 0.016,
              uint2(mf_pack1(28u, 14u, 21u, 0u, 0u), 0u), 3u));
    col = lerp(col, INK, hud * 0.95);
    float selNum = txtn(uv, float2(0.388, 0.013), 0.016, (uint)hdr.pos.y, 3u);
    col = lerp(col, hdr.pos.y > 0.5 ? ACCENT : DIM, selNum);

    // ---- hint strip: the actual bindings this module declares
    float hb = step(0.962, uv.y);
    col *= lerp(1.0, 0.20, hb);
    float hint = 0.0;
    hint = max(hint, txt(uv, float2(0.014, 0.972), 0.014, uint2(mf_pack1(20u, 63u, 20u, 18u, 23u), mf_pack1(13u, 0u, 0u, 0u, 0u)), 6u)); // K KIND
    hint = max(hint, txt(uv, float2(0.120, 0.972), 0.014, uint2(mf_pack1(33u, 63u, 10u, 12u, 29u), 0u), 5u));                              // X ACT
    hint = max(hint, txt(uv, float2(0.210, 0.972), 0.014, uint2(mf_pack1(23u, 63u, 27u, 24u, 21u), mf_pack1(21u, 0u, 0u, 0u, 0u)), 6u));  // N ROLL
    hint = max(hint, txt(uv, float2(0.316, 0.972), 0.014, uint2(mf_pack1(27u, 63u, 28u, 14u, 14u), mf_pack1(13u, 0u, 0u, 0u, 0u)), 6u));  // R SEED
    hint = max(hint, txt(uv, float2(0.422, 0.972), 0.014, uint2(mf_pack1(12u, 63u, 12u, 21u, 27u), 0u), 5u));                              // C CLR
    col = lerp(col, DIM * 1.8, hint);

    // ---- live pointer crosshair
    float2 mp = _ViewportPointerPosition;
    if (mp.x > 0.0 && mp.y > 0.0)
    {
        float ch = pStroke(uv.x - mp.x, pxs * 0.6, pxs) * step(abs(uv.y - mp.y), 0.018);
        ch = max(ch, pStroke(uv.y - mp.y, pxs * 0.6, pxs) * step(abs(uv.x - mp.x), 0.018));
        col += ACCENT * ch * 0.7;
    }

    OutputUAV[px] = float4(col, 1.0);
}
