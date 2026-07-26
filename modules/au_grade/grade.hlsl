// AUTOPSIA — final compositor.
//
// The instrument's layers are not stacked side by side; they are printed onto
// one plate. Four composite LOOKS are authored so the piece can be explored
// rather than settled on the first arrangement that works:
//
//   0 IMPRESSION  the rack bleeds into the relief's empty field
//   1 INSPECTION  a travelling band exposes the analytical layer beneath
//   2 REGISTER    misregistered print: ghosted specimen offset under the relief
//   3 SECTIONED   interlaced strips interleave relief and analysis
//
// _Tex0 = relief instrument   _Tex1 = census rack   _Tex2 = specimen plate
StructuredBuffer<float4> Clock : register(t3);
RWTexture2D<float4> Out : register(u0);

float au_hash(float2 p) {
    p = frac(p * float2(443.897, 441.423));
    p += dot(p, p + 19.19);
    return frac(p.x * p.y);
}

float luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// Every input arrives already display-encoded (each upstream node applies its
// own 1/2.2). Compositing those encoded values and then encoding AGAIN lifts
// the blacks twice and turns a black-field instrument into flat grey. So
// linearize on the way in, composite in linear light, encode exactly once out.
float3 toLinear(float3 c) { return pow(max(c, 0.0), 2.2); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;

    float phase = frac(Clock[0].x + sweep_phase);
    float tsec = Clock[0].y;

    float3 relief = toLinear(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb);
    float3 rack   = toLinear(_Tex1.SampleLevel(LinearSampler, uv, 0).rgb);
    float3 plate  = toLinear(_Tex2.SampleLevel(LinearSampler, uv, 0).rgb);

    float3 col = relief;
    int look = (int)round(clamp(look_mode, 0.0, 3.0));

    // ---------------------------------------------------------------- 0
    if (look == 0) {
        // Rack printed into the relief's negative space. Where the relief is
        // dark the analysis shows through; where it is bright it stays clean.
        float room = 1.0 - smoothstep(0.02, 0.30, luma(relief));
        col = relief + rack * room * layer_mix;
        col += plate * (1.0 - smoothstep(0.01, 0.12, luma(relief))) * ghost_gain * 0.35;
    }
    // ---------------------------------------------------------------- 1
    else if (look == 1) {
        float bandC = phase;
        float h = max(band_height, 0.01);
        float d = abs(uv.y - bandC);
        d = min(d, 1.0 - d);                      // wrap
        float inBand = 1.0 - smoothstep(h * 0.5, h * 0.5 + 0.004, d);

        // the exposed layer is torn slightly sideways, like a scan slip
        float slip = (au_hash(float2(floor(uv.y * 240.0), floor(tsec * 8.0))) - 0.5) * band_tear;
        float3 exposed = toLinear(_Tex1.SampleLevel(LinearSampler, uv + float2(slip, 0.0), 0).rgb);

        col = lerp(relief, exposed, inBand * layer_mix);
        // bright rules at the band boundary
        float rule = (1.0 - smoothstep(0.0, 1.6 * px.y, abs(d - h * 0.5)));
        col += float3(0.85, 0.855, 0.83) * rule * 0.75;
        col += accent_color * rule * 0.22;
    }
    // ---------------------------------------------------------------- 2
    else if (look == 2) {
        // Misregistered print: the specimen ghosts under the relief, offset by
        // a real distance, the way a plate shifts between passes.
        float2 off = float2(register_offset, -register_offset * 0.55);
        float3 g1 = toLinear(_Tex2.SampleLevel(LinearSampler, uv + off, 0).rgb);
        float3 g2 = toLinear(_Tex2.SampleLevel(LinearSampler, uv - off * 0.6, 0).rgb);
        col = relief;
        // two offset impressions of the specimen: the organic ghost that the
        // hard instrument geometry is printed over
        col += g1 * ghost_gain * 0.85;
        col += g2 * ghost_gain * 0.34;
        // a faint third impression, tinted, so the misregistration reads as a
        // real multi-pass print rather than a blur
        float3 g3 = toLinear(_Tex2.SampleLevel(LinearSampler, uv + off * 2.1, 0).rgb);
        col += g3 * accent_color * ghost_gain * 0.16;
        // the analytical sheet stays a WATERMARK here: present, never competing
        float room = 1.0 - smoothstep(0.03, 0.28, luma(relief));
        col += rack * room * layer_mix * 0.16;
    }
    // ---------------------------------------------------------------- 3
    else {
        float strips = max(section_count, 2.0);
        float s = frac(uv.y * strips + phase);
        float odd = step(0.5, s);
        float3 a = relief;
        float3 b = rack * 0.9 + plate * ghost_gain * 0.25;
        col = lerp(a, b, odd * layer_mix);
        // hairline between strips
        float edge = 1.0 - smoothstep(0.0, 1.4 * px.y * strips, abs(s - 0.5));
        col += float3(0.30, 0.305, 0.29) * edge * 0.35;
    }

    // ================= shared film response =================================
    // halation: bright linework blooms slightly into its surroundings
    if (halation > 0.001) {
        float3 h = float3(0.0, 0.0, 0.0);
        [unroll] for (int k = 0; k < 8; ++k) {
            float a = (float)k * 0.7853981634;
            float2 o = float2(cos(a), sin(a)) * px * halation_radius;
            h += toLinear(_Tex0.SampleLevel(LinearSampler, uv + o, 0).rgb);
        }
        h /= 8.0;
        float bright = smoothstep(0.35, 0.95, luma(h));
        col += h * bright * halation;
    }

    // plate grain, scaled by exposure not by frame rate
    float g = au_hash(uv * _Resolution.xy + floor(tsec * 24.0) * 17.0) - 0.5;
    col += g * grain * (0.25 + 0.75 * (1.0 - luma(col)));

    // very slight warm/cool split so the monochrome still reads as a print
    float lm = luma(col);
    col = lerp(col, float3(lm * 1.015, lm, lm * 0.975), split_tone);

    float2 vc = (uv - 0.5) * float2(1.04, 1.62);
    col *= 1.0 - saturate(dot(vc, vc)) * vignette;

    col *= exposure;
    col = col / (1.0 + col * 0.35);
    col = pow(saturate(col), 1.0 / max(gamma_out, 0.05));

    Out[tid.xy] = float4(saturate(col), 1.0);
}
