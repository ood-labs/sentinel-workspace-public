struct FaceRecord {
    float2 center; float2 size;
    float2 axis_x; float2 axis_y;
    float depth; float face_kind; float palette; float pattern;
    float source_id; float group_id; float phase; float active;
};
struct RouteRecord {
    float2 p0; float2 p1;
    float width; float palette; float group_id; float phase;
    float dash; float elevation; float active; float reserved;
};

StructuredBuffer<FaceRecord> Faces : register(t0);
StructuredBuffer<RouteRecord> Routes : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float hash_print(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float3 paletteColor(int idx) {
    if (idx == 0) return paper_color;
    if (idx == 1) return ink_color;
    if (idx == 2) return float3(0.025, 0.085, 0.23);
    if (idx == 3) return float3(0.93, 0.055, 0.035);
    if (idx == 4) return float3(0.98, 0.34, 0.025);
    if (idx == 5) return float3(0.94, 0.13, 0.47);
    if (idx == 6) return float3(0.04, 0.80, 0.22);
    return float3(0.47, 0.50, 0.53);
}

float orientedBox(float2 uv, FaceRecord f, float aspect, out float2 q, out float2 halfSize) {
    float2 p = float2((uv.x - f.center.x) * aspect, uv.y - f.center.y);
    float2 ax = normalize(float2(f.axis_x.x * aspect, f.axis_x.y));
    float2 ay = normalize(float2(f.axis_y.x * aspect, f.axis_y.y));
    q = float2(dot(p, ax), dot(p, ay));
    halfSize = max(f.size * float2(aspect, 1.0) * 0.5, 0.0005.xx);
    float2 d = abs(q) - halfSize;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdSegmentInfo(float2 p, float2 a, float2 b, out float along) {
    float2 pa = p - a;
    float2 ba = b - a;
    along = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * along);
}

float panelPattern(FaceRecord f, float2 q, float2 b) {
    float2 n = q / max(b, 0.0001.xx);
    int mode = (int)f.pattern;
    if (mode == 0) {
        float bars = step(0.70, frac((n.y + 1.0) * pattern_scale * 2.2 + f.source_id * 0.17));
        return bars * step(abs(n.x), 0.82);
    }
    if (mode == 1) {
        float2 cell = floor((n + 1.0) * pattern_scale);
        return fmod(cell.x + cell.y, 2.0);
    }
    if (mode == 2) {
        float2 cell = frac((n + 1.0) * pattern_scale * float2(1.4, 1.0)) - 0.5;
        float tooth = step(abs(cell.y + cell.x * 0.52), 0.20) +
                      step(length(cell - float2(0.22, -0.18)), 0.18);
        return saturate(tooth);
    }
    float diagonal = step(0.0, n.x + n.y * 0.72 + sin(f.source_id) * 0.22);
    return diagonal;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = float2((uv.x - 0.5) * aspect, uv.y - 0.5);
    float aa = 1.25 / _Resolution.y;

    float3 col = paper_color * (0.94 + 0.06 * uv.y);
    float pageGrid = min(abs(frac(uv.x * 18.0) - 0.5), abs(frac(uv.y * 10.0) - 0.5));
    col = lerp(col, ink_color, smoothstep(0.018, 0.0, pageGrid) * grid_ink);

    float checkerBand = step(0.78, uv.y) * step(0.5, frac(uv.x * 18.0));
    col = lerp(col, ink_color, checkerBand * 0.92);
    float mast = smoothstep(0.022, 0.0, abs(uv.x - 0.055)) * step(0.08, uv.y) * step(uv.y, 0.92);
    col = lerp(col, float3(0.93, 0.055, 0.035), mast);

    // Pass 1: shadow/back records.
    [loop]
    for (uint i = 2u; i < 288u; i += 3u) {
        FaceRecord f = Faces[i];
        if (f.active < 0.5) continue;
        float2 ruptureDelta = rupture_vector * rupture_strength *
            smoothstep(0.48, 0.0, distance(f.center, focus_point)) *
            (0.35 + 0.65 * hash_print(f.source_id + 2.0));
        f.center += ruptureDelta;
        float2 q, b;
        float d = orientedBox(uv, f, aspect, q, b);
        float fill = smoothstep(aa * 1.5, -aa * 1.5, d);
        col = lerp(col, ink_color * 0.32, fill * shadow_opacity);
    }

    // Pass 2: fold/side records.
    [loop]
    for (uint j = 1u; j < 288u; j += 3u) {
        FaceRecord f = Faces[j];
        if (f.active < 0.5) continue;
        float2 ruptureDelta = rupture_vector * rupture_strength *
            smoothstep(0.48, 0.0, distance(f.center, focus_point)) *
            (0.35 + 0.65 * hash_print(f.source_id + 2.0));
        f.center += ruptureDelta;
        float2 q, b;
        float d = orientedBox(uv, f, aspect, q, b);
        float fill = smoothstep(aa, -aa, d);
        float edge = smoothstep(aa * outline_width, 0.0, abs(d));
        float3 fc = paletteColor((int)f.palette) * (0.52 + 0.20 * saturate(f.depth + 0.2));
        col = lerp(col, fc, fill * 0.96);
        col = lerp(col, ink_color, edge * 0.88);
    }

    // Pass 3: front faces and their attached record-derived pattern language.
    [loop]
    for (uint k = 0u; k < 288u; k += 3u) {
        FaceRecord f = Faces[k];
        if (f.active < 0.5) continue;
        float focal = smoothstep(0.58, 0.0, distance(f.center, focus_point));
        float2 ruptureDelta = rupture_vector * rupture_strength * focal *
            (0.35 + 0.65 * hash_print(f.source_id + 2.0));
        f.center += ruptureDelta;
        float2 q, b;
        float d = orientedBox(uv, f, aspect, q, b);
        float fill = smoothstep(aa, -aa, d);
        float edge = smoothstep(aa * outline_width, 0.0, abs(d));
        float3 base = paletteColor((int)f.palette);
        float shade = 0.82 + 0.18 * saturate(f.depth + 0.25);
        float patt = panelPattern(f, q, b);
        float3 contrastInk = dot(base, 0.333.xxx) > 0.52 ? ink_color : paper_color;
        float patternAmount = pattern_density * (0.12 + 0.48 * step(0.5, f.pattern));
        float3 faceCol = lerp(base * shade, contrastInk, patt * patternAmount);

        // A record-attached aperture, keyed to the source id and group.
        float apertureRadius = (0.08 + 0.06 * hash_print(f.source_id + 71.0)) * min(b.x, b.y);
        float2 apertureCenter = float2(
            (hash_print(f.source_id + 17.0) - 0.5) * b.x,
            (hash_print(f.source_id + 29.0) - 0.5) * b.y
        );
        float aperture = smoothstep(apertureRadius + aa, apertureRadius - aa, length(q - apertureCenter));
        faceCol = lerp(faceCol, ink_color * 0.20, aperture * aperture_gain);

        // Source-attached registration ticks: count and location derive from live ids.
        float tickPhase = frac((q.x / max(b.x, 0.001) + 1.0) * (3.0 + fmod(f.group_id, 5.0)));
        float tickRail = smoothstep(0.05, 0.0, abs(q.y / b.y + 0.82));
        float ticks = step(0.68, tickPhase) * tickRail;
        faceCol = lerp(faceCol, contrastInk, ticks * 0.58);

        col = lerp(col, faceCol, fill * 0.98);
        col = lerp(col, ink_color, edge * 0.90);
    }

    // Routes retain per-record phase and width; elevation controls prominence.
    [loop]
    for (uint rIndex = 0u; rIndex < 48u; ++rIndex) {
        RouteRecord r = Routes[rIndex];
        if (r.active < 0.5) continue;
        float2 a = float2((r.p0.x - 0.5) * aspect, r.p0.y - 0.5);
        float2 b = float2((r.p1.x - 0.5) * aspect, r.p1.y - 0.5);
        float along;
        float d = sdSegmentInfo(p, a, b, along);
        float dash = step(0.30, frac(along * (1.0 + r.dash * 5.0) + r.phase + route_phase));
        float routeMask = smoothstep(r.width * route_width + aa, r.width * route_width, d);
        routeMask *= lerp(1.0, dash, dash_mix);
        float3 routeCol = r.palette < 0.5 ? float3(0.93, 0.055, 0.035) :
                          r.palette < 1.5 ? float3(0.98, 0.34, 0.025) :
                          r.palette < 2.5 ? float3(0.04, 0.80, 0.22) :
                                            paper_color;
        float prominence = saturate(0.45 + r.elevation * 0.45) * route_intensity;
        col = lerp(col, routeCol, routeMask * prominence);
    }

    // Focal registration reticle is real state, not decorative telemetry.
    float2 fp = float2((focus_point.x - 0.5) * aspect, focus_point.y - 0.5);
    float fd = length(p - fp);
    float ring = smoothstep(aa * 1.6, 0.0, abs(fd - 0.028));
    float cross = max(
        smoothstep(aa * 1.4, 0.0, abs(p.x - fp.x)) * step(abs(p.y - fp.y), 0.043),
        smoothstep(aa * 1.4, 0.0, abs(p.y - fp.y)) * step(abs(p.x - fp.x), 0.043)
    );
    col = lerp(col, float3(0.93, 0.055, 0.035), (ring + cross) * focus_marker);

    float grain = hash_print(dot((float2)tid.xy, float2(0.06711056, 0.00583715)) + route_phase * 19.0) - 0.5;
    col += grain * print_grain;
    float vignette = 1.0 - vignette_amount * dot(uv - 0.5, uv - 0.5);
    col *= vignette;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}

