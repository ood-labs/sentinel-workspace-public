#ifndef ZAHA_CLONER_TYPES_HLSLI
#define ZAHA_CLONER_TYPES_HLSLI
struct LoftSection {
    float3 center; float radius_x;
    float radius_z; float rotation; float curvature; float u;
    float floor_band; float skin_bias; float void_bias; float active;
    float3 tangent; float seed;
};
struct SurfaceInstance {
    float3 position; float type_id;
    float3 scale; float rotation;
    float3 normal; float material_id;
    float2 uv; float emissive; float active;
};
#endif
