
#define SEGMENTS 49
#define FIXTURES 288
struct RigRecord {float4 a;float4 b;float4 shape;float4 meta;};
struct MountRecord {float3 position;float fixture_id;float mount_pitch;float mount_roll;float base_visible;float active;float2 content_origin;float2 content_extent;float4 reserved;};
