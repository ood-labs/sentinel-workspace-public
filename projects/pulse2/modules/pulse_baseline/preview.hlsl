// CRYOGRAM / PULSE — the detector's own readout.
//
// Beat detection is invisible until you can see it being wrong. This preview
// exists so the thresholds can be tuned by eye:
//
//   left  : live mel spectrogram, 138 bands scrolling over our 512-hop history
//   right : three lane flux traces, each with its ADAPTIVE THRESHOLD drawn as a
//           line and accepted onsets ticked. If the trace never crosses the
//           threshold, sensitivity is too high; if it crosses constantly, too low.
//   bottom: BPM, tempo confidence, beat-phase ring, and lane counters.

#include "../_shared/ui/sui_core.hlsli"
#include "../_shared/ui/sui_typography.hlsli"

struct PS { float a, b, c, d, e, f, g, h; };

StructuredBuffer<PS> S : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const uint HIST     = 512u;
static const uint BANDBASE = 512u;
static const uint HDR_A    = 650u;
static const uint HDR_B    = 651u;
static const uint HDR_C    = 652u;
static const uint HDR_D    = 653u;

static const float3 INK   = float3(0.93, 0.93, 0.94);
static const float3 DIM   = float3(0.34, 0.34, 0.37);
static const float3 FAINT = float3(0.16, 0.16, 0.18);
static const float3 AMBER = float3(1.00, 0.66, 0.22);
static const float3 RED   = float3(0.88, 0.30, 0.26);

float cryoStr(SuiContext c, float2 atPx, SuiTextStyle st, int codes[8], int n) {
    float cov = 0.0;
    float adv = 6.0 * st.scalePx + st.trackingPx;
    [loop] for (int i = 0; i < n; ++i)
        cov = max(cov, suiGlyph(c, (atPx + float2((float)i * adv, 0.0)) * c.invResolution, st, codes[i]));
    return cov;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;

    SuiContext c = suiContext(id.xy, _Resolution.xy);
    float2 P = c.pixel;
    float2 inv = c.invResolution;
    SuiTextStyle body = suiTextStyleTracked(1.5, 0.0, -1.5);
    SuiTextStyle small = suiTextStyleTracked(1.0, 0.0, -1.0);

    PS A = S[HDR_A], B = S[HDR_B], C = S[HDR_C], D = S[HDR_D];
    uint head = (uint)max(A.b, 0.0);

    float3 col = float3(0.005, 0.005, 0.006);

    float m = 16.0;
    float footerY = _Resolution.y - 74.0;
    float splitX = _Resolution.x * 0.44;

    // ================= mel spectrogram ======================================
    float4 spec = float4(m, m, splitX - 10.0, footerY - 10.0);
    if (P.x > spec.x && P.x < spec.z && P.y > spec.y && P.y < spec.w) {
        float tx = (P.x - spec.x) / (spec.z - spec.x);        // 0 = oldest
        float ty = 1.0 - (P.y - spec.y) / (spec.w - spec.y);  // 0 = low band

        uint hops = (uint)clamp(spectro_hops, 32.0, 480.0);
        uint back = (uint)((1.0 - tx) * (float)hops);
        uint idx = (head - 1u - back) % HIST;

        // our history stores lane energies, not all 138 bands, so the
        // spectrogram shows the three lanes as stacked energy bands
        PS r = S[idx];
        float v = (ty < 0.34) ? r.g : ((ty < 0.67) ? (r.a + r.b) * 0.5 : r.h);
        v = saturate(v * spectro_gain);
        col = float3(v, v, v) * 0.9;

        // onset ticks along the top of the spectrogram
        float onset = max(r.d, max(r.e, r.f));
        if (ty > 0.94 && onset > 0.0) col = lerp(col, AMBER, saturate(onset * 2.0));
    }
    {
        float4 sr = spec / float4(_Resolution.xy, _Resolution.xy);
        suiComposite(col, DIM, suiStrokeRect(c, sr, 1.0) * 0.7);
        int L[8] = { 77, 69, 76, 32, 32, 32, 32, 32 };   // MEL
        suiComposite(col, DIM, cryoStr(c, float2(spec.x, spec.y - 12.0), small, L, 3));
    }

    // ================= three lane traces ====================================
    float laneX0 = splitX + 10.0;
    float laneX1 = _Resolution.x - m;
    float laneH = (footerY - 10.0 - m) / 3.0;

    [unroll] for (int lane = 0; lane < 3; ++lane) {
        float y0 = m + laneH * (float)lane;
        float y1 = y0 + laneH - 8.0;
        float4 lr = float4(laneX0, y0, laneX1, y1);
        float4 ln = lr / float4(_Resolution.xy, _Resolution.xy);
        suiComposite(col, FAINT, suiStrokeRect(c, ln, 1.0) * 0.8);

        float3 lc = (lane == 0) ? AMBER : ((lane == 1) ? INK : DIM);
        float thr = (lane == 0) ? D.e : ((lane == 1) ? D.f : D.g);

        if (P.x > lr.x && P.x < lr.z && P.y > lr.y && P.y < lr.w) {
            float tx = (P.x - lr.x) / (lr.z - lr.x);
            uint hops = (uint)clamp(trace_hops, 32.0, 480.0);
            uint back = (uint)((1.0 - tx) * (float)hops);
            uint idx = (head - 1u - back) % HIST;
            PS r = S[idx];

            float fl = (lane == 0) ? r.a : ((lane == 1) ? r.b : r.c);
            float hit = (lane == 0) ? r.d : ((lane == 1) ? r.e : r.f);

            float sc = max(trace_scale, 1e-4);
            float fy = lr.w - saturate(fl / sc) * (lr.w - lr.y);
            float ty2 = lr.w - saturate(thr / sc) * (lr.w - lr.y);

            // flux fill
            if (P.y > fy) suiComposite(col, lc, 0.55);
            // adaptive threshold line
            suiComposite(col, RED, (1.0 - smoothstep(0.7, 1.8, abs(P.y - ty2))) * 0.9);
            // accepted onset tick
            if (hit > 0.0) suiComposite(col, AMBER, (1.0 - smoothstep(0.0, 1.4, abs(P.x - (lr.x + tx * (lr.z - lr.x))))) * 0.9);
        }
    }

    // ================= footer ================================================
    {
        suiComposite(col, FAINT, suiLinePx(c, float2(0.0, footerY) * inv,
                                              float2(_Resolution.x, footerY) * inv, 1.0));
        float fy = footerY + 16.0;

        int LB[8] = { 66, 80, 77, 32, 32, 32, 32, 32 };   // BPM
        suiComposite(col, DIM, cryoStr(c, float2(m, fy), small, LB, 3));
        suiComposite(col, AMBER, suiInteger(c, float2(m + 26.0, fy - 3.0) * inv, body, (int)round(A.c), 3));

        int LC[8] = { 67, 79, 78, 70, 32, 32, 32, 32 };   // CONF
        suiComposite(col, DIM, cryoStr(c, float2(m + 96.0, fy), small, LC, 4));
        suiComposite(col, INK, suiInteger(c, float2(m + 128.0, fy) * inv, small, (int)(saturate(A.g) * 100.0), 3));

        // beat phase ring
        float2 ctr = float2(m + 210.0, fy + 4.0);
        suiComposite(col, DIM, (1.0 - smoothstep(0.8, 1.9, abs(length(P - ctr) - 14.0))) * 0.6);
        float ang = frac(A.d) * 6.28318530718 - 1.5707963;
        float2 tip = ctr + float2(cos(ang), sin(ang)) * 14.0;
        suiComposite(col, AMBER, suiLinePx(c, ctr * inv, tip * inv, 1.6));
        suiComposite(col, AMBER, (1.0 - smoothstep(1.0, 3.0, length(P - ctr))) * saturate(A.h));

        // lane counters
        int LK[8] = { 75, 73, 67, 75, 32, 32, 32, 32 };   // KICK
        int LS[8] = { 83, 78, 82, 32, 32, 32, 32, 32 };   // SNR
        int LH[8] = { 72, 65, 84, 32, 32, 32, 32, 32 };   // HAT
        float cx = m + 260.0;
        suiComposite(col, DIM, cryoStr(c, float2(cx, fy), small, LK, 4));
        suiComposite(col, INK, suiInteger(c, float2(cx + 32.0, fy) * inv, small, (int)B.d % 1000, 3));
        suiComposite(col, DIM, cryoStr(c, float2(cx + 78.0, fy), small, LS, 3));
        suiComposite(col, INK, suiInteger(c, float2(cx + 104.0, fy) * inv, small, (int)B.e % 1000, 3));
        suiComposite(col, DIM, cryoStr(c, float2(cx + 150.0, fy), small, LH, 3));
        suiComposite(col, INK, suiInteger(c, float2(cx + 176.0, fy) * inv, small, (int)B.f % 1000, 3));

        // envelope bars
        float bx = cx + 240.0;
        float bw = max(_Resolution.x - m - bx, 40.0);
        [unroll] for (int e = 0; e < 3; ++e) {
            float ev = (e == 0) ? B.a : ((e == 1) ? B.b : B.c);
            float3 ec = (e == 0) ? AMBER : ((e == 1) ? INK : DIM);
            float by = fy - 4.0 + (float)e * 9.0;
            float4 br = float4(bx, by, bx + bw, by + 6.0);
            float4 bn = br / float4(_Resolution.xy, _Resolution.xy);
            suiComposite(col, FAINT, suiFillRect(c, bn) * 0.7);
            float4 fr2 = float4(bx, by, bx + bw * saturate(ev), by + 6.0) / float4(_Resolution.xy, _Resolution.xy);
            suiComposite(col, ec, suiFillRect(c, fr2));
        }
    }

    OutputUAV[id.xy] = float4(saturate(col), 1.0);
}
