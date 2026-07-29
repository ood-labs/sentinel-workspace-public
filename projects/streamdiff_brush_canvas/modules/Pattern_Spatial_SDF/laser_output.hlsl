// Binary boundary of the explicit SDF visibility mask authored by render.hlsl.
// No shaded RGB is sampled or analyzed.

RWTexture2D<float4> OutputUAV : register(u0);

float authoredSurfaceValueAt(float2 uv)
{
    return _Tex0.SampleLevel(PointSampler, saturate(uv), 0).a;
}

float authoredSurfaceAt(float2 uv)
{
    return step(0.25, authoredSurfaceValueAt(uv));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= (uint)_Resolution.x || DTid.y >= (uint)_Resolution.y) return;

    float2 pixel = (float2)DTid.xy + 0.5;
    float edgeBuffer = max(laser_edge_buffer_px, 0.0);
    if (pixel.x < edgeBuffer || pixel.y < edgeBuffer
        || pixel.x >= _Resolution.x - edgeBuffer
        || pixel.y >= _Resolution.y - edgeBuffer)
    {
        OutputUAV[DTid.xy] = float4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    float2 texel = 1.0 / _Resolution.xy;
    float2 uv = pixel * texel;
    float radius = max(laser_line_thickness_px, 0.5);
    float2 dx = float2(texel.x * radius, 0.0);
    float2 dy = float2(0.0, texel.y * radius);
    float2 dd = float2(texel.x * radius, texel.y * radius);

    float center = authoredSurfaceAt(uv);
    float encodedLife = authoredSurfaceValueAt(uv);
    encodedLife = max(encodedLife, authoredSurfaceValueAt(uv + dx));
    encodedLife = max(encodedLife, authoredSurfaceValueAt(uv - dx));
    encodedLife = max(encodedLife, authoredSurfaceValueAt(uv + dy));
    encodedLife = max(encodedLife, authoredSurfaceValueAt(uv - dy));
    float latestLife = saturate(encodedLife * 2.0 - 1.0);
    float contour = 0.0;
    contour = max(contour, abs(center - authoredSurfaceAt(uv + dx)));
    contour = max(contour, abs(center - authoredSurfaceAt(uv - dx)));
    contour = max(contour, abs(center - authoredSurfaceAt(uv + dy)));
    contour = max(contour, abs(center - authoredSurfaceAt(uv - dy)));
    contour = max(contour, abs(center - authoredSurfaceAt(uv + dd)));
    contour = max(contour, abs(center - authoredSurfaceAt(uv - dd)));
    contour = max(contour, abs(center - authoredSurfaceAt(uv + float2(dd.x, -dd.y))));
    contour = max(contour, abs(center - authoredSurfaceAt(uv + float2(-dd.x, dd.y))));
    contour = step(0.5, contour);
    // Pattern Canvas owns scheduling. The physical laser output is only the
    // complete current contour, strictly binary, with no flash/chase layer.
    float mark = contour * step(0.001, latestLife);
    OutputUAV[DTid.xy] = float4(mark.xxx, 1.0);
}
