RWTexture2D<float4> OutputUAV : register(u0);

float lineSegment(float2 p, float2 a, float2 b, float width)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.00001));
    return 1.0 - smoothstep(width, width * 1.8, length(pa - ba * h));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= (uint)_Resolution.x || DTid.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)DTid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float4 memory = _Tex0.SampleLevel(LinearSampler, uv, 0);

    float whiteInk = smoothstep(trace_threshold, trace_threshold + 0.12, memory.r);
    float warmInk = smoothstep(0.12, 0.68, memory.g);
    float field = saturate(memory.b * 2.0);

    float3 black = float3(0.004, 0.004, 0.005);
    float3 gray = float3(0.17, 0.175, 0.185);
    float3 white = float3(0.91, 0.92, 0.93);
    float3 warm = float3(0.98, 0.44, 0.11);

    float3 color = black + gray * field * 0.10;
    color = lerp(color, white, whiteInk);
    color = lerp(color, warm, warmInk * accent_gain);

    float frame = 1.0 - smoothstep(0.0015, 0.004, abs(max(abs(p.x) - aspect * 0.47, abs(p.y) - 0.45)));
    color = lerp(color, white, frame * 0.58);

    float registration = 0.0;
    registration = max(registration, lineSegment(p, float2(-aspect * 0.46, -0.38), float2(-aspect * 0.39, -0.38), 0.0012));
    registration = max(registration, lineSegment(p, float2(-aspect * 0.425, -0.415), float2(-aspect * 0.425, -0.345), 0.0012));
    registration = max(registration, lineSegment(p, float2(aspect * 0.39, 0.38), float2(aspect * 0.46, 0.38), 0.0012));
    registration = max(registration, lineSegment(p, float2(aspect * 0.425, 0.345), float2(aspect * 0.425, 0.415), 0.0012));
    color = lerp(color, master_play > 0.5 ? warm : gray, registration * 0.75);

    OutputUAV[DTid.xy] = float4(saturate(color), 1.0);
}
