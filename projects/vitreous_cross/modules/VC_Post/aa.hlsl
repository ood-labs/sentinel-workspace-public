// VC_Post / aa.hlsl — edge antialiasing.
//
// This image aliases in a specific way: the sculpture is made almost entirely of straight
// box arrises, and every one of them is a one-ray-per-pixel silhouette between two very
// different values. A luminance-gradient filter that blurs ONLY along the detected edge
// direction fixes those without touching the dispersion fringes and membrane detail, which a
// general softening pass would erase.
//
// Reach is deliberately short. A long filter stops being an edge filter and becomes a blur.
RWTexture2D<float4> OutputUAV : register(u0);

float lum(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pix = DTid.xy;
    if (pix.x >= W || pix.y >= H) return;

    float2 res = float2(W, H);
    float2 uv = ((float2)pix + 0.5) / res;
    float2 px = 1.0 / res;

    float3 cM = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    if (aa_strength < 1e-4) { OutputUAV[pix] = float4(cM, 1.0); return; }

    float lN = lum(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, -px.y), 0).rgb);
    float lS = lum(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0,  px.y), 0).rgb);
    float lE = lum(_Tex0.SampleLevel(LinearSampler, uv + float2( px.x, 0.0), 0).rgb);
    float lW = lum(_Tex0.SampleLevel(LinearSampler, uv + float2(-px.x, 0.0), 0).rgb);
    float lM = lum(cM);

    float lMin = min(lM, min(min(lN, lS), min(lE, lW)));
    float lMax = max(lM, max(max(lN, lS), max(lE, lW)));
    float range = lMax - lMin;

    if (range < max(aa_threshold, 1e-4))
    {
        OutputUAV[pix] = float4(cM, 1.0);
        return;
    }

    // Filter direction is PERPENDICULAR to the luminance gradient, so the blur runs along the
    // edge and never across it.
    float2 grad = float2(lE - lW, lS - lN);
    float gl = length(grad);
    float2 dir = (gl > 1e-6) ? float2(-grad.y, grad.x) / gl : float2(1.0, 0.0);

    float reach = aa_reach;
    float3 a = _Tex0.SampleLevel(LinearSampler, uv + dir * px * reach, 0).rgb;
    float3 b = _Tex0.SampleLevel(LinearSampler, uv - dir * px * reach, 0).rgb;
    float3 c = _Tex0.SampleLevel(LinearSampler, uv + dir * px * reach * 2.0, 0).rgb;
    float3 d = _Tex0.SampleLevel(LinearSampler, uv - dir * px * reach * 2.0, 0).rgb;

    float3 blurred = (cM * 2.0 + a + b + (c + d) * 0.5) / 5.0;

    // Blend proportional to how strong the edge is, capped by the control.
    float w = saturate(range / max(aa_threshold, 1e-4) - 1.0);
    OutputUAV[pix] = float4(lerp(cM, blurred, saturate(w) * aa_strength), 1.0);
}
