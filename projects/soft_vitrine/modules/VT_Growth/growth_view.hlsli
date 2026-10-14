// VT_Growth / growth_view.hlsli - the Growth View's geometry, derived from the live extent (the
// canvas follows its panel). preview.hlsl draws into these rects and layout.hlsl captions them and
// hovers over them, so a circle or a bar is inspected exactly where it is drawn.
//
//   head    title and the live counts
//   stage   the square stage (masses front-projected at z = 0, strokes in stage space)
//   tally   one bar per group header: masses left, strokes right
//   foot    the verbs
#ifndef VT_GROWTH_VIEW_HLSLI
#define VT_GROWTH_VIEW_HLSLI

struct GVLayout
{
    float  s;        // ui scale (type never below ~9 px)
    float4 head;
    float4 stage;    // square
    float4 tally;    // the tally plate
    float4 bars;     // the bar area inside it
    float4 foot;
};

float gvScale(float2 R) { return clamp(min(R.x, R.y) / 800.0, 0.86, 2.0); }

// The stage takes the largest square the panel allows, up to GV_STAGE_MAX pixels a side: every stage
// pixel walks every group and node (preview.hlsl), so the cap keeps that work within the 900 x 900
// the node rendered before it followed its panel. The tally sits right under the stage and takes
// the height left over, up to tallyMax: at its minimum a node is under a pixel of bar, so a
// shortfall of two or three nodes would be a sliver of red. The two sit centred between the head
// and the foot, so any height still left over is shared above and below them.
#define GV_STAGE_MAX 900.0
GVLayout gvLayout(float2 R)
{
    GVLayout L;
    float s = gvScale(R);
    L.s = s;
    float pad = 12.0 * s;
    float headH = 40.0 * s, footH = 34.0 * s, tallyMin = 104.0 * s, tallyMax = 240.0 * s, gap = 10.0 * s;
    L.head = float4(0.0, 0.0, R.x, headH);
    L.foot = float4(0.0, R.y - footH, R.x, R.y);
    float avail = R.y - headH - footH - gap;
    float side = max(min(min(R.x - 2.0 * pad, avail - tallyMin), GV_STAGE_MAX), 64.0 * s);
    float tallyH = clamp(avail - side, tallyMin, tallyMax);
    float cx = 0.5 * R.x, top = headH + 0.5 * max(avail - side - tallyH, 0.0);
    L.stage = float4(cx - 0.5 * side, top, cx + 0.5 * side, top + side);
    L.tally = float4(pad, L.stage.w + gap, R.x - pad, L.stage.w + gap + tallyH);
    L.bars = float4(L.tally.x + 12.0 * s, L.tally.y + 30.0 * s, L.tally.z - 12.0 * s, L.tally.w - 24.0 * s);
    return L;
}

// The 32 group headers as bars, a gap between the two families.
float gvBarGap(GVLayout L) { return 20.0 * L.s; }
float gvBarPitch(GVLayout L) { return (L.bars.z - L.bars.x - gvBarGap(L)) / (float)LIMB_HEADERS; }
float4 gvBarSlot(GVLayout L, uint g)
{
    float w = gvBarPitch(L);
    float x = L.bars.x + (float)g * w + (g >= LIMB_STROKE_H_0 ? gvBarGap(L) : 0.0);
    return float4(x, L.bars.y, x + w, L.bars.w);
}
float4 gvBar(GVLayout L, uint g) { float4 r = gvBarSlot(L, g); float w = r.z - r.x; return float4(r.x + 0.18 * w, r.y, r.z - 0.18 * w, r.w); }
// the header under p in the bar area (the whole slot is the target), or 0xFFFF
uint gvBarAt(GVLayout L, float2 p)
{
    if (p.y < L.bars.y || p.y > L.bars.w) return 0xFFFFu;
    float w = gvBarPitch(L), x = p.x - L.bars.x, split = (float)LIMB_STROKE_H_0 * w;
    if (x < 0.0) return 0xFFFFu;
    if (x < split) return min((uint)(x / w), LIMB_STROKE_H_0 - 1u);
    x -= split + gvBarGap(L);
    if (x < 0.0) return 0xFFFFu;
    uint g = LIMB_STROKE_H_0 + (uint)(x / w);
    return g < LIMB_HEADERS ? g : 0xFFFFu;
}

// stage uv (0..1) -> canvas px, and the canonical camera's front projection at z = 0
float  gvSide(GVLayout L) { return L.stage.z - L.stage.x; }
float2 gvPx(GVLayout L, float2 uv) { return L.stage.xy + uv * gvSide(L); }
float2 gvWorldToUV(float3 w) { return float2(w.x * 0.5 + 0.5, 0.5 - w.y * 0.5); }

// a group header's bounding circle in canvas px (xy centre, z radius)
float3 gvBound(GVLayout L, uint g, LimbRec h)
{
    bool mass = g < LIMB_STROKE_H_0;
    float2 c = mass ? gvWorldToUV(h.pos) : h.pos.xy;
    float r = mass ? h.radius * 0.5 : h.radius;          // world radius -> uv (half-extent = 1.0)
    return float3(gvPx(L, c), r * gvSide(L));
}

#endif
