#ifndef PD_RAIL_CAMERA_HLSLI
#define PD_RAIL_CAMERA_HLSLI

float2 pdRailRotate2(float2 p, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float3 pdRailRotateY(float3 p, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

float3 pdRailRotateZ(float3 p, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return float3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

float2 pdRailCameraOffset(float cameraDistance)
{
    return 0.0;
}

float2 pdRailVanish(float aspect)
{
    float4 clip = mul(_ViewProjMatrix, float4(float3(0.0, 0.0, depth_length), 1.0));
    clip /= max(clip.w, 1e-5);
    return float2(clip.x * 0.5 * aspect, -clip.y * 0.5);
}

float pdRailFocalLength()
{
    return lerp(1.03, 1.34, camera_follow);
}

float3 pdRailCameraOrigin(float cameraDistance)
{
    return _CameraPos;
}

float2 pdRailScreen(float2 uv, float aspect)
{
    return (uv - 0.5) * float2(aspect, 1.0);
}

float3 pdRailCameraRay(float2 uv, float aspect, float cameraDistance)
{
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 nearWorld = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farWorld = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nearWorld /= nearWorld.w;
    farWorld /= farWorld.w;
    return normalize(farWorld.xyz - nearWorld.xyz);
}

float3 pdLedgerToWorld(float3 ledgerPosition, float aspect)
{
    float3 localPosition = float3(
        (ledgerPosition.x - 0.5) * plane_scale * aspect * 4.0,
        (ledgerPosition.y - 0.5) * plane_scale * 4.0,
        ledgerPosition.z
    );
    localPosition = pdRailRotateY(localPosition, plane_yaw);
    localPosition = pdRailRotateZ(localPosition, plane_roll);
    return localPosition + float3(-0.035, 0.012, 0.0);
}

float3 pdWorldToLedgerLocal(float3 worldPosition)
{
    float3 localPosition = worldPosition - float3(-0.035, 0.012, 0.0);
    localPosition = pdRailRotateZ(localPosition, -plane_roll);
    localPosition = pdRailRotateY(localPosition, -plane_yaw);
    return localPosition;
}

float3 pdWorldDirectionToLedger(float3 worldDirection)
{
    float3 localDirection = pdRailRotateZ(worldDirection, -plane_roll);
    return pdRailRotateY(localDirection, -plane_yaw);
}

float2 pdProjectLedger(
    float3 ledgerPosition,
    float aspect,
    float cameraDistance)
{
    float3 worldPosition = pdLedgerToWorld(ledgerPosition, aspect);
    float4 clip = mul(_ViewProjMatrix, float4(worldPosition, 1.0));
    clip /= max(clip.w, 1e-5);
    return float2(clip.x * 0.5 * aspect, -clip.y * 0.5);
}

#endif
