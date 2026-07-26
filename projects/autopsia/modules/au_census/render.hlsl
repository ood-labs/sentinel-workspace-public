// AUTOPSIA — the measurement rack.
// Every mark here is a reading of the live agent population: nothing is
// decorative telemetry. Population history is a real persistent ring, the age
// distribution and heading rose are real reductions, the colony census comes
// from the Features blob channel via agent membership.
#include "../_shared/au_hud/au_text.hlsli"

#define AU_HIST_BASE 64u
#define AU_HIST_LEN  256u

RWTexture2D<float4> Out : register(u0);
StructuredBuffer<float4> Census : register(t0);

float rectIn(float2 uv, float4 r) {
    return step(r.x, uv.x) * step(uv.x, r.z) * step(r.y, uv.y) * step(uv.y, r.w);
}
float rectFrame(float2 uv, float4 r, float2 t) {
    return rectIn(uv, r) - rectIn(uv, float4(r.x + t.x, r.y + t.y, r.z - t.x, r.w - t.y));
}
float seg2(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float h = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-7));
    return length(p - (a + ab * h));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float2 tp = uv * _Resolution.xy;

    float3 col = float3(0.0045, 0.005, 0.0055);
    float3 ink = float3(0.88, 0.885, 0.86);
    float3 dim = float3(0.40, 0.405, 0.39);
    float3 mid = float3(0.60, 0.605, 0.58);

    float4 st0 = Census[0];      // active, established, meanConf, meanAge
    float4 st1 = Census[1];      // colony counts
    float4 st2 = Census[2];      // meanSpeed, maxAge, -, peakConf
    float4 ctl = Census[3];

    float4 pPop = float4(0.030, 0.098, 0.700, 0.380);
    float4 pAge = float4(0.030, 0.460, 0.330, 0.760);
    float4 pRose = float4(0.360, 0.460, 0.660, 0.760);
    float4 pCol = float4(0.700, 0.460, 0.970, 0.760);
    float4 pRead = float4(0.730, 0.098, 0.970, 0.380);

    // ============ POPULATION: persistent chart recorder =====================
    if (rectIn(uv, pPop) > 0.5) {
        col = float3(0.010, 0.011, 0.012);
        float lx = (uv.x - pPop.x) / (pPop.z - pPop.x);
        float ly = (pPop.w - uv.y) / (pPop.w - pPop.y);

        // oldest sample at the left, newest at the right
        uint w = (uint)clamp(ctl.x, 0.0, (float)(AU_HIST_LEN - 1u));
        uint idx = (w + (uint)(lx * (float)(AU_HIST_LEN - 1u))) % AU_HIST_LEN;
        float4 h = Census[AU_HIST_BASE + idx];

        float scale = max(pop_scale, 1.0);
        float aY = saturate(h.x / scale);
        float eY = saturate(h.y / scale);

        float lw = 2.0 * px.y / (pPop.w - pPop.y);
        col += float3(0.050, 0.052, 0.049) * step(ly, aY);
        col += ink * (1.0 - smoothstep(0.0, lw, abs(ly - aY)));
        col += accent_color * (1.0 - smoothstep(0.0, lw, abs(ly - eY))) * 0.95;

        // graticule
        col += float3(0.045, 0.046, 0.044) * step(0.972, frac(lx * 8.0));
        col += float3(0.045, 0.046, 0.044) * step(0.972, frac(ly * 4.0));
        // write head
        col += accent_color * (1.0 - smoothstep(0.0, 1.6 * px.x / (pPop.z - pPop.x),
                                                abs(lx - 1.0))) * 0.5;
    }

    // ============ AGE DISTRIBUTION ==========================================
    if (rectIn(uv, pAge) > 0.5) {
        col = float3(0.010, 0.011, 0.012);
        float lx = (uv.x - pAge.x) / (pAge.z - pAge.x);
        float ly = (pAge.w - uv.y) / (pAge.w - pAge.y);
        uint bin = min((uint)(lx * 16.0), 15u);

        float peak = 1.0;
        [loop] for (uint b = 0u; b < 16u; ++b) peak = max(peak, Census[8 + b].x);
        float hgt = saturate(Census[8 + bin].x / peak);

        float inBar = step(ly, hgt) * step(0.10, frac(lx * 16.0));
        col += mid * inBar * 0.75;
        col += float3(0.045, 0.046, 0.044) * step(0.972, frac(ly * 4.0));
    }

    // ============ HEADING ROSE ==============================================
    if (rectIn(uv, pRose) > 0.5) {
        col = float3(0.010, 0.011, 0.012);
        float2 c = float2((pRose.x + pRose.z) * 0.5, (pRose.y + pRose.w) * 0.5);
        float2 d = (uv - c) * float2(_Resolution.x / _Resolution.y, 1.0);
        float rr = length(d) / ((pRose.w - pRose.y) * 0.44);
        float ang = frac(atan2(d.y, d.x) / 6.2831853 + 0.5);
        uint bin = min((uint)(ang * 16.0), 15u);

        float peak = 1.0;
        [loop] for (uint b = 0u; b < 16u; ++b) peak = max(peak, Census[24 + b].x);
        float petal = saturate(Census[24 + bin].x / peak);

        col += mid * step(rr, petal) * 0.55;
        col += ink * (1.0 - smoothstep(0.0, 0.035, abs(rr - petal))) * step(0.02, petal);
        // reference rings and cardinal spokes
        col += float3(0.10, 0.102, 0.098) * (1.0 - smoothstep(0.0, 0.012, abs(rr - 0.5)));
        col += float3(0.14, 0.142, 0.136) * (1.0 - smoothstep(0.0, 0.012, abs(rr - 1.0)));
        float spoke = 1.0 - smoothstep(0.0, 0.010, abs(frac(ang * 4.0) - 0.0));
        col += float3(0.08, 0.082, 0.078) * spoke * step(rr, 1.05);
    }

    // ============ COLONY CENSUS =============================================
    if (rectIn(uv, pCol) > 0.5) {
        col = float3(0.010, 0.011, 0.012);
        float lx = (uv.x - pCol.x) / (pCol.z - pCol.x);
        float ly = (pCol.w - uv.y) / (pCol.w - pCol.y);
        uint bar = min((uint)(lx * 4.0), 3u);
        float v = (bar == 0u) ? st1.x : (bar == 1u) ? st1.y : (bar == 2u) ? st1.z : st1.w;
        float peak = max(max(st1.x, st1.y), max(st1.z, max(st1.w, 1.0)));
        float hgt = saturate(v / peak);
        float inBar = step(ly, hgt) * step(0.14, frac(lx * 4.0));
        col += (bar == 3u ? dim : mid) * inBar * 0.8;
        col += float3(0.045, 0.046, 0.044) * step(0.972, frac(ly * 4.0));
    }

    // ============ NUMERIC READOUTS ==========================================
    if (rectIn(uv, pRead) > 0.5) {
        col = float3(0.009, 0.010, 0.011);
    }

    // panel frames
    col += float3(0.28, 0.285, 0.27) * rectFrame(uv, pPop, px);
    col += float3(0.28, 0.285, 0.27) * rectFrame(uv, pAge, px);
    col += float3(0.28, 0.285, 0.27) * rectFrame(uv, pRose, px);
    col += float3(0.28, 0.285, 0.27) * rectFrame(uv, pCol, px);
    col += float3(0.28, 0.285, 0.27) * rectFrame(uv, pRead, px);

    // ============ typography ================================================
    float s1 = 2.0, s0 = 1.0;
    col += ink * auText(tp, float2(20.0, 22.0), s1,
        G_C,G_E,G_N,G_S,G_U,G_S, 0,0,0,0,0,0);
    col += dim * auText(tp, float2(20.0, 46.0), s0,
        G_P,G_O,G_P,G_U,G_L,G_A,G_T,G_I,G_O,G_N,0,0);

    float2 pop0 = float2(pPop.x * _Resolution.x, pPop.y * _Resolution.y - 13.0);
    col += ink * auText(tp, pop0, s0, G_P,G_O,G_P,G_SP,G_H,G_I,G_S,G_T, 0,0,0,0);
    col += dim * auText(tp, pop0 + float2(0.0, (pPop.w - pPop.y) * _Resolution.y + 14.0), s0,
        G_O,G_L,G_D, 0,0,0,0,0,0,0,0,0);
    col += dim * auText(tp, float2(pPop.z * _Resolution.x - 28.0,
                                   pPop.w * _Resolution.y + 14.0), s0,
        G_N,G_O,G_W, 0,0,0,0,0,0,0,0,0);

    col += ink * auText(tp, float2(pAge.x * _Resolution.x, pAge.y * _Resolution.y - 13.0), s0,
        G_A,G_G,G_E,G_SP,G_D,G_I,G_S,G_T, 0,0,0,0);
    col += ink * auText(tp, float2(pRose.x * _Resolution.x, pRose.y * _Resolution.y - 13.0), s0,
        G_H,G_E,G_A,G_D,G_SP,G_R,G_O,G_S,G_E, 0,0,0);
    col += ink * auText(tp, float2(pCol.x * _Resolution.x, pCol.y * _Resolution.y - 13.0), s0,
        G_C,G_O,G_L,G_O,G_N,G_Y, 0,0,0,0,0,0);
    col += ink * auText(tp, float2(pRead.x * _Resolution.x, pRead.y * _Resolution.y - 13.0), s0,
        G_R,G_E,G_A,G_D,G_O,G_U,G_T, 0,0,0,0,0);

    // colony bar labels
    [unroll] for (int cb = 0; cb < 4; ++cb) {
        float bx = lerp(pCol.x, pCol.z, ((float)cb + 0.5) / 4.0) * _Resolution.x - 4.0;
        col += dim * auNum(tp, float2(bx, pCol.w * _Resolution.y + 6.0), s0, cb, 1);
    }

    // live readout column
    float rx = pRead.x * _Resolution.x + 12.0;
    float ry = pRead.y * _Resolution.y + 16.0;
    float step_ = 20.0;

    col += dim * auText(tp, float2(rx, ry), s0, G_A,G_C,G_T,G_I,G_V,G_E, 0,0,0,0,0,0);
    col += ink * auNum(tp, float2(rx + 110.0, ry), s0, (int)st0.x, 2);

    col += dim * auText(tp, float2(rx, ry + step_), s0, G_E,G_S,G_T,G_A,G_B, 0,0,0,0,0,0,0);
    col += accent_color * auNum(tp, float2(rx + 110.0, ry + step_), s0, (int)st0.y, 2);

    col += dim * auText(tp, float2(rx, ry + step_ * 2.0), s0, G_C,G_O,G_N,G_F, 0,0,0,0,0,0,0,0);
    col += ink * auFixed(tp, float2(rx + 96.0, ry + step_ * 2.0), s0, st0.z);

    col += dim * auText(tp, float2(rx, ry + step_ * 3.0), s0, G_A,G_G,G_E,G_SP,G_A,G_V,G_G, 0,0,0,0,0);
    col += ink * auFixed(tp, float2(rx + 96.0, ry + step_ * 3.0), s0, st0.w);

    col += dim * auText(tp, float2(rx, ry + step_ * 4.0), s0, G_A,G_G,G_E,G_SP,G_M,G_A,G_X, 0,0,0,0,0);
    col += ink * auFixed(tp, float2(rx + 96.0, ry + step_ * 4.0), s0, st2.y);

    col += dim * auText(tp, float2(rx, ry + step_ * 5.0), s0, G_S,G_P,G_E,G_E,G_D, 0,0,0,0,0,0,0);
    col += ink * auFixed(tp, float2(rx + 96.0, ry + step_ * 5.0), s0, st2.x * 10.0);

    col += dim * auText(tp, float2(rx, ry + step_ * 6.0), s0, G_S,G_A,G_M,G_P,G_SP,G_N, 0,0,0,0,0,0);
    col += ink * auNum(tp, float2(rx + 96.0, ry + step_ * 6.0), s0, (int)ctl.z, 5);

    // ============ LEDGER: the eight longest-surviving agents ================
    // Named individuals, not aggregates — the instrument's record of what it
    // has actually held onto. ID is the real stable_id from the stabilizer.
    float4 pLed = float4(0.030, 0.830, 0.970, 0.965);
    if (rectIn(uv, pLed) > 0.5) {
        col = float3(0.009, 0.010, 0.011);
        float lx = (uv.x - pLed.x) / (pLed.z - pLed.x);
        uint slot = min((uint)(lx * 8.0), 7u);
        float4 rec = Census[40 + slot];
        float within = frac(lx * 8.0);

        if (rec.w >= 0.0) {
            // confidence fill across the cell
            float ly = (pLed.w - uv.y) / (pLed.w - pLed.y);
            col += float3(0.030, 0.031, 0.030) * step(within, 0.94) * step(ly, 0.22)
                 * step(within, saturate(rec.z) * 0.94);
            col += (rec.z >= establish_conf && rec.y >= establish_time ? accent_color : mid)
                 * step(within, 0.94) * step(ly, 0.055)
                 * step(within, saturate(rec.z) * 0.94) * 0.85;
        }
        col += float3(0.10, 0.102, 0.098) * step(0.955, within);   // cell divider
    }
    col += float3(0.28, 0.285, 0.27) * rectFrame(uv, pLed, px);

    col += ink * auText(tp, float2(pLed.x * _Resolution.x, pLed.y * _Resolution.y - 13.0), s0,
        G_L,G_E,G_D,G_G,G_E,G_R, 0,0,0,0,0,0);
    col += dim * auText(tp, float2(pLed.x * _Resolution.x + 60.0, pLed.y * _Resolution.y - 13.0), s0,
        G_I,G_D,G_SP,G_SL,G_SP,G_A,G_G,G_E, 0,0,0,0);

    [unroll] for (int ls = 0; ls < 8; ++ls) {
        float4 rec = Census[40 + ls];
        if (rec.w < 0.0) continue;
        float cx = lerp(pLed.x, pLed.z, ((float)ls) / 8.0) * _Resolution.x + 8.0;
        float cy = pLed.y * _Resolution.y + 12.0;
        col += ink * auNum(tp, float2(cx, cy), s0, (int)rec.x, 5);
        col += dim * auFixed(tp, float2(cx, cy + 16.0), s0, rec.y);
    }

    // frame + registration
    col += float3(0.24, 0.245, 0.235) * rectFrame(uv, float4(0.010, 0.014, 0.990, 0.986), px);
    float2 cc = min(uv, 1.0 - uv);
    float corner = step(cc.x, 0.030) * step(cc.y, 0.0035) + step(cc.y, 0.030) * step(cc.x, 0.0035);
    col += float3(0.68, 0.685, 0.66) * saturate(corner);

    Out[tid.xy] = float4(saturate(col), 1.0);
}
