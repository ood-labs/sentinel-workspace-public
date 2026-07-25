#ifndef AU_RELIEF_SCENE_HLSLI
#define AU_RELIEF_SCENE_HLSLI

// AUTOPSIA — shared scene definition for the 3D relief.
// The specimen becomes terrain: field density drives height over a flat plate,
// contained inside a wireframe survey cage. Every camera-dependent ray in every
// pass is built from the injected internal camera; nothing here invents a view.

// world domain of the plate (16:9)
static const float2 AU_DOMAIN = float2(3.2, 1.8);

#define MAT_MISS    0.0
#define MAT_TERRAIN 1.0
#define MAT_CAGE    2.0

float2 auWorldToUV(float2 xz) {
    return xz / AU_DOMAIN + 0.5;
}

float3 auUVToWorld(float2 uv, float y) {
    return float3((uv.x - 0.5) * AU_DOMAIN.x, y, (uv.y - 0.5) * AU_DOMAIN.y);
}

// Field texture: r = density, gb = gradient (biased), a = operator heat.
float auDensityAt(Texture2D<float4> fieldTex, SamplerState samp, float2 xz) {
    float2 uv = auWorldToUV(xz);
    if (any(uv < 0.0) || any(uv > 1.0)) return -1.0;
    return fieldTex.SampleLevel(samp, uv, 0).r;
}

float auTerrainHeight(Texture2D<float4> fieldTex, SamplerState samp, float2 xz, float heightScale) {
    float d = auDensityAt(fieldTex, samp, xz);
    if (d < 0.0) return -1000.0;                  // outside the plate: no ground
    return max(d, 0.0) * heightScale;
}

// Height sampled with CLAMPED uv so the function stays defined outside the
// plate; the domain bound below is what actually cuts the block.
float auHeightClamped(Texture2D<float4> fieldTex, SamplerState samp, float2 xz, float heightScale) {
    float2 uv = saturate(auWorldToUV(xz));
    return max(fieldTex.SampleLevel(samp, uv, 0).r, 0.0) * heightScale;
}

// The specimen as a SOLID BLOCK: the height field capped on top, a flat base
// underneath, intersected with the plate footprint. Modelling it as real solid
// geometry (rather than an open surface) gives consistent cut side-walls, which
// shade as a geological section through the sample.
float auSolid(Texture2D<float4> fieldTex, SamplerState samp, float3 p,
              float heightScale, float slabDepth) {
    float2 q = abs(p.xz) - AU_DOMAIN * 0.5;
    float dXZ = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);

    float h = auHeightClamped(fieldTex, samp, p.xz, heightScale);
    float dTop = p.y - h;
    float dBot = -(p.y + slabDepth);

    return max(max(dTop, dBot), dXZ);
}

// rounded box frame — the survey cage
float auSdBoxFrame(float3 p, float3 b, float e) {
    p = abs(p) - b;
    float3 q = abs(p + e) - e;
    return min(min(
        length(max(float3(p.x, q.y, q.z), 0.0)) + min(max(p.x, max(q.y, q.z)), 0.0),
        length(max(float3(q.x, p.y, q.z), 0.0)) + min(max(q.x, max(p.y, q.z)), 0.0)),
        length(max(float3(q.x, q.y, p.z), 0.0)) + min(max(q.x, max(q.y, p.z)), 0.0));
}

// Scene map. Returns x = signed-ish distance, y = material id.
// The terrain term is a vertical difference scaled down to stay a safe step.
float2 auMap(Texture2D<float4> fieldTex, SamplerState samp, float3 p,
             float heightScale, float cageInset) {
    float h = auTerrainHeight(fieldTex, samp, p.xz, heightScale);
    float dTerr = (p.y - h) * 0.55;

    float3 cageB = float3(AU_DOMAIN.x * 0.5, heightScale * 0.62, AU_DOMAIN.y * 0.5);
    float3 cageC = float3(0.0, heightScale * 0.62, 0.0);
    float dCage = auSdBoxFrame(p - cageC, cageB, max(cageInset, 0.0005));

    if (dTerr < dCage) return float2(dTerr, MAT_TERRAIN);
    return float2(dCage, MAT_CAGE);
}

float3 auNormal(Texture2D<float4> fieldTex, SamplerState samp, float3 p,
                float heightScale, float cageInset, float eps) {
    float2 e = float2(eps, 0.0);
    float dx = auMap(fieldTex, samp, p + e.xyy, heightScale, cageInset).x
             - auMap(fieldTex, samp, p - e.xyy, heightScale, cageInset).x;
    float dy = auMap(fieldTex, samp, p + e.yxy, heightScale, cageInset).x
             - auMap(fieldTex, samp, p - e.yxy, heightScale, cageInset).x;
    float dz = auMap(fieldTex, samp, p + e.yyx, heightScale, cageInset).x
             - auMap(fieldTex, samp, p - e.yyx, heightScale, cageInset).x;
    return normalize(float3(dx, dy, dz) + float3(0.0, 1e-6, 0.0));
}

#endif
