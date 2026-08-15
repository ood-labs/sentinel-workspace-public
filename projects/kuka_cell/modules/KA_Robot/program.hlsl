// KA_Robot / program.hlsl — the clean image. Grade only; no marks.
// This is the output that feeds anything downstream. The scope output is a separate texture so
// a grade never blooms an instrument readout.
RWTexture2D<float4> OutputUAV : register(u0);

float3 tonemap(float3 x)
{
    // ACES-ish filmic curve
    float3 a = x * (2.51 * x + 0.03);
    float3 b = x * (2.43 * x + 0.59) + 0.14;
    return saturate(a / b);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pixel = DTid.xy;
    if (pixel.x >= W || pixel.y >= H) return;

    uint bw, bh;
    _Tex0.GetDimensions(bw, bh);
    int2 src = clamp(int2(pixel), int2(0, 0), int2(bw, bh) - 1);
    float3 c = _Tex0.Load(int3(src, 0)).rgb;

    c *= exp2(exposure);
    c = tonemap(c);
    c = saturate((c - 0.5) * contrast + 0.5);
    c = pow(max(c, 0.0), 1.0 / 2.2);

    OutputUAV[pixel] = float4(c, 1.0);
}
