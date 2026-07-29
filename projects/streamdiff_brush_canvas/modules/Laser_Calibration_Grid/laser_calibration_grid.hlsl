// Copied from LaserViz laser_calibration_grid_01.
// Explicit line and dot masks for a single 1920x1080 laser calibration source.

RWTexture2D<float4> OutputUAV : register(u0);

float gridLineMask(float2 px, float2 tileSize, int divisionsX, int divisionsY, float thicknessPx)
{
    float divX = (float)max(divisionsX, 1);
    float divY = (float)max(divisionsY, 1);
    float2 stepPx = float2(tileSize.x / divX, tileSize.y / divY);
    float2 modPx = float2(fmod(px.x, stepPx.x), fmod(px.y, stepPx.y));
    float dx = min(min(modPx.x, stepPx.x - modPx.x), min(px.x, tileSize.x - px.x));
    float dy = min(min(modPx.y, stepPx.y - modPx.y), min(px.y, tileSize.y - px.y));
    float d = min(dx, dy);
    return 1.0 - smoothstep(thicknessPx, thicknessPx + 0.001, d);
}

float borderMask(float2 px, float2 tileSize, float thicknessPx)
{
    float d = min(min(px.x, tileSize.x - px.x), min(px.y, tileSize.y - px.y));
    return 1.0 - smoothstep(thicknessPx, thicknessPx + 0.001, d);
}

float cornerMask(float2 px, float2 tileSize, float lenPx, float thicknessPx)
{
    float2 q = min(px, tileSize - px);
    float h = (1.0 - smoothstep(thicknessPx, thicknessPx + 0.001, q.y))
            * (1.0 - smoothstep(lenPx, lenPx + 0.001, q.x));
    float v = (1.0 - smoothstep(thicknessPx, thicknessPx + 0.001, q.x))
            * (1.0 - smoothstep(lenPx, lenPx + 0.001, q.y));
    return saturate(max(h, v));
}

float vertexDotMask(float2 px, float2 tileSize, int divisionsX, int divisionsY)
{
    float radius = max(dot_radius_px, 0.0);
    if (radius <= 0.0001) return 0.0;
    float divX = (float)max(divisionsX, 1);
    float divY = (float)max(divisionsY, 1);
    float2 stepPx = float2(tileSize.x / divX, tileSize.y / divY);
    float2 modPx = float2(fmod(px.x, stepPx.x), fmod(px.y, stepPx.y));
    float dx = min(modPx.x, stepPx.x - modPx.x);
    float dy = min(modPx.y, stepPx.y - modPx.y);
    float d = length(float2(dx, dy));
    float feather = max(dot_feather_px, 0.001);
    float soft = 1.0 - smoothstep(radius, radius + feather, d);
    float shaped = pow(saturate(soft), max(dot_sharpness, 0.1));
    float hard = step(d, radius);
    return lerp(shaped, hard, saturate(dot_harshness));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 frameSize = _Resolution.xy;
    float2 framePx = (float2)pixel + 0.5;
    float bufferPx = clamp(edge_buffer_px, 0.0, 256.0);
    float scale = clamp(pattern_scale, 0.10, 1.0);
    float2 bufferedSize = max(frameSize - bufferPx * 2.0, float2(16.0, 16.0));
    float2 innerSize = max(bufferedSize * scale, float2(16.0, 16.0));
    float2 innerMin = (frameSize - innerSize) * 0.5;
    float2 innerPx = framePx - innerMin;
    float inInner = step(0.0, min(innerPx.x, innerPx.y))
                  * step(max(innerPx.x - innerSize.x, innerPx.y - innerSize.y), 0.0);

    int divsX = max(grid_divisions_x, 1);
    int divsY = max(grid_divisions_y, 1);
    float thickness = max(line_thickness_px, 1.0);
    float cornerLen = min(120.0, min(innerSize.x, innerSize.y) * 0.2);
    float lineMask = gridLineMask(innerPx, innerSize, divsX, divsY, thickness);
    float border = borderMask(innerPx, innerSize, thickness);
    float corners = cornerMask(innerPx, innerSize, cornerLen, thickness);
    float dots = vertexDotMask(innerPx, innerSize, divsX, divsY);

    float lineOut = saturate(max(max(lineMask, border), corners) * inInner);
    float dotOut = saturate(dots * inInner);
    OutputUAV[pixel] = float4(lineOut, dotOut, 0.0, 1.0);
}
