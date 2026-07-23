struct GlyphRecord
{
    float2 position;
    float2 direction;
    float weight;
    float kind;
    float group_id;
    float active;
};

StructuredBuffer<GlyphRecord> Previous : register(t1);
RWStructuredBuffer<GlyphRecord> GlyphsOut : register(u0);

static const float2 ANALYSIS_SIZE = float2(480.0, 270.0);
static const float ANALYSIS_AREA = 129600.0;
static const float PI = 3.14159265359;
static const float TAU = 6.28318530718;

GlyphRecord emptyGlyph()
{
    GlyphRecord g;
    g.position = 0.0;
    g.direction = float2(1.0, 0.0);
    g.weight = 0.0;
    g.kind = 0.0;
    g.group_id = 0.0;
    g.active = 0.0;
    return g;
}

GlyphRecord blobGlyph(uint i)
{
    GlyphRecord g = emptyGlyph();
    float2 pos = float2(_Data0[i].centroidX, _Data0[i].centroidY) / ANALYSIS_SIZE;
    pos += composition_bias;

    float2 extent = max(
        float2(_Data0[i].x2 - _Data0[i].x1, _Data0[i].y2 - _Data0[i].y1) / ANALYSIS_SIZE,
        float2(1e-4, 1e-4)
    );
    float2 boxAxis = normalize(float2(extent.x, extent.y));
    float2 radial = normalize(pos - 0.5 + float2(1e-5, 0.0));
    float2 tangent = float2(-radial.y, radial.x);
    float twist = saturate(radial_twist * 0.5 + 0.5);
    float2 fieldDirection = normalize(lerp(radial, tangent, twist));

    g.position = saturate(pos);
    g.direction = normalize(lerp(fieldDirection, boxAxis, shape_direction));
    g.weight = saturate(sqrt(max(_Data0[i].area, 0.0) / ANALYSIS_AREA) * blob_area_gain);
    g.kind = 0.0;
    float angle = atan2(radial.y, radial.x) + PI;
    g.group_id = floor(frac(angle / TAU) * (float)clamp(group_count, 2, 8));
    g.active = 1.0;
    return g;
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint blobCount = min(_Data0_Count, 8u);
    uint matchedMask = 0u;
    float dt = clamp(_DeltaTime, 0.0, 0.1);
    float follow = 1.0 - exp(-dt * tracking_response);
    float directionFollow = 1.0 - exp(-dt * tracking_response * 0.55);

    GlyphRecord next[8];

    // Preserve track identity by nearest-neighbor association with the prior
    // stabilized positions. Blob array reordering no longer reindexes the graph.
    [unroll]
    for (uint slot = 0u; slot < 8u; ++slot)
    {
        GlyphRecord old = Previous[slot];
        next[slot] = old;

        if (old.active > 0.01)
        {
            float bestDistance = 100.0;
            int bestIndex = -1;
            [unroll]
            for (uint j = 0u; j < 8u; ++j)
            {
                if (j >= blobCount || (matchedMask & (1u << j)) != 0u) continue;
                GlyphRecord candidate = blobGlyph(j);
                float d = length(candidate.position - old.position);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    bestIndex = (int)j;
                }
            }

            if (bestIndex >= 0 && bestDistance < match_radius)
            {
                GlyphRecord target = blobGlyph((uint)bestIndex);
                matchedMask |= 1u << (uint)bestIndex;
                next[slot].position = lerp(old.position, target.position, follow);
                next[slot].direction = normalize(lerp(old.direction, target.direction, directionFollow));
                next[slot].weight = lerp(old.weight, target.weight, follow);
                next[slot].group_id = target.group_id;
                next[slot].kind = 0.0;
                next[slot].active = min(1.0, old.active + dt * attack_rate);
            }
            else
            {
                next[slot].active = max(0.0, old.active - dt * release_rate);
                next[slot].weight *= exp(-dt * release_rate * 0.6);
            }
        }
        else
        {
            next[slot] = emptyGlyph();
        }
    }

    // New regions enter only into fully released slots and ramp on gradually.
    [unroll]
    for (uint j = 0u; j < 8u; ++j)
    {
        if (j >= blobCount || (matchedMask & (1u << j)) != 0u) continue;
        [unroll]
        for (uint slot = 0u; slot < 8u; ++slot)
        {
            if (next[slot].active <= 0.01)
            {
                next[slot] = blobGlyph(j);
                next[slot].active = min(1.0, dt * attack_rate);
                matchedMask |= 1u << j;
                break;
            }
        }
    }

    [unroll]
    for (uint slot = 0u; slot < 8u; ++slot)
    {
        GlyphsOut[slot] = next[slot];
    }
    [unroll]
    for (uint slot = 8u; slot < 64u; ++slot)
    {
        GlyphsOut[slot] = emptyGlyph();
    }
}
