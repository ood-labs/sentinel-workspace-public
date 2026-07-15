static const uint MAX_SLOTS = 64;
static const float TWO_PI = 6.28318530718;

struct VS_OUTPUT {
    float4 Position : SV_POSITION;
    float2 CellUV   : TEXCOORD0;
    float  Valid    : TEXCOORD1;
    float3 Tint     : COLOR0;
    float2 LocalUV  : TEXCOORD2;
    float  Slot     : TEXCOORD3;
};

static const float2 QUAD_OFFSETS[6] = {
    float2(-1.0, -1.0), float2( 1.0, -1.0), float2( 1.0,  1.0),
    float2(-1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
};

static const float2 QUAD_UVS[6] = {
    float2(0.0, 1.0), float2(1.0, 1.0), float2(1.0, 0.0),
    float2(0.0, 1.0), float2(1.0, 0.0), float2(0.0, 0.0)
};

uint blockColumns(uint slots)
{
    if (slots <= 1) return 1;
    if (slots <= 4) return 2;
    if (slots <= 9) return 3;
    if (slots <= 16) return 4;
    if (slots <= 25) return 5;
    if (slots <= 36) return 6;
    if (slots <= 49) return 7;
    return 8;
}

float2 cellOrigin(uint slot, uint column)
{
    uint slots = max(1, (uint)slot_count);
    uint columns = max(1, (uint)column_count);
    uint blocks = blockColumns(slots);
    uint blockX = slot % blocks;
    uint blockY = slot / blocks;
    return float2((blockX * columns + column) * tile_width, blockY * tile_height);
}

float2 cellUV(uint slot, uint column, float2 localUv)
{
    float2 origin = cellOrigin(slot, column);
    float2 pixel = origin + localUv * float2(tile_width, tile_height);
    float2 atlasSize;
    _Tex0.GetDimensions(atlasSize.x, atlasSize.y);
    return pixel / max(float2(1.0, 1.0), atlasSize);
}

float slotHash(uint slot, float salt)
{
    float v = frac(sin(dot(float2((float)slot + 1.0, salt + scatter_seed), float2(12.9898, 78.233))) * 43758.5453);
    return v;
}

float slotDepth(uint slot)
{
    uint column = min((uint)depth_column, max(1, (uint)column_count) - 1);
    float2 uv = cellUV(slot, column, float2(0.5, 0.5));
    return saturate(dot(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb, float3(0.299, 0.587, 0.114)));
}

float segmentationMask(uint slot, float2 localUv)
{
    if (segmentation_enabled == 0) return 1.0;
    uint column = min((uint)segmentation_column, max(1, (uint)column_count) - 1);
    float2 uv = cellUV(slot, column, localUv);
    float4 maskValue = _Tex0.SampleLevel(LinearSampler, uv, 0);
    return saturate(dot(maskValue.rgb, float3(0.299, 0.587, 0.114)));
}

VS_OUTPUT VSMain(uint vertexId : SV_VertexID)
{
    VS_OUTPUT o;
    uint recordIndex = vertexId / 6;
    uint corner = vertexId % 6;
    uint liveSlots = min(_Data0_Count, min((uint)slot_count, MAX_SLOTS));
    if (liveSlots == 0) {
        liveSlots = min((uint)occupied_count, min((uint)slot_count, MAX_SLOTS));
    }
    if (recordIndex >= liveSlots) {
        o.Position = float4(0.0, 0.0, -999.0, 1.0);
        o.CellUV = float2(0.0, 0.0);
        o.Valid = 0.0;
        o.Tint = float3(0.0, 0.0, 0.0);
        o.LocalUV = float2(0.0, 0.0);
        o.Slot = 0.0;
        return o;
    }

    uint slot = recordIndex;
    if (_Data0_Count > 0) {
        _DataType_0 occ = _Data0[recordIndex];
        if (occ.occupied < 0.5) {
            o.Position = float4(0.0, 0.0, -999.0, 1.0);
            o.CellUV = float2(0.0, 0.0);
            o.Valid = 0.0;
            o.Tint = float3(0.0, 0.0, 0.0);
            o.LocalUV = float2(0.0, 0.0);
            o.Slot = 0.0;
            return o;
        }
        slot = min((uint)round(occ.slot_index), max(1, (uint)slot_count) - 1);
    }

    float depth = slotDepth(slot) * depth_scale;

    float scatterX = (slotHash(slot, 3.1) * 2.0 - 1.0) * spread_x;
    float scatterY = (slotHash(slot, 17.7) * 2.0 - 1.0) * spread_y;
    float bobPhase = phase * TWO_PI + slotHash(slot, 41.3) * TWO_PI;
    float bobY = sin(bobPhase) * bob_amount;
    float swayX = cos(bobPhase * 0.5) * bob_amount * 0.5;

    float parallaxX = orbit * (depth - 0.35) * 0.65;
    float scale = card_scale / (1.0 + depth * 0.55);
    float outAspect = 1280.0 / 720.0;
    float2 aspect = float2((tile_width / max(1.0, tile_height)) / outAspect, 1.0);
    float2 local = QUAD_OFFSETS[corner] * aspect * scale;
    float2 ndc = float2(scatterX + swayX + parallaxX, scatterY + bobY - depth * 0.12) + local;

    o.Position = float4(ndc, depth * 0.5, 1.0);
    o.CellUV = cellUV(slot, 0, QUAD_UVS[corner]);
    o.Valid = 1.0;
    o.Tint = lerp(float3(1.0, 1.0, 1.0), float3(0.82, 0.9, 1.0), saturate(depth) * 0.5);
    o.LocalUV = QUAD_UVS[corner];
    o.Slot = (float)slot;
    return o;
}

float4 PSMain(VS_OUTPUT input) : SV_TARGET
{
    if (input.Valid < 0.5) {
        discard;
    }
    uint slot = (uint)round(input.Slot);
    float4 color = _Tex0.SampleLevel(LinearSampler, input.CellUV, 0);
    float mask = segmentationMask(slot, input.LocalUV);
    if (segmentation_enabled != 0 && mask <= 0.05) {
        discard;
    }

    float3 sceneColor = color.rgb * input.Tint;
    return float4(sceneColor, mask);
}
