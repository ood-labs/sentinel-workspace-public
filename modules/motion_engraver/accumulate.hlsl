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

    float3 program = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float2 encodedFlow = _Tex1.SampleLevel(LinearSampler, uv, 0).rg;
    float2 flow = (encodedFlow - 0.5) * 2.0;
    float magnitude = length(flow) * motion_gain;

    float l = luminance(program);
    float lL = luminance(_Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0.0), 0).rgb);
    float lR = luminance(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).rgb);
    float lU = luminance(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y), 0).rgb);
    float lD = luminance(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).rgb);
    float edge = abs(lR - lL) + abs(lD - lU);

    float2 previousUv = uv - flow * advection * 0.035;
    float inside = step(0.0, previousUv.x) * step(previousUv.x, 1.0)
                 * step(0.0, previousUv.y) * step(previousUv.y, 1.0);
    float4 previous = _Tex2.SampleLevel(LinearSampler, saturate(previousUv), 0) * inside;

    float keep = pow(saturate(memory), _DeltaTime * 60.0);
    float motionMask = smoothstep(0.035, 0.42, magnitude);
    float source = motionMask * (0.08 + edge * 2.8 + l * 0.16) * injection;
    float sourceStep = source * _DeltaTime * 60.0;

    float energy = min(previous.r * keep + sourceStep, 4.0);
    float angle = atan2(flow.y, flow.x) / 6.2831853 + 0.5;
    float angleBlend = saturate(sourceStep * 2.5);
    float direction = lerp(previous.g, angle, angleBlend);
    float speed = lerp(previous.b * keep, saturate(magnitude * 0.65), angleBlend);

    OutputUAV[pixel] = float4(energy, direction, speed, 1.0);
}
