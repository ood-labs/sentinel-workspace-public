// abstract_shape_gen: emits addressable poster object records for shape_render.

struct ShapeRecord {
    float4 p0;     // xy = center/start uv, z = depth, w = kind
    float4 p1;     // xy = scale/end uv, z = rotation, w = group
    float4 color;  // rgb = color, a = opacity
    float4 style;  // x = value, y = aux, z = active, w = seed
};

RWStructuredBuffer<ShapeRecord> OutputBuffer : register(u0);

float2 rot2(float2 v, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

ShapeRecord makeShape(float kind, float2 center, float2 scale, float rot, float3 col, float alpha, float group, float value, float aux, float active)
{
    ShapeRecord r;
    float2 c = (center - 0.5) * global_scale + 0.5 + global_offset;
    r.p0 = float4(c, 0.5, kind);
    r.p1 = float4(scale * global_scale, rot, group);
    r.color = float4(col, alpha);
    r.style = float4(value, aux, active, (float)seed);
    return r;
}

ShapeRecord makeSegment(float kind, float2 a, float2 b, float width, float3 col, float alpha, float group, float aux, float active)
{
    ShapeRecord r;
    float2 aa = (a - 0.5) * global_scale + 0.5 + global_offset;
    float2 bb = (b - 0.5) * global_scale + 0.5 + global_offset;
    r.p0 = float4(aa, 0.5, kind);
    r.p1 = float4(bb, width * global_scale, group);
    r.color = float4(col, alpha);
    r.style = float4(length(bb - aa), aux, active, (float)seed);
    return r;
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= 32) return;

    ShapeRecord blank = makeShape(0.0, float2(0, 0), float2(0, 0), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    OutputBuffer[i] = blank;

    float3 blue = blue_color;
    float3 black = float3(0.012, 0.011, 0.012);
    float3 white = float3(0.94, 0.92, 0.86);
    float3 glass = float3(0.88, 0.92, 0.88);
    float3 chrome = float3(0.74, 0.73, 0.68);
    float3 lineCol = float3(0.52, 0.50, 0.46);

    float2 left = left_stack;
    float2 ring = ring_center;
    float2 stripe = stripe_center;
    float2 cluster = sphere_cluster;
    float2 bar = right_bar_center;
    float2 cap = capsule_anchor;

    if (i == 0)  OutputBuffer[i] = makeShape(0.0, left + float2(0.030, -0.020), float2(0.027, 0.096), 0.0, blue, left_visible, 0.0, 0.0, 0.0, 1.0);
    if (i == 1)  OutputBuffer[i] = makeShape(0.0, left + float2(-0.005, 0.045), float2(0.0355, 0.0345), 0.0, black, left_visible, 0.0, 0.0, 0.0, 1.0);
    if (i == 2)  OutputBuffer[i] = makeShape(0.0, bar, float2(0.139, 0.0045), 0.0, blue, bar_visible, 1.0, 0.0, 0.0, 1.0);
    if (i == 3)  OutputBuffer[i] = makeShape(0.0, ring + float2(-0.052, 0.065), float2(0.089, 0.0435), 0.0, white, 0.35 * solids_visible, 2.0, 0.0, 0.0, 1.0);
    if (i == 4)  OutputBuffer[i] = makeShape(1.0, ring + float2(-0.008, 0.027), float2(0.050, 0.050), 0.0, black, solids_visible, 2.0, 0.0, 0.0, 1.0);
    if (i == 5)  OutputBuffer[i] = makeShape(3.0, ring, float2(0.136, 0.136), 0.0, chrome, solids_visible, 2.0, 0.0, 0.018, 1.0);
    if (i == 6)  OutputBuffer[i] = makeShape(3.0, ring, float2(0.110, 0.110), 0.0, chrome, solids_visible, 2.0, 0.0, 0.008, 1.0);
    if (i == 7)  OutputBuffer[i] = makeShape(4.0, stripe, float2(0.134, 0.055), stripe_rot, white, solids_visible, 3.0, stripe_freq, 0.0, 1.0);
    if (i == 8)  OutputBuffer[i] = makeShape(1.0, cluster + float2(-0.040, 0.000), float2(0.055, 0.055), 0.0, white, solids_visible, 4.0, 0.0, 0.0, 1.0);
    if (i == 9)  OutputBuffer[i] = makeShape(1.0, cluster + float2(0.026, -0.004), float2(0.061, 0.061), 0.0, white, solids_visible, 4.0, 0.0, 0.0, 1.0);
    if (i == 10) OutputBuffer[i] = makeShape(1.0, lower_sphere, float2(0.036, 0.036), 0.0, white, solids_visible, 4.0, 0.0, 0.0, 1.0);
    if (i == 11) OutputBuffer[i] = makeShape(1.0, float2(0.382, 0.334), float2(0.014, 0.014), 0.0, white, solids_visible, 4.0, 0.0, 0.0, 1.0);
    if (i == 12) OutputBuffer[i] = makeSegment(5.0, cap + float2(0.000, 0.000), cap + float2(0.000, 0.035), 0.007, glass, capsule_visible, 5.0, 0.0, 1.0);
    if (i == 13) OutputBuffer[i] = makeSegment(5.0, cap + float2(0.026, 0.042), cap + float2(0.026, 0.073), 0.007, glass, capsule_visible, 5.0, 0.0, 1.0);
    if (i == 14) OutputBuffer[i] = makeSegment(5.0, bottom_capsules + float2(-0.018, 0.000), bottom_capsules + float2(0.016, 0.000), 0.006, glass, capsule_visible, 5.0, 0.0, 1.0);
    if (i == 15) OutputBuffer[i] = makeSegment(5.0, bottom_capsules + float2(-0.036, 0.026), bottom_capsules + float2(0.000, 0.026), 0.006, glass, capsule_visible, 5.0, 0.0, 1.0);
    if (i == 16) OutputBuffer[i] = makeSegment(6.0, guide_a_start, guide_a_end, guide_width, lineCol, guide_visible, 6.0, 0.0, 1.0);
    if (i == 17) OutputBuffer[i] = makeSegment(6.0, guide_b_start, guide_b_end, guide_width * 0.85, lineCol, guide_visible * 0.45, 6.0, 0.0, 1.0);
    if (i == 18) OutputBuffer[i] = makeShape(2.0, ring + float2(-0.028, 0.012), float2(0.176, 0.052), -1.18, lineCol, guide_visible * 0.35, 6.0, 0.0, 0.014, 1.0);
    if (i == 19) OutputBuffer[i] = makeShape(2.0, ring + float2(-0.055, 0.010), float2(0.236, 0.030), -1.36, lineCol, guide_visible * 0.22, 6.0, 0.0, 0.010, 1.0);
}
