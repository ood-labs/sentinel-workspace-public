RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 nearWorld = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farWorld = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nearWorld /= nearWorld.w;
    farWorld /= farWorld.w;
    float3 rayOrigin = _CameraPos;
    float3 rayDir = normalize(farWorld.xyz - nearWorld.xyz);

    float3 sphereCenter = float3(0.0, 1.0, 0.0);
    float3 oc = rayOrigin - sphereCenter;
    float b = dot(oc, rayDir);
    float c = dot(oc, oc) - 1.0;
    float discriminant = b * b - c;

    float3 color = lerp(float3(0.025, 0.035, 0.065), float3(0.08, 0.12, 0.20), uv.y);
    if (discriminant >= 0.0) {
        float t = -b - sqrt(discriminant);
        if (t > 0.0) {
            float3 hitPos = rayOrigin + rayDir * t;
            float3 normal = normalize(hitPos - sphereCenter);
            float light = 0.22 + 0.78 * saturate(dot(normal, normalize(float3(-0.4, 0.8, -0.5))));
            float longitude = step(0.92, abs(sin(atan2(normal.z, normal.x) * 8.0)));
            float latitude = step(0.94, abs(sin(asin(normal.y) * 10.0)));
            float3 base = lerp(float3(1.0, 0.20, 0.06), float3(1.0, 0.82, 0.20), longitude * 0.5 + latitude * 0.5);
            color = base * light;
        }
    }
    OutputUAV[pixel] = float4(color, 1.0);
}
