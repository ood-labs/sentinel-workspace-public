#include "types.hlsli"
RWStructuredBuffer<PNode> OutputBuffer : register(u0);

static const PNode kRecords[23] = {
    { float3(-0.65,0.12,2.35),1,6,520709856,3.14159,1.08,3.20,1.08,float2(0.000003,-1) },
    { float3(-2.55,0.12,0.70),1,7,2159804416,-1.30,1.08,1.15,1.18,float2(0.963558,0.267499) },
    { float3(1.55,0.12,1.45),1,7,2325006592,1.95,1.08,1.15,1.18,float2(-0.928960,-0.370181) },
    { float3(-0.35,0.15,0.50),1,8,4266785792,-0.08,0.45,1.85,0.92,float2(-0.079915,0.996802) },
    { float3(1.65,0.15,0.10),1,19,51662876,-0.18,0.42,0.92,0.72,float2(-0.179030,0.983844) },
    { float3(-2.85,0.12,2.05),1,9,1448165632,0,0.60,0.60,0.60,float2(0,1) },
    { float3(1.85,0.12,2.50),1,9,441855168,0,0.60,0.60,0.60,float2(0,1) },
    { float3(0.95,0.12,-3.12),1,10,3741216512,0,0.62,2.75,0.52,float2(0,1) },
    { float3(0.95,1.22,-3.38),1,11,1351758208,0,1.32,2.35,0.12,float2(0,1) },
    { float3(3.45,0.12,-2.40),1,12,471903136,0,2.35,1.25,0.38,float2(0,1) },
    { float3(-0.75,0.12,-3.12),1,18,577790976,0,1.08,0.34,0.36,float2(0,1) },
    { float3(2.65,0.12,-3.12),1,18,3898537984,0,1.08,0.34,0.36,float2(0,1) },
    { float3(-3.35,0.12,2.45),1,14,3211099392,0,1.90,0.58,0.58,float2(0,1) },
    { float3(1.85,0.72,2.50),1,15,2202852352,0,0.68,0.42,0.42,float2(0,1) },
    { float3(-3.55,0.12,-2.20),1,16,2536314112,0.40,1.45,0.85,0.85,float2(0.389418,0.921061) },
    { float3(2.75,0.12,-2.55),1,16,1023553280,-0.70,1.45,0.85,0.85,float2(-0.644218,0.764842) },
    { float3(-1.65,0.74,2.28),1,20,2438612480,0.18,0.18,0.52,0.52,float2(0.179030,0.983844) },
    { float3(-0.55,0.74,2.29),1,20,2421834752,-0.12,0.18,0.52,0.52,float2(-0.119712,0.992809) },
    { float3(0.55,0.74,2.28),1,20,2405057024,0.08,0.18,0.52,0.52,float2(0.079915,0.996802) },
    { float3(-0.45,0.60,0.45),1,21,1458404224,0,0.22,0.42,0.28,float2(0,1) },
    { float3(1.35,0.76,-3.10),1,21,1978570752,0,0.46,0.26,0.26,float2(0,1) },
    { float3(3.25,1.16,-2.36),1,21,4276021760,0,0.36,0.28,0.24,float2(0,1) },
    { float3(3.60,1.82,-2.36),1,21,4225688832,0,0.40,0.30,0.26,float2(0,1) }
};

[numthreads(64,1,1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= LR_RECORD_COUNT) return;
    uint i = id.x; PNode r = kRecords[i];
    r.position.x += layout_offset.x; r.position.z += layout_offset.y;
    bool seating = i <= 6u || (i >= 12u && i <= 13u) || (i >= 16u && i <= 19u);
    if (seating) {
        float2 center = float2(-0.45,1.20) + layout_offset;
        r.position.xz = center + (r.position.xz - center) * seating_spread;
    }
    if (i == 0u || (i >= 16u && i <= 18u)) r.position.xz += sofa_offset;
    if (i == 1u) { r.position.xz += left_chair_offset; r.yaw = left_chair_yaw; }
    if (i == 2u) { r.position.xz += right_chair_offset; r.yaw = right_chair_yaw; }
    if (i == 3u || i == 19u) { r.position.xz += coffee_table_offset; if (i == 3u) r.yaw = coffee_table_yaw; }
    if ((i >= 7u && i <= 11u) || (i >= 20u && i <= 22u)) r.position.xz += media_wall_offset;
    if (i == 14u || i == 15u) {
        float plantCenterX = -0.40 + layout_offset.x;
        r.position.x = plantCenterX + (r.position.x - plantCenterX) * plant_spread;
        r.position.z += plant_depth_offset;
    }
    r.dir = float2(-sin(r.yaw), cos(r.yaw)); OutputBuffer[i] = r;
}
