// RS_Lens / bright.hlsl — soft-knee highlight extraction.
//
// A hard threshold makes the bloom pop on and off as a tube drifts past the cut, which reads as
// flicker while flying. The knee ramps the contribution in over a range instead.
Texture2D<float4> Src : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (px.x >= W || px.y >= H) return;

    float3 c = Src[px].rgb;
    float lum = max(c.r, max(c.g, c.b));
    float knee = max(bloom_knee, 0.01);
    float w = saturate((lum - bloom_threshold + knee) / (2.0 * knee));
    w = w * w * (lum > bloom_threshold - knee ? 1.0 : 0.0);
    w = max(w, step(bloom_threshold, lum));

    OutputUAV[px] = float4(c * w, 1.0);
}
