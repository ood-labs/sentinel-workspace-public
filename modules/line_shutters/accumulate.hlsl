RWTexture2D<float4> OutputUAV : register(u0);

static const float2 ANALYSIS_SIZE = float2(480.0, 270.0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    uint width;
    uint height;
    _Tex0.GetDimensions(width, height);
    if (pixel.x >= width || pixel.y >= height) return;

    float2 extent = float2((float)width, (float)height);
    float2 uv = ((float2)pixel + 0.5) / extent;
    float aspect = extent.x / max(extent.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float px = 1.0 / max(extent.y, 1.0);

    uint requested = (uint)clamp(blade_count, 1, 5);
    uint count = min(_Data0_Count, requested);
    float currentMask = 0.0;

    for (uint i = 0; i < count; ++i)
    {
        float2 aUv = float2(_Data0[i].x1, _Data0[i].y1) / ANALYSIS_SIZE;
        float2 bUv = float2(_Data0[i].x2, _Data0[i].y2) / ANALYSIS_SIZE;
        float2 a = (aUv - 0.5) * float2(aspect, 1.0);
        float2 b = (bUv - 0.5) * float2(aspect, 1.0);
        float2 ab = b - a;
        float segLen = max(length(ab), 0.0001);
        float2 dir = ab / segLen;
        float2 normal = float2(-dir.y, dir.x);
        float2 mid = (a + b) * 0.5;

        float along = abs(dot(p - mid, dir));
        float across = abs(dot(p - mid, normal));
        float halfReach = segLen * 0.5 + blade_reach * 0.42;
        float widthPx = blade_width + px * (1.0 + (float)i);
        float crossShape = 1.0 - smoothstep(widthPx, widthPx + px * 2.0, across);
        float endShape = 1.0 - smoothstep(halfReach, halfReach + 0.025, along);
        currentMask = max(currentMask, crossShape * endShape);
    }

    float previous = _Tex2.SampleLevel(LinearSampler, uv, 0).r;
    float decay = pow(saturate(retention), max(_DeltaTime, 0.0) * 60.0);
    float decayed = previous * decay;
    float persistentTarget = max(decayed, currentMask);

    // A detection must remain spatially coherent for several frames before it
    // becomes a full blade; unstable records only leave a faint short trace.
    float memory = lerp(decayed, persistentTarget, saturate(attack));
    OutputUAV[pixel] = float4(memory.xxx, 1.0);
}
