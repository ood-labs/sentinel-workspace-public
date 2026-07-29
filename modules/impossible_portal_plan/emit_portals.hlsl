struct PortalRecord {
    float2 center;
    float radius;
    float thickness;
    float rotation;
    float sector_count;
    float depth;
    float material;
    float phase;
    float speed;
    float2 eccentricity;
    float opacity;
    float scale;
    float active;
    float reserved;
};

RWStructuredBuffer<PortalRecord> PortalsOut : register(u0);

float pp_hash(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

[numthreads(16, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i >= 16u) return;

    PortalRecord r = (PortalRecord)0;
    int count = clamp(portal_count, 3, 16);
    if ((int)i >= count) {
        PortalsOut[i] = r;
        return;
    }

    float fi = (float)i;
    float seedf = fi + (float)portal_seed * 11.71;
    float ring = floor(fi / 5.0);
    float spoke = fmod(fi, 5.0) / 5.0;
    float direction = pp_hash(seedf + 3.0) < 0.5 ? -1.0 : 1.0;
    float a = spoke * 6.2831853 + ring * 0.81 + master_phase * 6.2831853 * direction;
    float orbit = lerp(0.05, 0.36, pp_hash(seedf + 7.0)) * spread;
    float2 motion = float2(cos(a), sin(a)) * orbit;

    r.center = 0.5 + focus * 0.18 + motion;
    r.radius = lerp(0.055, 0.21, pp_hash(seedf + 13.0)) * radius_scale;
    r.thickness = lerp(0.004, 0.024, pp_hash(seedf + 17.0));
    r.rotation = a + lerp(-1.2, 1.2, pp_hash(seedf + 19.0));
    r.sector_count = floor(lerp(3.0, 13.0, pp_hash(seedf + 23.0)));
    r.depth = lerp(-0.4, 1.4, pp_hash(seedf + 29.0)) * depth_spread;
    r.material = fmod(floor(pp_hash(seedf + 31.0) * 7.0), 3.0);
    r.phase = frac(master_phase + pp_hash(seedf + 37.0));
    r.speed = direction * lerp(0.45, 1.1, pp_hash(seedf + 41.0));
    r.eccentricity = float2(
        lerp(0.72, 1.28, pp_hash(seedf + 43.0)),
        lerp(0.72, 1.28, pp_hash(seedf + 47.0))
    );
    r.opacity = lerp(0.42, 1.0, pp_hash(seedf + 53.0));
    r.scale = lerp(0.72, 1.55, pp_hash(seedf + 59.0));
    r.active = 1.0;
    r.reserved = 0.0;
    PortalsOut[i] = r;
}
