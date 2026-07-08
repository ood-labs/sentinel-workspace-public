// collage_render stamps — one textured quad per Face_Stitch PNode anchor. Each quad samples an
// atlas cell (kind -> slot, column 0 = color, column 1 = matte) and is placed at the anchor's
// NDC pos, rotated to its dir, scaled by its feature weight. Matte-cut so only the element shows.
// _Tex0 = Parts_Atlas (color|matte|depth block grid); _Data0 = PNode anchors.

static const uint MAX_NODES = 16;

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight;
    float group; float kind; float seed; float active;
};

struct VS_OUT {
    float4 Position : SV_POSITION;
    float2 CellUV   : TEXCOORD0;
    float2 LocalUV  : TEXCOORD1;
    float  Slot     : TEXCOORD2;
    float  Valid    : TEXCOORD3;
};

static const float2 QUAD_OFFSETS[6] = {
    float2(-1,-1), float2(1,-1), float2(1,1),
    float2(-1,-1), float2(1,1), float2(-1,1)
};
static const float2 QUAD_UVS[6] = {
    float2(0,1), float2(1,1), float2(1,0),
    float2(0,1), float2(1,0), float2(0,0)
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

float2 cellUV(uint slot, uint column, float2 localUv)
{
    uint slots = max(1u, (uint)slot_count);
    uint columns = max(1u, (uint)column_count);
    uint blocks = blockColumns(slots);
    uint blockX = slot % blocks;
    uint blockY = slot / blocks;
    float2 origin = float2((blockX * columns + column) * tile_width, blockY * tile_height);
    float2 pixel = origin + localUv * float2(tile_width, tile_height);
    float2 atlasSize;
    _Tex0.GetDimensions(atlasSize.x, atlasSize.y);
    return pixel / max(float2(1.0, 1.0), atlasSize);
}

VS_OUT VSMain(uint vid : SV_VertexID)
{
    VS_OUT o;
    uint rec = vid / 6u;
    uint corner = vid % 6u;

    PNode n = _Data0[min(rec, MAX_NODES - 1u)];
    if (rec >= MAX_NODES || rec >= (uint)_Data0_Count || n.active < 0.5)
    {
        o.Position = float4(0, 0, -999, 1);
        o.CellUV = 0; o.LocalUV = 0; o.Slot = 0; o.Valid = 0;
        return o;
    }

    uint slot = (uint)round(n.kind);
    float outAspect = _Resolution.x / max(1.0, _Resolution.y);
    float scale = max(0.02, n.weight) * stamp_scale;

    // rotate a unit quad to the anchor direction, then aspect-correct
    float ang = atan2(n.dir.y, n.dir.x);
    float ca = cos(ang), sa = sin(ang);
    float2 q = QUAD_OFFSETS[corner];
    float2 qr = float2(q.x * ca - q.y * sa, q.x * sa + q.y * ca);
    float2 local = qr * float2((tile_width / max(1.0, tile_height)) / outAspect, 1.0) * scale;

    float2 ndc = n.pos + local;
    o.Position = float4(ndc, 0.0, 1.0);
    o.CellUV = cellUV(slot, 0u, QUAD_UVS[corner]);
    o.LocalUV = QUAD_UVS[corner];
    o.Slot = (float)slot;
    o.Valid = 1.0;
    return o;
}

float4 PSMain(VS_OUT i) : SV_TARGET
{
    if (i.Valid < 0.5) discard;
    uint slot = (uint)round(i.Slot);
    float4 color = _Tex0.SampleLevel(LinearSampler, i.CellUV, 0);
    float2 mUV = cellUV(slot, (uint)segmentation_column, i.LocalUV);
    float mask = saturate(dot(_Tex0.SampleLevel(LinearSampler, mUV, 0).rgb, float3(0.299, 0.587, 0.114)));
    mask = smoothstep(mask_cutoff, mask_cutoff + 0.12, mask);
    if (mask <= 0.02) discard;
    return float4(color.rgb, mask * stamp_opacity);
}
