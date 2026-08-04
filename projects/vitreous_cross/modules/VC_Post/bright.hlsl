// VC_Post / bright.hlsl — bloom source. Everything above the threshold, at quarter scale.
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    // SCALED PASS: this target is a quarter of the root, so extent comes from the texture.
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pix = DTid.xy;
    if (pix.x >= W || pix.y >= H) return;

    float2 uv = ((float2)pix + 0.5) / float2(W, H);
    float3 c = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    // Soft knee, so a highlight ramps into the bloom instead of switching on at a hard value
    // and leaving a visible contour across a smooth gradient.
    float l = max(c.r, max(c.g, c.b));
    float k = max(bloom_knee, 1e-3);
    float w = saturate((l - bloom_threshold + k) / (2.0 * k));
    w = w * w * (l > bloom_threshold - k ? 1.0 : 0.0);
    w = max(w, saturate(l - bloom_threshold));

    OutputUAV[pix] = float4(c * w, 1.0);
}
