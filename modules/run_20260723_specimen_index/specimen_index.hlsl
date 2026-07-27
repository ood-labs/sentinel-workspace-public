RWTexture2D<float4> OutputUAV : register(u0);

float si_luma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float4 si_sample(float2 uv)
{
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
    {
        return float4(void_color, 1.0);
    }

    uint width;
    uint height;
    _Tex0.GetDimensions(width, height);
    float2 extent = float2(max(width, 1u), max(height, 1u));
    int2 coord = int2(saturate(uv) * max(extent - 1.0, float2(1.0, 1.0)));
    return _Tex0.Load(int3(coord, 0));
}

bool si_contains(float2 uv, float2 rectMin, float2 rectMax)
{
    return uv.x >= rectMin.x && uv.x <= rectMax.x &&
           uv.y >= rectMin.y && uv.y <= rectMax.y;
}

void si_assign_panel(
    float2 uv,
    float2 rectMin,
    float2 rectMax,
    int candidateId,
    inout int panelId,
    inout float2 selectedMin,
    inout float2 selectedMax)
{
    if (si_contains(uv, rectMin, rectMax))
    {
        panelId = candidateId;
        selectedMin = rectMin;
        selectedMax = rectMax;
    }
}

float si_box_line(float2 uv, float2 center, float2 halfSize, float width)
{
    float2 d = abs(uv - center) - halfSize;
    float signedDistance = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    return 1.0 - smoothstep(width, width * 2.2, abs(signedDistance));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / max(_Resolution.xy, float2(1.0, 1.0));
    float px = 1.0 / max(_Resolution.y, 1.0);
    float gap = 0.006 + separation * 0.022;

    int panelId = -1;
    float2 rectMin = 0.0;
    float2 rectMax = 1.0;

    if (layout_mode == 0)
    {
        si_assign_panel(uv, float2(0.036, 0.052), float2(0.514 - gap, 0.946), 0, panelId, rectMin, rectMax);
        si_assign_panel(uv, float2(0.522 + gap, 0.052), float2(0.964, 0.397 - gap), 1, panelId, rectMin, rectMax);
        si_assign_panel(uv, float2(0.522 + gap, 0.405 + gap), float2(0.792 - gap, 0.946), 2, panelId, rectMin, rectMax);
        si_assign_panel(uv, float2(0.800 + gap, 0.405 + gap), float2(0.964, 0.946), 3, panelId, rectMin, rectMax);
    }
    else if (layout_mode == 1)
    {
        si_assign_panel(uv, float2(0.036, 0.052), float2(0.188 - gap, 0.946), 0, panelId, rectMin, rectMax);
        si_assign_panel(uv, float2(0.196 + gap, 0.052), float2(0.804 - gap, 0.946), 1, panelId, rectMin, rectMax);
        si_assign_panel(uv, float2(0.812 + gap, 0.052), float2(0.964, 0.946), 2, panelId, rectMin, rectMax);
    }
    else
    {
        si_assign_panel(uv, float2(0.036, 0.078), float2(0.405 - gap, 0.572 - gap), 0, panelId, rectMin, rectMax);
        si_assign_panel(uv, float2(0.414 + gap, 0.052), float2(0.964, 0.365 - gap), 1, panelId, rectMin, rectMax);
        si_assign_panel(uv, float2(0.486 + gap, 0.374 + gap), float2(0.862, 0.946), 2, panelId, rectMin, rectMax);
        si_assign_panel(uv, float2(0.036, 0.581 + gap), float2(0.477 - gap, 0.946), 3, panelId, rectMin, rectMax);
    }

    float3 col = void_color;

    if (panelId >= 0)
    {
        float2 rectSize = max(rectMax - rectMin, float2(0.001, 0.001));
        float2 local = (uv - rectMin) / rectSize;
        float idf = (float)panelId;
        float driftPhase = frac(phase + idf * 0.217);
        float driftAngle = driftPhase * 6.28318530718 + idf * 1.41;
        float2 drift = float2(cos(driftAngle), sin(driftAngle * 0.73)) * drift_amount;

        float perPanelZoom = panel_zoom * (1.0 + idf * 0.075);
        float2 sourceUv = (local - 0.5) / max(perPanelZoom, 0.05) + 0.5;
        sourceUv += focus + drift;

        if (layout_mode == 1 && (panelId == 0 || panelId == 2))
        {
            float inputAspect = _Resolution.x / max(_Resolution.y, 1.0);
            float railAspect = rectSize.x / max(rectSize.y, 0.001);
            sourceUv.x = 0.5 + (local.x - 0.5) * railAspect / max(inputAspect * panel_zoom, 0.05);
            sourceUv.y = 0.5 + (local.y - 0.5) / max(panel_zoom, 0.05);
            sourceUv += focus;
            sourceUv.x += panelId == 0 ? -0.22 : 0.22;
            sourceUv += drift * float2(0.32, 0.48);
        }
        else if (panelId == 1)
        {
            sourceUv.x = 1.0 - sourceUv.x;
            sourceUv.y = sourceUv.y * 0.72 + 0.14;
        }
        else if (panelId == 2)
        {
            sourceUv.x = sourceUv.x * 0.68 + 0.18;
            sourceUv.y = 1.0 - sourceUv.y;
        }
        else if (panelId == 3)
        {
            sourceUv.x = frac(sourceUv.x * 1.72 + phase * 0.37);
            sourceUv.y = sourceUv.y * 0.82 + 0.09;
        }

        uint inputWidth;
        uint inputHeight;
        _Tex0.GetDimensions(inputWidth, inputHeight);
        float2 texel = 1.0 / float2(max(inputWidth, 1u), max(inputHeight, 1u));

        float3 current = si_sample(sourceUv).rgb;
        float3 echoSample = si_sample(sourceUv + float2(-drift.y, drift.x) * 0.27).rgb;
        float3 leftSample = si_sample(sourceUv - float2(texel.x * 2.0, 0.0)).rgb;
        float3 rightSample = si_sample(sourceUv + float2(texel.x * 2.0, 0.0)).rgb;
        float3 upSample = si_sample(sourceUv - float2(0.0, texel.y * 2.0)).rgb;
        float3 downSample = si_sample(sourceUv + float2(0.0, texel.y * 2.0)).rgb;

        float edge = abs(si_luma(rightSample) - si_luma(leftSample)) +
                     abs(si_luma(downSample) - si_luma(upSample));
        float contour = smoothstep(contour_threshold, contour_threshold * 2.8 + 0.001, edge);

        float quantDivisor = max((float)tone_steps - 1.0, 1.0);
        float quantized = floor(saturate(si_luma(current)) * quantDivisor + 0.5) / quantDivisor;
        float3 indexedTone = paper_color * quantized;
        col = lerp(current, indexedTone, monochrome_pull);
        col = lerp(col, max(col, echoSample * 0.68), ghost_mix);
        col = lerp(col, accent_color, contour * contour_weight * accent_weight);

        float edgeDistance = min(min(uv.x - rectMin.x, rectMax.x - uv.x),
                                 min(uv.y - rectMin.y, rectMax.y - uv.y));
        float border = 1.0 - smoothstep(px * (0.8 + border_weight), px * (2.2 + border_weight * 2.4), edgeDistance);
        col = max(col, rail_color * border * border_weight);

        float cellX = frac(local.x * (float)grid_density);
        float cellY = frac(local.y * max(2.0, floor((float)grid_density * rectSize.y / max(rectSize.x, 0.01))));
        float gridX = 1.0 - smoothstep(0.003, 0.012, min(cellX, 1.0 - cellX));
        float gridY = 1.0 - smoothstep(0.003, 0.012, min(cellY, 1.0 - cellY));
        float grid = max(gridX, gridY) * 0.12;
        col = max(col, rail_color * grid);

        float notchCount = 2.0 + idf;
        float notchCell = frac(local.x * notchCount);
        float notch = step(local.y, 0.018) * (1.0 - smoothstep(0.12, 0.22, notchCell));
        col = max(col, accent_color * notch * accent_weight);
    }

    float outerFrame = si_box_line(uv, float2(0.5, 0.5), float2(0.474, 0.464), px * 0.9);
    float phaseRail = si_box_line(uv, float2(0.5, 0.972), float2(0.44, 0.006), px * 0.8);
    float phaseCursor = si_box_line(uv, float2(0.06 + phase * 0.88, 0.972), float2(0.004, 0.017), px * 0.8);
    col = max(col, rail_color * outerFrame * 0.72);
    col = max(col, rail_color * phaseRail * 0.48);
    col = max(col, accent_color * phaseCursor * accent_weight);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
