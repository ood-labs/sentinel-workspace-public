#include "fruit_scene_types.hlsli"

static const uint MAX_SLOTS = 64u;
static const uint MAX_PARTICLES = 256u;
StructuredBuffer<CardOverride> _Tex1 : register(t1);

struct VS_OUTPUT {
    float4 Position : SV_POSITION;
    float2 CellUV : TEXCOORD0;
    float2 LocalUV : TEXCOORD1;
    float Slot : TEXCOORD2;
    float Fade : TEXCOORD3;
    float DepthSample : TEXCOORD4;
    float Highlight : TEXCOORD5;
};

static const float2 QUAD_OFFSETS[6] = {
    float2(-1.0, -1.0), float2(1.0, -1.0), float2(1.0, 1.0),
    float2(-1.0, -1.0), float2(1.0, 1.0), float2(-1.0, 1.0)
};
static const float2 QUAD_UVS[6] = {
    float2(0.0, 1.0), float2(1.0, 1.0), float2(1.0, 0.0),
    float2(0.0, 1.0), float2(1.0, 0.0), float2(0.0, 0.0)
};

uint blockColumns(uint slots) {
    if (slots <= 1u) return 1u;
    if (slots <= 4u) return 2u;
    if (slots <= 9u) return 3u;
    if (slots <= 16u) return 4u;
    if (slots <= 25u) return 5u;
    if (slots <= 36u) return 6u;
    if (slots <= 49u) return 7u;
    return 8u;
}

float2 cellUV(uint slot, uint column, float2 localUv) {
    uint slots = max(1u, (uint)slot_count);
    uint columns = max(1u, (uint)column_count);
    uint blocks = blockColumns(slots);
    uint blockX = slot % blocks;
    uint blockY = slot / blocks;
    float2 origin = float2((blockX * columns + column) * tile_width, blockY * tile_height);
    float2 atlasSize;
    _Tex0.GetDimensions(atlasSize.x, atlasSize.y);
    return (origin + localUv * float2(tile_width, tile_height)) / max(atlasSize, 1.0.xx);
}

float slotDepth(uint slot) {
    uint column = min((uint)depth_column, max(1u, (uint)column_count) - 1u);
    float3 d = _Tex0.SampleLevel(LinearSampler, cellUV(slot, column, 0.5.xx), 0).rgb;
    return saturate(dot(d, float3(0.299, 0.587, 0.114)));
}

float segmentationMask(uint slot, float2 localUv) {
    if (!segmentation_enabled) return 1.0;
    uint column = min((uint)segmentation_column, max(1u, (uint)column_count) - 1u);
    float3 m = _Tex0.SampleLevel(LinearSampler, cellUV(slot, column, localUv), 0).rgb;
    return saturate(dot(m, float3(0.299, 0.587, 0.114)));
}

VS_OUTPUT VSMain(uint vertexId : SV_VertexID) {
    VS_OUTPUT o = (VS_OUTPUT)0;
    uint particleIndex = vertexId / 6u;
    uint corner = vertexId % 6u;
    uint liveSlots = min(_Data0_Count, min((uint)slot_count, MAX_SLOTS));
    if (liveSlots == 0u) liveSlots = min((uint)occupied_count, min((uint)slot_count, MAX_SLOTS));
    uint cloneCount = (uint)clamp(particle_clones, 1, 4);
    uint particleCount = min(liveSlots * cloneCount, MAX_PARTICLES);
    if (particleIndex >= particleCount || liveSlots == 0u) {
        o.Position = float4(0.0, 0.0, -999.0, 1.0);
        return o;
    }

    uint recordIndex = particleIndex % liveSlots;
    uint cloneIndex = particleIndex / liveSlots;

    uint slot = recordIndex;
    float sequence = (float)recordIndex;
    float ageRank = (float)recordIndex;
    if (_Data0_Count > 0u) {
        _DataType_0 occ = _Data0[recordIndex];
        if (occ.occupied < 0.5) {
            o.Position = float4(0.0, 0.0, -999.0, 1.0);
            return o;
        }
        slot = min((uint)round(occ.slot_index), max(1u, (uint)slot_count) - 1u);
        sequence = occ.sequence + (float)cloneIndex * 31.731;
        ageRank = occ.age_rank + (float)cloneIndex * 0.37;
    }

    float life = fruitLife(particleIndex, sequence, particleCount);
    CardOverride edit = _Tex1[recordIndex];
    float3 center = fruitTrajectory(particleIndex, life, ageRank) + edit.offset;
    float depthValue = slotDepth(slot);
    center.z += (depthValue - 0.5) * depth_scale * 0.7;

    float cloneScale = lerp(0.72, 1.18, hash1(particleIndex + 121.0));
    float scale = fruitScale(slot, life, edit) * cloneScale;
    float angle = signedHash(particleIndex + 51.0) * 0.24 + _Time * spin * signedHash(particleIndex + 71.0) * 0.18 + edit.rotation;
    float cs = cos(angle), sn = sin(angle);
    float2 local = QUAD_OFFSETS[corner];
    local = float2(local.x * cs - local.y * sn, local.x * sn + local.y * cs);
    float atlasAspect = tile_width / max(tile_height, 1.0);
    local.x *= atlasAspect;
    float3 world = center + float3(local * scale, 0.0);

    float4 clip = mul(_ViewProjMatrix, float4(world, 1.0));
    o.Position = clip;
    o.CellUV = cellUV(slot, 0u, QUAD_UVS[corner]);
    o.LocalUV = QUAD_UVS[corner];
    o.Slot = (float)slot;
    o.Fade = smoothstep(0.0, 0.07, life) * (1.0 - smoothstep(0.90, 1.0, life));
    o.DepthSample = depthValue;
    o.Highlight = pow(saturate(1.0 - abs(life - 0.78) * 3.5), 2.0);
    return o;
}

float4 PSMain(VS_OUTPUT input) : SV_TARGET {
    uint slot = (uint)round(input.Slot);
    float mask = segmentationMask(slot, input.LocalUV);
    if (segmentation_enabled && mask <= 0.045) discard;

    float2 reliefOffset = (input.LocalUV - 0.5) * (input.DepthSample - 0.5) * depth_scale * 0.012;
    float3 fruit = _Tex0.SampleLevel(LinearSampler, input.CellUV + reliefOffset, 0).rgb;
    float luminance = dot(fruit, float3(0.299, 0.587, 0.114));
    fruit *= lerp(0.84, 1.18, input.DepthSample);
    fruit += input.Highlight * stage_glow * (0.04 + luminance * 0.05);
    return float4(saturate(fruit), mask * input.Fade);
}
