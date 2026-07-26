struct LfoState
{
    float master_phase;
    float sine;
    float triangle_value;
    float pulse;
    float ramp;
    float orbit_x;
    float orbit_y;
    float accent;
    float slow_phase;
    float slow_sine;
    float odd_phase;
    float odd_triangle;
    float envelope;
    float drift;
    float last_scrub;
    float initialized;
};

StructuredBuffer<LfoState> State : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.28318530718;

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float stroke(float distanceValue, float widthValue, float pixelSize)
{
    return 1.0 - smoothstep(widthValue, widthValue + pixelSize * 1.5, distanceValue);
}

float boxOutline(float2 p, float4 boxValue, float widthValue, float pixelSize)
{
    float2 center = (boxValue.xy + boxValue.zw) * 0.5;
    float2 extent = (boxValue.zw - boxValue.xy) * 0.5;
    float2 d = abs(p - center) - extent;
    float outer = max(d.x, d.y);
    float inner = max(abs(p.x - center.x) - max(extent.x - widthValue, 0.0),
                      abs(p.y - center.y) - max(extent.y - widthValue, 0.0));
    return (1.0 - smoothstep(0.0, pixelSize * 1.5, outer))
         * smoothstep(-pixelSize * 1.5, 0.0, inner);
}

float ring(float2 p, float2 center, float radius, float widthValue, float pixelSize)
{
    return stroke(abs(length(p - center) - radius), widthValue, pixelSize);
}

float laneValue(int lane, float q)
{
    q = frac(q);
    if (lane == 0) return 0.5 + 0.5 * sin(q * TAU);
    if (lane == 1) return 1.0 - abs(q * 2.0 - 1.0);
    if (lane == 2) return 0.5 + 0.5 * sin(q * TAU);
    if (lane == 3) return 1.0 - abs(q * 2.0 - 1.0);
    if (lane == 4) return q < saturate(pulse_width) ? 1.0 : 0.0;
    return pow(saturate(0.5 + 0.5 * cos(q * TAU)), max(accent_sharpness, 1.0));
}

float activeValue(LfoState state, int lane)
{
    if (lane == 0) return state.sine;
    if (lane == 1) return state.triangle_value;
    if (lane == 2) return state.slow_sine;
    if (lane == 3) return state.odd_triangle;
    if (lane == 4) return state.pulse;
    return state.accent;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / max(_Resolution.xy, 1.0);
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float px = 1.0 / max(_Resolution.y, 1.0);
    float3 black = float3(0.003, 0.0035, 0.0033);
    float3 dim = float3(0.095, 0.10, 0.095);
    float3 mid = float3(0.34, 0.35, 0.33);
    float3 paper = float3(0.90, 0.89, 0.84);
    float3 accent = float3(1.0, 0.16, 0.025);
    float3 col = black;
    LfoState state = State[0];

    float gridX = 1.0 - smoothstep(0.486, 0.499, abs(frac(uv.x * 24.0) - 0.5));
    float gridY = 1.0 - smoothstep(0.486, 0.499, abs(frac(uv.y * 14.0) - 0.5));
    col += max(gridX, gridY) * 0.018;

    float margin = 0.032;
    float4 frame = float4(margin * aspect, margin, aspect - margin * aspect, 1.0 - margin);
    col = lerp(col, mid, boxOutline(p, frame, px * 1.1, px));

    float2 clockCenter = float2(aspect * 0.175, 0.39);
    float clockRadius = min(aspect * 0.10, 0.175);
    float phases[3] = { state.master_phase, state.slow_phase, state.odd_phase };
    [unroll]
    for (int c = 0; c < 3; ++c)
    {
        float radius = clockRadius * (1.0 - c * 0.22);
        col = lerp(col, c == 0 ? paper : mid, ring(p, clockCenter, radius, px * 0.8, px));
        float2 clockPoint = clockCenter + float2(cos(phases[c] * TAU), sin(phases[c] * TAU)) * radius;
        col = lerp(col, c == 0 ? accent : paper,
                   1.0 - smoothstep(px * 3.0, px * 5.4, length(p - clockPoint)));
    }
    float2 masterPoint = clockCenter + float2(cos(state.master_phase * TAU), sin(state.master_phase * TAU)) * clockRadius;
    col = lerp(col, paper, stroke(sdSegment(p, clockCenter, masterPoint), px * 0.6, px));

    float graphLeft = aspect * 0.31;
    float graphRight = aspect * 0.955;
    float graphTop = 0.065;
    float laneHeight = 0.112;
    float laneGap = 0.014;
    [unroll]
    for (int lane = 0; lane < 6; ++lane)
    {
        float y0 = graphTop + lane * (laneHeight + laneGap);
        float y1 = y0 + laneHeight;
        float4 laneBox = float4(graphLeft, y0, graphRight, y1);
        col = lerp(col, dim, boxOutline(p, laneBox, px * 0.7, px));
        float q = saturate((p.x - graphLeft) / max(graphRight - graphLeft, px));
        float wave = laneValue(lane, q);
        float waveY = lerp(y1 - laneHeight * 0.16, y0 + laneHeight * 0.16, wave);
        bool inLane = p.x >= graphLeft && p.x <= graphRight && p.y >= y0 && p.y <= y1;
        float trace = stroke(abs(p.y - waveY), px * 0.85, px) * (inLane ? 1.0 : 0.0);
        col = lerp(col, lane >= 4 ? accent : paper, trace);
        // Master lanes share the master cursor. The ratio lanes use their
        // persistent local phases, so their dots remain attached across
        // master wraps instead of appearing to slip every other cycle.
        float lanePhase = lane == 2 ? state.slow_phase :
                          (lane == 3 ? state.odd_phase : state.master_phase);
        float cursorX = lerp(graphLeft, graphRight, lanePhase);
        float activeY = lerp(y1 - laneHeight * 0.16, y0 + laneHeight * 0.16, activeValue(state, lane));
        float cursor = stroke(abs(p.x - cursorX), px * 0.4, px) * (inLane ? 1.0 : 0.0);
        col = lerp(col, accent, cursor * 0.60);
        col = lerp(col, accent, 1.0 - smoothstep(px * 2.5, px * 4.5, length(p - float2(cursorX, activeY))));
    }

    float barLeft = aspect * 0.055;
    float barRight = aspect * 0.275;
    float values[3] = { state.envelope, state.drift, state.accent };
    [unroll]
    for (int b = 0; b < 3; ++b)
    {
        float y0 = 0.61 + b * 0.075;
        float y1 = y0 + 0.018;
        col = lerp(col, mid, step(barLeft, p.x) * step(p.x, barRight) * step(y0, p.y) * step(p.y, y1));
        float fillRight = lerp(barLeft, barRight, values[b]);
        col = lerp(col, b == 2 ? accent : paper,
                   step(barLeft, p.x) * step(p.x, fillRight) * step(y0, p.y) * step(p.y, y1));
    }

    float transportY0 = 0.865;
    float transportY1 = 0.952;
    float playX0 = aspect * 0.045;
    float playX1 = aspect * 0.125;
    float resetX0 = aspect * 0.135;
    float resetX1 = aspect * 0.215;
    float scrubX0 = aspect * 0.245;
    float scrubX1 = aspect * 0.945;
    col = lerp(col, transport_run != 0 ? paper : mid,
               boxOutline(p, float4(playX0, transportY0, playX1, transportY1), px, px));
    col = lerp(col, mid, boxOutline(p, float4(resetX0, transportY0, resetX1, transportY1), px, px));
    col = lerp(col, mid, boxOutline(p, float4(scrubX0, transportY0, scrubX1, transportY1), px, px));
    float scrubY = (transportY0 + transportY1) * 0.5;
    col = lerp(col, mid, stroke(abs(p.y - scrubY), px * 0.6, px)
                               * (p.x >= scrubX0 && p.x <= scrubX1 ? 1.0 : 0.0));
    float phaseX = lerp(scrubX0, scrubX1, state.master_phase);
    col = lerp(col, accent, stroke(abs(p.x - phaseX), px * 1.25, px)
                                  * (p.y >= transportY0 && p.y <= transportY1 ? 1.0 : 0.0));
    col += accent * state.accent * 0.04;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
