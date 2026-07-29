RWTexture2D<float4> OutputUAV : register(u0);

float af_line(float d, float w) { return 1.0 - smoothstep(w, w * 2.5, abs(d)); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float phase = accordion_phase * 6.2831853 + _Time * fold_speed;
    float count = max(3.0, fold_count);
    float bandId = floor(uv.x * count);
    float local = frac(uv.x * count);
    float parity = fmod(bandId, 2.0);
    float mirrorLocal = (parity < 1.0) ? local : 1.0 - local;
    float wave = sin(phase + bandId * 0.73 + uv.y * 5.0) * bend * 0.12;
    float yWarp = (mirrorLocal - 0.5) * fold_width + wave;
    float2 sampleUv = saturate(float2(uv.x + (mirrorLocal - 0.5) * 0.035 * bend, uv.y + yWarp));
    float3 src = _Tex0.SampleLevel(LinearSampler, sampleUv, 0).rgb;
    float3 neighbor = _Tex0.SampleLevel(LinearSampler, saturate(sampleUv + float2(0.0, px.y * 6.0)), 0).rgb;
    float edge = length(src - neighbor);
    float seam = af_line(local - 0.02, px.x * 4.0) + af_line(local - 0.98, px.x * 4.0);
    float ridge = af_line(mirrorLocal - 0.5, 0.012 + fold_width * 0.05);
    float faceShade = 0.70 + 0.30 * sin(mirrorLocal * 3.14159 + phase + bandId);
    float3 ink = src * (0.44 + 0.30 * faceShade) + fold_color * seam * seam_gain * 0.42;
    ink += fold_color * ridge * 0.24 + accent_color * (edge * 1.4 + seam * seam_gain * 0.52);
    float3 outCol = lerp(src * 0.16 + dark_color * 0.30, ink, accordion_mix);
    OutputUAV[tid.xy] = float4(saturate(outCol), 1.0);
}
