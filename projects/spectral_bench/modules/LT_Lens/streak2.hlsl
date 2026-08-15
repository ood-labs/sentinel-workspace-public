// LT_Lens / streak.hlsl — the horizontal flare, second octave.
//
// TWO CHAINED PASSES, and this is the second. A single 13-tap blur stretched over three hundred
// pixels does not read as a streak: each tap lands as its own visible ghost and the result is a
// ladder of copies marching away from every bright edge. Pass one covers +/-6 steps, pass two
// steps by exactly 13, so pass one's coverage meets pass two's gaps and 169 effective taps come
// out of 26 samples.
RWTexture2D<float4> OutputUAV : register(u0);
static const float W13[13] = {
    0.0100, 0.0230, 0.0440, 0.0720, 0.1010, 0.1220, 0.1300,
    0.1220, 0.1010, 0.0720, 0.0440, 0.0230, 0.0100 };

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H; OutputUAV.GetDimensions(W, H);
    uint2 pix = DTid.xy;
    if (pix.x >= W || pix.y >= H) return;
    float2 res = float2(W, H);
    float2 uv = ((float2)pix + 0.5) / res;
    float st = streak_length * 13.0 / res.x;
    float3 s = 0.0.xxx;
    [unroll] for (int i = 0; i < 13; i++)
        s += _Tex0.SampleLevel(LinearSampler, uv + float2(((float)i - 6.0) * st, 0.0), 0).rgb * W13[i];
    OutputUAV[pix] = float4(s, 1.0);
}
