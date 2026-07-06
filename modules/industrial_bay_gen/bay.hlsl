// industrial_bay_gen - procedural 3D steel-mill structure generator.
// Emits StructPart records for columns, beams, braces, decks, pipes, ladders,
// roof lights, equipment boxes, and broken stubs.

struct StructPart {
    float3 center;
    float3 axis;
    float3 up;
    float3 half_extents;
    float length;
    float radius;
    float kind;
    float material;
    float seed;
    float group;
    float active;
    float spare;
};

RWStructuredBuffer<StructPart> Out : register(u0);

float h11(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float2 h22(float p)
{
    return float2(h11(p * 1.71 + 0.17), h11(p * 3.13 + 4.2));
}

float3 h33(float p)
{
    return float3(h11(p * 1.13 + 2.1), h11(p * 2.71 + 7.3), h11(p * 5.31 + 1.9));
}

float3 safeNorm(float3 v, float3 fallback)
{
    float l = length(v);
    return (l > 1e-4) ? (v / l) : fallback;
}

StructPart makePart(float3 c, float3 axis, float3 up, float3 he, float kind,
                    float mat, float sd, float groupId, float activeFlag)
{
    StructPart p;
    p.center = c;
    p.axis = safeNorm(axis, float3(0.0, 0.0, 1.0));
    p.up = safeNorm(up - p.axis * dot(up, p.axis), float3(0.0, 1.0, 0.0));
    p.half_extents = max(he, float3(0.001, 0.001, 0.001));
    p.length = he.z * 2.0;
    p.radius = max(max(he.x, he.y), he.z);
    p.kind = kind;
    p.material = mat;
    p.seed = sd;
    p.group = groupId;
    p.active = activeFlag;
    p.spare = 0.0;
    return p;
}

float presetDensity(float baseVal, float denseVal, float openVal, float pipeVal)
{
    if (preset == 1) return denseVal;
    if (preset == 2) return openVal;
    if (preset == 4) return pipeVal;
    return baseVal;
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 512u) return;

    StructPart p = makePart(0, float3(0,0,1), float3(0,1,0), float3(0.1,0.1,0.1),
                            0.0, 1.0, (float)i, 0.0, 0.0);

    int bxCount = clamp(bay_count_x, 2, 8);
    int bzCount = clamp(bay_count_z, 2, 8);
    int lvlCount = clamp(level_count, 2, 10);
    float sx = max(bay_spacing_x, 0.4);
    float sz = max(bay_spacing_z, 0.4);
    float sy = max(level_spacing, 0.4);
    float3 origin = float3(-0.5 * (float)(bxCount - 1) * sx, 0.0,
                           -0.5 * (float)(bzCount - 1) * sz);
    float height = (float)(lvlCount - 1) * sy + sy * 0.85;
    float sdBase = (float)seed * 97.0 + (float)preset * 311.0;

    float colD = saturate(column_density * presetDensity(1.0, 1.15, 0.72, 0.92));
    float beamD = saturate(primary_beam_density * presetDensity(1.0, 1.1, 0.65, 0.9));
    float braceD = saturate(brace_density * presetDensity(1.0, 1.35, 0.45, 0.85));
    float deckD = saturate(deck_density * presetDensity(1.0, 1.0, 0.35, 0.62));
    float pipeD = saturate(pipe_density * presetDensity(1.0, 1.25, 0.55, 1.75));

    if (i < 96u)
    {
        int n = bxCount * bzCount;
        if ((int)i < n)
        {
            int x = (int)i % bxCount;
            int z = (int)i / bxCount;
            float r = h11(sdBase + (float)i * 2.7);
            float foreground = (z == 0 || x == bxCount - 1) ? 0.22 * reference_composition_bias : 0.0;
            float live = (r < colD + foreground) ? 1.0 : 0.0;
            float3 c = origin + float3((float)x * sx, height * 0.5, (float)z * sz);
            c.xz += (h22(sdBase + (float)i) - 0.5) * skew_amount * 0.18;
            float w = column_width * lerp(0.78, 1.35, h11(sdBase + (float)i * 9.1));
            p = makePart(c, float3(0,1,0), float3(1,0,0), float3(w, w, height * 0.5),
                         0.0, 1.0, sdBase + (float)i, (float)(x + z * 16), live);
        }
    }
    else if (i < 288u)
    {
        uint j = i - 96u;
        int dir = (j & 1u) == 0u ? 0 : 1;
        int k = (int)(j >> 1u);
        int spansPerLevel = (bxCount - 1) * bzCount + bxCount * (bzCount - 1);
        int level = k / max(spansPerLevel, 1);
        int span = k - level * max(spansPerLevel, 1);
        if (level < lvlCount)
        {
            bool alongX = span < (bxCount - 1) * bzCount;
            int a = alongX ? (span % (bxCount - 1)) : (span % bxCount);
            int b = alongX ? (span / (bxCount - 1)) : ((span - (bxCount - 1) * bzCount) / bxCount);
            float3 c0 = origin + float3((float)a * sx, (float)level * sy, (float)b * sz);
            float3 c1 = c0 + (alongX ? float3(sx, 0, 0) : float3(0, 0, sz));
            float live = (h11(sdBase + (float)i * 5.3) < beamD * (1.0 - missing_span_rate)) ? 1.0 : 0.0;
            float3 mid = (c0 + c1) * 0.5;
            mid.y += lerp(-0.05, 0.06, h11(sdBase + (float)i * 2.2)) * skew_amount;
            float3 ax = c1 - c0;
            float len = length(ax);
            float thick = beam_thickness * lerp(0.78, 1.32, h11(sdBase + (float)i * 4.2));
            float hero = ((level == 1 || level == 2) && (b == 0 || a == bxCount - 2)) ? reference_composition_bias : 0.0;
            thick *= 1.0 + hero * 0.45;
            p = makePart(mid, ax, float3(0,1,0), float3(thick * 1.25, thick * 0.55, len * 0.5),
                         alongX ? 1.0 : 2.0, 1.0, sdBase + (float)i, (float)(level * 64 + span), live);
        }
    }
    else if (i < 352u)
    {
        uint j = i - 288u;
        int x = (int)(j % (uint)max(bxCount - 1, 1));
        int z = (int)((j / (uint)max(bxCount - 1, 1)) % (uint)max(bzCount - 1, 1));
        int level = (int)(j / (uint)max((bxCount - 1) * (bzCount - 1), 1));
        if (level < lvlCount - 1)
        {
            float flip = h11(sdBase + (float)i * 1.7) < 0.5 ? 0.0 : 1.0;
            float3 a = origin + float3((float)x * sx, (float)level * sy, (float)z * sz);
            float3 b = origin + float3((float)(x + 1) * sx, (float)(level + 1) * sy,
                                       (float)(z + (flip > 0.5 ? 1 : 0)) * sz);
            float3 d = b - a;
            float live = (h11(sdBase + (float)i * 8.1) < braceD) ? 1.0 : 0.0;
            p = makePart((a + b) * 0.5, d, float3(0,1,0),
                         float3(brace_radius * 1.2, brace_radius, length(d) * 0.5),
                         3.0, 2.0, sdBase + (float)i, (float)(level * 64 + x + z * 8), live);
        }
    }
    else if (i < 400u)
    {
        uint j = i - 352u;
        int level = (int)(j % (uint)max(lvlCount, 1));
        int side = (int)((j / (uint)max(lvlCount, 1)) % 4u);
        float3 c = float3(0, (float)level * sy - 0.08, 0);
        float longHalf = sx * (float)max(bxCount - 1, 1) * 0.35;
        float widthHalf = catwalk_width * lerp(0.7, 1.4, h11(sdBase + (float)i));
        float3 he = float3(widthHalf, deck_thickness, longHalf);
        if (side == 0) c.z = origin.z - sz * 0.22;
        if (side == 1) c.z = origin.z + (float)(bzCount - 1) * sz + sz * 0.22;
        if (side >= 2)
        {
            c.x = origin.x + (side == 2 ? -sx * 0.22 : (float)(bxCount - 1) * sx + sx * 0.22);
            c.z = 0.0;
            he = float3(widthHalf, deck_thickness, longHalf);
        }
        float live = (h11(sdBase + (float)i * 3.9) < deckD) ? 1.0 : 0.0;
        p = makePart(c, side >= 2 ? float3(0,0,1) : float3(1,0,0), float3(0,1,0),
                     he, 4.0, 2.0, sdBase + (float)i, (float)(level * 8 + side), live);
    }
    else if (i < 464u)
    {
        uint j = i - 400u;
        float r0 = h11(sdBase + (float)i * 2.2);
        float r1 = h11(sdBase + (float)i * 6.2);
        bool vertical = r0 < vertical_pipe_weight;
        float3 a;
        float3 b;
        if (vertical)
        {
            int x = (int)(j % (uint)bxCount);
            int z = (int)((j / (uint)bxCount) % (uint)bzCount);
            a = origin + float3((float)x * sx + (r1 - 0.5) * sx * 0.35, 0.2, (float)z * sz);
            b = a + float3(0, height * lerp(0.35, 0.95, h11(sdBase + (float)i * 1.4)), 0);
        }
        else
        {
            float y = (float)((int)j % lvlCount) * sy + sy * 0.25;
            a = origin + float3(-sx * 0.35, y, lerp(0.0, (float)(bzCount - 1) * sz, r1));
            b = origin + float3((float)(bxCount - 1) * sx + sx * 0.35, y + (h11(sdBase + (float)i) - 0.5) * sy * 0.2, a.z);
        }
        float3 d = b - a;
        float live = (h11(sdBase + (float)i * 4.4) < pipeD) ? 1.0 : 0.0;
        float pr = lerp(pipe_radius_min, pipe_radius_max, h11(sdBase + (float)i * 7.7));
        p = makePart((a + b) * 0.5, d, float3(0,1,0), float3(pr, pr, length(d) * 0.5),
                     6.0, 3.0, sdBase + (float)i, (float)j, live);
    }
    else if (i < 496u)
    {
        uint j = i - 464u;
        int x = (int)(j % (uint)bxCount);
        int z = (int)((j / (uint)bxCount) % (uint)bzCount);
        float side = h11(sdBase + (float)i * 1.5) < 0.5 ? -1.0 : 1.0;
        float3 c = origin + float3((float)x * sx + side * column_width * 2.1, height * 0.42, (float)z * sz);
        float live = (h11(sdBase + (float)i * 4.8) < ladder_density) ? 1.0 : 0.0;
        p = makePart(c, float3(0,1,0), float3(1,0,0), float3(0.16, 0.035, height * 0.26),
                     7.0, 3.0, sdBase + (float)i, (float)j, live);
    }
    else
    {
        uint j = i - 496u;
        float x = lerp(origin.x, origin.x + (float)(bxCount - 1) * sx, h11(sdBase + (float)i * 1.8));
        float z = lerp(origin.z, origin.z + (float)(bzCount - 1) * sz, h11(sdBase + (float)i * 3.8));
        float3 c = float3(x, height + 0.08, z);
        float3 he = float3(sx * lerp(0.18, 0.55, h11(sdBase + (float)i * 2.4)), 0.025,
                           sz * lerp(0.12, 0.42, h11(sdBase + (float)i * 5.4)));
        float live = (h11(sdBase + (float)i * 8.3) < skylight_density) ? 1.0 : 0.0;
        p = makePart(c, float3(1,0,0), float3(0,1,0), he, 9.0, 4.0, sdBase + (float)i, (float)j, live);
    }

    if (preset == 3 && h11(sdBase + (float)i * 12.7) < collapse_amount)
    {
        p.center += (h33(sdBase + (float)i) - 0.5) * float3(sx, sy, sz) * 0.35;
        p.axis = safeNorm(p.axis + (h33(sdBase + (float)i * 2.0) - 0.5) * collapse_amount, p.axis);
        if (h11(sdBase + (float)i * 18.1) < collapse_amount * 0.4) p.kind = 11.0;
    }

    Out[i] = p;
}
