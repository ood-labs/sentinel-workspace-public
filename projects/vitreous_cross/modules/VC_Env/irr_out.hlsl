// VC_Env / irr_out.hlsl — publishes the convolved irradiance as a real output texture.
//
// The convolution itself runs at 64x32 into buffer:irr, because that is all the frequency a
// cosine lobe carries. A pass that writes to a named BUFFER has no render target of its own,
// though, so it cannot be a module output — the node would publish a slot with no SRV and
// every diffuse surface downstream would read pure black. This pass exists solely to give the
// map a bindable texture, upsampled bilinearly, which costs nothing and loses nothing.
#include "../_shared/vitreous.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pix = DTid.xy;
    if (pix.x >= W || pix.y >= H) return;

    float2 uv = ((float2)pix + 0.5) / float2(W, H);
    OutputUAV[pix] = float4(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb, 1.0);
}
