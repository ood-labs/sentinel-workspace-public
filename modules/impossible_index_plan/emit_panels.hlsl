struct PanelRecord {
    float2 center;
    float2 size;
    float angle;
    float depth;
    float kind;
    float palette;
    float group_id;
    float order_id;
    float fold;
    float pattern;
    float skew;
    float phase;
    float weight;
    float active;
};

RWStructuredBuffer<PanelRecord> PanelsOut : register(u0);

float hash11_local(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float2 hash21_local(float p) {
    return float2(hash11_local(p + 7.17), hash11_local(p + 41.73));
}

PanelRecord inactivePanel() {
    PanelRecord r = (PanelRecord)0;
    r.active = 0.0;
    return r;
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i >= 96u) return;

    int activeCount = clamp(panel_count, 12, 96);
    if ((int)i >= activeCount) {
        PanelsOut[i] = inactivePanel();
        return;
    }

    float fi = (float)i;
    float s = fi + (float)seed * 19.19;
    float2 h = hash21_local(s);
    float group = floor(fi / 12.0);
    float local = fmod(fi, 12.0);

    float2 grid = float2(fmod(local, 4.0), floor(local / 4.0));
    float2 base = float2(0.13 + grid.x * 0.245, 0.13 + grid.y * 0.31);
    base += float2(group * 0.041, group * -0.027);
    base += (h - 0.5) * float2(0.18, 0.14) * irregularity;

    float angleStep = angle_family == 0 ? 0.0 :
                      angle_family == 1 ? 0.785398163 :
                      angle_family == 2 ? 0.523598776 : 0.392699082;
    float angleIndex = floor(hash11_local(s + 3.0) * 5.0) - 2.0;

    PanelRecord r;
    r.center = (base - 0.5) * layout_scale + 0.5 + layout_offset;
    r.size = float2(
        lerp(0.10, 0.31, hash11_local(s + 11.0)),
        lerp(0.07, 0.25, hash11_local(s + 17.0))
    );
    r.size *= lerp(0.72, 1.36, hierarchy * hash11_local(s + 29.0));
    r.angle = angleStep * angleIndex;
    r.depth = lerp(-0.2, 1.0, hash11_local(s + 5.0)) + group * 0.035;
    r.kind = fmod(floor(hash11_local(s + 23.0) * 11.0), 5.0);
    r.palette = fmod(floor(hash11_local(s + 31.0) * 19.0), 8.0);
    r.group_id = group;
    r.order_id = fi;
    r.fold = lerp(-1.0, 1.0, hash11_local(s + 37.0));
    r.pattern = fmod(floor(hash11_local(s + 43.0) * 7.0), 4.0);
    r.skew = lerp(-0.45, 0.45, hash11_local(s + 47.0)) * irregularity;
    r.phase = hash11_local(s + 53.0);
    r.weight = lerp(0.25, 1.0, hash11_local(s + 59.0));
    r.active = 1.0;
    PanelsOut[i] = r;
}

