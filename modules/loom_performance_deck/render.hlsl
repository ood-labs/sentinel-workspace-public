#include "../_shared/ui/sui_theme.hlsli"
#include "../_shared/ui/sui_core.hlsli"
#include "../_shared/ui/sui_typography.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;

    float wave = _Tex1.SampleLevel(LinearSampler, uv, 0).r;
    float2 grad = float2(
        _Tex1.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).r - _Tex1.SampleLevel(LinearSampler, uv - float2(texel.x, 0.0), 0).r,
        _Tex1.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).r - _Tex1.SampleLevel(LinearSampler, uv - float2(0.0, texel.y), 0).r
    );

    float2 warpedUv = saturate(uv + grad * (0.012 * refraction));
    float3 color = _Tex0.SampleLevel(LinearSampler, warpedUv, 0).rgb;
    float crest = saturate(abs(wave) * 0.55 + length(grad) * 2.8);
    float signedLight = wave * 0.5 + dot(grad, normalize(float2(-0.6, 0.8))) * 2.0;
    color += contour_color * max(0.0, signedLight) * contour_gain;
    color -= color * max(0.0, -signedLight) * contour_gain * 0.16;
    color += contour_color * crest * crest * contour_gain * 0.10;

    SuiContext c = suiContext(id.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    float4 ctrl = _Tex2.Load(int3(0, 0, 0));
    float alpha = saturate(hud_opacity);

    float4 hud = float4(0.018, 0.025, 0.235, 0.145);
    suiComposite(color, float3(0.006, 0.016, 0.024), suiFillRect(c, hud) * alpha * 0.72);
    suiComposite(color, float3(0.16, 0.78, 0.90), suiFillRect(c, float4(hud.x, hud.y, hud.x + 0.002, hud.w)) * alpha);
    suiComposite(color, theme.text, suiLabelText(c, float2(0.033, 0.043), suiSectionStyle(), UI_LABEL_TITLE) * alpha);
    suiComposite(color, float3(0.20, 0.82, 0.92), suiLabelText(c, float2(0.183, 0.043), suiBodyStyle(), UI_LABEL_LIVE) * alpha);
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.033, 0.086), suiBodyStyle(), UI_LABEL_CORNERS) * alpha);
    suiComposite(color, theme.text, suiInteger(c, float2(0.105, 0.086), suiBodyStyle(), (int)round(corner_count), 2) * alpha);
    suiComposite(color, theme.muted, suiLabelText(c, float2(0.145, 0.086), suiBodyStyle(), UI_LABEL_BLOBS) * alpha);
    suiComposite(color, theme.text, suiInteger(c, float2(0.198, 0.086), suiBodyStyle(), (int)round(blob_count), 2) * alpha);

    float4 activityBar = float4(0.033, 0.118, 0.220, 0.126);
    suiComposite(color, float3(0.04, 0.10, 0.13), suiFillRect(c, activityBar) * alpha);
    suiComposite(color, float3(0.18, 0.82, 0.94), suiFillRect(c, float4(activityBar.x, activityBar.y, lerp(activityBar.x, activityBar.z, saturate(ctrl.b)), activityBar.w)) * alpha);

    if (ViewportButtonDown(0)) {
        float aspect = _Resolution.x / max(_Resolution.y, 1.0);
        float2 d = (uv - _ViewportPointerPosition) * float2(aspect, 1.0);
        float ring = abs(length(d) - ctrl.r * 0.21);
        color += contour_color * smoothstep(0.0035, 0.0, ring) * 0.65;
    }

    OutputUAV[id.xy] = float4(saturate(color), 1.0);
}
