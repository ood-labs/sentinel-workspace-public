#ifndef ZAHA_RENDER_TYPES_HLSLI
#define ZAHA_RENDER_TYPES_HLSLI
struct LoftSection { float3 center; float radius_x; float radius_z; float rotation; float curvature; float u; float floor_band; float skin_bias; float void_bias; float active; float3 tangent; float seed; };
struct SurfaceInstance { float3 position; float type_id; float3 scale; float rotation; float3 normal; float material_id; float2 uv; float emissive; float active; };
struct MaterialRecord { float3 base_color; float roughness; float3 secondary_color; float metallic; float texture_scale; float texture_strength; float pattern_id; float emissive; float specular; float normal_strength; float seed; float reserved; };
#endif
