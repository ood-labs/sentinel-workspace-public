struct RouteRecord {
    float2 p0;
    float2 p1;
    float width;
    float palette;
    float group_id;
    float phase;
    float dash;
    float elevation;
    float active;
    float reserved;
};

RWStructuredBuffer<RouteRecord> RoutesOut : register(u0);

float hash_route(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i >= 48u) return;

    int activeCount = clamp(route_count, 6, 48);
    RouteRecord r = (RouteRecord)0;
    if ((int)i >= activeCount) {
        RoutesOut[i] = r;
        return;
    }

    float fi = (float)i;
    float s = fi + (float)seed * 13.7;
    float lane = fmod(fi, 12.0) / 11.0;
    bool horizontal = fmod(fi, 3.0) < 1.5;
    float jitter = (hash_route(s + 4.0) - 0.5) * 0.20 * irregularity;
    float endInset = lerp(0.02, 0.22, hash_route(s + 9.0));

    if (horizontal) {
        float y = 0.06 + lane * 0.88 + jitter;
        r.p0 = float2(endInset, y);
        r.p1 = float2(1.0 - endInset, y + (hash_route(s + 14.0) - 0.5) * 0.34);
    } else {
        float x = 0.06 + lane * 0.88 + jitter;
        r.p0 = float2(x, endInset);
        r.p1 = float2(x + (hash_route(s + 18.0) - 0.5) * 0.34, 1.0 - endInset);
    }

    r.p0 = (r.p0 - 0.5) * layout_scale + 0.5 + layout_offset;
    r.p1 = (r.p1 - 0.5) * layout_scale + 0.5 + layout_offset;
    r.width = lerp(0.0015, 0.008, hash_route(s + 21.0)) * route_weight;
    r.palette = fmod(floor(hash_route(s + 27.0) * 13.0), 4.0);
    r.group_id = floor(fi / 4.0);
    r.phase = hash_route(s + 31.0);
    r.dash = lerp(0.15, 0.9, hash_route(s + 37.0));
    r.elevation = lerp(-0.2, 1.2, hash_route(s + 43.0));
    r.active = 1.0;
    r.reserved = 0.0;
    RoutesOut[i] = r;
}

