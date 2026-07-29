struct PanelRecord {
    float2 center; float2 size;
    float angle; float depth; float kind; float palette;
    float group_id; float order_id; float fold; float pattern;
    float skew; float phase; float weight; float active;
};
struct RouteRecord {
    float2 p0; float2 p1;
    float width; float palette; float group_id; float phase;
    float dash; float elevation; float active; float reserved;
};
struct FaceRecord {
    float2 center; float2 size;
    float2 axis_x; float2 axis_y;
    float depth; float face_kind; float palette; float pattern;
    float source_id; float group_id; float phase; float active;
};
struct RibbonRecord {
    float2 p0; float2 p1;
    float width; float feather; float material; float layer;
    float phase; float speed; float warp; float opacity;
    float2 uv_offset; float active; float reserved;
};
struct PortalRecord {
    float2 center; float radius; float thickness; float rotation;
    float sector_count; float depth; float material; float phase;
    float speed; float2 eccentricity; float opacity; float scale;
    float active; float reserved;
};

StructuredBuffer<PanelRecord> Panels : register(t6);
StructuredBuffer<RouteRecord> Routes : register(t7);
StructuredBuffer<FaceRecord> Faces : register(t8);
StructuredBuffer<RibbonRecord> Ribbons : register(t9);
StructuredBuffer<PortalRecord> Portals : register(t10);
RWTexture2D<float4> OutputUAV : register(u0);

float mc_luma(float3 c) {
    return dot(c, float3(0.299, 0.587, 0.114));
}

float2 mc_rotate(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float mc_box(float2 p, float2 b, float feather) {
    float2 d = abs(p) - b;
    float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    return smoothstep(feather, -feather, sd);
}

float mc_segment(float2 p, float2 a, float2 b, out float along) {
    float2 pa = p - a;
    float2 ba = b - a;
    along = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * along);
}

float3 mc_material(int id, float2 uv) {
    uv = saturate(uv);
    if (id == 0) return _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    if (id == 1) return _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    if (id == 2) return _Tex2.SampleLevel(LinearSampler, uv, 0).rgb;
    if (id == 3) return _Tex3.SampleLevel(LinearSampler, uv, 0).rgb;
    if (id == 4) return _Tex4.SampleLevel(LinearSampler, uv, 0).rgb;
    return _Tex5.SampleLevel(LinearSampler, uv, 0).rgb;
}

float mc_panel_mask(float2 uv, PanelRecord r, float aspect, out float2 localUv) {
    float2 q = float2((uv.x - r.center.x) * aspect, uv.y - r.center.y);
    q = mc_rotate(q, -r.angle);
    q.x += q.y * r.skew;
    float2 halfSize = max(r.size * float2(aspect, 1.0) * 0.5, 0.001.xx);
    localUv = q / (halfSize * 2.0) + 0.5;
    return mc_box(q, halfSize, 1.5 / _Resolution.y);
}

float mc_face_mask(float2 uv, FaceRecord r, float aspect, out float2 localUv) {
    float2 p = float2((uv.x - r.center.x) * aspect, uv.y - r.center.y);
    float2 ax = normalize(float2(r.axis_x.x * aspect, r.axis_x.y));
    float2 ay = normalize(float2(r.axis_y.x * aspect, r.axis_y.y));
    float2 q = float2(dot(p, ax), dot(p, ay));
    float2 halfSize = max(r.size * float2(aspect, 1.0) * 0.5, 0.001.xx);
    localUv = q / (halfSize * 2.0) + 0.5;
    return mc_box(q, halfSize, 1.2 / _Resolution.y);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = float2(uv.x * aspect, uv.y);
    float phase = master_phase * 6.2831853;

    float3 architecture = mc_material(0, uv);
    float3 col = lerp(architecture, mc_luma(architecture).xxx, 0.22 + pressure * 0.24);
    col *= 0.62;

    // The dominant intervention: a huge diagonal blackout that protects negative space.
    float2 slabP = float2((uv.x - 0.58) * aspect, uv.y - 0.48);
    slabP = mc_rotate(slabP, -0.34 + rupture.y * 0.10);
    float slab = mc_box(slabP, float2(0.62 + pressure * 0.12, 0.43), 0.018);
    float2 slabUv = uv + rupture * 0.035 + float2(sin(phase * 0.23), cos(phase * 0.19)) * 0.012;
    float3 slabTexture = mc_material(1, slabUv);
    float slabFracture = smoothstep(0.24, 0.74, mc_luma(slabTexture));
    float3 slabInk = ink_color + slabTexture * 0.065;
    col = lerp(col, slabInk, slab * (0.94 - slabFracture * 0.12));

    // Original panel records become broad occlusion plates and negative-space cuts.
    [loop]
    for (uint pi = 0u; pi < 96u; ++pi) {
        PanelRecord r = Panels[pi];
        if (r.active < 0.5 || r.weight < 0.44) continue;
        r.center += rupture * (0.018 + 0.028 * r.weight) * sin(phase + r.phase * 6.2831853);
        float2 localUv;
        float mask = mc_panel_mask(uv, r, aspect, localUv);
        float select = step(0.58, frac(r.order_id * 0.318 + r.group_id * 0.17));
        float2 blackUv = frac(localUv + float2(r.phase, r.fold * 0.07));
        float3 blackMat = mc_material(1, blackUv) * 0.30 + ink_color;
        col = lerp(col, blackMat, mask * select * r.weight * black_coverage * 0.82);
    }

    // Assembled primary faces place six different texture worlds as actual materials.
    [loop]
    for (uint fi = 0u; fi < 288u; fi += 3u) {
        FaceRecord r = Faces[fi];
        if (r.active < 0.5) continue;
        float travel = sin(phase * (0.18 + reindex * 0.22) + r.phase * 6.2831853);
        r.center += rupture * travel * (0.008 + 0.020 * saturate(r.depth + 0.2));
        float2 localUv;
        float mask = mc_face_mask(uv, r, aspect, localUv);
        int materialId = ((int)r.palette + (int)r.pattern * 2) % 6;
        float2 materialUv = localUv;
        materialUv = mc_rotate(materialUv - 0.5, r.phase * 0.22 + phase * 0.015 * reindex) + 0.5;
        materialUv += float2(r.group_id * 0.031, r.source_id * 0.017);
        float3 mat = mc_material(materialId, frac(materialUv));
        float depthGain = saturate(0.58 + r.depth * 0.34);
        float archiveZone = saturate(
            (1.0 - smoothstep(0.43, 0.72, uv.x)) +
            smoothstep(0.74, 0.94, uv.y) * 0.58
        );
        col = lerp(col, mat * (0.66 + depthGain * 0.34), mask * archiveZone * data_mix * 0.78);
    }

    // Ribbon records are moving, material-bearing masks rather than screen overlays.
    [loop]
    for (uint ri = 0u; ri < 24u; ++ri) {
        RibbonRecord r = Ribbons[ri];
        if (r.active < 0.5) continue;
        float2 a = float2(r.p0.x * aspect, r.p0.y);
        float2 b = float2(r.p1.x * aspect, r.p1.y);
        float along;
        float d = mc_segment(p, a, b, along);
        float wave = sin(along * 19.0 + r.phase * 6.2831853 + phase * r.speed * 0.08) * r.warp * 0.010;
        float ribbonMask = 1.0 - smoothstep(r.width * 0.5 + r.feather, r.width * 0.5 + r.feather * 2.0, abs(d + wave));
        float edge = 1.0 - smoothstep(r.feather, r.feather * 3.0, abs(abs(d + wave) - r.width * 0.5));
        int materialId = r.material < 0.5 ? 5 : r.material < 1.5 ? 3 : r.material < 2.5 ? 0 : 1;
        float2 materialUv = frac(float2(along, uv.y + phase * 0.012 * r.speed) + r.uv_offset);
        float3 mat = mc_material(materialId, materialUv);
        float layerGain = 0.60 + 0.08 * r.layer;
        col = lerp(col, mat * layerGain, ribbonMask * r.opacity * (0.36 + pressure * 0.16));
        col += accent_color * edge * accent_gain * (0.055 + 0.025 * r.layer);
    }

    // Portal records carve circular windows into Mirror, Orbital, and Corridor worlds.
    [loop]
    for (uint oi = 0u; oi < 16u; ++oi) {
        PortalRecord r = Portals[oi];
        if (r.active < 0.5) continue;
        float2 q = (uv - r.center) * float2(aspect, 1.0);
        q = mc_rotate(q, -r.rotation - phase * r.speed * 0.035);
        q /= max(r.eccentricity, float2(0.2, 0.2));
        float d = length(q);
        float disk = 1.0 - smoothstep(r.radius, r.radius + 0.008, d);
        float ring = 1.0 - smoothstep(r.thickness, r.thickness * 2.8, abs(d - r.radius));
        float angle = atan2(q.y, q.x);
        float sectors = step(0.46, frac(angle / 6.2831853 * max(3.0, r.sector_count) + r.phase));
        float2 materialUv = mc_rotate(q / max(r.radius * 2.0, 0.02), phase * 0.025 * r.speed) + 0.5;
        int materialId = r.material < 0.5 ? 4 : r.material < 1.5 ? 2 : 3;
        float3 mat = mc_material(materialId, materialUv);
        float depthGain = saturate(0.62 + r.depth * 0.24);
        col = lerp(col, mat * depthGain * 0.72, disk * r.opacity * (0.48 + strike * 0.12));
        col += accent_color * ring * accent_gain * (0.15 + sectors * 0.16);
    }

    // Route records stitch the whole composition into the original drawing grammar.
    [loop]
    for (uint li = 0u; li < 48u; ++li) {
        RouteRecord r = Routes[li];
        if (r.active < 0.5) continue;
        float2 a = float2(r.p0.x * aspect, r.p0.y);
        float2 b = float2(r.p1.x * aspect, r.p1.y);
        float along;
        float d = mc_segment(p, a, b, along);
        float dash = step(0.62 + r.dash * 0.22, frac(along * (3.0 + r.group_id) + r.phase + master_phase * 0.16));
        float width = r.width * (0.48 + pressure * 0.62);
        float lineMask = smoothstep(width + 0.002, width, d) * dash;
        float3 routeColor = r.palette < 1.5 ? accent_color : float3(0.82, 0.76, 0.65);
        float routeGate = step(0.42, frac(r.group_id * 0.381 + r.phase));
        col = lerp(col, routeColor, lineMask * routeGate * (0.22 + strike * 0.18));
    }

    float border = 1.0 - mc_box(uv - 0.5, float2(0.487, 0.478), 0.003);
    float scan = 1.0 - smoothstep(0.003, 0.010, abs(frac(uv.y * 7.0 - master_phase * 0.14) - 0.5));
    col += accent_color * border * 0.48;
    col = lerp(col, architecture, scan * reindex * 0.12);
    col = col / (1.0 + col * 0.24);
    col = saturate((col - 0.5) * (1.04 + pressure * 0.15) + 0.5);
    col = lerp(architecture, col, master_mix);
    OutputUAV[tid.xy] = float4(col, 1.0);
}
