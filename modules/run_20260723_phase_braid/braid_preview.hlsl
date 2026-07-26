RWTexture2D<float4> OutputUAV : register(u0);

struct BraidData
{
    float loom_phase;
    float gate_phase;
    float memory_phase;
    float energy;
};

StructuredBuffer<BraidData> BraidValues : register(t0);

float pb_wrap(float x)
{
    return frac(x);
}

float pb_fold(float x)
{
    return abs(frac(x) - 0.5) * 2.0;
}

float pb_lane_value(float p, int lane)
{
    p = pb_wrap(p);
    float wave = sin(p * 6.28318530718);
    if (lane == 0) return p;

    if (braid_mode == 1)
    {
        return lane == 1 ? pb_wrap(p + gate_offset) : pb_wrap(p + memory_offset);
    }

    if (braid_mode == 2)
    {
        return lane == 1
            ? pb_fold(p * gate_ratio + gate_offset)
            : pb_wrap(1.0 - p + memory_offset + wave * memory_lag * 0.25);
    }

    return lane == 1
        ? pb_wrap(p * gate_ratio + gate_offset + wave * crossmod * 0.08)
        : pb_wrap(p - wave * memory_lag + memory_offset);
}

float pb_current_value(BraidData values, int lane)
{
    if (lane == 0) return values.loom_phase;
    if (lane == 1) return values.gate_phase;
    return values.memory_phase;
}

float pb_circle(float2 p, float2 center, float radius, float width)
{
    return 1.0 - smoothstep(width, width * 2.0, abs(length(p - center) - radius));
}

float pb_segment(float2 p, float2 a, float2 b, float width)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.000001));
    return 1.0 - smoothstep(width, width * 2.0, length(pa - ba * h));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / max(_Resolution.xy, float2(1.0, 1.0));
    float px = 1.0 / max(_Resolution.y, 1.0);
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 ap = uv * float2(aspect, 1.0);
    BraidData values = BraidValues[0];

    float3 col = background_color;
    float laneBases[3] = { 0.73, 0.50, 0.27 };

    float rail = 0.0;
    float ticks = 0.0;
    for (int lane = 0; lane < 3; ++lane)
    {
        rail = max(rail, 1.0 - smoothstep(px, px * 2.0, abs(uv.y - laneBases[lane])));
    }

    float tickPhase = frac(uv.x * (float)beat_divisions);
    float tickLine = 1.0 - smoothstep(px * 0.7, px * 2.0, min(tickPhase, 1.0 - tickPhase) / max((float)beat_divisions, 1.0));
    float tickBand = smoothstep(0.91, 0.94, uv.y) * (1.0 - smoothstep(0.965, 0.985, uv.y));
    ticks = tickLine * tickBand;
    col = max(col, rail.xxx * rail_color * rail_weight);
    col = max(col, ticks.xxx * rail_color * 0.65);

    float curveMask = 0.0;
    float3 curveColor = float3(0.0, 0.0, 0.0);
    for (int lane = 0; lane < 3; ++lane)
    {
        float mapped = pb_lane_value(uv.x, lane);
        float curveY = laneBases[lane] + (mapped - 0.5) * lane_height;
        float curve = 1.0 - smoothstep(px * line_weight, px * (line_weight + 1.7), abs(uv.y - curveY));
        float3 laneColor = lane == 0 ? loom_color : (lane == 1 ? gate_color : memory_color);
        curveColor = max(curveColor, laneColor * curve);
        curveMask = max(curveMask, curve);
    }
    col = max(col, curveColor);

    float masterX = saturate(values.loom_phase);
    float2 marker[3];
    for (int markerLane = 0; markerLane < 3; ++markerLane)
    {
        float markerValue = pb_current_value(values, markerLane);
        marker[markerLane] = float2(masterX * aspect, laneBases[markerLane] + (markerValue - 0.5) * lane_height);
    }

    float connector = pb_segment(ap, marker[0], marker[1], px * connector_weight);
    connector = max(connector, pb_segment(ap, marker[1], marker[2], px * connector_weight));
    col = lerp(col, accent_color, connector * accent_weight);

    float markers = 0.0;
    for (int m = 0; m < 3; ++m)
    {
        markers = max(markers, pb_circle(ap, marker[m], px * marker_radius, px * 1.4));
    }
    col = lerp(col, accent_color, saturate(markers * accent_weight));

    float masterLine = 1.0 - smoothstep(px * 0.7, px * 2.2, abs(uv.x - masterX));
    masterLine *= smoothstep(0.08, 0.13, uv.y) * (1.0 - smoothstep(0.87, 0.92, uv.y));
    col = max(col, masterLine.xxx * accent_color * 0.42);

    float energyWidth = values.energy * 0.42;
    float energyBand = smoothstep(0.075, 0.095, uv.y) * (1.0 - smoothstep(0.12, 0.14, uv.y));
    float energyFill = (uv.x >= 0.08 && uv.x <= 0.08 + energyWidth) ? 1.0 : 0.0;
    float energyFrame = pb_segment(ap, float2(0.08 * aspect, 0.107), float2(0.50 * aspect, 0.107), px * 0.85);
    col = max(col, energyBand * energyFill * accent_color * energy_brightness);
    col = max(col, energyFrame.xxx * rail_color * 0.38);

    float borderDistance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float border = 1.0 - smoothstep(px * 1.4, px * 3.0, borderDistance);
    col = max(col, border.xxx * rail_color * 0.65);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
