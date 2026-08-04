// AX_Plan / canvas.hlsl — the editor surface.
//
// THE PLATE over THE OCTAVE LADDER, sharing the radius axis. Reading it should answer, without
// opening the renderer: what is the arrangement, where does the fall converge, how far out does
// the collage reach, which records are hand-edited or switched off, where in the octave the
// flight currently is — and, critically, whether the loop is SOUND.
//
// Two failure modes are drawn rather than left to be discovered as a bad frame:
//   * a record whose radial extent exceeds one octave will overlap its own copy one octave up
//     and read as doubled mush. Its ladder bar goes ALARM.
//   * a log-radius column that NO record covers is a hole you fall through into empty field.
//     The coverage strip flags it ALARM.
//
// Every handle is drawn through the same helpers plan.hlsl picks with, so what you can see is
// exactly what you can grab.
#include "../_shared/axon.hlsli"
#include "../_shared/plan_theme.hlsli"

StructuredBuffer<AxRec> Plan : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float disc(float2 uv, float2 c, float r, float2 asp, float px)
{
    return 1.0 - smoothstep(r - px, r + px, length((uv - c) * asp));
}
float ring(float2 uv, float2 c, float r, float w, float2 asp, float px)
{
    float d = abs(length((uv - c) * asp) - r);
    return 1.0 - smoothstep(w - px, w + px, d);
}
float vline(float x, float gx, float w, float px)
{
    return 1.0 - smoothstep(w, w + px, abs(x - gx));
}
float frameBox(float2 uv, float2 c, float2 h, float w, float px)
{
    float2 d = abs(uv - c) - h;
    return 1.0 - smoothstep(w, w + px, abs(max(d.x, d.y)));
}

// Face value ladder: top brightest, right mid, left dark. This is the axonometric shading that
// makes a box read as a box in a monochrome diagram, so it does the work hue would otherwise
// have to do.
float faceValue(int face)
{
    return (face == AX_FACE_TOP) ? 0.92 : ((face == AX_FACE_RIGHT) ? 0.58 : 0.30);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (pixel.x >= W || pixel.y >= H) return;

    float2 uv = ((float2)pixel + 0.5) / float2(W, H);
    float2 asp = float2((float)W / max((float)H, 1.0), 1.0);
    float px = 1.0 / (float)H;

    AxRec hdr = Plan[AX_HEADER];
    float sel      = hdr.pos.y;
    float2 focusL  = float2(hdr.pad0, hdr.pad1);
    float travel   = hdr.phase;
    uint liveV, liveP, liveW, liveT;
    axUnpackCounts(hdr.host, liveV, liveP, liveW, liveT);

    float2 A, B, C; float3 D;
    axBasis((int)lattice, A, B, C, D);
    float viewHalf = axViewHalf(span, octave_ratio);
    float ratio    = max(octave_ratio, 1.05);
    float spanView = max(span, 0.3) + 0.65;
    float2 f2 = axProj(float3(focusL, 0.0), A, B, C);

    float3 col = PT_FIELD;
    int region = axRegionAt(uv);

    // =====================================================================================
    // THE PLATE — the axonometric arrangement of one period, with the octave rings on it.
    // =====================================================================================
    if (region == 1)
    {
        float2 hp = float2(axPlateHX(), AX_PLATE_HY);
        float2 cp = float2(AX_PLATE_CX, AX_PLATE_CY);
        bool inside = (abs(uv.x - cp.x) < hp.x) && (abs(uv.y - cp.y) < hp.y);
        if (inside)
        {
            col = PT_WELL;

            float2 v = axUvToPlate(uv, viewHalf);     // plate offset from the focus
            float2 q = f2 + v;                        // absolute plate point
            float rHere = length(v);
            float rhoHere = axRho(rHere, ratio);
            // scale of one canvas pixel in plate units — the record bounds test needs it
            float pxPlate = viewHalf / (AX_PLATE_HY * (float)H);

            // --- octave rings, drawn UNDER the arrangement. These are the whole point of
            // putting a plate view next to a ladder: you can see which records straddle a ring.
            for (int k = -1; k <= 6; k++)
            {
                if ((float)k > span + 0.6) break;
                float rr = AX_APER_L * pow(ratio, (float)k);
                float d = abs(rHere - rr) / max(pxPlate, 1e-6) * px;
                float hit = 1.0 - smoothstep(0.0009, 0.0009 + px, d);
                col = lerp(col, (k == 0) ? PT_RULE : PT_GRID, hit * ((k == 0) ? 1.0 : 1.0) * 1.6);
            }
            // the LIVE ring: where the fall currently is inside the octave. A real reading, so
            // it earns the accent.
            {
                float rr = AX_APER_L * pow(ratio, frac(travel));
                float d = abs(rHere - rr) / max(pxPlate, 1e-6) * px;
                col = lerp(col, PT_ACCENT, (1.0 - smoothstep(0.0011, 0.0011 + px, d)) * 0.55);
            }

            // --- the arrangement itself, painter-ordered by lattice depth
            float bestDepth = -1e9;
            float3 bestCol = float3(0.0, 0.0, 0.0);
            float bestEdge = 0.0;
            int   bestIdx = -1;
            for (uint i = 0u; i < AX_RECORDS - 1u; i++)
            {
                AxRec r = Plan[i];
                if (r.role == ROLE_TRC) continue;

                float2 bc; float br;
                axBound(r.pos, r.ext, A, B, C, bc, br);
                if (length(q - bc) > br) continue;          // bounding-circle early out

                int face; float2 fl; float dep;
                if (!axBoxHit(r.pos, r.ext, q, A, B, C, D, face, fl, dep)) continue;
                if (r.active < 0.5) dep -= 1e4;             // switched off: drops behind everything
                if (dep <= bestDepth) continue;

                // wedges keep only one half of their facet
                if (r.role == ROLE_WDG)
                {
                    float2 ee = (face == AX_FACE_TOP)   ? r.ext.xy
                              : (face == AX_FACE_RIGHT) ? r.ext.yz : r.ext.xz;
                    float2 t = fl / max(ee, 1e-4);
                    int cnr = (int)r.kind;
                    float s = (cnr == 0) ? (t.x + t.y) : (cnr == 1) ? (2.0 - t.x - t.y)
                            : (cnr == 2) ? (1.0 + t.x - t.y) : (1.0 - t.x + t.y);
                    if (s > 1.0) continue;
                }
                // frames only draw a border band, which is what lets the fall see through them
                if (r.role == ROLE_VOL && (int)r.kind == AX_VK_FRAME)
                {
                    float2 ee = (face == AX_FACE_TOP)   ? r.ext.xy
                              : (face == AX_FACE_RIGHT) ? r.ext.yz : r.ext.xz;
                    float2 t = fl / max(ee, 1e-4);
                    float m = min(min(t.x, 1.0 - t.x), min(t.y, 1.0 - t.y));
                    if (m > 0.16) continue;
                }

                bestDepth = dep;
                bestIdx = (int)i;
                float3 own = ptSampleFill(axPal((int)r.col));
                float3 val = ptRamp(faceValue(face) * (r.active > 0.5 ? 1.0 : 0.25));
                bestCol = lerp(val, own, (r.active > 0.5) ? 0.55 : 0.15);

                // facet border, so interlocking boxes stay countable
                float2 ee2 = (face == AX_FACE_TOP)   ? r.ext.xy
                           : (face == AX_FACE_RIGHT) ? r.ext.yz : r.ext.xz;
                float2 t2 = fl / max(ee2, 1e-4);
                float m2 = min(min(t2.x, 1.0 - t2.x), min(t2.y, 1.0 - t2.y));
                float lw = pxPlate * 1.4 / max(min(ee2.x, ee2.y), 1e-3);
                bestEdge = 1.0 - smoothstep(lw, lw * 2.2, m2);
            }
            if (bestIdx >= 0)
            {
                AxRec br2 = Plan[(uint)bestIdx];
                uint bf = (uint)br2.flags;
                col = bestCol;
                col = lerp(col, PT_INK, bestEdge * 0.55);
                if ((bf & F_EDITED) != 0u)   col = lerp(col, PT_MID, bestEdge * 0.9);
                if ((bf & F_SELECTED) != 0u) col = lerp(col, PT_ACCENT, max(bestEdge, 0.22));
            }

            // --- traces, drawn on top: they are ink over the arrangement, not part of it
            for (uint t3 = 0u; t3 < AX_TRCS; t3++)
            {
                AxRec r = Plan[AX_TRC_0 + t3];
                if (r.active < 0.5) continue;
                float2 p0 = axProj(r.pos, A, B, C);
                float2 p1 = axProj(r.pos + r.ext, A, B, C);
                float d = axSegD(q, p0, p1) / max(pxPlate, 1e-6) * px;
                float w = 0.0010;
                float hit = 1.0 - smoothstep(w, w + px, d);
                if ((int)r.kind == AX_TK_DASH)
                    hit *= step(0.4, frac(dot(q - p0, normalize(p1 - p0 + 1e-6)) / max(viewHalf * 0.05, 1e-4)));
                bool ts = (sel > 0.5) && ((uint)(sel - 1.0) == AX_TRC_0 + t3);
                col = lerp(col, ts ? PT_ACCENT : PT_MID, hit * (ts ? 1.0 : 0.75));
            }

            // --- the focus reticle: the single most consequential number in the project
            {
                float2 fc = axPlateToUv(float2(0.0, 0.0), viewHalf);
                bool fsel = (hdr.pos.z > 2.5);
                float3 fcol = fsel ? PT_ACCENT : PT_INK;
                col = lerp(col, fcol, ring(uv, fc, 0.0135, 0.0013, asp, px));
                float cross = max(1.0 - smoothstep(0.0011, 0.0011 + px, abs(uv.x - fc.x)),
                                  1.0 - smoothstep(0.0011, 0.0011 + px, abs(uv.y - fc.y)));
                float near = 1.0 - smoothstep(0.026, 0.028, length((uv - fc) * asp));
                col = lerp(col, fcol, cross * near * 0.9);
            }
        }
        col = lerp(col, PT_RULE, frameBox(uv, cp, hp, 0.0013, px) * 0.8);
    }

    // =====================================================================================
    // THE OCTAVE LADDER — every record's radial extent unrolled onto a log axis. One row per
    // record index (stable, so a record never changes row when a neighbour is switched off).
    // =====================================================================================
    if (region == 2)
    {
        float2 hc = float2((AX_LAD_X0 + AX_LAD_X1) * 0.5, (AX_LAD_Y0 + AX_LAD_Y1) * 0.5);
        float2 hh = float2((AX_LAD_X1 - AX_LAD_X0) * 0.5, (AX_LAD_Y1 - AX_LAD_Y0) * 0.5);
        bool inside = (abs(uv.x - hc.x) < hh.x) && (abs(uv.y - hc.y) < hh.y);
        if (inside)
        {
            col = PT_WELL;

            // octave rules; the WRAP SEAM at rho = period is the one that matters, because that
            // is where the whole frame repeats
            for (int k = 0; k <= 8; k++)
            {
                if ((float)k > spanView) break;
                float gx = axRhoToX((float)k, spanView);
                bool seam = (k == (int)period);
                float hit = vline(uv.x, gx, seam ? 0.0011 : 0.0006, px);
                if (seam) hit *= step(0.35, frac(uv.y * 220.0));
                col = lerp(col, seam ? PT_DIM : PT_GRID, hit);
            }

            float rowH = (AX_LAD_Y1 - AX_LAD_Y0) / (float)(AX_RECORDS - 1u);
            int row = (int)floor((uv.y - AX_LAD_Y0) / max(rowH, 1e-5));
            if (row >= 0 && row < (int)(AX_RECORDS - 1u))
            {
                AxRec r = Plan[(uint)row];
                // role band separators, so the four families stay legible as families
                if (row == (int)AX_PAN_0 || row == (int)AX_WDG_0 || row == (int)AX_TRC_0)
                    col = lerp(col, PT_RULE, 1.0 - smoothstep(0.0006, 0.0006 + px,
                                                              abs(uv.y - (AX_LAD_Y0 + (float)row * rowH))) * 0.9);

                float x0 = axRhoToX(axRho(r.rmin, ratio), spanView);
                float x1 = axRhoToX(axRho(r.rmax, ratio), spanView);
                float yc = AX_LAD_Y0 + ((float)row + 0.5) * rowH;
                float bandY = 1.0 - smoothstep(rowH * 0.30, rowH * 0.30 + px, abs(uv.y - yc));
                float bandX = step(x0, uv.x) * step(uv.x, x1);
                float bar = bandY * bandX;
                if (bar > 0.001 && r.active > 0.5)
                {
                    // ALARM. Layers overlapping by about an octave is what a self-similar zoom
                    // IS, so that is not the failure. The failure is a record straddling nearly
                    // two octaves: it is then visible at three scales along one bearing at once,
                    // and the eye reads the repeat instead of the fall. Traces are exempt —
                    // a hairline crossing its own copy reads as more line work, not as mush,
                    // and long spans across scales are the reference's most characteristic mark.
                    float octs = axRho(r.rmax, ratio) - axRho(r.rmin, ratio);
                    bool broken = (octs > 1.8) && (r.role != ROLE_TRC);
                    uint fl = (uint)r.flags;
                    float3 bc = broken ? PT_ALARM
                              : lerp(ptRamp(0.35 + 0.5 * (r.role / 3.0)),
                                     ptSampleFill(axPal((int)r.col)), 0.45);
                    col = lerp(col, bc, bar);
                    if ((fl & F_EDITED) != 0u)
                        col = lerp(col, PT_MID, bar * step(0.5, frac(uv.x * 300.0)) * 0.55);
                    if ((fl & F_SELECTED) != 0u) col = lerp(col, PT_ACCENT, bar);
                }
                else if (bar > 0.001)
                {
                    col = lerp(col, PT_RULE, bar * 0.30);   // switched off: the slot stays visible
                }
            }

            // the playhead: where in the octave the fall is right now
            float phx = axRhoToX(frac(travel), spanView);
            col = lerp(col, PT_ACCENT, vline(uv.x, phx, 0.0010, px) * 0.95);
        }
        col = lerp(col, PT_RULE, frameBox(uv, hc, hh, 0.0013, px) * 0.8);
    }

    // =====================================================================================
    // COVERAGE — how many records occupy each log radius. A column at zero is a hole the fall
    // drops through into empty field, and it is invisible in every other view.
    // =====================================================================================
    if (region == 3)
    {
        float2 hc = float2((AX_LAD_X0 + AX_LAD_X1) * 0.5, (AX_COV_Y0 + AX_COV_Y1) * 0.5);
        float2 hh = float2((AX_LAD_X1 - AX_LAD_X0) * 0.5, (AX_COV_Y1 - AX_COV_Y0) * 0.5);
        bool inside = (abs(uv.x - hc.x) < hh.x) && (abs(uv.y - hc.y) < hh.y);
        if (inside)
        {
            col = PT_WELL;
            float rho = axXToRho(uv.x, spanView);
            uint cnt = 0u;
            for (uint i = 0u; i < AX_RECORDS - 1u; i++)
            {
                AxRec r = Plan[i];
                if (r.active < 0.5 || r.role == ROLE_TRC) continue;
                if (rho >= axRho(r.rmin, ratio) && rho <= axRho(r.rmax, ratio)) cnt++;
            }
            float t = saturate((float)cnt / 18.0);
            float top = AX_COV_Y1 - t * (AX_COV_Y1 - AX_COV_Y0);
            float fill = step(top, uv.y);
            col = lerp(col, PT_MID, fill * 0.55);
            col = lerp(col, PT_INK, (1.0 - smoothstep(0.0011, 0.0011 + px, abs(uv.y - top))) * 0.9);
            if (cnt == 0u && rho >= 0.0 && rho <= span)
                col = lerp(col, PT_ALARM, step(AX_COV_Y1 - 0.020, uv.y));

            for (int k = 0; k <= 8; k++)
            {
                if ((float)k > spanView) break;
                col = lerp(col, PT_GRID, vline(uv.x, axRhoToX((float)k, spanView), 0.0006, px));
            }
            col = lerp(col, PT_ACCENT, vline(uv.x, axRhoToX(frac(travel), spanView), 0.0010, px) * 0.8);
        }
        col = lerp(col, PT_RULE, frameBox(uv, hc, hh, 0.0013, px) * 0.8);
    }

    // =====================================================================================
    // Tallies — live count per family, one dot each. Bottom right, under the coverage strip.
    // =====================================================================================
    {
        uint counts[4] = { liveV, liveP, liveW, liveT };
        uint caps[4]   = { AX_VOLS, AX_PANS, AX_WDGS, AX_TRCS };
        for (uint g = 0u; g < 4u; g++)
        {
            float y = 0.800 + (float)g * 0.038;
            for (uint t = 0u; t < caps[g]; t++)
            {
                float2 p = float2(AX_LAD_X0 + 0.004 + (float)t * 0.0100, y);
                float on = (t < counts[g]) ? 1.0 : 0.0;
                col = lerp(col, lerp(PT_RULE * 0.8, PT_INK, on), disc(uv, p, 0.0034, asp, px));
            }
        }
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
