// BR_Render / present.hlsl -- the node's own preview ("Preview" output).
//
// A neutral filmic view of the linear radiance so the renderer can be judged on its own, before
// the lens: a camera white balance (the light is physical -- a 2700 K lamp IS deep orange against
// D65 -- so, like a camera, the view neutralises a chosen colour temperature), exposure in EV, a
// max-channel shoulder (saturated colour does not chalk), sRGB. The lens node (BR_Lens) consumes
// the raw HDR output instead. Diagnostic views pass straight through.
#include "render_common.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float3 filmic(float3 c)
{
    // a max-channel exponential shoulder keeps saturated mid-tones saturated (per-channel curves
    // chalk them out); the brightest highlights roll through PER-CHANNEL compression instead, so
    // a flame or a lit shade burns through orange and yellow to white the way film does --
    // desaturating toward grey instead turns bright orange pink
    float l = max(c.r, max(c.g, c.b));
    float3 mc = c * ((1.0 - exp(-l * 1.35)) / max(l, 1e-5));
    float3 pc = 1.0 - exp(-max(c, 0.0) * 1.35);
    return lerp(mc, pc, smoothstep(0.6, 3.0, l) * 0.85);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;
    // every image's header texels (br_camtexels.hlsli) are data, not colour: show the row below
    int2 hp = isCamTexel(int2(tid.xy)) ? int2(tid.x, 1) : int2(tid.xy);
    float3 c = _Tex1.Load(int3(hp, 0)).rgb;
    // the raw shade and the G-buffer fill only the render region (render_common: renderRes)
    int2 RR = renderRes(int2(W, H));
    hp = min((int2)((float2(tid.xy) + 0.5) * float2(RR) / float2(W, H)), RR - 1);
    if (isCamTexel(hp)) hp.y = 1;
    float3 o;
    if (view == 11)
    {
        // the shade pass before fog and TAA, through the same view transform
        o = brLinearToSrgb(filmic(_Tex2.Load(int3(hp, 0)).rgb / brKelvin(white_balance) * exp2(preview_ev)));
    }
    else if (view == 12)
    {
        GSample g = unpackG(_Tex3.Load(int3(hp, 0)));
        bool ext = (g.flags & (G_FLAG_EXTERIOR | G_FLAG_MISS)) != 0u;
        o = ext ? float3(0.2, 0.4, 0.9) : float3(frac(g.t), frac(g.t * 4.0), saturate(g.t / 8.0));
    }
    else if (view == 16)
    {
        // the G-buffer's own normal, before any material bump
        GSample g = unpackG(_Tex3.Load(int3(hp, 0)));
        o = g.n * 0.5 + 0.5;
    }
    else if (view == 15)
    {
        // where primary rays ended: box faces (red), outside (blue), unproven misses (green)
        GSample g = unpackG(_Tex3.Load(int3(hp, 0)));
        float3 base = frac(g.t * 0.5).xxx * 0.3 + 0.2;
        o = ((g.flags & G_FLAG_BOXHIT) != 0u) ? float3(0.9, 0.15, 0.1) : (((g.flags & G_FLAG_EXTERIOR) != 0u) ? float3(0.1, 0.3, 0.9) : (((g.flags & G_FLAG_MISS) != 0u) ? float3(0.1, 0.9, 0.2) : base));
    }
    else if (view == 17)
    {
        // SCOPE: the finish selected on BR_Finish's board, in place. Every surface made of it keeps
        // its colour; the rest of the room drops to a dim grey, so a material can be found at a glance.
        GSample g = unpackG(_Tex3.Load(int3(hp, 0)));
        float3 b = brLinearToSrgb(filmic(c / brKelvin(white_balance) * exp2(preview_ev)));
        float lum = dot(b, float3(0.2126, 0.7152, 0.0722));
        int sel = scFinishSel();
        bool inside = (g.flags & (G_FLAG_EXTERIOR | G_FLAG_MISS)) == 0u;
        bool hit = sel >= 0 && inside && (int)g.mat == sel;
        o = hit ? b : lum.xxx * ((sel >= 0) ? 0.45 : 0.60);
    }
    else if (view != 0) o = saturate(c);
    else o = brLinearToSrgb(filmic(c / brKelvin(white_balance) * exp2(preview_ev)));
    OutputUAV[tid.xy] = float4(saturate(o), 1.0);
}
