// TP_Scope / draw.hlsl — resolve the plates, composite the linework.
//
// TWO DIFFERENT KINDS OF MARK, DRAWN TWO DIFFERENT WAYS, and the split is deliberate.
//
// The PLATES are continuous fields — the caustic atlas, the surface relief. They are flat sheets
// and a camera ray meets one exactly once, so a ray-plane intersection resolves a whole plate in
// a handful of instructions with no scatter, no accumulation and no aliasing. Scattering those
// would be absurd.
//
// The LINEWORK is sparse and one-dimensional, which is the opposite case: cheap to scatter,
// ruinous to test per pixel. It arrives here already accumulated in `acc`.
//
// Using the wrong tool for either is the entire difference between this node costing nothing and
// it costing more than the renderer it annotates.
#include "scope.hlsli"

StructuredBuffer<TpSCtl> Ctl  : register(t1);
StructuredBuffer<uint>   Acc  : register(t2);
StructuredBuffer<TpRec>  Plan : register(t3);
RWTexture2D<float4> OutputUAV : register(u0);

// _Tex0 = Beauty (rgb + euclidean ray distance in a)
// _Tex4 = TP_Sim Field (h, v, dh/dx, dh/dz)
// _Tex5 = TP_Caustics atlas

// A plate: intersect the ray with a horizontal sheet at `y`, inside the tank footprint.
bool tpPlate(float3 ro, float3 rd, float y, float3 half3, out float2 uv, out float dist)
{
    uv = float2(0, 0);
    dist = 0.0;
    if (abs(rd.y) < 1e-5) return false;

    float t = (y - ro.y) / rd.y;
    if (t <= 0.0) return false;

    float3 p = ro + rd * t;
    if (abs(p.x) > half3.x || abs(p.z) > half3.z) return false;

    uv = float2(p.x / half3.x * 0.5 + 0.5, p.z / half3.z * 0.5 + 0.5);
    dist = t * length(rd);
    return true;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;

    float2 uv = ((float2)tid.xy + 0.5) / float2(W, H);
    float4 beauty = _Tex0.SampleLevel(LinearSampler, uv, 0);

    // Read the half the SCATTER says it filled — never re-derive it from the cook counter.
    uint parity = Acc[tpAccStamp(W, H)] & 1u;

    TpRec tank = Plan[TP_TANK];
    float3 half3 = tpTankHalf(tank);

    float3 c = beauty.rgb;

    // The instrument only dims the render while it is actually open, so closing the explode
    // returns the frame to exactly the beauty pass and nothing else.
    float open = saturate(explode) * saturate(scope_mix);
    c *= lerp(1.0, saturate(beauty_dim), open);

    // ---- the plates ------------------------------------------------------------------------
    // Reconstruct this pixel's ray from the SHARED camera. Same matrices the renderer used, so
    // a plate at explode = 0 lands exactly on the surface it stands for.
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nearW /= nearW.w;
    farW  /= farW.w;

    float3 ro = _CameraPos;
    float3 rd = normalize(farW.xyz - nearW.xyz);

    float sceneD = beauty.a;

    // A PLATE HAS TO READ AS AN OBJECT, not only as its data.
    //
    // The first version drew nothing but the signal, multiplied by Explode. That failed twice
    // over: the sheets were invisible until the stack was open, and where the data happened to
    // be zero — calm water, unlit floor — there was simply nothing there, so a "plate" was a few
    // disconnected smudges floating in space rather than a surface you could believe in.
    //
    // So each plate now draws a faint body, a rim, and a graticule regardless of its data, and
    // the measurement rides on top. The rim is what actually sells it: an edge tells the eye
    // where the sheet stops, and without one there is no sheet.
    float mixP = saturate(scope_mix);

    // Caustic plate: the light that lands on the lining, shown as its own object rather than as
    // an effect painted onto tiles.
    if (show_caus > 0.5 && mixP > 0.001)
    {
        float y = -half3.y + tpLayerLift(TP_LAYER_CAUS, -half3.y, half3.y, explode);
        float2 puv; float pd;
        if (tpPlate(ro, rd, y, half3, puv, pd))
        {
            float2 auv = float2(lerp(TP_A_C0, TP_A_C1, puv.x), lerp(TP_A_C0, TP_A_C1, puv.y));
            float3 e = _Tex5.SampleLevel(LinearSampler, auv, 0).rgb;
            // The atlas is an energy-neutral multiplier around 1; the departure FROM neutral is
            // the signal, so subtracting it makes the focus lines the subject, not a wash.
            float v = saturate((max(max(e.r, e.g), e.b) - 1.0) * 0.9);

            float2 g = abs(frac(puv * 8.0) - 0.5);
            float grid = 1.0 - smoothstep(0.0, 0.03, min(g.x, g.y));
            float rimD = max(abs(puv.x * 2.0 - 1.0), abs(puv.y * 2.0 - 1.0));
            float rim = smoothstep(0.975, 1.0, rimD);

            float vis = (pd <= sceneD + 1e-3) ? 1.0 : saturate(occlude);
            float body = 0.045 + grid * 0.07 + rim * 0.9;
            c += ink_struct * (body + v * 2.2) * plate_gain * mixP * vis;
        }
    }

    // Surface plate: TP_Sim's field. SLOPE and height contours, not height alone — but with a
    // body under it, because a calm surface genuinely has no slope and would otherwise vanish
    // exactly when the user is trying to see whether it is calm.
    if (show_surf > 0.5 && mixP > 0.001)
    {
        float y = tpLayerLift(TP_LAYER_SURF, 0.0, half3.y, explode);
        float2 puv; float pd;
        if (tpPlate(ro, rd, y, half3, puv, pd))
        {
            float4 fld = _Tex4.SampleLevel(LinearSampler, puv, 0);
            float slope = length(fld.zw);
            float v = saturate(slope * 3.2);
            // Height contours, so relief reads as a MEASURED quantity and not only as shading.
            float band = abs(frac(fld.x / 0.004) - 0.5) * 2.0;
            v = max(v, (1.0 - smoothstep(0.80, 1.0, band)) * 0.55);

            float2 g = abs(frac(puv * 8.0) - 0.5);
            float grid = 1.0 - smoothstep(0.0, 0.03, min(g.x, g.y));
            float rimD = max(abs(puv.x * 2.0 - 1.0), abs(puv.y * 2.0 - 1.0));
            float rim = smoothstep(0.975, 1.0, rimD);

            float vis = (pd <= sceneD + 1e-3) ? 1.0 : saturate(occlude);
            float body = 0.045 + grid * 0.07 + rim * 0.9;
            c += ink_measure * (body + v * 1.5) * plate_gain * mixP * vis;
        }
    }

    // ---- the linework ----------------------------------------------------------------------
    float inv = 1.0 / 2048.0;
    float s0 = (float)Acc[tpAccIndex(tid.xy, W, H, 0u, parity)] * inv;
    float s1 = (float)Acc[tpAccIndex(tid.xy, W, H, 1u, parity)] * inv;
    float s2 = (float)Acc[tpAccIndex(tid.xy, W, H, 2u, parity)] * inv;

    float mix = saturate(scope_mix);
    c += ink_struct  * saturate(s0) * mix;
    c += ink_measure * saturate(s1) * mix;
    c += ink_predict * saturate(s2) * mix;

    // The gizmo resolves to TRUE red/green/blue rather than to the palette. That is the whole
    // reason it has its own channels: the axis convention only reads without a legend if the
    // colours are the ones every other 3D tool uses, so they must not be user-tintable.
    float gx = (float)Acc[tpAccIndex(tid.xy, W, H, TP_CH_GIZ_X, parity)] * inv;
    float gy = (float)Acc[tpAccIndex(tid.xy, W, H, TP_CH_GIZ_Y, parity)] * inv;
    float gz = (float)Acc[tpAccIndex(tid.xy, W, H, TP_CH_GIZ_Z, parity)] * inv;
    c += float3(1.0, 0.16, 0.16) * saturate(gx) * mix;
    c += float3(0.20, 1.0, 0.28) * saturate(gy) * mix;
    c += float3(0.26, 0.42, 1.0) * saturate(gz) * mix;

    // Depth is carried through in alpha. TP_Post ignores it, but passing it on keeps this node
    // a transparent link in the chain rather than a terminus, so anything added downstream can
    // still depth-test against the original render.
    OutputUAV[tid.xy] = float4(max(c, 0.0), beauty.a);
}
