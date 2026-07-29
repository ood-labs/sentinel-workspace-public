struct RouteRecord {
    float2 p0; float2 p1;
    float width; float palette; float group_id; float phase;
    float dash; float elevation; float active; float reserved;
};

StructuredBuffer<RouteRecord> Routes : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float hash_weave(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float sdSegmentWeave(float2 p, float2 a, float2 b, out float along) {
    float2 pa = p - a;
    float2 ba = b - a;
    along = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * along);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = float2((uv.x - 0.5) * aspect, uv.y - 0.5);
    float2 px = 1.0 / _Resolution.xy;
    float4 src = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float3 col = src.rgb;

    // Quiet the extreme edges into an editorial trim field.
    float sideTrim = smoothstep(trim_width + px.x * 2.0, trim_width, min(uv.x, 1.0 - uv.x));
    float bottomTrim = smoothstep(trim_width * 0.62 + px.y * 2.0, trim_width * 0.62, 1.0 - uv.y);
    float trim = max(sideTrim, bottomTrim);
    col = lerp(col, trim_color, trim * trim_opacity);

    // Record-derived route hierarchy: only high-elevation records become hero rails.
    [loop]
    for (uint i = 0u; i < 48u; ++i) {
        RouteRecord r = Routes[i];
        if (r.active < 0.5 || r.elevation < elevation_gate) continue;
        float2 a = float2((r.p0.x - 0.5) * aspect, r.p0.y - 0.5);
        float2 b = float2((r.p1.x - 0.5) * aspect, r.p1.y - 0.5);
        float along;
        float d = sdSegmentWeave(p, a, b, along);
        float movingWindow = smoothstep(0.0, 0.08, along) *
                             smoothstep(1.0, 0.92, along) *
                             step(0.26, frac(along * (2.0 + r.dash * 7.0) + r.phase + weave_phase));
        float rail = smoothstep(r.width * hero_width + 1.5 / _Resolution.y,
                                r.width * hero_width, d) * movingWindow;
        float3 railColor = r.palette < 0.5 ? float3(0.94, 0.045, 0.025) :
                           r.palette < 1.5 ? float3(0.98, 0.34, 0.02) :
                           r.palette < 2.5 ? float3(0.03, 0.80, 0.20) :
                                             float3(0.94, 0.92, 0.86);
        col = lerp(col, railColor, rail * hero_gain);

        // Endpoint registration rings attach directly to the route endpoints.
        float da = length(p - a);
        float db = length(p - b);
        float ring = max(
            smoothstep(1.8 / _Resolution.y, 0.0, abs(da - endpoint_radius)),
            smoothstep(1.8 / _Resolution.y, 0.0, abs(db - endpoint_radius))
        );
        col = lerp(col, railColor, ring * endpoint_gain);
    }

    // A live index strip: cells correspond to route groups, never invented telemetry.
    float stripY = 1.0 - trim_width * 0.31;
    float inStrip = step(abs(uv.y - stripY), trim_width * 0.16) *
                    step(trim_width * 1.4, uv.x) * step(uv.x, 1.0 - trim_width * 1.4);
    float stripCell = floor((uv.x - trim_width * 1.4) /
                            max(1.0 - trim_width * 2.8, 0.01) * 12.0);
    float cellParity = fmod(stripCell, 2.0);
    float3 stripCol = lerp(float3(0.94, 0.92, 0.86), float3(0.02, 0.022, 0.03), cellParity);
    col = lerp(col, stripCol, inStrip * index_strip_gain);

    // Microtype-like bars are measured from group count and route phase.
    float leftRail = step(uv.x, trim_width * 0.72) * step(trim_width * 0.75, uv.y) * step(uv.y, 0.92);
    float row = floor((uv.y - trim_width) * 42.0);
    float rowFrac = frac((uv.y - trim_width) * 42.0);
    float liveWidth = 0.18 + 0.72 * hash_weave(row + floor(weave_phase * 12.0));
    float bar = step(rowFrac, 0.18) * step(uv.x / max(trim_width * 0.72, 0.001), liveWidth);
    col = lerp(col, float3(0.94, 0.92, 0.86), leftRail * bar * microbar_gain);

    // Print registration cross derived from the active weave phase.
    float2 regCenter = float2(
        trim_width * 0.50,
        0.18 + 0.62 * frac(weave_phase + 0.17)
    );
    float2 rp = float2((uv.x - regCenter.x) * aspect, uv.y - regCenter.y);
    float cross = max(
        smoothstep(1.6 / _Resolution.y, 0.0, abs(rp.x)) * step(abs(rp.y), 0.020),
        smoothstep(1.6 / _Resolution.y, 0.0, abs(rp.y)) * step(abs(rp.x), 0.020)
    );
    col = lerp(col, float3(0.94, 0.045, 0.025), cross * registration_gain);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}

