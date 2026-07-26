RWTexture2D<float4> OutputUAV : register(u0);

float hashEmitter(float n)
{
    return frac(sin(n * 91.117) * 43758.5453);
}

float emitterStroke(float2 uv, float2 center, float2 direction, float lengthScale, float width)
{
    float2 a = center - direction * lengthScale;
    float2 b = center + direction * lengthScale;
    float2 pa = uv - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.00001));
    float distanceToStroke = length(pa - ba * h);
    return 1.0 - smoothstep(width, width * 2.2, distanceToStroke);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint width;
    uint height;
    _Tex0.GetDimensions(width, height);
    if (DTid.x >= width || DTid.y >= height)
        return;

    float2 extent = max(float2(width, height), float2(1.0, 1.0));
    float2 uv = ((float2)DTid.xy + 0.5) / extent;
    float2 p = uv - 0.5;
    float phase = master_phase * 6.2831853;

    float curl = sin(p.y * 11.0 + phase * 0.45) * cos(p.x * 7.0 - phase * 0.22);
    float2 flow = float2(
        sin(p.y * 13.0 + phase) + curl * 0.7,
        cos(p.x * 9.0 - phase * 0.8) - curl * 0.55);
    flow *= advection * 0.0009;

    float4 previous = _Tex0.SampleLevel(LinearSampler, saturate(uv - flow), 0);
    float decayPerFrame = pow(saturate(memory_decay), min(max(_DeltaTime, 0.0), 0.1) * 60.0);
    float4 memory = previous * (master_play > 0.5 ? decayPerFrame : 1.0);

    if (master_scrub > 0.5)
        memory = 0.0;

    float whiteDeposit = 0.0;
    float warmDeposit = 0.0;
    [loop] for (int i = 0; i < 9; ++i)
    {
        if (i >= emitter_count)
            break;

        float fi = (float)i;
        float seed = hashEmitter(fi + 1.0);
        int historySteps = master_scrub > 0.5 ? 24 : 1;
        [loop] for (int j = 0; j < 24; ++j)
        {
            if (j >= historySteps)
                break;

            float historyPhase = phase - (float)j * 0.055;
            float localPhase = historyPhase * (0.55 + 0.08 * fi) + fi * 2.39996;
            float2 center = 0.5 + float2(
                sin(localPhase * 1.17 + seed * 3.0) * (0.21 + seed * 0.18),
                cos(localPhase * 0.83 - seed * 4.0) * (0.16 + (1.0 - seed) * 0.22));
            float2 direction = normalize(float2(cos(localPhase + seed * 6.0), sin(localPhase + seed * 6.0)));
            float stroke = emitterStroke(uv, center, direction, 0.006 + master_envelope * 0.012, 0.0014 + 0.0012 * seed);
            float historyFade = pow(0.94, (float)j);
            whiteDeposit = max(whiteDeposit, stroke * historyFade);
            if (i == 0 || i == emitter_count - 1)
                warmDeposit = max(warmDeposit, stroke * historyFade * (0.45 + master_pulse));
        }
    }

    memory.r = saturate(max(memory.r, whiteDeposit * deposit_gain));
    memory.g = saturate(max(memory.g, warmDeposit * accent_gain));
    memory.b = saturate(max(memory.b * 0.995, curl * 0.03 + 0.03));
    memory.a = 1.0;

    OutputUAV[DTid.xy] = memory;
}
