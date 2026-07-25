// CRYOGRAM / PROGRAM — final plate.
//
// Presentation only: this node adds no new information, it makes the existing
// information land. Halation and grain give the relief a photographed weight,
// the registration frame and title block declare it as an instrument record,
// and the readouts are the SAME live values the measurement layer publishes —
// never re-derived, never faked.

#include "../_shared/ui/sui_core.hlsli"
#include "../_shared/ui/sui_typography.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

static const float3 INK   = float3(0.93, 0.93, 0.94);
static const float3 DIM   = float3(0.40, 0.40, 0.43);
static const float3 FAINT = float3(0.19, 0.19, 0.21);
static const float3 AMBER = float3(1.00, 0.66, 0.22);

float3 loadIn(Texture2D<float4> t, int2 p) {
    uint w, h;
    t.GetDimensions(w, h);
    return t.Load(int3(clamp(p, int2(0, 0), int2(w, h) - 1), 0)).rgb;
}

float3 bilinIn(Texture2D<float4> t, float2 uv) {
    uint w, h;
    t.GetDimensions(w, h);
    if (w == 0u) return float3(0, 0, 0);
    float2 q = saturate(uv) * float2(w, h) - 0.5;
    int2 b = (int2)floor(q);
    float2 f = q - (float2)b;
    float3 c00 = loadIn(t, b), c10 = loadIn(t, b + int2(1, 0));
    float3 c01 = loadIn(t, b + int2(0, 1)), c11 = loadIn(t, b + int2(1, 1));
    return lerp(lerp(c00, c10, f.x), lerp(c01, c11, f.x), f.y);
}

float cryoStr(SuiContext c, float2 atPx, SuiTextStyle st, int codes[12], int n) {
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
    int2 px = int2(id.xy);
    SuiContext c = suiContext(id.xy, _Resolution.xy);
    float2 inv = c.invResolution;
    SuiTextStyle body = suiTextStyleTracked(1.5, 0.0, -1.5);
    SuiTextStyle small = suiTextStyleTracked(1.0, 0.0, -1.0);

    float3 col = loadIn(_Tex0, px);

    // ---- halation: bright relief edges bleed like a real exposure ----------
    if (halation > 0.001) {
        float3 glow = float3(0, 0, 0);
        [unroll] for (int k = 0; k < 12; ++k) {
            float a = 6.28318530718 * (float)k / 12.0;
            float2 d = float2(cos(a), sin(a));
            float3 s1 = loadIn(_Tex0, px + (int2)(d * halation_radius));
            float3 s2 = loadIn(_Tex0, px + (int2)(d * halation_radius * 2.3));
            glow += max(s1 - halation_threshold, 0.0) + max(s2 - halation_threshold, 0.0) * 0.55;
        }
        col += glow / 12.0 * halation;
    }

    // ---- tone: gentle S, lifted toe so the black field stays a field -------
    col = saturate(col);
    col = lerp(col, col * col * (3.0 - 2.0 * col), contrast_s);
    col = pow(max(col, 0.0), 1.0 / max(gamma_out, 0.05));
    col += lift;

    // ---- grain -------------------------------------------------------------
    if (grain > 0.001) {
        uint n = (uint)(px.x * 1973 + px.y * 9277 + (int)(_Time * 60.0) * 26699);
        n = (n ^ 61u) ^ (n >> 16u); n *= 9u; n = n ^ (n >> 4u); n *= 0x27d4eb2du; n = n ^ (n >> 15u);
        float g = ((float)(n & 0xFFFFu) / 65535.0 - 0.5);
        col += g * grain * (0.35 + 0.65 * saturate(1.0 - dot(col, 0.333)));
    }

    // ---- plan inset: the specimen the relief was measured from -------------
    float insetW = _Resolution.x * inset_scale;
    float insetH = insetW * 9.0 / 16.0;
    float4 inset = float4(_Resolution.x - insetW - 26.0, 26.0, _Resolution.x - 26.0, 26.0 + insetH);
    if (inset_gain > 0.005) {
        if (c.pixel.x > inset.x && c.pixel.x < inset.z && c.pixel.y > inset.y && c.pixel.y < inset.w) {
            float2 iuv = (c.pixel - inset.xy) / max(inset.zw - inset.xy, float2(1.0, 1.0));
            col = lerp(col, bilinIn(_Tex1, iuv) * inset_gain, inset_mix);
        }
        float4 ir = inset / float4(_Resolution.xy, _Resolution.xy);
        suiComposite(col, DIM, suiStrokeRect(c, ir, 1.0) * 0.8);
        int P[12] = { 80, 76, 65, 78, 32, 32, 32, 32, 32, 32, 32, 32 };
        suiComposite(col, DIM, cryoStr(c, float2(inset.x, inset.y - 12.0), small, P, 4));
    }

    // ---- registration frame -------------------------------------------------
    float m = frame_inset;
    float4 fr = float4(m, m, _Resolution.x - m, _Resolution.y - m) / float4(_Resolution.xy, _Resolution.xy);
    suiComposite(col, DIM, suiStrokeRect(c, fr, 1.0) * frame_gain);

    float2 fp[4] = { float2(m, m), float2(_Resolution.x - m, m),
                     float2(m, _Resolution.y - m), float2(_Resolution.x - m, _Resolution.y - m) };
    [unroll] for (int q = 0; q < 4; ++q) {
        suiComposite(col, INK, suiLinePx(c, (fp[q] - float2(11.0, 0.0)) * inv, (fp[q] + float2(11.0, 0.0)) * inv, 1.0) * frame_gain);
        suiComposite(col, INK, suiLinePx(c, (fp[q] - float2(0.0, 11.0)) * inv, (fp[q] + float2(0.0, 11.0)) * inv, 1.0) * frame_gain);
    }
    // edge ticks
    int ticks = 24;
    [loop] for (int t = 1; t < ticks; ++t) {
        float fx = lerp(m, _Resolution.x - m, (float)t / (float)ticks);
        float len = (t % 6 == 0) ? 9.0 : 4.0;
        suiComposite(col, FAINT, suiLinePx(c, float2(fx, m) * inv, float2(fx, m + len) * inv, 1.0) * frame_gain);
        suiComposite(col, FAINT, suiLinePx(c, float2(fx, _Resolution.y - m) * inv, float2(fx, _Resolution.y - m - len) * inv, 1.0) * frame_gain);
    }

    // ---- title block: live values only -------------------------------------
    {
        int liveT = 0, confT = 0, bonds = 0, probes = 0;
        uint tc = min(_Data0_Count, 97u);
        [loop] for (uint i = 0u; i < tc; ++i) {
            if (_Data0[i].active < 0.5) continue;
            liveT++;
            if (_Data0[i].confidence >= 0.90) confT++;
        }
        uint fc = min(_Data1_Count, 160u);
        [loop] for (uint j = 0u; j < fc; ++j) if (_Data1[j].weight > 0.0) bonds++;
        uint pc = min(_Data2_Count, 32u);
        [loop] for (uint k = 0u; k < pc; ++k) if (_Data2[k].active > 0.5) probes++;

        float bx = m + 14.0;
        float by = _Resolution.y - m - 40.0;

        int T[12] = { 67, 82, 89, 79, 71, 82, 65, 77, 32, 32, 32, 32 };
        suiComposite(col, INK, cryoStr(c, float2(bx, by), body, T, 8) * title_gain);
        suiComposite(col, FAINT, suiLinePx(c, float2(bx, by + 16.0) * inv,
                                              float2(bx + 210.0, by + 16.0) * inv, 1.0) * title_gain);

        float ry = by + 24.0;
        int LT[12] = { 84, 82, 75, 32, 32, 32, 32, 32, 32, 32, 32, 32 };
        int LC[12] = { 67, 78, 70, 32, 32, 32, 32, 32, 32, 32, 32, 32 };
        int LB[12] = { 66, 78, 68, 32, 32, 32, 32, 32, 32, 32, 32, 32 };
        int LP[12] = { 80, 82, 66, 32, 32, 32, 32, 32, 32, 32, 32, 32 };
        float sp = 54.0;
        suiComposite(col, DIM,   cryoStr(c, float2(bx, ry), small, LT, 3) * title_gain);
        suiComposite(col, INK,   suiInteger(c, float2(bx + 22.0, ry) * inv, small, liveT, 3) * title_gain);
        suiComposite(col, DIM,   cryoStr(c, float2(bx + sp, ry), small, LC, 3) * title_gain);
        suiComposite(col, AMBER, suiInteger(c, float2(bx + sp + 22.0, ry) * inv, small, confT, 3) * title_gain);
        suiComposite(col, DIM,   cryoStr(c, float2(bx + sp * 2.0, ry), small, LB, 3) * title_gain);
        suiComposite(col, INK,   suiInteger(c, float2(bx + sp * 2.0 + 22.0, ry) * inv, small, bonds, 3) * title_gain);
        suiComposite(col, DIM,   cryoStr(c, float2(bx + sp * 3.0, ry), small, LP, 3) * title_gain);
        suiComposite(col, AMBER, suiInteger(c, float2(bx + sp * 3.0 + 22.0, ry) * inv, small, probes, 3) * title_gain);
    }

    // ---- vignette -----------------------------------------------------------
    float2 v = (c.uv - 0.5) * 2.0;
    col *= 1.0 - vignette * saturate(dot(v, v) * 0.40);

    OutputUAV[id.xy] = float4(saturate(col * exposure), 1.0);
}
