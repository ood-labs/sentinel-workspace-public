struct BlobRecord
{
    float centroidX;
    float centroidY;
    float area;
    float x1;
    float y1;
    float x2;
    float y2;
    float colorR;
    float colorG;
    float colorB;
    float pad0;
    float pad1;
};

struct CornerRecord
{
    float x;
    float y;
    float response;
    float pad;
};

struct LineRecord
{
    float x1;
    float y1;
    float x2;
    float y2;
    float angle;
    float length;
    float pad0;
    float pad1;
};

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

StructuredBuffer<BlobRecord> BlobInput : register(t0);
StructuredBuffer<CornerRecord> CornerInput : register(t1);
StructuredBuffer<LineRecord> LineInput : register(t2);
StructuredBuffer<DebtQuantum> PreviousQuanta : register(t3);
RWStructuredBuffer<DebtQuantum> OutputBuffer : register(u0);

float2 pdNormalizePixel(float2 pixel)
{
    return float2(
        pixel.x / max(analysis_width, 1.0),
        pixel.y / max(analysis_height, 1.0)
    );
}

float2 pdSafeAxis(float2 value)
{
    float len = length(value);
    return len > 1e-5 ? value / len : float2(1.0, 0.0);
}

uint pdLedgerId(uint kindValue, uint sourceValue)
{
    return 0x50440000u | ((kindValue & 0xffu) << 8u) | (sourceValue & 0xffu);
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint outputIndex = tid.x;
    if (outputIndex >= 64u) return;

    DebtQuantum next;
    next.position = float2(0.5, 0.5);
    next.axis = float2(1.0, 0.0);
    next.mass = 0.0;
    next.radius = 0.0;
    next.kind = 0u;
    next.sourceIndex = 0u;
    next.ledgerId = 0u;
    next.active = 0u;
    next.phase = 0.0;
    next.age = 0.0;

    uint blobBudget = (uint)clamp(max_blob_quanta, 0, 8);
    uint cornerBudget = (uint)clamp(max_corner_quanta, 0, 40);
    uint lineBudget = (uint)clamp(max_line_quanta, 0, 16);

    if (outputIndex < blobBudget)
    {
        uint sourceIndex = outputIndex;
        if (sourceIndex < _Data0_Count)
        {
            BlobRecord source = BlobInput[sourceIndex];
            float2 bounds = max(float2(source.x2 - source.x1, source.y2 - source.y1), float2(1.0, 1.0));
            next.position = pdNormalizePixel(float2(source.centroidX, source.centroidY));
            next.axis = pdSafeAxis(float2(bounds.x, bounds.y) * float2(1.0, -1.0));
            next.mass = saturate(source.area / max(analysis_width * analysis_height, 1.0) * blob_mass_gain);
            next.radius = clamp(
                sqrt(max(source.area, 1.0) / 3.14159265) / max(analysis_height, 1.0) * blob_radius_gain,
                0.012,
                0.42
            );
            next.kind = 1u;
            next.sourceIndex = sourceIndex;
            next.ledgerId = pdLedgerId(next.kind, sourceIndex);
            next.active = 1u;
        }
    }
    else if (outputIndex < blobBudget + cornerBudget)
    {
        uint sourceIndex = outputIndex - blobBudget;
        if (sourceIndex < _Data1_Count)
        {
            CornerRecord source = CornerInput[sourceIndex];
            float2 position = pdNormalizePixel(float2(source.x, source.y));
            float2 leverageUv = leverage_origin * 0.5 + 0.5;
            next.position = position;
            next.axis = pdSafeAxis(position - leverageUv);
            next.mass = saturate(source.response / max(corner_response_reference, 0.001));
            next.radius = lerp(corner_radius_min, corner_radius_max, next.mass);
            next.kind = 2u;
            next.sourceIndex = sourceIndex;
            next.ledgerId = pdLedgerId(next.kind, sourceIndex);
            next.active = 1u;
        }
    }
    else if (outputIndex < blobBudget + cornerBudget + lineBudget)
    {
        uint sourceIndex = outputIndex - blobBudget - cornerBudget;
        if (sourceIndex < _Data2_Count)
        {
            LineRecord source = LineInput[sourceIndex];
            float2 a = pdNormalizePixel(float2(source.x1, source.y1));
            float2 b = pdNormalizePixel(float2(source.x2, source.y2));
            next.position = (a + b) * 0.5;
            next.axis = pdSafeAxis((b - a) * float2(1.0, -1.0));
            next.mass = saturate(source.length / max(line_length_reference, 1.0) * line_mass_gain);
            next.radius = clamp(source.length / max(analysis_width, analysis_height) * 0.5, 0.025, 0.32);
            next.kind = 3u;
            next.sourceIndex = sourceIndex;
            next.ledgerId = pdLedgerId(next.kind, sourceIndex);
            next.active = 1u;
        }
    }

    DebtQuantum previous = PreviousQuanta[outputIndex];
    bool compatible =
        previous.active != 0u &&
        previous.kind == next.kind &&
        previous.sourceIndex == next.sourceIndex;

    if (next.active != 0u)
    {
        float follow = 1.0 - exp(-max(temporal_follow, 0.01) * max(_DeltaTime, 0.0001) * 60.0);
        if (compatible)
        {
            next.position = lerp(previous.position, next.position, follow);
            next.axis = pdSafeAxis(lerp(previous.axis, next.axis, follow));
            next.mass = lerp(previous.mass, next.mass, follow);
            next.radius = lerp(previous.radius, next.radius, follow);
            next.age = previous.age + max(_DeltaTime, 0.0);
        }
        next.phase = frac(ledger_phase + (float)next.sourceIndex * 0.071 + (float)next.kind * 0.19);
    }

    OutputBuffer[outputIndex] = next;
}
