// Console render — display spectrogram, region bands, firing flash, mini-traces.
//
// Everything positional goes through the shared p2_* transform so the pixels a
// user sees and the coordinates the detector reduces are the same mapping.

#include "types.hlsli"

StructuredBuffer<DH> Hist : register(t0);
StructuredBuffer<RG> Rgn  : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    uint W = (uint)_Resolution.x, H = (uint)_Resolution.y;
    if (px.x >= W || px.y >= H) return;

    // Panel UV with y up, so the frequency axis rises like a spectrogram.
    float2 uv = float2(((float)px.x + 0.5) / (float)W,
                       1.0 - ((float)px.y + 0.5) / (float)H);

    float3 col = P2_INK;
    float nHops = (float)min(DISP_HOPS, (uint)max(hist_hops, 32.0));

    uint newest = (uint)max(Hist[CURSOR_IDX].v, 0.0);
    if (newest > 0u) {
        // uv.x -> hops back from newest; uv.y -> log frequency axis directly,
        // because the display rows ARE the log axis.
        float hopsBack = (1.0 - uv.x) * max(nHops - 1.0, 1.0);

        // A 768x192 history stretched over a ~1280x720 panel is a magnification
        // on both axes. Point sampling turns real audio into blocks and reads as
        // a synthetic pattern, so interpolate. The hop axis is only interpolated
        // where BOTH taps are inside the retained window, otherwise the pair
        // straddles the ring cursor and blends the newest hop against the oldest.
        float gf = (float)newest - hopsBack;
        uint  g0 = (uint)max(floor(gf), 0.0);
        uint  g1 = min(g0 + 1u, newest);
        float gt = (g1 > g0) ? frac(gf) : 0.0;

        float by = uv.y * (float)DISP_BINS - 0.5;
        uint  b0 = (uint)clamp(floor(by), 0.0, (float)(DISP_BINS - 1u));
        uint  b1 = min(b0 + 1u, DISP_BINS - 1u);
        float bt = saturate(by - floor(by));

        uint r0 = (g0 % DISP_HOPS) * DISP_BINS, r1 = (g1 % DISP_HOPS) * DISP_BINS;
        float e = lerp(lerp(Hist[r0 + b0].eq, Hist[r0 + b1].eq, bt),
                       lerp(Hist[r1 + b0].eq, Hist[r1 + b1].eq, bt), gt);
        col = lerp(P2_INK, float3(0.93, 0.95, 0.96), saturate(e));
    }

    // Decade gridlines, so the frequency axis is readable rather than implied.
    [unroll] for (int d = 0; d < 4; ++d) {
        float hz = 100.0 * pow(10.0, (float)d);
        if (hz < P2_AXIS_LO_HZ || hz > P2_AXIS_HI_HZ) continue;
        float t = log(hz / P2_AXIS_LO_HZ) / log(P2_AXIS_HI_HZ / P2_AXIS_LO_HZ);
        if (abs(uv.y - t) < (0.8 / (float)H)) col = lerp(col, P2_GRID, 0.85);
    }

    // ---- regions -----------------------------------------------------------
    float binHz = 0.0;
    uint capacity = max(_Data1_HopCapacity, 1u);
    {
        uint vc = max(_Data0_ValueCount, 1u);
        uint sb = (_Data0_Generation % max(_Data0_HopCapacity, 1u)) * vc;
        if (sb + vc <= (uint)_Data0_Count && _Data0[sb].fft_size != 0u)
            binHz = (float)_Data0[sb].sample_rate / (float)_Data0[sb].fft_size;
    }

    RG flash = Rgn[P2_FLASH_IDX];
    float fv[P2_MAXFLASH] = { flash.binLo, flash.binHi, flash.hopLo,
                              flash.hopHi, flash.profile, flash.gain };

    float pxH = 1.0 / max((float)H, 1.0);

    if (binHz > 0.0) {
        [loop] for (uint i = 0u; i < P2_MAXFLASH; ++i) {
            RG r = Rgn[i];
            if (r.enabled < 0.5) continue;

            float tLo = p2_bin_to_axis(r.binLo, binHz);
            float tHi = p2_bin_to_axis(r.binHi, binHz);
            if (uv.y < tLo || uv.y > tHi) continue;

            float fl = saturate(fv[i]);

            // Fill: a faint warm wash so the band is legible over the
            // spectrogram without hiding the evidence underneath it.
            col = lerp(col, P2_ACCENT, 0.06 + 0.22 * fl);

            // Border, thickened and brightened by the firing flash.
            float edge = min(abs(uv.y - tLo), abs(uv.y - tHi));
            float wide = pxH * (1.2 + 2.5 * fl);
            if (edge < wide) col = lerp(col, P2_ACCENT, 0.55 + 0.45 * fl);

            // ---- mini-trace: flux against threshold ------------------------
            // Plotted inside the band, over the same time axis as the
            // spectrogram, so over- and under-triggering are visible without
            // any ground truth: the trace riding above its threshold line is
            // exactly what the picker acted on.
            uint tcursor = (uint)max(_Data1[0].f0, 0.0);
            if (tcursor > 1u && (tHi - tLo) > 0.02) {
                float hopsBack = (1.0 - uv.x) * max(nHops - 1.0, 1.0);
                float span = min(nHops, (float)P2_TRACE_SLOTS - 1.0);
                if (hopsBack < span) {
                    uint g = (uint)max((float)tcursor - 1.0 - hopsBack, 0.0);
                    uint ln = (uint)clamp(r.lane, 0.0, 2.0);
                    uint ti = p2_trace_index(g, ln);
                    if (ti < (uint)_Data1_Count) {
                        float o   = _Data1[ti].f0;
                        float thr = _Data1[ti].f1;

                        // Normalise against the threshold, so the crossing sits
                        // at a fixed height and the eye reads margin directly.
                        float ref = max(thr, 1e-6);
                        float yO   = saturate(0.5 * (o   / (2.0 * ref)));
                        float yT   = saturate(0.5 * (thr / (2.0 * ref)));

                        float base = tLo + 0.06 * (tHi - tLo);
                        float hgt  = 0.88 * (tHi - tLo);
                        float yv = base + yO * hgt;
                        float yt = base + yT * hgt;

                        if (abs(uv.y - yt) < pxH * 1.2)
                            col = lerp(col, P2_GRID * 3.0, 0.8);   // threshold
                        if (abs(uv.y - yv) < pxH * 1.6)
                            col = lerp(col, P2_TRACE, 0.95);       // flux
                    }
                }
            }
        }
    }

    // ---- drag in progress --------------------------------------------------
    RG hdr = Rgn[P2_HDR_IDX];
    if (hdr.binHi > 0.5) {
        float t0 = min(hdr.hopHi, hdr.gain), t1 = max(hdr.hopHi, hdr.gain);
        if (uv.y >= t0 && uv.y <= t1) {
            col = lerp(col, P2_ACCENT, 0.16);
            float edge = min(abs(uv.y - t0), abs(uv.y - t1));
            if (edge < pxH * 1.5) col = lerp(col, P2_ACCENT, 0.9);
        }
    }

    OutputUAV[px] = float4(col, 1.0);
}
