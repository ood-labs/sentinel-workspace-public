struct RibbonRecord {
    float2 p0;
    float2 p1;
    float width;
    float feather;
    float material;
    float layer;
    float phase;
    float speed;
    float warp;
    float opacity;
    float2 uv_offset;
    float active;
    float reserved;
};

RWStructuredBuffer<RibbonRecord> RibbonsOut : register(u0);

float rp_hash(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

[numthreads(32, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i >= 24u) return;

    RibbonRecord r = (RibbonRecord)0;
    int count = clamp(ribbon_count, 4, 24);
    if ((int)i >= count) {
        RibbonsOut[i] = r;
        return;
    }

    float fi = (float)i;
    float seedf = fi + (float)ribbon_seed * 17.31;
    float lane = (fi + 0.5) / (float)count;
    float localPhase = frac(master_phase + rp_hash(seedf + 7.0));
    float direction = (fmod(fi, 2.0) < 1.0) ? 1.0 : -1.0;
    float travel = sin((master_phase + rp_hash(seedf + 7.0)) * 6.2831853) * travel_amount * 0.5 * direction;
    float jitter = (rp_hash(seedf + 13.0) - 0.5) * irregularity;

    float y = lane + travel + jitter * 0.16;
    float slope = lerp(-0.58, 0.58, rp_hash(seedf + 19.0));
    slope += rupture.y * 0.28;
    float inset = lerp(-0.28, 0.08, rp_hash(seedf + 23.0));

    r.p0 = float2(inset, y - slope * 0.5);
    r.p1 = float2(1.0 - inset, y + slope * 0.5);
    r.width = lerp(0.025, 0.145, rp_hash(seedf + 29.0)) * width_scale;
    r.feather = lerp(0.002, 0.018, rp_hash(seedf + 31.0));
    r.material = fmod(floor(rp_hash(seedf + 37.0) * 7.0), 4.0);
    r.layer = floor(rp_hash(seedf + 41.0) * 6.0);
    r.phase = localPhase;
    r.speed = lerp(0.25, 1.45, rp_hash(seedf + 43.0)) * direction;
    r.warp = lerp(-1.0, 1.0, rp_hash(seedf + 47.0)) * warp_amount;
    r.opacity = lerp(0.38, 1.0, rp_hash(seedf + 53.0));
    r.uv_offset = float2(rp_hash(seedf + 59.0), rp_hash(seedf + 61.0));
    r.active = 1.0;
    r.reserved = 0.0;
    RibbonsOut[i] = r;
}
