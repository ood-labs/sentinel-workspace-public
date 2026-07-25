// CRYOGRAM / INTERPRETATION — shared domain mapping for the relief renderer.
//
// One mapping, used by the marcher, the shader, and every 3D overlay. If the
// filaments and the terrain disagree about where (0.5, 0.5) is, the whole
// interpretation layer is lying.

#ifndef CRYO_RELIEF_COMMON
#define CRYO_RELIEF_COMMON

static const float CRYO_ASPECT = 16.0 / 9.0;

// Field uv (0..1, y down, exactly the analysis/track normalisation) -> world XZ.
float3 cryoWorldFromUv(float2 uv, float y) {
    return float3((uv.x - 0.5) * 2.0 * CRYO_ASPECT, y, (uv.y - 0.5) * 2.0);
}

float2 cryoUvFromWorld(float3 p) {
    return float2(p.x / (2.0 * CRYO_ASPECT) + 0.5, p.z * 0.5 + 0.5);
}

// Bilinear read of the packed field. Compute passes have no sampler, and the
// field is 8-bit, so filtering here is what keeps the relief from terracing.
float4 cryoFieldBilinear(Texture2D<float4> tex, float2 uv) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return float4(0, 0, 0, 0);
    uint w, h;
    tex.GetDimensions(w, h);
    float2 t = uv * float2(w, h) - 0.5;
    int2 b = (int2)floor(t);
    float2 f = t - (float2)b;
    int2 mx = int2(w, h) - 1;
    float4 c00 = tex.Load(int3(clamp(b + int2(0, 0), int2(0, 0), mx), 0));
    float4 c10 = tex.Load(int3(clamp(b + int2(1, 0), int2(0, 0), mx), 0));
    float4 c01 = tex.Load(int3(clamp(b + int2(0, 1), int2(0, 0), mx), 0));
    float4 c11 = tex.Load(int3(clamp(b + int2(1, 1), int2(0, 0), mx), 0));
    return lerp(lerp(c00, c10, f.x), lerp(c01, c11, f.x), f.y);
}

// Project a world point to pixel coordinates through the INTERNAL camera.
// Returns false behind the eye. w carries view distance for depth testing.
bool cryoProject(float3 world, float2 resolution, out float2 pixel, out float dist) {
    float4 clip = mul(_ViewProjMatrix, float4(world, 1.0));
    pixel = float2(0.0, 0.0);
    dist = 0.0;
    if (clip.w <= 1e-4) return false;
    float3 ndc = clip.xyz / clip.w;
    pixel = float2((ndc.x * 0.5 + 0.5) * resolution.x, (1.0 - (ndc.y * 0.5 + 0.5)) * resolution.y);
    dist = length(world - _CameraPos);
    return true;
}

float cryoSegDist(float2 p, float2 a, float2 b, out float tOut) {
    float2 ab = b - a;
    float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-6));
    tOut = t;
    return length(p - (a + ab * t));
}

#endif
