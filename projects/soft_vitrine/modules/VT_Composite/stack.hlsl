// VT_Composite / stack.hlsl — collapse the four object layers into ONE premultiplied RGBA.
//
// Every renderer publishes colour premultiplied by its own coverage plus a separate coverage
// lane, so stacking is a plain over-operator and needs no divisions. Doing this in its own
// pass means the reflection and shadow passes downstream sample ONE texture instead of eight.
//
// Order is back plates -> masses -> strokes -> front plates. The plate half of that order is
// decided by the F_FRONT flag the plan authority set, not re-decided here.
RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> BackCol : register(t0);
Texture2D<float4> BackCov : register(t1);
Texture2D<float4> VolCol : register(t2);
Texture2D<float4> VolCov : register(t3);
Texture2D<float4> StrCol : register(t4);
Texture2D<float4> StrCov : register(t5);
Texture2D<float4> FrontCol : register(t6);
Texture2D<float4> FrontCov : register(t7);

void over(inout float3 dc, inout float da, float3 sc, float sa)
{
    dc = dc * (1.0 - sa) + sc;
    da = da * (1.0 - sa) + sa;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 p = DTid.xy;
    if (p.x >= (uint)_Resolution.x || p.y >= (uint)_Resolution.y) return;

    float3 c = float3(0, 0, 0);
    float a = 0.0;

    over(c, a, BackCol[p].rgb * back_gain, saturate(BackCov[p].r));
    over(c, a, VolCol[p].rgb * mass_gain, saturate(VolCov[p].r));
    over(c, a, StrCol[p].rgb * stroke_gain, saturate(StrCov[p].r));
    over(c, a, FrontCol[p].rgb * front_gain, saturate(FrontCov[p].r));

    OutputUAV[p] = float4(c, a);
}
