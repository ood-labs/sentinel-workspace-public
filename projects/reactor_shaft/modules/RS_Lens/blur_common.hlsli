// Shared separable gaussian. Two chained chains (tight then wide) give a two-scale bloom for
// four cheap passes, which is what produces the reference's combination of a crisp core and a
// very large soft halo. One kernel can do one or the other, never both.
#ifndef RS_BLUR_HLSLI
#define RS_BLUR_HLSLI

static const float RS_GW[7] = { 0.1963, 0.1747, 0.1210, 0.0656, 0.0277, 0.0091, 0.0023 };

float3 rs_blurDir(Texture2D<float4> src, uint2 px, uint2 dim, float2 dir, float radius)
{
    float3 acc = src[px].rgb * RS_GW[0];
    float wsum = RS_GW[0];
    [loop] for (int i = 1; i < 7; i++)
    {
        float2 o = dir * radius * (float)i;
        int2 a = clamp((int2)px + (int2)round(o),  int2(0, 0), (int2)dim - 1);
        int2 b = clamp((int2)px - (int2)round(o),  int2(0, 0), (int2)dim - 1);
        acc += (src[(uint2)a].rgb + src[(uint2)b].rgb) * RS_GW[i];
        wsum += 2.0 * RS_GW[i];
    }
    return acc / max(wsum, 1e-5);
}
#endif
