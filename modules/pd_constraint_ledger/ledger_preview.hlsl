RWTexture2D<float4> OutputUAV : register(u0);

struct DebtQuantum
{
    float2 position;
    float2 axis;
    float mass;
    float radius;
    uint kind;
    uint sourceIndex;
    uint ledgerId;
    uint active;
    float phase;
    float age;
};

struct LedgerStats
{
    float activeCount;
    float meanMass;
    float macroMass;
    float meanAxisAngle;
};

StructuredBuffer<DebtQuantum> DebtInput : register(t0);
StructuredBuffer<LedgerStats> StatsInput : register(t1);

float pdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float pdStroke(float distanceValue, float width)
{
    float aa = 1.5 / max(_Resolution.y, 1.0);
    return 1.0 - smoothstep(width, width + aa, distanceValue);
}

float pdRing(float distanceValue, float radius, float width)
{
    return pdStroke(abs(distanceValue - radius), width);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float2 leverageUv = leverage_origin * 0.5 + 0.5;
    float2 leverageP = (leverageUv - 0.5) * float2(aspect, 1.0);

    float3 black = float3(0.003, 0.0035, 0.003);
    float3 white = float3(0.88, 0.895, 0.865);
    float3 graphite = float3(0.22, 0.235, 0.22);
    float3 liability = liability_color;
    float3 color = black;

    float2 gridUv = uv * float2(24.0, 14.0);
    float grid = 1.0 - saturate(min(abs(frac(gridUv.x) - 0.5), abs(frac(gridUv.y) - 0.5)) * 18.0);
    color += graphite * grid * 0.08;

    float blobMarks = 0.0;
    float cornerMarks = 0.0;
    float lineMarks = 0.0;
    float relationMarks = 0.0;
    float currentMarks = 0.0;

    [loop]
    for (uint i = 0u; i < 64u; ++i)
    {
        DebtQuantum quantum = DebtInput[i];
        if (quantum.active == 0u) continue;

        float2 qPosition = (quantum.position - 0.5) * float2(aspect, 1.0);
        float2 axis = normalize(quantum.axis * float2(1.0, -1.0));
        float2 side = float2(-axis.y, axis.x);
        float pulse = 0.5 + 0.5 * sin((quantum.phase + ledger_phase) * 6.2831853);

        if (quantum.kind == 1u)
        {
            float radius = max(0.025, quantum.radius);
            float bodyDistance = length((p - qPosition) * float2(0.78, 1.0));
            blobMarks = max(blobMarks, pdRing(bodyDistance, radius, 0.0022));
            blobMarks = max(blobMarks, pdRing(bodyDistance, radius * 0.52, 0.0011));
            relationMarks = max(
                relationMarks,
                pdStroke(pdSegment(p, qPosition, leverageP), 0.00075)
            );
            currentMarks = max(
                currentMarks,
                pdStroke(pdSegment(p, qPosition - axis * radius, qPosition + axis * radius), 0.0012) * pulse
            );
        }
        else if (quantum.kind == 2u)
        {
            float hingeLength = lerp(0.012, 0.035, quantum.mass);
            float2 a = qPosition - axis * hingeLength;
            float2 b = qPosition;
            float2 c = qPosition + side * hingeLength;
            cornerMarks = max(cornerMarks, pdStroke(pdSegment(p, a, b), 0.00115));
            cornerMarks = max(cornerMarks, pdStroke(pdSegment(p, b, c), 0.00115));
            cornerMarks = max(cornerMarks, pdRing(length(p - qPosition), 0.004 + quantum.mass * 0.003, 0.0010));
            relationMarks = max(
                relationMarks,
                pdStroke(pdSegment(p, qPosition, leverageP), 0.00045) * 0.45
            );
            currentMarks = max(currentMarks, pdRing(length(p - qPosition), hingeLength * 1.35, 0.0009) * pulse);
        }
        else if (quantum.kind == 3u)
        {
            float halfLength = max(0.03, quantum.radius * 0.85);
            lineMarks = max(
                lineMarks,
                pdStroke(pdSegment(p, qPosition - axis * halfLength, qPosition + axis * halfLength), 0.00165)
            );
            lineMarks = max(
                lineMarks,
                pdStroke(pdSegment(p, qPosition - side * 0.012, qPosition + side * 0.012), 0.0009)
            );
        }
    }

    color += liability * blobMarks * 1.15;
    color += white * cornerMarks;
    color += graphite * lineMarks * 1.7;
    color += graphite * relationMarks * relation_gain;
    color += liability * currentMarks * current_gain;

    LedgerStats stats = StatsInput[0];
    float barY = 0.945;
    float barHeight = 0.012;
    float activeWidth = saturate(stats.activeCount / 64.0) * 0.44;
    float massWidth = saturate(stats.meanMass) * 0.44;
    float activeBar = step(abs(uv.y - barY), barHeight) * step(0.05, uv.x) * step(uv.x, 0.05 + activeWidth);
    float massBar = step(abs(uv.y - (barY + 0.026)), barHeight) * step(0.05, uv.x) * step(uv.x, 0.05 + massWidth);
    color += white * activeBar * 0.8 + liability * massBar;

    float leverageMark = pdRing(length(p - leverageP), 0.028, 0.0014);
    leverageMark = max(leverageMark, pdStroke(pdSegment(p, leverageP - float2(0.045, 0.0), leverageP + float2(0.045, 0.0)), 0.0008));
    leverageMark = max(leverageMark, pdStroke(pdSegment(p, leverageP - float2(0.0, 0.045), leverageP + float2(0.0, 0.045)), 0.0008));
    color += liability * leverageMark;

    float border =
        step(0.018, uv.x) * step(uv.x, 0.982) *
        step(0.025, uv.y) * step(uv.y, 0.975);
    color *= border;

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
