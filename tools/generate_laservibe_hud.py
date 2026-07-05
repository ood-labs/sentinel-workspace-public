from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "modules"
RES = "[1920, 1080]"


def write_module(name, files):
    d = MOD / name
    d.mkdir(parents=True, exist_ok=True)
    for fn, text in files.items():
        (d / fn).write_text(text.strip() + "\n", encoding="utf-8")


COMMON_RENDER = r"""
RWTexture2D<float4> OutputUAV : register(u0);

float hash_lv(float n)
{
    return frac(sin(n * 12.9898 + 78.233) * 43758.5453);
}

float hash_lv2(float2 p)
{
    return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float2 aspect_uv(uint2 pixel)
{
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    return (uv - 0.5) * float2(aspect, 1.0);
}

float seg_dist(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.000001));
    return length(pa - ba * h);
}

float ring_mask(float2 p, float r, float w)
{
    return 1.0 - smoothstep(0.0, w, abs(length(p) - r));
}

float finite_glow(float d, float radius, float gain)
{
    float g = saturate(1.0 - d / max(radius, 0.0001));
    return g * g * gain;
}
"""


space_hlsl = COMMON_RENDER + r"""
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 p = aspect_uv(pixel);
    float2 q = p - lens_center;
    float r = length(q);
    float t = freeze_time ? 0.0 : _Time * animation_speed;
    float breath = 1.0 + sin(t * 1.7) * breathing_amount * 0.05;
    float shear = coordinate_shear * q.y;
    q.x += shear;
    q *= global_scale * breath;
    float ca = cos(global_rotation * 0.0174532925);
    float sa = sin(global_rotation * 0.0174532925);
    q = float2(ca * q.x - sa * q.y, sa * q.x + ca * q.y) + global_offset;
    float grid = 0.0;
    float2 gp = frac((q + t * drift_vector * 0.02) * (14.0 + space_quantize * 40.0)) - 0.5;
    grid = max(1.0 - smoothstep(0.0, 0.018, abs(gp.x)), 1.0 - smoothstep(0.0, 0.018, abs(gp.y)));
    float rings = ring_mask(q, 0.55 + 0.08 * sin(t), 0.006 + polar_fold_amount * 0.006);
    float vignette = smoothstep(1.1, 0.18, r) * edge_falloff;
    float3 col = float3(0.005, 0.025, 0.035);
    col += float3(0.02, 0.15, 0.20) * grid * 0.18 * motion_preview_gain;
    col += float3(0.05, 0.25, 0.35) * rings * 0.45;
    col *= lerp(1.0, vignette, 0.55);
    OutputUAV[pixel] = float4(col, 1.0);
}
"""


height_hlsl = COMMON_RENDER + r"""
float field(float2 p)
{
    float t = _Time * drift_speed;
    p *= field_scale;
    p += float2(cos(t), sin(t * 0.73)) * drift_amount * 0.08;
    float v = 0.0;
    float amp = 0.55;
    float f = 1.0;
    [loop]
    for (int i = 0; i < 8; ++i)
    {
        if (i < noise_octaves)
        {
            float2 ip = floor(p * f);
            float2 fp = frac(p * f);
            float a = hash_lv2(ip);
            float b = hash_lv2(ip + float2(1, 0));
            float c = hash_lv2(ip + float2(0, 1));
            float d = hash_lv2(ip + float2(1, 1));
            float2 u = fp * fp * (3.0 - 2.0 * fp);
            v += lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y) * amp;
            f *= 2.0;
            amp *= 0.5;
        }
    }
    float r = length(p);
    v += central_bias * exp(-r * r * 0.35);
    v += sin(p.x * 3.1 + p.y * 2.4 + terrain_phase) * ridge_strength * 0.12;
    v += sin((p.x + p.y) * 6.0 + fault_line_gain * 4.0) * fault_line_gain * 0.04;
    v = lerp(v, 1.0 - v, field_inversion);
    v += sin(atan2(p.y, p.x) * (3.0 + tectonic_shatter * 9.0) + r * 8.0) * magnetic_anomaly * 0.05;
    return v;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 p = aspect_uv(pixel);
    float v = field(p);
    float contour = abs(frac(v * (12.0 + contour_melt * 34.0)) - 0.5);
    float contourLine = 1.0 - smoothstep(0.0, 0.035, contour);
    float3 col = float3(0.005, 0.02, 0.028) + float3(0.0, 0.18, 0.24) * v * 0.35;
    col += float3(0.0, 0.65, 0.9) * contourLine * 0.55;
    OutputUAV[pixel] = float4(col, 1.0);
}
"""


contour_compute = r"""
struct ContourSegment
{
    float2 a; float2 b; float level; float group_id;
    float weight; float active; float role; float pad0;
    float pad1; float pad2;
};
RWStructuredBuffer<ContourSegment> OutputBuffer : register(u0);

float h1(float n) { return frac(sin(n * 12.9898 + 4.1414) * 43758.5453); }

[numthreads(16, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    ContourSegment s;
    uint segsPerLevel = 16u;
    float totalRing = floor((float)i / (float)segsPerLevel);
    float island = fmod(totalRing, 8.0);
    float ring = floor(totalRing / 8.0);
    float level = totalRing;
    float seg = fmod((float)i, (float)segsPerLevel);
    float lane = fmod(level, max((float)major_interval, 1.0));
    float localCount = max((float)segsPerLevel, 1.0);
    float ang = (seg / localCount) * 6.2831853 + scene_seed * 0.017 + island * 0.41 + ring * 0.09;
    float hx = h1(island * 13.1 + scene_seed);
    float hy = h1(island * 17.7 + scene_seed + 9.0);
    float2 c = float2(0.16 + hx * 0.68, 0.14 + hy * 0.70);
    c += float2(sin(island * 1.73), cos(island * 1.11)) * island_isolation * 0.035;
    float baseR = (0.026 + ring * 0.021 + h1(island * 5.3) * 0.01) * active_region_radius;
    float wobA = sin(ang * (2.7 + false_topology * 3.0) + island * 0.7 + level_bias * 5.0) * (0.004 + nested_loop_bias * 0.01);
    float wobB = sin((ang + 0.25) * (2.7 + false_topology * 3.0) + island * 0.7 + level_bias * 5.0) * (0.004 + nested_loop_bias * 0.01);
    float stepAng = 6.2831853 / localCount * 0.92;
    float2 a = c + float2(cos(ang), sin(ang)) * (baseR + wobA);
    float2 b = c + float2(cos(ang + stepAng), sin(ang + stepAng)) * (baseR + wobB);
    float breakGate = h1(i * 3.13 + scene_seed) > contour_breakup ? 1.0 : 0.0;
    s.a = a;
    s.b = b;
    s.level = level;
    s.group_id = floor(level);
    s.weight = (lane < 0.5) ? 1.0 : 0.45;
    s.active = (i < (uint)segment_count && totalRing < min((float)contour_density, 32.0)) ? breakGate : 0.0;
    s.role = lane < 0.5 ? 1.0 : 0.0;
    s.pad0 = contour_echo_count;
    s.pad1 = contour_echo_offset;
    s.pad2 = scanline_slice;
    OutputBuffer[i] = s;
}
"""


contour_preview = COMMON_RENDER + r"""
struct ContourSegment { float2 a; float2 b; float level; float group_id; float weight; float active; float role; float pad0; float pad1; float pad2; };
StructuredBuffer<ContourSegment> Segments : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 p = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = float3(0.004, 0.015, 0.02);
    [loop]
    for (uint i = 0; i < 512; ++i)
    {
        ContourSegment s = Segments[i];
        if (s.active > 0.5)
        {
            float d = seg_dist(p, s.a, s.b);
            float m = 1.0 - smoothstep(0.0, 0.0025 + s.weight * 0.002, d);
            col += float3(0.0, 0.55, 0.85) * m * (0.35 + s.weight);
        }
    }
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


contour_render = COMMON_RENDER + r"""
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 p = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = float3(0, 0, 0);
    uint count = min((uint)_Data0_Count, 512u);
    [loop]
    for (uint i = 0; i < 512u; ++i)
    {
        if (i < count && _Data0[i].active > 0.5)
        {
            float d = seg_dist(p, _Data0[i].a, _Data0[i].b);
            float major = _Data0[i].role;
            float w = lerp(minor_line_width, major_line_width, major) * (1.0 + xray_double_line * 0.7);
            float core = 1.0 - smoothstep(w, w + line_softness, d);
            float glow = finite_glow(d, glow_radius, glow_gain);
            float dash = 1.0;
            if (line_dash_amount > 0.01)
            {
                float t = frac((float)i * 0.173 + dash_phase + _Data0[i].level * 0.11);
                dash = lerp(1.0, step(t, 0.56), line_dash_amount);
            }
            float gain = lerp(minor_gain, major_gain, major) * dash * (1.0 + brightness_by_level * frac(_Data0[i].level * 0.19));
            float3 cyan = contour_color * (1.0 + spectral_split * float3(0.1, 0.0, 0.3));
            col += cyan * (core * gain + glow * 0.18);
            if (contour_afterimage > 0.01)
                col += cyan.bgr * finite_glow(abs(d - 0.01), glow_radius * 1.8, contour_afterimage * 0.35);
        }
    }
    float2 q = p - 0.5;
    float edge = smoothstep(0.9, 0.15, length(q * float2(_Resolution.x/_Resolution.y, 1)));
    col *= lerp(1.0, edge, fade_near_edges);
    col *= 1.0 + neon_overburn * 1.4;
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


hud_compute = r"""
struct HudArcRecord { float2 center; float radius; float start_angle; float end_angle; float width; float dash_count; float role; float active; float pad0; float pad1; float pad2; };
RWStructuredBuffer<HudArcRecord> OutputBuffer : register(u0);

[numthreads(16, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    HudArcRecord r;
    float fi = (float)i;
    float total = max((float)ring_count + (float)dotted_band_count + 8.0, 1.0);
    float k = fi / total;
    r.center = float2(0.5, 0.5) + float2(sin(fi * 2.1), cos(fi * 1.7)) * ring_jitter;
    r.radius = lerp(inner_ring_radius, outer_frame_radius, frac(k * 1.7));
    r.start_angle = angle_offset * 0.0174532925 + k * 6.28318 + broken_scope_mode * sin(fi);
    r.end_angle = r.start_angle + lerp(0.5, 6.15, 1.0 - arc_fragmentation) + sin(fi * 1.7) * ritual_geometry;
    r.width = ring_width * (1.0 + 0.4 * frac(fi * 0.37));
    r.dash_count = lerp(0.0, (float)tick_density, frac(fi * 0.23)) + misregistered_rings * 18.0;
    r.role = fmod(fi, 4.0);
    r.active = (i < (uint)total) ? 1.0 : 0.0;
    r.pad0 = radial_line_count;
    r.pad1 = sweep_angle;
    r.pad2 = orbital_precession;
    OutputBuffer[i] = r;
}
"""


hud_preview = COMMON_RENDER + r"""
struct HudArcRecord { float2 center; float radius; float start_angle; float end_angle; float width; float dash_count; float role; float active; float pad0; float pad1; float pad2; };
StructuredBuffer<HudArcRecord> Arcs : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 p = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float3 col = float3(0, 0, 0);
    [loop]
    for (uint i = 0; i < 96; ++i)
    {
        HudArcRecord a = Arcs[i];
        if (a.active > 0.5)
        {
            float2 q = (p - a.center) * float2(aspect, 1);
            float d = abs(length(q) - a.radius);
            float m = 1.0 - smoothstep(a.width, a.width + 0.003, d);
            col += float3(0.02, 0.42, 0.62) * m;
        }
    }
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


hud_render = COMMON_RENDER + r"""
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 p = ((float2)pixel + 0.5) / _Resolution.xy + parallax_offset * 0.02;
    float aspect = _Resolution.x / _Resolution.y;
    float3 col = float3(0, 0, 0);
    uint count = min((uint)_Data0_Count, 96u);
    [loop]
    for (uint i = 0; i < 96u; ++i)
    {
        if (i < count && _Data0[i].active > 0.5)
        {
            float2 q = (p - _Data0[i].center) * float2(aspect, 1);
            float ang = atan2(q.y, q.x);
            if (ang < 0.0) ang += 6.2831853;
            float d = abs(length(q) - _Data0[i].radius);
            float dash = 1.0;
            if (_Data0[i].dash_count > 1.0)
                dash = smoothstep(0.12, 0.12 + dash_sharpness, frac(ang / 6.2831853 * _Data0[i].dash_count + _Time * tick_crawl_speed));
            float m = (1.0 - smoothstep(ring_width, ring_width + 0.004, d)) * dash;
            float glow = finite_glow(d, max(0.01, ring_width * 8.0), ring_glow);
            col += lerp(ring_color, accent_color, frac(_Data0[i].role * 0.37)) * (m * ring_opacity + glow * 0.08);
        }
    }
    col *= 1.0 + scope_burn_in + radial_chromatic_split * float3(0.2, 0.0, 0.35);
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


route_plan = r"""
struct RouteSpec { float2 p0; float2 p1; float2 p2; float2 p3; float width; float role; float route_id; float active; };
RWStructuredBuffer<RouteSpec> OutputBuffer : register(u0);
float h1(float n) { return frac(sin(n * 15.27 + 9.11) * 43758.5453); }

[numthreads(16, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    float fi = (float)i;
    RouteSpec r;
    float a = fi * 2.399 + route_seed * 0.11;
    float rr = 0.14 + route_span * (0.18 + 0.58 * h1(fi + 4.0));
    float2 c = float2(0.5, 0.5) + float2(sin(fi * 0.61), cos(fi * 0.47)) * route_layer_spread * 0.12;
    r.p0 = c + float2(cos(a), sin(a)) * rr * 0.48;
    r.p3 = c + float2(cos(a + 1.2 + route_curvature), sin(a + 1.2 + route_curvature)) * rr;
    r.p1 = lerp(r.p0, r.p3, 0.33) + float2(-sin(a), cos(a)) * route_curvature * 0.18;
    r.p2 = lerp(r.p0, r.p3, 0.66) - float2(-sin(a), cos(a)) * route_curvature * 0.12;
    r.width = 0.0012 + 0.0032 * h1(fi * 3.0) * (1.0 + route_interference * 0.5);
    r.role = (h1(fi) < orange_vs_cyan_mix) ? 1.0 : 0.0;
    r.route_id = fi;
    float limit = (float)route_count + (fi < (float)orbit_arc_count ? 1.0 : 0.0);
    r.active = (i < (uint)limit) ? 1.0 : 0.0;
    if (fi < (float)diagonal_count)
    {
        float x = h1(fi + 71.0);
        r.p0 = float2(x, 0.05 + 0.2 * h1(fi));
        r.p3 = float2(1.0 - x * 0.25, 0.8 + 0.18 * h1(fi + 9.0));
    }
    OutputBuffer[i] = r;
}
"""


route_expand = r"""
struct RouteSegment { float2 a; float2 b; float width; float role; float route_id; float route_t0; float route_t1; float active; float pad0; float pad1; };
RWStructuredBuffer<RouteSegment> OutputBuffer : register(u0);

float2 bez(float2 a, float2 b, float2 c, float2 d, float t)
{
    float u = 1.0 - t;
    return u*u*u*a + 3.0*u*u*t*b + 3.0*u*t*t*c + t*t*t*d;
}

[numthreads(16, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    uint routeI = i / 8u;
    uint segI = i % 8u;
    RouteSegment s;
    s.active = 0.0;
    if (routeI < (uint)_Data0_Count && _Data0[routeI].active > 0.5)
    {
        float t0 = (float)segI / 8.0;
        float t1 = (float)(segI + 1u) / 8.0;
        float dropout = frac(sin(((float)i + route_id_bias) * 17.17) * 43758.5453);
        s.a = bez(_Data0[routeI].p0, _Data0[routeI].p1, _Data0[routeI].p2, _Data0[routeI].p3, t0);
        s.b = bez(_Data0[routeI].p0, _Data0[routeI].p1, _Data0[routeI].p2, _Data0[routeI].p3, t1);
        s.width = _Data0[routeI].width * width_scale * (1.0 + danger_zone_thicken * smoothstep(0.3, 0.7, t0));
        s.role = _Data0[routeI].role;
        s.route_id = _Data0[routeI].route_id;
        s.route_t0 = t0;
        s.route_t1 = t1;
        s.active = (dropout > signal_dropout) ? 1.0 : 0.0;
        s.pad0 = dash_count;
        s.pad1 = dash_phase;
    }
    OutputBuffer[i] = s;
}
"""


route_preview = COMMON_RENDER + r"""
struct RouteSegment { float2 a; float2 b; float width; float role; float route_id; float route_t0; float route_t1; float active; float pad0; float pad1; };
StructuredBuffer<RouteSegment> Segments : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 p = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = float3(0, 0, 0);
    [loop]
    for (uint i = 0; i < 768; ++i)
    {
        RouteSegment s = Segments[i];
        if (s.active > 0.5)
        {
            float m = 1.0 - smoothstep(s.width, s.width + 0.004, seg_dist(p, s.a, s.b));
            col += lerp(float3(0.0, 0.55, 0.9), float3(1.0, 0.28, 0.02), s.role) * m;
        }
    }
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


route_spec_preview = COMMON_RENDER + r"""
struct RouteSpec { float2 p0; float2 p1; float2 p2; float2 p3; float width; float role; float route_id; float active; };
StructuredBuffer<RouteSpec> Routes : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 p = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = float3(0, 0, 0);
    [loop]
    for (uint i = 0; i < 96; ++i)
    {
        RouteSpec s = Routes[i];
        if (s.active > 0.5)
        {
            float m = 1.0 - smoothstep(s.width, s.width + 0.004, seg_dist(p, s.p0, s.p3));
            col += lerp(float3(0.0, 0.55, 0.9), float3(1.0, 0.28, 0.02), s.role) * m;
        }
    }
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


route_render = COMMON_RENDER + r"""
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 p = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = float3(0, 0, 0);
    uint count = min((uint)_Data0_Count, 768u);
    [loop]
    for (uint i = 0; i < 768u; ++i)
    {
        if (i < count && _Data0[i].active > 0.5)
        {
            float d = seg_dist(p, _Data0[i].a, _Data0[i].b);
            float dash = 1.0;
            if (dash_count > 0.1)
                dash = step(frac(lerp(_Data0[i].route_t0, _Data0[i].route_t1, 0.5) * dash_count + dash_phase + _Time * travel_dot_speed * 0.05), 0.58);
            float core = (1.0 - smoothstep(_Data0[i].width, _Data0[i].width + 0.004, d)) * dash;
            float glow = finite_glow(d, route_glow_radius, route_glow_gain);
            float3 c = lerp(cyan_route_color, orange_color, _Data0[i].role);
            c += red_alert_mode * float3(0.5, -0.05, -0.05);
            col += c * (core * route_core_gain * 0.62 + glow * 0.045);
            col += c * finite_glow(length(p - _Data0[i].a), _Data0[i].width * 4.0 + 0.006, endpoint_boost * 0.07);
        }
    }
    col *= 1.0 + plasma_route_bleed * 0.35 + route_corona * 0.35;
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


beacon_plan = r"""
struct BeaconRecord { float2 pos; float radius; float role; float intensity; float linked_route; float label_id; float active; };
RWStructuredBuffer<BeaconRecord> OutputBuffer : register(u0);
float h1(float n) { return frac(sin(n * 19.19 + 2.77) * 43758.5453); }

[numthreads(16, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    float fi = (float)i;
    BeaconRecord b;
    float a = fi * 2.399 + beacon_seed * 0.05;
    float r = 0.08 + 0.65 * h1(fi + 3.0);
    b.pos = float2(0.5, 0.5) + float2(cos(a), sin(a)) * r * (0.55 + anomaly_cluster * 0.25);
    b.pos = lerp(b.pos, float2(0.5, 0.5), central_cluster_strength * h1(fi + 5.0));
    b.radius = 0.004 + 0.02 * h1(fi + 6.0);
    b.role = (fi < (float)white_beacon_count) ? 0.0 : ((fi < (float)(white_beacon_count + orange_node_count)) ? 1.0 : 2.0);
    b.intensity = 0.45 + 1.4 * h1(fi + 8.0);
    b.linked_route = floor(h1(fi + 10.0) * 64.0);
    b.label_id = fi;
    float total = (float)white_beacon_count + (float)orange_node_count + (float)cyan_micro_count + rogue_signal_count;
    b.active = (i < (uint)total) ? 1.0 : 0.0;
    OutputBuffer[i] = b;
}
"""


beacon_preview = COMMON_RENDER + r"""
struct BeaconRecord { float2 pos; float radius; float role; float intensity; float linked_route; float label_id; float active; };
StructuredBuffer<BeaconRecord> Beacons : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 p = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = float3(0, 0, 0);
    [loop]
    for (uint i = 0; i < 512; ++i)
    {
        BeaconRecord b = Beacons[i];
        if (b.active > 0.5)
        {
            float d = length(p - b.pos);
            float m = finite_glow(d, b.radius * 3.0, b.intensity);
            col += lerp(float3(0.8, 0.95, 1.0), lerp(float3(1.0, 0.32, 0.05), float3(0.0, 0.75, 1.0), step(1.5, b.role)), step(0.5, b.role)) * m;
        }
    }
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


beacon_render = COMMON_RENDER + r"""
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 p = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = float3(0, 0, 0);
    uint count = min((uint)_Data0_Count, 512u);
    [loop]
    for (uint i = 0; i < 512u; ++i)
    {
        if (i < count && _Data0[i].active > 0.5)
        {
            float d = length(p - _Data0[i].pos);
            float pulse = 1.0 + pulse_amount * sin(_Time * pulse_speed + _Data0[i].label_id);
            float core = 1.0 - smoothstep(beacon_core_size * _Data0[i].radius, beacon_core_size * _Data0[i].radius + 0.003, d);
            float glow = finite_glow(d, beacon_glow_size * _Data0[i].radius * 5.0, beacon_glow_gain * pulse);
            float ring = 1.0 - smoothstep(0.0, 0.003, abs(d - reticle_radius * _Data0[i].radius * 4.0));
            float3 c = (_Data0[i].role < 0.5) ? white_beacon_color : ((_Data0[i].role < 1.5) ? orange_node_color : cyan_micro_color);
            col += c * (core * _Data0[i].intensity + glow * 0.18 + ring * reticle_count * 0.08);
        }
    }
    col *= 1.0 + signal_overload + lens_spark;
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


plate_hlsl = COMMON_RENDER + r"""
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 p = (uv - plate_center) * float2(_Resolution.x/_Resolution.y, 1.0) / max(plate_scale, 0.001);
    float ca = cos(plate_rotation * 0.0174532925);
    float sa = sin(plate_rotation * 0.0174532925);
    p = float2(ca*p.x - sa*p.y, sa*p.x + ca*p.y);
    float2 gp = frac(p * grid_density + internal_parallax * sin(_Time)) - 0.5;
    float grid = max(1.0 - smoothstep(0.0, 0.02, abs(gp.x)), 1.0 - smoothstep(0.0, 0.02, abs(gp.y)));
    float hatch = 1.0 - smoothstep(0.0, 0.018, abs(frac((p.x + p.y) * max(hatch_density, 1)) - 0.5));
    float circles = 0.0;
    [loop]
    for (int i = 1; i <= 16; ++i)
    {
        if (i <= circle_count) circles = max(circles, ring_mask(p, 0.08 * i, 0.006));
    }
    float mask = smoothstep(0.72, 0.18, length(p));
    float3 c = lerp(float3(0.0, 0.65, 0.9), float3(0.95, 0.25, 0.75), magenta_mix);
    float sigil = sin(atan2(p.y, p.x) * (6.0 + sigil_overlay * 12.0)) * sigil_overlay;
    float v = (grid * mesh_line_gain + hatch * 0.18 + circles * 0.8 + sigil * 0.1) * mask * plate_opacity;
    v *= 1.0 + broken_hologram * sin(_Time * 8.0 + p.x * 30.0);
    OutputUAV[pixel] = float4(saturate(c * v), 1.0);
}
"""


micro_hlsl = COMMON_RENDER + r"""
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 p = aspect_uv(pixel);
    float3 col = float3(0, 0, 0);
    float flick = lerp(1.0, step(0.18, hash_lv2(floor(uv * 90.0) + floor(_Time * flicker_speed))), flicker_amount);
    float dots = step(1.0 - scan_noise_gain * 0.22, hash_lv2(floor(uv * scan_dot_count * 0.07 + detail_seed)));
    float ticks = max(1.0 - smoothstep(0.0, 0.002, abs(frac(uv.x * tick_count * 0.08) - 0.5)), 0.0) * step(0.985, hash_lv(floor(uv.y * 80.0)));
    float labels = step(0.995 - label_gain * 0.004, hash_lv2(floor(uv * label_count * 0.14 + 17.0)));
    float rain = numeric_rain * step(0.97, hash_lv2(floor(float2(uv.x * 80.0, uv.y * 220.0 + _Time * 18.0))));
    col += lerp(float3(0.0, 0.7, 0.9), float3(1.0, 0.35, 0.05), detail_color_mix) * (dots + ticks * tick_gain + labels * label_gain + rain) * flick;
    col += float3(0.02, 0.25, 0.32) * edge_decals * ring_mask(p, 0.82, 0.004);
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


mod_compute = r"""
struct ModulatorRecord { float slow_sine; float fast_pulse; float random_hold; float saw_sweep; float danger_pulse; float breath; float pad0; float pad1; };
RWStructuredBuffer<ModulatorRecord> OutputBuffer : register(u0);
float h1(float n) { return frac(sin(n * 12.9898 + random_seed) * 43758.5453); }

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float t = _Time * tempo + phase_offset;
    ModulatorRecord m;
    m.slow_sine = sin(t * 0.45) * 0.5 + 0.5;
    m.fast_pulse = smoothstep(1.0 - pulse_width, 1.0, frac(t * 2.7));
    m.random_hold = h1(floor(t * hold_rate));
    m.saw_sweep = frac(t * 0.2);
    m.danger_pulse = pow(sin(t * 3.14159) * 0.5 + 0.5, 5.0) * mod_depth;
    m.breath = sin(t * 0.23) * 0.5 + 0.5;
    m.pad0 = 0.0;
    m.pad1 = 0.0;
    OutputBuffer[0] = m;
}
"""


mod_preview = COMMON_RENDER + r"""
struct ModulatorRecord { float slow_sine; float fast_pulse; float random_hold; float saw_sweep; float danger_pulse; float breath; float pad0; float pad1; };
StructuredBuffer<ModulatorRecord> Mods : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    ModulatorRecord m = Mods[0];
    float v = 0.0;
    v += 1.0 - smoothstep(0.0, 0.01, abs(uv.y - (0.15 + m.slow_sine * 0.7)));
    v += 1.0 - smoothstep(0.0, 0.01, abs(uv.y - (0.15 + m.fast_pulse * 0.7)));
    v += 1.0 - smoothstep(0.0, 0.01, abs(uv.y - (0.15 + m.danger_pulse * 0.7)));
    OutputUAV[pixel] = float4(float3(0.0, 0.45, 0.65) + float3(1.0, 0.25, 0.02) * v, 1.0);
}
"""


compositor_hlsl = COMMON_RENDER + r"""
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 p = aspect_uv(pixel);
    float3 bg = float3(0.004, 0.018, 0.026) + float3(0.0, 0.035, 0.055) * smoothstep(0.95, 0.1, length(p));
    float3 space = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 field = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 contours = _Tex2.SampleLevel(LinearSampler, uv, 0).rgb * contour_gain;
    float3 hud = _Tex3.SampleLevel(LinearSampler, uv, 0).rgb * hud_gain;
    float3 routes = _Tex4.SampleLevel(LinearSampler, uv, 0).rgb * route_gain;
    float3 beacons = _Tex5.SampleLevel(LinearSampler, uv, 0).rgb * beacon_gain;
    float3 plate = _Tex6.SampleLevel(LinearSampler, uv, 0).rgb * plate_gain;
    float3 micro = _Tex7.SampleLevel(LinearSampler, uv, 0).rgb * microdetail_gain;
    float3 col = (bg + space * 0.7 + field * 0.18) * background_gain + contours + hud * hud_depth_mix + plate * plate_under_routes + routes * route_over_contours + beacons * beacon_priority + micro;
    if (layer_solo == 1) col = contours;
    if (layer_solo == 2) col = hud;
    if (layer_solo == 3) col = routes;
    if (layer_solo == 4) col = beacons;
    if (layer_solo == 5) col = plate;
    if (layer_solo == 6) col = micro;
    col.rg = lerp(col.rg, col.gr, channel_swap);
    col = lerp(col, 1.0 - col, blueprint_invert);
    col *= 1.0 + additive_overload;
    col = min(col, additive_clip);
    col = max(col, black_floor);
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


post_hlsl = COMMON_RENDER + r"""
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 p = uv - 0.5;
    float r = length(p);
    float2 warp = p * (1.0 + barrel_distortion_post * r * r);
    float2 su = warp + 0.5;
    float ca = chromatic_aberration;
    float3 col;
    col.r = _Tex0.SampleLevel(LinearSampler, su + float2(ca, 0), 0).r;
    col.g = _Tex0.SampleLevel(LinearSampler, su, 0).g;
    col.b = _Tex0.SampleLevel(LinearSampler, su - float2(ca, 0), 0).b;
    col = (col - 0.5) * contrast + 0.5 + exposure;
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = lerp(float3(lum, lum, lum), col, saturation);
    col += max(col - bloom_threshold, 0.0) * bloom_gain * 0.28;
    col.b += cyan_push * 0.08;
    col.r += orange_push * 0.04;
    float vig = smoothstep(vignette_radius, vignette_radius - 0.45, r) * vignette_strength;
    col *= lerp(1.0, vig, vignette_strength);
    float grain = (hash_lv2(uv * _Resolution.xy + _Time * 17.0) - 0.5) * grain_amount;
    col += grain + scanline_amount * sin(uv.y * _Resolution.y * 3.14159) * 0.018;
    col = lerp(col, col.bgr, infrared_mode * 0.25);
    col *= 1.0 + sensor_damage * step(0.997, hash_lv2(floor(uv * 80.0 + _Time)));
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
"""


def params(lines):
    return "\n".join("  - " + x for x in lines)


def manifest_header(title, mode="generator", inputs=None, features=None):
    txt = f'name: "{title}"\nversion: "1.0"\nmode: {mode}\n'
    if mode == "generator":
        txt += f"resolution: {RES}\n"
    else:
        txt += 'resolution_source: "match:input"\n'
    if features:
        txt += "features: [" + ", ".join(features) + "]\n"
    if inputs:
        txt += "\ninputs:\n" + "\n".join(f'  - {{ name: "{n}", slot: {i}, required: true }}' for i, n in enumerate(inputs)) + "\n"
    return txt


write_module("lv_space_field", {
    "render.hlsl": space_hlsl,
    "manifest.yaml": manifest_header("LV Space Field") + "\nparameters:\n" + params([
        "{ name: layout_preset, display: \"Layout Preset\", type: enum, default: 0, options: [Reference, WideOrbit, DenseMap, DeepLens, Minimal], flags: button_grid, group: \"Instrument\" }",
        "{ name: scene_seed, display: \"Scene Seed\", type: int, min: 0, max: 999, default: 7, group: \"Instrument\" }",
        "{ name: global_scale, display: \"Global Scale\", type: float, min: 0.5, max: 2.5, default: 1.0, group: \"Space\" }",
        "{ name: global_offset, display: \"Global Offset\", type: point2D, min: [-1,-1], max: [1,1], default: [0,0], group: \"Space\" }",
        "{ name: global_rotation, display: \"Global Rotation\", type: float, min: -45, max: 45, default: 0, group: \"Space\" }",
        "{ name: lens_center, display: \"Lens Center\", type: point2D, min: [-1,-1], max: [1,1], default: [0,0], group: \"Lens\" }",
        "{ name: barrel_distortion, display: \"Barrel Distortion\", type: float, min: 0, max: 0.35, default: 0.09, group: \"Lens\" }",
        "{ name: edge_falloff, display: \"Edge Falloff\", type: float, min: 0, max: 1, default: 0.88, group: \"Lens\" }",
        "{ name: time_mode, display: \"Time Mode\", type: enum, default: 1, options: [Still, SlowDrift, RadarSweep, Pulse], flags: button_grid, group: \"Motion\" }",
        "{ name: animation_speed, display: \"Animation Speed\", type: float, min: 0, max: 4, default: 0.45, group: \"Motion\" }",
        "{ name: drift_vector, display: \"Drift Vector\", type: point2D, min: [-1,-1], max: [1,1], default: [0.2,-0.08], group: \"Motion\" }",
        "{ name: breathing_amount, display: \"Breathing\", type: float, min: 0, max: 1, default: 0.18, group: \"Motion\" }",
        "{ name: coordinate_shear, display: \"Coordinate Shear\", type: float, min: -1, max: 1, default: 0, group: \"Avant\" }",
        "{ name: polar_fold_amount, display: \"Polar Fold\", type: float, min: 0, max: 1, default: 0.12, group: \"Avant\" }",
        "{ name: space_quantize, display: \"Space Quantize\", type: float, min: 0, max: 1, default: 0.08, group: \"Avant\" }",
        "{ name: lens_wobble, display: \"Lens Wobble\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
        "{ name: anamorphic_pull, display: \"Anamorphic Pull\", type: float, min: -1, max: 1, default: 0, group: \"Avant\" }",
        "{ name: freeze_time, display: \"Freeze Time\", type: bool, default: false, flags: button, group: \"Performance\" }",
        "{ name: motion_preview_gain, display: \"Motion Preview\", type: float, min: 0, max: 2, default: 1, group: \"Performance\" }",
    ]) + "\n\npasses:\n  - { name: render, shader: render.hlsl, target: cs_5_0, output: output }\n\noutputs:\n  - { name: \"Space\", pass: render }\n"
})

write_module("lv_heightfield", {
    "render.hlsl": height_hlsl,
    "manifest.yaml": manifest_header("LV Heightfield", features=["noise"]) + "\nparameters:\n" + params([
        "{ name: terrain_preset, display: \"Terrain Preset\", type: enum, default: 0, options: [ReferenceIslands, MountainRings, LiquidRidges, SparseSurvey, DenseScan], flags: button_grid, group: \"Instrument\" }",
        "{ name: field_scale, display: \"Field Scale\", type: float, min: 0.4, max: 6, default: 2.3, group: \"Field\" }",
        "{ name: ridge_strength, display: \"Ridge Strength\", type: float, min: 0, max: 2, default: 0.65, group: \"Field\" }",
        "{ name: island_count, display: \"Island Count\", type: int, min: 1, max: 12, default: 7, group: \"Field\" }",
        "{ name: central_bias, display: \"Central Bias\", type: float, min: 0, max: 2, default: 0.7, group: \"Field\" }",
        "{ name: noise_octaves, display: \"Noise Octaves\", type: int, min: 1, max: 8, default: 5, group: \"Field\" }",
        "{ name: warp_amount, display: \"Warp Amount\", type: float, min: 0, max: 1.5, default: 0.45, group: \"Deform\" }",
        "{ name: warp_scale, display: \"Warp Scale\", type: float, min: 0.5, max: 8, default: 2.2, group: \"Deform\" }",
        "{ name: erosion_amount, display: \"Erosion\", type: float, min: 0, max: 1, default: 0.2, group: \"Deform\" }",
        "{ name: fault_line_gain, display: \"Fault Lines\", type: float, min: 0, max: 1, default: 0.25, group: \"Deform\" }",
        "{ name: vortex_pull, display: \"Vortex Pull\", type: float, min: 0, max: 1, default: 0.15, group: \"Deform\" }",
        "{ name: tectonic_shatter, display: \"Tectonic Shatter\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
        "{ name: magnetic_anomaly, display: \"Magnetic Anomaly\", type: float, min: 0, max: 1, default: 0.2, group: \"Avant\" }",
        "{ name: contour_melt, display: \"Contour Melt\", type: float, min: 0, max: 1, default: 0.15, group: \"Avant\" }",
        "{ name: field_inversion, display: \"Field Inversion\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
        "{ name: ghost_field_mix, display: \"Ghost Field\", type: float, min: 0, max: 1, default: 0.12, group: \"Avant\" }",
        "{ name: drift_amount, display: \"Drift Amount\", type: float, min: 0, max: 1, default: 0.15, group: \"Motion\" }",
        "{ name: drift_speed, display: \"Drift Speed\", type: float, min: 0, max: 2, default: 0.22, group: \"Motion\" }",
        "{ name: terrain_phase, display: \"Terrain Phase\", type: float, min: 0, max: 6.283, default: 0, group: \"Motion\" }",
        "{ name: phase_lock, display: \"Phase Lock\", type: bool, default: false, flags: button, group: \"Motion\" }",
    ]) + "\n\npasses:\n  - { name: render, shader: render.hlsl, target: cs_5_0, output: output }\n\noutputs:\n  - { name: \"Heightfield\", pass: render }\n"
})

write_module("lv_contour_plan", {
    "compute.hlsl": contour_compute,
    "preview.hlsl": contour_preview,
    "manifest.yaml": manifest_header("LV Contour Plan") + """
buffers:
  - { name: contour_segments, structured: true, element_size: 48, element_count: 512 }

parameters:
""" + params([
        "{ name: scene_seed, display: \"Scene Seed\", type: int, min: 0, max: 999, default: 7, group: \"Instrument\" }",
        "{ name: contour_density, display: \"Contour Density\", type: int, min: 8, max: 80, default: 42, group: \"Contours\" }",
        "{ name: major_interval, display: \"Major Interval\", type: int, min: 2, max: 12, default: 5, group: \"Contours\" }",
        "{ name: segment_count, display: \"Segment Count\", type: int, min: 128, max: 512, default: 420, group: \"Contours\" }",
        "{ name: line_simplify, display: \"Line Simplify\", type: float, min: 0, max: 1, default: 0.2, group: \"Contours\" }",
        "{ name: active_region_radius, display: \"Active Region\", type: float, min: 0.2, max: 1.5, default: 1.0, group: \"Contours\" }",
        "{ name: contour_breakup, display: \"Breakup\", type: float, min: 0, max: 1, default: 0.04, group: \"Contours\" }",
        "{ name: grouping_mode, display: \"Grouping\", type: enum, default: 2, options: [ByLevel, ByIsland, Mixed], flags: button_grid, group: \"Structure\" }",
        "{ name: level_bias, display: \"Level Bias\", type: float, min: -1, max: 1, default: 0.1, group: \"Structure\" }",
        "{ name: island_isolation, display: \"Island Isolation\", type: float, min: 0, max: 1, default: 0.35, group: \"Structure\" }",
        "{ name: nested_loop_bias, display: \"Nested Loops\", type: float, min: 0, max: 1, default: 0.62, group: \"Structure\" }",
        "{ name: broken_survey_mode, display: \"Broken Survey\", type: float, min: 0, max: 1, default: 0.08, group: \"Avant\" }",
        "{ name: false_topology, display: \"False Topology\", type: float, min: 0, max: 1, default: 0.2, group: \"Avant\" }",
        "{ name: scanline_slice, display: \"Scanline Slice\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
        "{ name: contour_echo_count, display: \"Echo Count\", type: float, min: 0, max: 8, default: 1, group: \"Avant\" }",
        "{ name: contour_echo_offset, display: \"Echo Offset\", type: float, min: 0, max: 0.08, default: 0.012, group: \"Avant\" }",
    ]) + """

passes:
  - { name: compute, shader: compute.hlsl, target: cs_5_0, dispatch: [32, 1, 1], thread_group_x: 16, thread_group_y: 1, output: "buffer:contour_segments" }
  - { name: preview, shader: preview.hlsl, target: cs_5_0, inputs: [ { slot: 0, source: "buffer:contour_segments" } ] }

outputs:
  - { name: "Contour Preview", pass: preview }

data_outputs:
  - name: "Contour Segments"
    buffer: "contour_segments"
    schema:
      - { name: a, type: float2 }
      - { name: b, type: float2 }
      - { name: level, type: float }
      - { name: group_id, type: float }
      - { name: weight, type: float }
      - { name: active, type: float }
      - { name: role, type: float }
      - { name: pad0, type: float }
      - { name: pad1, type: float }
      - { name: pad2, type: float }
"""
})

contour_schema = """
data_inputs:
  - name: "Contour Segments"
    slot: 0
    schema:
      - { name: a, type: float2 }
      - { name: b, type: float2 }
      - { name: level, type: float }
      - { name: group_id, type: float }
      - { name: weight, type: float }
      - { name: active, type: float }
      - { name: role, type: float }
      - { name: pad0, type: float }
      - { name: pad1, type: float }
      - { name: pad2, type: float }
"""

write_module("lv_contour_renderer", {
    "render.hlsl": contour_render,
    "manifest.yaml": manifest_header("LV Contour Renderer") + contour_schema + "\nparameters:\n" + params([
        "{ name: contour_palette, display: \"Palette\", type: enum, default: 0, options: [ReferenceCyan, IceBlue, DeepTeal, ElectricBlue, WhiteTechnical], flags: button_grid, group: \"Instrument\" }",
        "{ name: contour_color, display: \"Contour Color\", type: color, default: [0.0, 0.74, 1.0], group: \"Color\" }",
        "{ name: minor_line_width, display: \"Minor Width\", type: float, min: 0.0005, max: 0.008, default: 0.0016, group: \"Stroke\" }",
        "{ name: major_line_width, display: \"Major Width\", type: float, min: 0.001, max: 0.015, default: 0.0032, group: \"Stroke\" }",
        "{ name: minor_gain, display: \"Minor Gain\", type: float, min: 0, max: 2, default: 0.75, group: \"Stroke\" }",
        "{ name: major_gain, display: \"Major Gain\", type: float, min: 0, max: 4, default: 1.65, group: \"Stroke\" }",
        "{ name: line_softness, display: \"Line Softness\", type: float, min: 0.0002, max: 0.02, default: 0.0025, group: \"Stroke\" }",
        "{ name: glow_radius, display: \"Glow Radius\", type: float, min: 0, max: 0.06, default: 0.018, group: \"Glow\" }",
        "{ name: glow_gain, display: \"Glow Gain\", type: float, min: 0, max: 4, default: 1.2, group: \"Glow\" }",
        "{ name: edge_bloom_bias, display: \"Edge Bloom\", type: float, min: 0, max: 1, default: 0.2, group: \"Glow\" }",
        "{ name: major_level_halo, display: \"Major Halo\", type: float, min: 0, max: 2, default: 0.5, group: \"Glow\" }",
        "{ name: line_dash_amount, display: \"Dash Amount\", type: float, min: 0, max: 1, default: 0.05, group: \"Pattern\" }",
        "{ name: dash_scale, display: \"Dash Scale\", type: float, min: 0, max: 16, default: 4, group: \"Pattern\" }",
        "{ name: dash_phase, display: \"Dash Phase\", type: float, min: 0, max: 1, default: 0, group: \"Pattern\" }",
        "{ name: brightness_by_level, display: \"Level Brightness\", type: float, min: 0, max: 1, default: 0.35, group: \"Pattern\" }",
        "{ name: fade_near_edges, display: \"Edge Fade\", type: float, min: 0, max: 1, default: 0.15, group: \"Pattern\" }",
        "{ name: neon_overburn, display: \"Neon Overburn\", type: float, min: 0, max: 2, default: 0.18, group: \"Avant\" }",
        "{ name: xray_double_line, display: \"XRay Double\", type: float, min: 0, max: 1, default: 0.08, group: \"Avant\" }",
        "{ name: thermal_edge_bleed, display: \"Thermal Bleed\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
        "{ name: spectral_split, display: \"Spectral Split\", type: float, min: 0, max: 1, default: 0.12, group: \"Avant\" }",
        "{ name: contour_afterimage, display: \"Afterimage\", type: float, min: 0, max: 1, default: 0.12, group: \"Avant\" }",
    ]) + "\n\npasses:\n  - { name: render, shader: render.hlsl, target: cs_5_0, inputs: [ { slot: 0, source: \"data:0\" } ] }\n\noutputs:\n  - { name: \"Contours\", pass: render }\n"
})

write_module("lv_hud_ring_plan", {
    "compute.hlsl": hud_compute,
    "preview.hlsl": hud_preview,
    "manifest.yaml": manifest_header("LV HUD Ring Plan") + """
buffers:
  - { name: hud_arcs, structured: true, element_size: 48, element_count: 96 }

parameters:
""" + params([
        "{ name: ring_preset, display: \"Ring Preset\", type: enum, default: 0, options: [Reference, DenseInstrument, SparseLens, Radar, Targeting], flags: button_grid, group: \"Instrument\" }",
        "{ name: ring_count, display: \"Ring Count\", type: int, min: 2, max: 18, default: 11, group: \"Structure\" }",
        "{ name: outer_frame_radius, display: \"Outer Radius\", type: float, min: 0.4, max: 1.4, default: 0.86, group: \"Structure\" }",
        "{ name: inner_ring_radius, display: \"Inner Radius\", type: float, min: 0.05, max: 1, default: 0.18, group: \"Structure\" }",
        "{ name: arc_fragmentation, display: \"Arc Fragmentation\", type: float, min: 0, max: 1, default: 0.28, group: \"Structure\" }",
        "{ name: tick_density, display: \"Tick Density\", type: int, min: 8, max: 240, default: 92, group: \"Ticks\" }",
        "{ name: dotted_band_count, display: \"Dotted Bands\", type: int, min: 0, max: 8, default: 3, group: \"Ticks\" }",
        "{ name: radial_line_count, display: \"Radial Lines\", type: int, min: 0, max: 64, default: 22, group: \"Ticks\" }",
        "{ name: angle_offset, display: \"Angle Offset\", type: float, min: 0, max: 360, default: 12, group: \"Motion\" }",
        "{ name: ring_jitter, display: \"Ring Jitter\", type: float, min: 0, max: 0.05, default: 0.006, group: \"Motion\" }",
        "{ name: edge_crop_bias, display: \"Edge Crop\", type: float, min: 0, max: 1, default: 0.65, group: \"Motion\" }",
        "{ name: broken_scope_mode, display: \"Broken Scope\", type: float, min: 0, max: 1, default: 0.08, group: \"Avant\" }",
        "{ name: ritual_geometry, display: \"Ritual Geometry\", type: float, min: 0, max: 1, default: 0.12, group: \"Avant\" }",
        "{ name: misregistered_rings, display: \"Misregistration\", type: float, min: 0, max: 1, default: 0.15, group: \"Avant\" }",
        "{ name: radar_sweep_gap, display: \"Sweep Gap\", type: float, min: 0, max: 1, default: 0.3, group: \"Avant\" }",
        "{ name: orbital_precession, display: \"Precession\", type: float, min: -2, max: 2, default: 0.2, group: \"Avant\" }",
        "{ name: ring_rotation_speed, display: \"Ring Rotation\", type: float, min: -2, max: 2, default: 0.03, group: \"Motion\" }",
        "{ name: tick_crawl_speed, display: \"Tick Crawl\", type: float, min: -4, max: 4, default: 0.15, group: \"Motion\" }",
        "{ name: sweep_angle, display: \"Sweep Angle\", type: float, min: 0, max: 6.283, default: 0, group: \"Motion\" }",
        "{ name: ring_width, display: \"Ring Width\", type: float, min: 0.0005, max: 0.018, default: 0.0024, group: \"Shared\" }",
    ]) + """

passes:
  - { name: compute, shader: compute.hlsl, target: cs_5_0, dispatch: [6, 1, 1], thread_group_x: 16, thread_group_y: 1, output: "buffer:hud_arcs" }
  - { name: preview, shader: preview.hlsl, target: cs_5_0, inputs: [ { slot: 0, source: "buffer:hud_arcs" } ] }

outputs:
  - { name: "HUD Preview", pass: preview }

data_outputs:
  - name: "HUD Arcs"
    buffer: "hud_arcs"
    schema:
      - { name: center, type: float2 }
      - { name: radius, type: float }
      - { name: start_angle, type: float }
      - { name: end_angle, type: float }
      - { name: width, type: float }
      - { name: dash_count, type: float }
      - { name: role, type: float }
      - { name: active, type: float }
      - { name: pad0, type: float }
      - { name: pad1, type: float }
      - { name: pad2, type: float }
"""
})

hud_schema = """
data_inputs:
  - name: "HUD Arcs"
    slot: 0
    schema:
      - { name: center, type: float2 }
      - { name: radius, type: float }
      - { name: start_angle, type: float }
      - { name: end_angle, type: float }
      - { name: width, type: float }
      - { name: dash_count, type: float }
      - { name: role, type: float }
      - { name: active, type: float }
      - { name: pad0, type: float }
      - { name: pad1, type: float }
      - { name: pad2, type: float }
"""

write_module("lv_hud_ring_renderer", {
    "render.hlsl": hud_render,
    "manifest.yaml": manifest_header("LV HUD Ring Renderer") + hud_schema + "\nparameters:\n" + params([
        "{ name: ring_color, display: \"Ring Color\", type: color, default: [0.0, 0.42, 0.62], group: \"Color\" }",
        "{ name: accent_color, display: \"Accent Color\", type: color, default: [0.45, 0.85, 1.0], group: \"Color\" }",
        "{ name: ring_width, display: \"Ring Width\", type: float, min: 0.0005, max: 0.018, default: 0.0022, group: \"Stroke\" }",
        "{ name: tick_width, display: \"Tick Width\", type: float, min: 0.0005, max: 0.012, default: 0.0014, group: \"Stroke\" }",
        "{ name: dash_sharpness, display: \"Dash Sharpness\", type: float, min: 0, max: 1, default: 0.35, group: \"Stroke\" }",
        "{ name: ring_opacity, display: \"Opacity\", type: float, min: 0, max: 2, default: 0.85, group: \"Glow\" }",
        "{ name: ring_glow, display: \"Ring Glow\", type: float, min: 0, max: 3, default: 0.9, group: \"Glow\" }",
        "{ name: outer_frame_gain, display: \"Outer Frame\", type: float, min: 0, max: 3, default: 1.1, group: \"Glow\" }",
        "{ name: background_ring_gain, display: \"Background Rings\", type: float, min: 0, max: 1, default: 0.4, group: \"Glow\" }",
        "{ name: parallax_offset, display: \"Parallax Offset\", type: point2D, min: [-1,-1], max: [1,1], default: [0.03,-0.02], group: \"Depth\" }",
        "{ name: depth_fade, display: \"Depth Fade\", type: float, min: 0, max: 1, default: 0.15, group: \"Depth\" }",
        "{ name: oscilloscope_wobble, display: \"Scope Wobble\", type: float, min: 0, max: 1, default: 0.05, group: \"Avant\" }",
        "{ name: scope_burn_in, display: \"Scope Burn\", type: float, min: 0, max: 1, default: 0.18, group: \"Avant\" }",
        "{ name: thin_glass_refraction, display: \"Glass Refraction\", type: float, min: 0, max: 1, default: 0.08, group: \"Avant\" }",
        "{ name: radial_chromatic_split, display: \"Radial Split\", type: float, min: 0, max: 1, default: 0.15, group: \"Avant\" }",
        "{ name: stuttered_ticks, display: \"Stuttered Ticks\", type: float, min: 0, max: 1, default: 0.1, group: \"Avant\" }",
        "{ name: tick_crawl_speed, display: \"Tick Crawl\", type: float, min: -4, max: 4, default: 0.15, group: \"Motion\" }",
    ]) + "\n\npasses:\n  - { name: render, shader: render.hlsl, target: cs_5_0, inputs: [ { slot: 0, source: \"data:0\" } ] }\n\noutputs:\n  - { name: \"HUD Rings\", pass: render }\n"
})

write_module("lv_route_plan", {
    "compute.hlsl": route_plan,
    "preview.hlsl": route_spec_preview,
    "manifest.yaml": manifest_header("LV Route Plan") + """
buffers:
  - { name: route_specs, structured: true, element_size: 48, element_count: 96 }

parameters:
""" + params([
        "{ name: route_preset, display: \"Route Preset\", type: enum, default: 0, options: [Reference, OrbitalTriangle, SurveyNetwork, SparseNodes, DenseMission], flags: button_grid, group: \"Instrument\" }",
        "{ name: route_seed, display: \"Route Seed\", type: int, min: 0, max: 999, default: 9, group: \"Instrument\" }",
        "{ name: route_count, display: \"Route Count\", type: int, min: 4, max: 96, default: 34, group: \"Structure\" }",
        "{ name: orbit_arc_count, display: \"Orbit Arcs\", type: int, min: 0, max: 24, default: 9, group: \"Structure\" }",
        "{ name: diagonal_count, display: \"Diagonals\", type: int, min: 0, max: 32, default: 7, group: \"Structure\" }",
        "{ name: polygon_chain_count, display: \"Polygon Chains\", type: int, min: 0, max: 24, default: 5, group: \"Structure\" }",
        "{ name: route_curvature, display: \"Route Curvature\", type: float, min: 0, max: 1, default: 0.55, group: \"Structure\" }",
        "{ name: route_span, display: \"Route Span\", type: float, min: 0.2, max: 1.8, default: 1.05, group: \"Structure\" }",
        "{ name: endpoint_snap_to_contours, display: \"Snap To Contours\", type: float, min: 0, max: 1, default: 0.35, group: \"Structure\" }",
        "{ name: orange_vs_cyan_mix, display: \"Orange Mix\", type: float, min: 0, max: 1, default: 0.72, group: \"Color\" }",
        "{ name: route_layer_spread, display: \"Layer Spread\", type: float, min: 0, max: 1, default: 0.55, group: \"Depth\" }",
        "{ name: mission_abort_paths, display: \"Mission Abort\", type: float, min: 0, max: 1, default: 0.08, group: \"Avant\" }",
        "{ name: forbidden_geometry, display: \"Forbidden Geometry\", type: float, min: 0, max: 1, default: 0.14, group: \"Avant\" }",
        "{ name: constellation_mode, display: \"Constellation\", type: float, min: 0, max: 1, default: 0.25, group: \"Avant\" }",
        "{ name: triangulation_web, display: \"Triangulation Web\", type: float, min: 0, max: 1, default: 0.25, group: \"Avant\" }",
        "{ name: route_interference, display: \"Interference\", type: float, min: 0, max: 1, default: 0.2, group: \"Avant\" }",
        "{ name: route_growth_phase, display: \"Growth Phase\", type: float, min: 0, max: 1, default: 1, group: \"Motion\" }",
        "{ name: route_retarget_rate, display: \"Retarget Rate\", type: float, min: 0, max: 4, default: 0.2, group: \"Motion\" }",
    ]) + """

passes:
  - { name: compute, shader: compute.hlsl, target: cs_5_0, dispatch: [6, 1, 1], thread_group_x: 16, thread_group_y: 1, output: "buffer:route_specs" }
  - { name: preview, shader: preview.hlsl, target: cs_5_0, inputs: [ { slot: 0, source: "buffer:route_specs" } ] }

outputs:
  - { name: "Route Preview", pass: preview }

data_outputs:
  - name: "Route Specs"
    buffer: "route_specs"
    schema:
      - { name: p0, type: float2 }
      - { name: p1, type: float2 }
      - { name: p2, type: float2 }
      - { name: p3, type: float2 }
      - { name: width, type: float }
      - { name: role, type: float }
      - { name: route_id, type: float }
      - { name: active, type: float }
"""
})

route_spec_schema = """
data_inputs:
  - name: "Route Specs"
    slot: 0
    schema:
      - { name: p0, type: float2 }
      - { name: p1, type: float2 }
      - { name: p2, type: float2 }
      - { name: p3, type: float2 }
      - { name: width, type: float }
      - { name: role, type: float }
      - { name: route_id, type: float }
      - { name: active, type: float }
"""

route_seg_schema = """
data_inputs:
  - name: "Route Segments"
    slot: 0
    schema:
      - { name: a, type: float2 }
      - { name: b, type: float2 }
      - { name: width, type: float }
      - { name: role, type: float }
      - { name: route_id, type: float }
      - { name: route_t0, type: float }
      - { name: route_t1, type: float }
      - { name: active, type: float }
      - { name: pad0, type: float }
      - { name: pad1, type: float }
"""

write_module("lv_route_expander", {
    "expand.hlsl": route_expand,
    "preview.hlsl": route_preview,
    "manifest.yaml": manifest_header("LV Route Expander") + """
buffers:
  - { name: route_segments, structured: true, element_size: 48, element_count: 768 }
""" + route_spec_schema + "\nparameters:\n" + params([
        "{ name: subdivision_quality, display: \"Subdivision\", type: int, min: 4, max: 64, default: 8, group: \"Expand\" }",
        "{ name: width_scale, display: \"Width Scale\", type: float, min: 0.25, max: 3, default: 1, group: \"Expand\" }",
        "{ name: taper_mode, display: \"Taper Mode\", type: enum, default: 1, options: [None, Endpoint, CenterBulge, Pulse], flags: button_grid, group: \"Shape\" }",
        "{ name: dash_count, display: \"Dash Count\", type: float, min: 0, max: 32, default: 0, group: \"Pattern\" }",
        "{ name: dash_phase, display: \"Dash Phase\", type: float, min: 0, max: 1, default: 0, group: \"Pattern\" }",
        "{ name: dash_softness, display: \"Dash Softness\", type: float, min: 0, max: 1, default: 0.2, group: \"Pattern\" }",
        "{ name: join_style, display: \"Join Style\", type: enum, default: 0, options: [Round, Bevel, Sharp], flags: button_grid, group: \"Caps\" }",
        "{ name: cap_style, display: \"Cap Style\", type: enum, default: 2, options: [Round, Flat, GlowDot], flags: button_grid, group: \"Caps\" }",
        "{ name: endpoint_swelling, display: \"Endpoint Swell\", type: float, min: 0, max: 2, default: 0.6, group: \"Caps\" }",
        "{ name: corner_energy, display: \"Corner Energy\", type: float, min: 0, max: 2, default: 0.4, group: \"Caps\" }",
        "{ name: signal_dropout, display: \"Signal Dropout\", type: float, min: 0, max: 1, default: 0.02, group: \"Avant\" }",
        "{ name: route_shiver, display: \"Route Shiver\", type: float, min: 0, max: 0.08, default: 0.004, group: \"Avant\" }",
        "{ name: temporal_smear, display: \"Temporal Smear\", type: float, min: 0, max: 1, default: 0.15, group: \"Avant\" }",
        "{ name: danger_zone_thicken, display: \"Danger Thicken\", type: float, min: 0, max: 1, default: 0.2, group: \"Avant\" }",
        "{ name: overdraw_echoes, display: \"Overdraw Echoes\", type: int, min: 0, max: 8, default: 1, group: \"Avant\" }",
        "{ name: route_id_bias, display: \"Route ID Bias\", type: float, min: 0, max: 999, default: 13, group: \"Debug\" }",
    ]) + """

passes:
  - { name: expand, shader: expand.hlsl, target: cs_5_0, dispatch: [48, 1, 1], thread_group_x: 16, thread_group_y: 1, output: "buffer:route_segments", inputs: [ { slot: 0, source: "data:0" } ] }
  - { name: preview, shader: preview.hlsl, target: cs_5_0, inputs: [ { slot: 0, source: "buffer:route_segments" } ] }

outputs:
  - { name: "Expanded Routes", pass: preview }

data_outputs:
  - name: "Route Segments"
    buffer: "route_segments"
    schema:
      - { name: a, type: float2 }
      - { name: b, type: float2 }
      - { name: width, type: float }
      - { name: role, type: float }
      - { name: route_id, type: float }
      - { name: route_t0, type: float }
      - { name: route_t1, type: float }
      - { name: active, type: float }
      - { name: pad0, type: float }
      - { name: pad1, type: float }
"""
})

write_module("lv_route_renderer", {
    "render.hlsl": route_render,
    "manifest.yaml": manifest_header("LV Route Renderer") + route_seg_schema + "\nparameters:\n" + params([
        "{ name: orange_color, display: \"Orange\", type: color, default: [1.0, 0.34, 0.03], group: \"Color\" }",
        "{ name: cyan_route_color, display: \"Cyan Route\", type: color, default: [0.0, 0.74, 1.0], group: \"Color\" }",
        "{ name: route_core_gain, display: \"Core Gain\", type: float, min: 0, max: 5, default: 1.5, group: \"Stroke\" }",
        "{ name: route_glow_gain, display: \"Glow Gain\", type: float, min: 0, max: 6, default: 1.8, group: \"Glow\" }",
        "{ name: route_glow_radius, display: \"Glow Radius\", type: float, min: 0, max: 0.08, default: 0.025, group: \"Glow\" }",
        "{ name: dotted_marker_gain, display: \"Dotted Markers\", type: float, min: 0, max: 4, default: 1, group: \"Markers\" }",
        "{ name: travel_dot_count, display: \"Travel Dots\", type: int, min: 0, max: 128, default: 26, group: \"Markers\" }",
        "{ name: travel_dot_speed, display: \"Travel Speed\", type: float, min: -4, max: 4, default: 0.25, group: \"Markers\" }",
        "{ name: endpoint_boost, display: \"Endpoint Boost\", type: float, min: 0, max: 5, default: 1.9, group: \"Markers\" }",
        "{ name: long_arc_emphasis, display: \"Long Arcs\", type: float, min: 0, max: 3, default: 1.2, group: \"Emphasis\" }",
        "{ name: diagonal_emphasis, display: \"Diagonals\", type: float, min: 0, max: 3, default: 1.0, group: \"Emphasis\" }",
        "{ name: white_hot_crossings, display: \"White Crossings\", type: float, min: 0, max: 2, default: 0.4, group: \"Emphasis\" }",
        "{ name: plasma_route_bleed, display: \"Plasma Bleed\", type: float, min: 0, max: 1, default: 0.18, group: \"Avant\" }",
        "{ name: red_alert_mode, display: \"Red Alert\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
        "{ name: route_corona, display: \"Route Corona\", type: float, min: 0, max: 1, default: 0.12, group: \"Avant\" }",
        "{ name: afterburn_trails, display: \"Afterburn\", type: float, min: 0, max: 1, default: 0.2, group: \"Avant\" }",
        "{ name: electrical_arcing, display: \"Electrical Arcing\", type: float, min: 0, max: 1, default: 0.1, group: \"Avant\" }",
        "{ name: dash_count, display: \"Dash Count\", type: float, min: 0, max: 32, default: 0, group: \"Pattern\" }",
        "{ name: dash_phase, display: \"Dash Phase\", type: float, min: 0, max: 1, default: 0, group: \"Pattern\" }",
    ]) + "\n\npasses:\n  - { name: render, shader: render.hlsl, target: cs_5_0, inputs: [ { slot: 0, source: \"data:0\" } ] }\n\noutputs:\n  - { name: \"Routes\", pass: render }\n"
})

write_module("lv_beacon_plan", {
    "compute.hlsl": beacon_plan,
    "preview.hlsl": beacon_preview,
    "manifest.yaml": manifest_header("LV Beacon Plan") + """
buffers:
  - { name: beacons, structured: true, element_size: 32, element_count: 512 }

parameters:
""" + params([
        "{ name: beacon_preset, display: \"Beacon Preset\", type: enum, default: 0, options: [Reference, SparseStars, DenseTelemetry, RouteNodes, ContourHotspots], flags: button_grid, group: \"Instrument\" }",
        "{ name: white_beacon_count, display: \"White Beacons\", type: int, min: 0, max: 32, default: 8, group: \"Counts\" }",
        "{ name: orange_node_count, display: \"Orange Nodes\", type: int, min: 0, max: 96, default: 48, group: \"Counts\" }",
        "{ name: cyan_micro_count, display: \"Cyan Micro\", type: int, min: 0, max: 512, default: 220, group: \"Counts\" }",
        "{ name: label_anchor_count, display: \"Label Anchors\", type: int, min: 0, max: 64, default: 28, group: \"Counts\" }",
        "{ name: snap_to_routes, display: \"Snap Routes\", type: float, min: 0, max: 1, default: 0.65, group: \"Placement\" }",
        "{ name: snap_to_contours, display: \"Snap Contours\", type: float, min: 0, max: 1, default: 0.35, group: \"Placement\" }",
        "{ name: central_cluster_strength, display: \"Central Cluster\", type: float, min: 0, max: 1, default: 0.18, group: \"Placement\" }",
        "{ name: edge_cluster_strength, display: \"Edge Cluster\", type: float, min: 0, max: 1, default: 0.25, group: \"Placement\" }",
        "{ name: beacon_seed, display: \"Beacon Seed\", type: int, min: 0, max: 999, default: 31, group: \"Placement\" }",
        "{ name: rogue_signal_count, display: \"Rogue Signals\", type: int, min: 0, max: 64, default: 8, group: \"Avant\" }",
        "{ name: dead_zone_radius, display: \"Dead Zone\", type: float, min: 0, max: 1, default: 0.08, group: \"Avant\" }",
        "{ name: signal_constellations, display: \"Constellations\", type: float, min: 0, max: 1, default: 0.4, group: \"Avant\" }",
        "{ name: anomaly_cluster, display: \"Anomaly Cluster\", type: float, min: 0, max: 1, default: 0.3, group: \"Avant\" }",
        "{ name: beacon_gravity, display: \"Beacon Gravity\", type: float, min: 0, max: 1, default: 0.22, group: \"Avant\" }",
        "{ name: migration_amount, display: \"Migration\", type: float, min: 0, max: 1, default: 0.04, group: \"Motion\" }",
        "{ name: migration_speed, display: \"Migration Speed\", type: float, min: 0, max: 2, default: 0.15, group: \"Motion\" }",
    ]) + """

passes:
  - { name: compute, shader: compute.hlsl, target: cs_5_0, dispatch: [32, 1, 1], thread_group_x: 16, thread_group_y: 1, output: "buffer:beacons" }
  - { name: preview, shader: preview.hlsl, target: cs_5_0, inputs: [ { slot: 0, source: "buffer:beacons" } ] }

outputs:
  - { name: "Beacon Preview", pass: preview }

data_outputs:
  - name: "Beacons"
    buffer: "beacons"
    schema:
      - { name: pos, type: float2 }
      - { name: radius, type: float }
      - { name: role, type: float }
      - { name: intensity, type: float }
      - { name: linked_route, type: float }
      - { name: label_id, type: float }
      - { name: active, type: float }
"""
})

beacon_schema = """
data_inputs:
  - name: "Beacons"
    slot: 0
    schema:
      - { name: pos, type: float2 }
      - { name: radius, type: float }
      - { name: role, type: float }
      - { name: intensity, type: float }
      - { name: linked_route, type: float }
      - { name: label_id, type: float }
      - { name: active, type: float }
"""

write_module("lv_beacon_renderer", {
    "render.hlsl": beacon_render,
    "manifest.yaml": manifest_header("LV Beacon Renderer") + beacon_schema + "\nparameters:\n" + params([
        "{ name: white_beacon_color, display: \"White Beacon\", type: color, default: [0.95, 0.98, 1.0], group: \"Color\" }",
        "{ name: orange_node_color, display: \"Orange Node\", type: color, default: [1.0, 0.34, 0.04], group: \"Color\" }",
        "{ name: cyan_micro_color, display: \"Cyan Micro\", type: color, default: [0.0, 0.78, 1.0], group: \"Color\" }",
        "{ name: beacon_core_size, display: \"Core Size\", type: float, min: 0.001, max: 0.04, default: 0.012, group: \"Shape\" }",
        "{ name: beacon_glow_size, display: \"Glow Size\", type: float, min: 0.005, max: 0.14, default: 0.055, group: \"Glow\" }",
        "{ name: beacon_glow_gain, display: \"Glow Gain\", type: float, min: 0, max: 8, default: 2.6, group: \"Glow\" }",
        "{ name: reticle_count, display: \"Reticles\", type: int, min: 0, max: 4, default: 2, group: \"Reticle\" }",
        "{ name: reticle_radius, display: \"Reticle Radius\", type: float, min: 0.005, max: 0.08, default: 0.03, group: \"Reticle\" }",
        "{ name: pulse_amount, display: \"Pulse\", type: float, min: 0, max: 1, default: 0.2, group: \"Motion\" }",
        "{ name: pulse_speed, display: \"Pulse Speed\", type: float, min: 0, max: 4, default: 0.8, group: \"Motion\" }",
        "{ name: blink_probability, display: \"Blink Probability\", type: float, min: 0, max: 1, default: 0.05, group: \"Motion\" }",
        "{ name: blink_hardness, display: \"Blink Hardness\", type: float, min: 0, max: 1, default: 0.6, group: \"Motion\" }",
        "{ name: micro_point_gain, display: \"Micro Gain\", type: float, min: 0, max: 3, default: 0.8, group: \"Shape\" }",
        "{ name: signal_overload, display: \"Signal Overload\", type: float, min: 0, max: 1, default: 0.1, group: \"Avant\" }",
        "{ name: halation_rings, display: \"Halation Rings\", type: float, min: 0, max: 1, default: 0.3, group: \"Avant\" }",
        "{ name: lens_spark, display: \"Lens Spark\", type: float, min: 0, max: 1, default: 0.08, group: \"Avant\" }",
        "{ name: target_lock_glitch, display: \"Target Glitch\", type: float, min: 0, max: 1, default: 0.1, group: \"Avant\" }",
        "{ name: whiteout_flash, display: \"Whiteout Flash\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
    ]) + "\n\npasses:\n  - { name: render, shader: render.hlsl, target: cs_5_0, inputs: [ { slot: 0, source: \"data:0\" } ] }\n\noutputs:\n  - { name: \"Beacons\", pass: render }\n"
})

write_module("lv_central_plate", {
    "render.hlsl": plate_hlsl,
    "manifest.yaml": manifest_header("LV Central Plate") + "\nparameters:\n" + params([
        "{ name: plate_preset, display: \"Plate Preset\", type: enum, default: 0, options: [ReferenceMesh, RadarTile, RotatedGrid, TargetPlate, Minimal], flags: button_grid, group: \"Instrument\" }",
        "{ name: plate_center, display: \"Plate Center\", type: point2D, min: [0,0], max: [1,1], default: [0.53,0.48], group: \"Layout\" }",
        "{ name: plate_scale, display: \"Plate Scale\", type: float, min: 0.1, max: 1.2, default: 0.42, group: \"Layout\" }",
        "{ name: plate_rotation, display: \"Plate Rotation\", type: float, min: -90, max: 90, default: -18, group: \"Layout\" }",
        "{ name: grid_density, display: \"Grid Density\", type: int, min: 4, max: 80, default: 28, group: \"Geometry\" }",
        "{ name: hatch_density, display: \"Hatch Density\", type: int, min: 0, max: 80, default: 32, group: \"Geometry\" }",
        "{ name: circle_count, display: \"Circle Count\", type: int, min: 0, max: 16, default: 6, group: \"Geometry\" }",
        "{ name: mesh_line_gain, display: \"Mesh Gain\", type: float, min: 0, max: 4, default: 1.25, group: \"Look\" }",
        "{ name: magenta_mix, display: \"Magenta Mix\", type: float, min: 0, max: 1, default: 0.28, group: \"Look\" }",
        "{ name: plate_opacity, display: \"Plate Opacity\", type: float, min: 0, max: 2, default: 0.75, group: \"Look\" }",
        "{ name: plate_blur, display: \"Plate Blur\", type: float, min: 0, max: 1, default: 0.1, group: \"Look\" }",
        "{ name: blend_mode, display: \"Blend Mode\", type: enum, default: 0, options: [Add, Screen, SoftAdd], flags: button_grid, group: \"Look\" }",
        "{ name: depth_stack_layers, display: \"Depth Layers\", type: int, min: 1, max: 8, default: 3, group: \"Depth\" }",
        "{ name: internal_parallax, display: \"Internal Parallax\", type: float, min: 0, max: 1, default: 0.18, group: \"Depth\" }",
        "{ name: broken_hologram, display: \"Broken Hologram\", type: float, min: 0, max: 1, default: 0.12, group: \"Avant\" }",
        "{ name: data_tomb_mode, display: \"Data Tomb\", type: float, min: 0, max: 1, default: 0.05, group: \"Avant\" }",
        "{ name: impossible_grid, display: \"Impossible Grid\", type: float, min: 0, max: 1, default: 0.1, group: \"Avant\" }",
        "{ name: glass_crack_lines, display: \"Glass Cracks\", type: float, min: 0, max: 1, default: 0.05, group: \"Avant\" }",
        "{ name: sigil_overlay, display: \"Sigil Overlay\", type: float, min: 0, max: 1, default: 0.2, group: \"Avant\" }",
    ]) + "\n\npasses:\n  - { name: render, shader: render.hlsl, target: cs_5_0, output: output }\n\noutputs:\n  - { name: \"Central Plate\", pass: render }\n"
})

write_module("lv_microdetail", {
    "render.hlsl": micro_hlsl,
    "manifest.yaml": manifest_header("LV Microdetail") + "\nparameters:\n" + params([
        "{ name: detail_preset, display: \"Detail Preset\", type: enum, default: 0, options: [Reference, Clean, Noisy, DenseTelemetry, Minimal], flags: button_grid, group: \"Instrument\" }",
        "{ name: label_count, display: \"Labels\", type: int, min: 0, max: 128, default: 48, group: \"Counts\" }",
        "{ name: tick_count, display: \"Ticks\", type: int, min: 0, max: 512, default: 220, group: \"Counts\" }",
        "{ name: scan_dot_count, display: \"Scan Dots\", type: int, min: 0, max: 2048, default: 920, group: \"Counts\" }",
        "{ name: short_line_count, display: \"Short Lines\", type: int, min: 0, max: 512, default: 160, group: \"Counts\" }",
        "{ name: label_gain, display: \"Label Gain\", type: float, min: 0, max: 2, default: 0.7, group: \"Gains\" }",
        "{ name: tick_gain, display: \"Tick Gain\", type: float, min: 0, max: 2, default: 0.65, group: \"Gains\" }",
        "{ name: scan_noise_gain, display: \"Scan Noise\", type: float, min: 0, max: 2, default: 0.5, group: \"Gains\" }",
        "{ name: detail_color_mix, display: \"Orange Mix\", type: float, min: 0, max: 1, default: 0.22, group: \"Color\" }",
        "{ name: detail_seed, display: \"Detail Seed\", type: int, min: 0, max: 999, default: 19, group: \"Gains\" }",
        "{ name: flicker_amount, display: \"Flicker\", type: float, min: 0, max: 1, default: 0.12, group: \"Motion\" }",
        "{ name: flicker_speed, display: \"Flicker Speed\", type: float, min: 0, max: 8, default: 1.2, group: \"Motion\" }",
        "{ name: illegible_language_mode, display: \"Illegible Language\", type: float, min: 0, max: 1, default: 0.25, group: \"Avant\" }",
        "{ name: microfilm_noise, display: \"Microfilm Noise\", type: float, min: 0, max: 1, default: 0.2, group: \"Avant\" }",
        "{ name: numeric_rain, display: \"Numeric Rain\", type: float, min: 0, max: 1, default: 0.08, group: \"Avant\" }",
        "{ name: ghost_annotations, display: \"Ghost Notes\", type: float, min: 0, max: 1, default: 0.15, group: \"Avant\" }",
        "{ name: edge_decals, display: \"Edge Decals\", type: float, min: 0, max: 1, default: 0.18, group: \"Avant\" }",
    ]) + "\n\npasses:\n  - { name: render, shader: render.hlsl, target: cs_5_0, output: output }\n\noutputs:\n  - { name: \"Microdetail\", pass: render }\n"
})

write_module("lv_signal_modulators", {
    "compute.hlsl": mod_compute,
    "preview.hlsl": mod_preview,
    "manifest.yaml": manifest_header("LV Signal Modulators") + """
buffers:
  - { name: modulators, structured: true, element_size: 32, element_count: 1 }

parameters:
""" + params([
        "{ name: tempo, display: \"Tempo\", type: float, min: 0, max: 8, default: 1, group: \"Clock\" }",
        "{ name: phase_offset, display: \"Phase Offset\", type: float, min: 0, max: 6.283, default: 0, group: \"Clock\" }",
        "{ name: random_seed, display: \"Random Seed\", type: int, min: 0, max: 999, default: 42, group: \"Random\" }",
        "{ name: hold_rate, display: \"Hold Rate\", type: float, min: 0.1, max: 16, default: 2, group: \"Random\" }",
        "{ name: pulse_width, display: \"Pulse Width\", type: float, min: 0.02, max: 0.9, default: 0.18, group: \"Pulse\" }",
        "{ name: mod_depth, display: \"Mod Depth\", type: float, min: 0, max: 2, default: 1, group: \"Pulse\" }",
    ]) + """

passes:
  - { name: compute, shader: compute.hlsl, target: cs_5_0, dispatch: [1, 1, 1], thread_group_x: 1, thread_group_y: 1, output: "buffer:modulators" }
  - { name: preview, shader: preview.hlsl, target: cs_5_0, inputs: [ { slot: 0, source: "buffer:modulators" } ] }

outputs:
  - { name: "Modulators", pass: preview }

control_outputs:
  - { name: slow_sine, buffer: modulators, element: 0, field_offset: 0, description: "Slow sine 0-1" }
  - { name: fast_pulse, buffer: modulators, element: 0, field_offset: 4, description: "Fast pulse 0-1" }
  - { name: random_hold, buffer: modulators, element: 0, field_offset: 8, description: "Random stepped hold 0-1" }
  - { name: saw_sweep, buffer: modulators, element: 0, field_offset: 12, description: "Saw sweep 0-1" }
  - { name: danger_pulse, buffer: modulators, element: 0, field_offset: 16, description: "Danger pulse 0-1" }
  - { name: breath, buffer: modulators, element: 0, field_offset: 20, description: "Breathing 0-1" }
"""
})

write_module("lv_compositor", {
    "composite.hlsl": compositor_hlsl,
    "manifest.yaml": manifest_header("LV Compositor", mode="filter", inputs=["Space Field", "Heightfield", "Contours", "HUD Rings", "Routes", "Beacons", "Central Plate", "Microdetail"]) + "\nparameters:\n" + params([
        "{ name: background_gain, display: \"Background\", type: float, min: 0, max: 2, default: 1, group: \"Layer Gains\" }",
        "{ name: contour_gain, display: \"Contours\", type: float, min: 0, max: 3, default: 1.1, group: \"Layer Gains\" }",
        "{ name: hud_gain, display: \"HUD\", type: float, min: 0, max: 3, default: 0.85, group: \"Layer Gains\" }",
        "{ name: route_gain, display: \"Routes\", type: float, min: 0, max: 4, default: 1.15, group: \"Layer Gains\" }",
        "{ name: beacon_gain, display: \"Beacons\", type: float, min: 0, max: 4, default: 1.2, group: \"Layer Gains\" }",
        "{ name: plate_gain, display: \"Plate\", type: float, min: 0, max: 3, default: 0.7, group: \"Layer Gains\" }",
        "{ name: microdetail_gain, display: \"Microdetail\", type: float, min: 0, max: 3, default: 0.55, group: \"Layer Gains\" }",
        "{ name: cyan_orange_balance, display: \"Cyan Orange\", type: float, min: -1, max: 1, default: 0, group: \"Balance\" }",
        "{ name: additive_clip, display: \"Additive Clip\", type: float, min: 0.5, max: 8, default: 2.2, group: \"Balance\" }",
        "{ name: black_floor, display: \"Black Floor\", type: float, min: 0, max: 0.2, default: 0.0, group: \"Balance\" }",
        "{ name: layer_solo, display: \"Layer Solo\", type: enum, default: 0, options: [Final, Contours, HUD, Routes, Beacons, Plate, Microdetail], flags: button_grid, group: \"Solo\" }",
        "{ name: route_over_contours, display: \"Routes Over\", type: float, min: 0, max: 2, default: 1, group: \"Depth\" }",
        "{ name: plate_under_routes, display: \"Plate Under\", type: float, min: 0, max: 2, default: 0.8, group: \"Depth\" }",
        "{ name: hud_depth_mix, display: \"HUD Depth\", type: float, min: 0, max: 2, default: 0.8, group: \"Depth\" }",
        "{ name: beacon_priority, display: \"Beacon Priority\", type: float, min: 0, max: 3, default: 1.2, group: \"Depth\" }",
        "{ name: feedback_bleed, display: \"Feedback Bleed\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
        "{ name: channel_swap, display: \"Channel Swap\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
        "{ name: negative_space_punch, display: \"Negative Punch\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
        "{ name: additive_overload, display: \"Additive Overload\", type: float, min: 0, max: 2, default: 0.1, group: \"Avant\" }",
        "{ name: blueprint_invert, display: \"Blueprint Invert\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
    ]) + "\n\npasses:\n  - name: composite\n    shader: composite.hlsl\n    target: cs_5_0\n    inputs:\n      - { slot: 0, source: \"input:0\" }\n      - { slot: 1, source: \"input:1\" }\n      - { slot: 2, source: \"input:2\" }\n      - { slot: 3, source: \"input:3\" }\n      - { slot: 4, source: \"input:4\" }\n      - { slot: 5, source: \"input:5\" }\n      - { slot: 6, source: \"input:6\" }\n      - { slot: 7, source: \"input:7\" }\n\noutputs:\n  - { name: \"Composite\", pass: composite }\n"
})

write_module("lv_post_grade", {
    "post.hlsl": post_hlsl,
    "manifest.yaml": manifest_header("LV Post Grade", mode="filter", inputs=["In"]) + "\nparameters:\n" + params([
        "{ name: look_preset, display: \"Look Preset\", type: enum, default: 0, options: [Reference, CleanTechnical, HighBloom, DarkLens, CrispMap], flags: button_grid, group: \"Instrument\" }",
        "{ name: exposure, display: \"Exposure\", type: float, min: -2, max: 2, default: 0.02, group: \"Grade\" }",
        "{ name: contrast, display: \"Contrast\", type: float, min: 0.2, max: 2.5, default: 1.18, group: \"Grade\" }",
        "{ name: saturation, display: \"Saturation\", type: float, min: 0, max: 2, default: 1.15, group: \"Grade\" }",
        "{ name: cyan_push, display: \"Cyan Push\", type: float, min: 0, max: 2, default: 0.75, group: \"Grade\" }",
        "{ name: orange_push, display: \"Orange Push\", type: float, min: 0, max: 2, default: 0.65, group: \"Grade\" }",
        "{ name: bloom_threshold, display: \"Bloom Threshold\", type: float, min: 0, max: 2, default: 0.55, group: \"Bloom\" }",
        "{ name: bloom_gain, display: \"Bloom Gain\", type: float, min: 0, max: 5, default: 0.65, group: \"Bloom\" }",
        "{ name: bloom_radius, display: \"Bloom Radius\", type: float, min: 0, max: 0.12, default: 0.035, group: \"Bloom\" }",
        "{ name: vignette_strength, display: \"Vignette\", type: float, min: 0, max: 1.5, default: 0.68, group: \"Lens\" }",
        "{ name: vignette_radius, display: \"Vignette Radius\", type: float, min: 0.2, max: 1.5, default: 0.86, group: \"Lens\" }",
        "{ name: chromatic_aberration, display: \"Chromatic Aberration\", type: float, min: 0, max: 0.02, default: 0.0025, group: \"Lens\" }",
        "{ name: barrel_distortion_post, display: \"Barrel Distortion\", type: float, min: 0, max: 0.35, default: 0.08, group: \"Lens\" }",
        "{ name: grain_amount, display: \"Grain\", type: float, min: 0, max: 0.2, default: 0.025, group: \"Degrade\" }",
        "{ name: scanline_amount, display: \"Scanlines\", type: float, min: 0, max: 0.3, default: 0.035, group: \"Degrade\" }",
        "{ name: final_sharpness, display: \"Sharpness\", type: float, min: 0, max: 1, default: 0.25, group: \"Degrade\" }",
        "{ name: film_gate_weave, display: \"Film Weave\", type: float, min: 0, max: 1, default: 0.05, group: \"Avant\" }",
        "{ name: sensor_damage, display: \"Sensor Damage\", type: float, min: 0, max: 1, default: 0.02, group: \"Avant\" }",
        "{ name: infrared_mode, display: \"Infrared\", type: float, min: 0, max: 1, default: 0, group: \"Avant\" }",
        "{ name: night_vision_crush, display: \"Night Crush\", type: float, min: 0, max: 1, default: 0.1, group: \"Avant\" }",
        "{ name: acid_scope_grade, display: \"Acid Scope\", type: float, min: 0, max: 1, default: 0.08, group: \"Avant\" }",
    ]) + "\n\npasses:\n  - name: post\n    shader: post.hlsl\n    target: cs_5_0\n    inputs:\n      - { slot: 0, source: \"input:0\" }\n\noutputs:\n  - { name: \"Out\", pass: post }\n"
})

print("Generated Laservibe HUD modules under", MOD)
