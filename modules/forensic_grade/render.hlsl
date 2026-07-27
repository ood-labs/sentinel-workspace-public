struct EvidenceAgent
{
    float2 position;
    float2 direction;
    float weight;
    float radius;
    uint kind;
    uint sourceIndex;
    uint groupId;
    uint active;
    float phase;
    float pad;
};

StructuredBuffer<EvidenceAgent> Agents : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float pixelHash(uint2 p)
{
    uint n = p.x * 1973u + p.y * 9277u + 89173u;
    n = (n << 13u) ^ n;
    return (float)(n * (n * n * 15731u + 789221u) + 1376312589u) / 4294967295.0;
}

float stroke(float d, float width)
{
    float px = 1.25 / max(_Resolution.y, 1.0);
    return 1.0 - smoothstep(width, width + px, d);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float3 src = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float warm = saturate(src.r - max(src.g, src.b) * accent_separation);
    float luma = luminance(src);
    luma = saturate((luma - black_point) / max(white_point - black_point, 1e-4));
    luma = pow(luma, max(contrast_curve, 0.05));

    float paperNoise = (pixelHash(tid.xy) - 0.5) * grain_amount;
    float screen = 0.5 + 0.5 * sin((uv.x * aspect + uv.y) * halftone_frequency * 6.2831853);
    float printLuma = luma + paperNoise + (screen - 0.5) * halftone_amount;
    float bands = max(tone_steps, 2.0);
    printLuma = floor(saturate(printLuma) * bands + 0.5) / bands;

    float3 paper = float3(0.82, 0.84, 0.81);
    float3 ink = float3(0.003, 0.0035, 0.0035);
    float3 graphite = float3(0.17, 0.18, 0.17);
    float3 current = current_color;

    float3 col;
    if (print_mode == 0)
        col = lerp(ink, paper, printLuma);
    else if (print_mode == 1)
        col = lerp(ink, graphite + paper * 0.55, printLuma);
    else
        col = lerp(paper * 0.92, ink, printLuma);

    col = lerp(col, current, warm * accent_gain);

    // Active Evidence Agents create truthful registration ticks.
    float tickInk = 0.0;
    float strongestWeight = 0.0;
    float2 strongestPos = float2(0.5, 0.5);
    [unroll]
    for (uint i = 0u; i < 64u; ++i)
    {
        EvidenceAgent a = Agents[i];
        if (a.active == 0u) continue;
        float x = ((float)i + 0.5) / 64.0;
        float tick = step(abs(uv.x - x), 0.0008) * step(0.955, uv.y);
        tickInk = max(tickInk, tick * (0.25 + a.weight));
        if (a.weight > strongestWeight)
        {
            strongestWeight = a.weight;
            strongestPos = a.position;
        }
    }
    col += paper * tickInk * telemetry_gain;

    // Strongest current record gets one quiet registration target.
    float2 q = (uv - strongestPos) * float2(aspect, 1.0);
    float target = stroke(abs(length(q) - 0.016), 0.0012);
    target = max(target, stroke(abs(q.x), 0.0007) * step(abs(q.y), 0.026));
    target = max(target, stroke(abs(q.y), 0.0007) * step(abs(q.x), 0.026));
    col += current * target * strongestWeight * target_gain;

    float frame = stroke(abs(max(abs(p.x) - aspect * crop_extent, abs(p.y) - crop_extent * 0.9375)), 0.0012);
    col += paper * frame * frame_gain;

    float vignette = saturate(1.0 - dot(p * float2(0.55, 0.9), p * float2(0.55, 0.9)) * vignette_gain);
    col *= lerp(0.35, 1.0, vignette);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
