// LFO display: a compact oscilloscope view of the selected waveform.
// This pass is visual-only; the control buffer remains the sole output authority.
StructuredBuffer<float4> Ctrl : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float WaveAt(float ph)
{
    ph = frac(ph);
    int wf = (int)waveform;
    if (wf == 1) return 1.0 - abs(2.0 * ph - 1.0);
    if (wf == 2) return 0.5 - 0.5 * cos(ph * 6.28318530718);
    if (wf == 3) return ph < 0.5 ? 0.0 : 1.0;
    return ph;
}

float LineMask(float distancePx, float halfWidthPx)
{
    return 1.0 - smoothstep(halfWidthPx, halfWidthPx + 1.0, distancePx);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float4 state = Ctrl[0];
    float value = saturate(state.y);
    float phase = frac(state.z);
    float uiScale = clamp(_Resolution.y / 160.0, 1.0, 2.5);

    const float2 graphMin = float2(0.035, 0.16);
    const float2 graphMax = float2(0.965, 0.84);
    float2 graphSize = graphMax - graphMin;
    float2 gp = (uv - graphMin) / graphSize;
    float inside = step(0.0, gp.x) * step(gp.x, 1.0) *
                   step(0.0, gp.y) * step(gp.y, 1.0);

    float3 col = float3(0.027, 0.030, 0.039);

    // Recessed plotting field.
    col = lerp(col, float3(0.040, 0.044, 0.054), inside);

    // Quarter-cycle guides and the 0.5 value reference.
    float verticalGrid = 0.0;
    verticalGrid = max(verticalGrid, LineMask(abs(gp.x - 0.25) * graphSize.x * _Resolution.x, 0.35 * uiScale));
    verticalGrid = max(verticalGrid, LineMask(abs(gp.x - 0.50) * graphSize.x * _Resolution.x, 0.35 * uiScale));
    verticalGrid = max(verticalGrid, LineMask(abs(gp.x - 0.75) * graphSize.x * _Resolution.x, 0.35 * uiScale));
    float midGrid = LineMask(abs(gp.y - 0.50) * graphSize.y * _Resolution.y, 0.35 * uiScale);
    col += inside * (verticalGrid + midGrid) * float3(0.055, 0.061, 0.073);

    // Waveform: completed phase is bright, upcoming phase is restrained.
    float waveValue = WaveAt(gp.x);
    float waveY = 1.0 - waveValue;
    float traceDistancePx = abs(gp.y - waveY) * graphSize.y * _Resolution.y;
    float trace = inside * LineMask(traceDistancePx, 0.75 * uiScale);
    float completed = step(gp.x, phase);
    float3 traceColor = lerp(float3(0.18, 0.28, 0.29),
                             float3(0.22, 0.86, 0.77),
                             completed);
    col = lerp(col, traceColor, trace);

    // Preserve the visible discontinuity in square mode.
    if ((int)waveform == 3)
    {
        float jumpDistancePx = abs(gp.x - 0.5) * graphSize.x * _Resolution.x;
        float jump = inside * LineMask(jumpDistancePx, 0.75 * uiScale);
        float jumpCompleted = step(0.5, phase);
        float3 jumpColor = lerp(float3(0.18, 0.28, 0.29),
                                float3(0.22, 0.86, 0.77),
                                jumpCompleted);
        col = lerp(col, jumpColor, jump);
    }

    // Live phase cursor.
    float cursorDistancePx = abs(gp.x - phase) * graphSize.x * _Resolution.x;
    float cursor = inside * LineMask(cursorDistancePx, 0.45 * uiScale);
    col = lerp(col, float3(0.15, 0.47, 0.45), cursor * 0.72);

    // Current value point with a crisp core and restrained halo.
    float2 currentGp = float2(phase, 1.0 - value);
    float2 pointDeltaPx = (gp - currentGp) * graphSize * _Resolution.xy;
    float pointDistancePx = length(pointDeltaPx);
    float halo = inside * (1.0 - smoothstep(5.5 * uiScale, 9.5 * uiScale, pointDistancePx));
    float ring = inside * (1.0 - smoothstep(0.8 * uiScale, 1.8 * uiScale,
                                            abs(pointDistancePx - 3.4 * uiScale)));
    float core = inside * (1.0 - smoothstep(0.0, 1.35 * uiScale, pointDistancePx));
    col += halo * float3(0.025, 0.11, 0.10);
    col = lerp(col, float3(0.34, 0.96, 0.83), max(ring, core));

    // One-pixel frame keeps the tiny preview legible at graph-node scale.
    float frameDistancePx = min(
        min(abs(uv.x - graphMin.x), abs(uv.x - graphMax.x)) * _Resolution.x,
        min(abs(uv.y - graphMin.y), abs(uv.y - graphMax.y)) * _Resolution.y);
    float frame = LineMask(frameDistancePx, 0.35 * uiScale);
    col = lerp(col, float3(0.10, 0.12, 0.14), frame);

    OutputUAV[px] = float4(col, 1.0);
}
