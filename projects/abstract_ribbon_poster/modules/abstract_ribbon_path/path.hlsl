// abstract_ribbon_path: semantic Y-up ribbon handles -> previewable PNode path buffer.

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight; float group; float kind; float seed; float active;
};

RWStructuredBuffer<PNode> Out : register(u0);

static const float TAU = 6.2831853;
static const int CP_COUNT = 8;

float2 rot2(float2 v, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float2 cpRaw(int idx)
{
    idx = (idx % CP_COUNT + CP_COUNT) % CP_COUNT;
    if (idx == 0) return top_lip;
    if (idx == 1) return left_shoulder;
    if (idx == 2) return left_belly;
    if (idx == 3) return lower_tip;
    if (idx == 4) return right_belly;
    if (idx == 5) return right_lip;
    if (idx == 6) return inner_throat;
    return inner_fold;
}

float2 cp(int idx)
{
    float2 p = cpRaw(idx);
    p = (p - ribbon_center) * ribbon_scale;
    p = rot2(p, rotation);
    return p + ribbon_center + global_offset;
}

float2 catmull(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float2 a = 2.0 * p1;
    float2 b = p2 - p0;
    float2 c = 2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3;
    float2 d = -p0 + 3.0 * p1 - 3.0 * p2 + p3;
    return 0.5 * (a + b * t + c * t * t + d * t * t * t);
}

float2 catmullTan(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float2 b = p2 - p0;
    float2 c = 2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3;
    float2 d = -p0 + 3.0 * p1 - 3.0 * p2 + p3;
    return 0.5 * (b + 2.0 * c * t + 3.0 * d * t * t);
}

float gauss01(float x, float c, float w)
{
    float d = min(abs(x - c), 1.0 - abs(x - c));
    return exp(-(d * d) / max(w * w, 1e-4));
}

float widthAt(float u)
{
    float w = width_base;
    w += width_lower * gauss01(u, lower_width_u, 0.17);
    w += width_right * gauss01(u, right_width_u, 0.18);
    w -= width_top_cut * gauss01(u, top_thin_u, 0.13);
    return max(w, 0.004);
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 160u) return;

    PNode p;
    p.pos = float2(0, 0);
    p.dir = float2(1, 0);
    p.depth = 0.55;
    p.u = 0;
    p.v = 0;
    p.weight = 0;
    p.group = 0;
    p.kind = 0;
    p.seed = (float)i;
    p.active = 0;

    int sampleCount = clamp(active_samples, 8, 160);
    if ((int)i < sampleCount)
    {
        float u = ((float)i + phase_offset) / (float)sampleCount;
        u = frac(u);
        float s = u * (float)CP_COUNT;
        int seg = (int)floor(s);
        float f = frac(s);

        float2 p0 = cp(seg - 1);
        float2 p1 = cp(seg);
        float2 p2 = cp(seg + 1);
        float2 p3 = cp(seg + 2);

        float2 pos = catmull(p0, p1, p2, p3, f);
        float2 tanv = normalize(catmullTan(p0, p1, p2, p3, f) + 1e-5);
        float2 n = float2(-tanv.y, tanv.x);

        float anim = _Time * animation_rate;
        float breathe = (sin(anim * TAU + u * TAU) * 0.5 + 0.5) * breathe_amount;
        pos += n * sin(u * TAU * wave_count + anim * TAU) * wave_amount;

        p.pos = pos;
        p.dir = tanv;
        p.depth = lerp(0.36, 0.78, 0.5 + 0.5 * sin(u * TAU + depth_phase));
        p.u = u;
        p.v = f;
        p.weight = widthAt(u) * (1.0 + breathe);
        p.group = 0.0;
        p.kind = gauss01(u, fold_u, fold_width);
        p.seed = (float)i + (float)seed * 97.0;
        p.active = 1.0;
    }

    Out[i] = p;
}
