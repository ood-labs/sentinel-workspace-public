RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float3 program = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float2 encodedFlow = _Tex1.SampleLevel(LinearSampler, uv, 0).rg;
    float2 liveFlow = (encodedFlow - 0.5) * 2.0;
    float liveMagnitude = length(liveFlow) * motion_gain;
    float4 trail = _Tex2.SampleLevel(LinearSampler, uv, 0);

    float energyL = _Tex2.SampleLevel(LinearSampler, uv - float2(texel.x, 0.0), 0).r;
    float energyR = _Tex2.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).r;
    float energyU = _Tex2.SampleLevel(LinearSampler, uv - float2(0.0, texel.y), 0).r;
    float energyD = _Tex2.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).r;
    float trailEdge = abs(energyR - energyL) + abs(energyD - energyU);

    float angle = (trail.g - 0.5) * 6.2831853;
    float2 direction = float2(cos(angle), sin(angle));
    float2 normal = float2(-direction.y, direction.x);
    float stripeCoord = dot(p, normal) * (36.0 + trail.b * 92.0) + _Time * 0.07;
    float stripeDistance = abs(frac(stripeCoord) - 0.5);
    float stripeWidth = 0.004 + etch_width * 0.008;
    float hatch = 1.0 - smoothstep(stripeWidth, stripeWidth * 2.2, stripeDistance);

    float energyMask = saturate(trail.r * 0.48);
    float etched = energyMask * hatch + saturate(trailEdge * 1.8);

    float programLum = luminance(program);
    float3 base = lerp(program, programLum.xxx, 0.72) * substrate;
    base *= 1.0 - energyMask * 0.35;

    float3 col = base;
    col += etched * trail_gain * float3(0.66, 0.69, 0.67);

    float livePulse = smoothstep(0.28, 1.15, liveMagnitude);
    float pulseBand = 0.5 + 0.5 * sin(dot(p, direction) * 19.0 - _Time * 0.31);
    float warm = livePulse * (0.25 + 0.75 * pulseBand) * saturate(trail.r);
    col += warm_signal * warm * warm_gain;

    float vignette = 1.0 - smoothstep(0.5, 0.96, length(p));
    col *= 0.76 + 0.24 * vignette;
    col = col / (1.0 + col);
    col = pow(saturate(col), 1.0 / 1.18);
    col += float3(0.0015, 0.0018, 0.0020);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
