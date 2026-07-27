RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> LedgerPlate : register(t0);
Texture2D<float4> ParticleField : register(t1);
StructuredBuffer<float4> StatsInput : register(t2);

#include "rail_camera.hlsli"

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint width;
    uint height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;

    float2 resolution = float2((float)width, (float)height);
    float2 uv = ((float2)tid.xy + 0.5) / resolution;
    float aspect = resolution.x / max(resolution.y, 1.0);
    float4 particles = ParticleField.SampleLevel(LinearSampler, uv, 0);
    float3 color = particles.rgb;

    float3 rayOrigin = _CameraPos;
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 nearWorld = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farWorld = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nearWorld /= nearWorld.w;
    farWorld /= farWorld.w;
    float3 rayDirection = normalize(farWorld.xyz - nearWorld.xyz);
    float3 localOrigin = pdWorldToLedgerLocal(rayOrigin);
    float3 localDirection = pdWorldDirectionToLedger(rayDirection);
    float planeT = -localOrigin.z / (abs(localDirection.z) > 1e-5 ? localDirection.z : 1e-5);
    float3 planeHit = localOrigin + localDirection * planeT;
    float2 planeUv = float2(
        planeHit.x / max(plane_scale * aspect * 4.0, 1e-5) + 0.5,
        1.0 - (planeHit.y / max(plane_scale * 4.0, 1e-5) + 0.5)
    );
    float planeMask =
        step(0.0, planeT) *
        step(0.0, planeUv.x) * step(planeUv.x, 1.0) *
        step(0.0, planeUv.y) * step(planeUv.y, 1.0);

    float3 ledger = LedgerPlate.SampleLevel(LinearSampler, saturate(planeUv), 0).rgb;
    float ledgerLuma = dot(ledger, float3(0.299, 0.587, 0.114));
    float inkAlpha = smoothstep(0.035, 0.17, ledgerLuma) * ledger_opacity * planeMask;
    float gridX = 1.0 - smoothstep(0.016, 0.05, abs(frac(planeUv.x * 16.0) - 0.5));
    float gridY = 1.0 - smoothstep(0.016, 0.05, abs(frac(planeUv.y * 9.0) - 0.5));
    float membraneGrid = max(gridX, gridY) * planeMask;
    float3 membrane = float3(0.035, 0.038, 0.034) + liability_color * membraneGrid * 0.035;
    color = lerp(color, membrane, membrane_opacity * planeMask);
    color = lerp(color, ledger * (0.72 + ledgerLuma * 0.42), saturate(inkAlpha));

    float edgeDistance = min(
        min(abs(planeUv.x), abs(1.0 - planeUv.x)),
        min(abs(planeUv.y), abs(1.0 - planeUv.y))
    );
    float planeBorder = (1.0 - smoothstep(0.002, 0.006, edgeDistance)) * planeMask;
    // The border is only a faint registration trace; its structural
    // continuation is authored in the 3D field pass.
    color += float3(0.72, 0.74, 0.69) * planeBorder * 0.10;

    float4 stats = StatsInput[0];
    float activeBarWidth = saturate(stats.x / 64.0) * 0.27;
    float bar = step(abs(uv.y - 0.955), 0.006) * step(0.035, uv.x) * step(uv.x, 0.035 + activeBarWidth);
    color += liability_color * bar * 0.75;

    float border =
        step(0.009, uv.x) * step(uv.x, 0.991) *
        step(0.015, uv.y) * step(uv.y, 0.985);
    color *= border;
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
