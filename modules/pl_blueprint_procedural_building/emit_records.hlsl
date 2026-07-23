#include "types.hlsli"

RWStructuredBuffer<PNode> OutputBuffer : register(u0);

static const uint kRecordCount = 12;
static const PNode kRecords[12] = {
    { float3(0.0,0.0,0.0),1.0,0.0,2206954752.0,0.0,0.25,18.0,14.0,float2(0,1) },
    { float3(0.0,0.25,0.0),1.0,1.0,4134025984.0,0.0,1.20,12.0,8.4,float2(0,1) },
    { float3(0.0,1.45,-0.35),1.0,2.0,1636468992.0,0.0,8.80,10.4,6.8,float2(0,1) },
    { float3(0.7,10.25,-0.7),1.0,3.0,2060461696.0,0.0,1.15,7.4,4.8,float2(0,1) },
    { float3(0.0,3.25,4.15),1.0,4.0,405618976.0,0.0,0.32,5.2,2.6,float2(0,1) },
    { float3(-2.65,10.25,-0.75),1.0,7.0,465968064.0,0.0,2.2,2.6,2.4,float2(0,1) },
    { float3(-4.65,0.25,4.8),1.0,5.0,3187655424.0,0.08,0.55,2.5,1.25,float2(.079915,.996802) },
    { float3(4.65,0.25,4.8),1.0,5.0,2244793856.0,-0.08,0.55,2.5,1.25,float2(-.079915,.996802) },
    { float3(-3.55,0.25,6.1),1.0,6.0,2569552384.0,0.0,2.9,.3,.3,float2(0,1) },
    { float3(3.55,0.25,6.1),1.0,6.0,3122305280.0,0.0,2.9,.3,.3,float2(0,1) },
    { float3(-6.4,0.25,2.25),1.0,6.0,1151908992.0,0.0,2.9,.3,.3,float2(0,1) },
    { float3(6.4,0.25,2.25),1.0,6.0,521586560.0,0.0,2.9,.3,.3,float2(0,1) }
};

[numthreads(64,1,1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= kRecordCount) return;
    PNode n = kRecords[i];

    float2 towerXZ = float2(0.0, -0.35);
    float2 podiumXZ = float2(0.0, 0.0);
    float2 canopyXZ = float2(0.0, 4.15);
    float2 crownXZ = float2(0.7, -0.7);
    int mode = clamp(composition, 0, 3);

    if (i == 1u) {
        n.position.xz = podiumXZ;
        n.width = podium_width;
        n.depth = podium_depth;
    }
    if (i == 2u) {
        n.position.xz = towerXZ;
        n.position.y = 1.45;
        n.height = tower_height;
        n.width = tower_width;
        n.depth = tower_depth;
        if (mode == 1) n.width *= 0.82;
        if (mode == 2) n.depth *= 1.18;
        if (mode == 3) n.width *= 1.10;
    }
    if (i == 3u) {
        n.position.xz = crownXZ;
        n.position.y = 1.45 + tower_height;
        n.width = tower_width * lerp(0.42, 0.86, crown_scale);
        n.depth = tower_depth * lerp(0.38, 0.78, crown_scale);
        n.height = lerp(0.7, 2.4, crown_scale);
        if (mode == 2) { n.position.x += tower_width * 0.18; n.width *= 0.72; }
    }
    if (i == 4u) {
        n.position.xz = canopyXZ;
        n.position.y = 3.25;
        n.width = lerp(3.4, 7.4, canopy_scale);
        n.depth = lerp(1.7, 3.4, canopy_scale);
    }
    if (i == 5u) {
        float side = mode == 1 ? 1.0 : -1.0;
        n.position = float3(towerXZ.x + side * tower_width * 0.29,
                            1.45 + tower_height,
                            towerXZ.y - tower_depth * 0.08);
        n.height = lerp(1.0, 4.8, secondary_scale);
        n.width = lerp(1.8, tower_width * 0.58, secondary_scale);
        n.depth = lerp(1.6, tower_depth * 0.64, secondary_scale);
        if (mode == 3) {
            n.position.y = 1.45 + tower_height * 0.62;
            n.position.x = towerXZ.x - tower_width * 0.34;
            n.width *= 1.25;
        }
    }
    if (i == 6u || i == 7u) {
        float side = i == 6u ? -1.0 : 1.0;
        n.position.x = podiumXZ.x + side * podium_width * 0.39;
        n.position.z = podiumXZ.y + podium_depth * 0.57;
    }
    if (i >= 8u) {
        float side = (i == 8u || i == 10u) ? -1.0 : 1.0;
        float front = i < 10u ? 0.72 : 0.28;
        n.position.x = podiumXZ.x + side * podium_width * (i < 10u ? 0.30 : 0.53);
        n.position.z = podiumXZ.y + podium_depth * front;
    }

    OutputBuffer[i] = n;
}
