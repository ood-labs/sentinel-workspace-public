// LT_Lens / bright.hlsl — the bloom source: what is genuinely brighter than white.
//
// A soft knee rather than a hard step. A hard threshold makes the bloom pop on and off as a beam
// crosses the cut, which on a moving bench reads as flicker rather than as glow.
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pix = DTid.xy;
    if (pix.x >= W || pix.y >= H) return;

    float2 uv = ((float2)pix + 0.5) / float2(W, H);
    float3 c = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    float l = max(c.r, max(c.g, c.b));
    float knee = max(bloom_knee, 1e-3);
    float soft = saturate((l - bloom_threshold + knee) / (2.0 * knee));
    float w = max(l - bloom_threshold, soft * soft * knee) / max(l, 1e-4);

    OutputUAV[pix] = float4(c * saturate(w), 1.0);
}
