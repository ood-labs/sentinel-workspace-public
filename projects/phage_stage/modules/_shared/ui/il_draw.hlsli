// il_draw.hlsli - Interaction Lab kit: the GPU DRAW LIST (layout side).
//
// WHY. A per-pixel UI shader that calls a text or widget function at sixty call sites compiles
// sixty inlined copies of it - the first Kit took 104 s to compile. Instead, a station's LAYOUT
// pass records what to draw - rects, segments, arcs, diamonds, text - into a structured buffer,
// exactly like an immediate-mode UI (ImGui) records a command list. One shared, generic
// rasterizer (il_raster.hlsli) then draws the list with ONE copy of each painter. Station code
// reads like ordinary UI code; compile time no longer scales with the amount of UI; and the rects
// used for drawing are the same values the reducer hit-tests.
//
// TEXT IS DEFERRED AND PARALLEL. A dlLabel / dlNum / dlPanelLabel call records a small request
// (label id, value + format, or host control index) and reserves its glyph range; after thread 0
// has recorded everything, ALL threads of the group expand the requests into glyph runs with
// absolute, kerned pen positions. One inlined copy of the glyph code per pass (37 s -> seconds of
// compile), and the glyph work is spread over 64 threads (one GPU thread writing ~1000 glyphs
// cost 0.3 ms by itself). Widths are known at the call from the generated tables, so layout flow
// (x -= dlLabel(...)) still works. The rasterizer needs no label tables: it is byte-identical in
// every module.
//
// Usage (layout pass: dispatch [1,1,1], thread_group_x 64, output "buffer:dl"):
//
//     #include "_labels.generated.hlsli"
//     #include "../_shared/ui/il_ui.hlsli"          // (includes this file)
//     [numthreads(IL_LAYOUT_THREADS, 1, 1)]
//     void main(uint gi : SV_GroupIndex)
//     {
//         if (gi == 0u) { dlBegin(_Resolution.xy); ... dlRect / dlLabel ...; dlFinish(); }
//         dlEnd(gi);                                // every thread, outside any branch
//     }
//
// `DL` (u0) is declared here - do not redeclare it. Buffer: element_size 16, element_count
// IL_DL_SIZE.
#ifndef IL_DRAW_HLSLI
#define IL_DRAW_HLSLI

#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_type_metrics.hlsli"

#define IL_LAYOUT_THREADS 64u
#define IL_DL_MAXCMD   4096u
#define IL_DL_MAXGLYPH 8192u
#define IL_DL_GLYPH0   (1u + 4u * IL_DL_MAXCMD)
#define IL_DL_SIZE     (IL_DL_GLYPH0 + IL_DL_MAXGLYPH)    // 24577 elements = 393,232 bytes

#define DL_RECT     1u   // e1 rect          e3 (kind, radius, border width, border rgb24)
#define DL_SEG      2u   // e1 (a.xy, b.xy)  e3 (kind, width, dash, gap)
#define DL_CIRCLE   3u   // e1 (c.xy, r, ring width or 0 = fill)
#define DL_DIAMOND  4u   // e1 (c.xy, r, ring width or 0 = fill)
#define DL_TRI      5u   // e1 (apex.xy, half width, height) e3 (kind, direction 0 down 1 up 2 left 3 right)
#define DL_ARC      6u   // e1 (c.xy, r, width) e3 (kind, a0, a1) angles clockwise from 12 o'clock
#define DL_TEXT     7u   // e1 (baseline, size, face, 0) e3 (kind, first glyph, glyph count)
#define DL_IMAGE    8u   // e1 rect, e2 uv rect, e3 (kind, tint rgb24, alpha)
#define DL_HGRAD    9u   // e1 rect, e2 left rgba, e3 (kind, right rgb24, radius)
#define DL_ELLIPSE 10u   // e1 (c.xy, rx, ry) e3 (kind, ring width or 0 = fill, dash, gap)
#define DL_REQ_LABEL 20u // e1 (x0, midY, size, id)            e3 (kind, g0, n)            -> DL_TEXT
#define DL_REQ_NUM   21u // e1 (x0, midY, size, value)         e3 (kind, g0, n, format)    -> DL_TEXT
#define DL_REQ_PANEL 22u // e1 (anchor x, midY, size, control) e3 (kind, g0, n, face|align) -> DL_TEXT

#define IL_SANS 0u
#define IL_BOLD 1u
#define IL_MONO 2u
#define IL_LEFT   0u
#define IL_CENTER 1u
#define IL_RIGHT  2u

RWStructuredBuffer<float4> DL : register(u0);

#define IL_DL_NONE     0xFFFFFFFFu
#define IL_DL_MAXBATCH 4u

static uint   g_dlCmd = 0u;
static uint   g_dlGlyph = 0u;
static float4 g_dlClip = float4(-1e9, -1e9, 1e9, 1e9);
static float2 g_dlRes = float2(1.0, 1.0);
static uint   g_dlDropped = 0u;
static uint   g_dlBatches = 0u;
static uint   g_dlAt = IL_DL_NONE;      // batch fill: the absolute slot the next shape writes
static uint   g_dlAtEnd = 0u;           // ... and one past the last slot this record owns

groupshared uint gsDlCmd;
groupshared uint gsDlGlyph;
groupshared uint gsDlDropped;
groupshared float gsDlW;
groupshared uint4 gsDlBatch[IL_DL_MAXBATCH];       // (first slot, count, user, 0)
groupshared float4 gsDlBatchClip[IL_DL_MAXBATCH];

// Integer fields are stored as EXACT FLOAT VALUES (all < 2^24), never as asfloat() bit patterns:
// asfloat(small uint) is a denormal, and FXC constant-folds it into a float literal that is
// flushed to zero (the first Kit drew nothing because every command kind read 0). Colours pack
// to 24-bit RGB for the same reason - 32-bit RGBA with alpha 255 is a NaN bit pattern.
float ilPack(float3 c)
{
    uint3 q = (uint3)round(saturate(c) * 255.0);
    return (float)(q.x | (q.y << 8) | (q.z << 16));
}

void dlBegin(float2 res)
{
    g_dlCmd = 0u; g_dlGlyph = 0u; g_dlDropped = 0u; g_dlBatches = 0u; g_dlAt = IL_DL_NONE;
    gsDlGlyph = 0u;                         // dlTextReq adds 0 to it while recording serially
    g_dlRes = res;
    g_dlClip = float4(0.0, 0.0, res);
}

// Commands outside the clip rect are dropped and the rest are clipped in the rasterizer; set a
// clip for a scrolled list or a pane body so nothing spills over its frame.
void   dlClip(float4 r) { g_dlClip = float4(max(r.xy, 0.0), min(r.zw, g_dlRes)); }
void   dlClipReset()    { g_dlClip = float4(0.0, 0.0, g_dlRes); }
float4 dlGetClip()      { return g_dlClip; }
void   dlSetClip(float4 c) { g_dlClip = c; }

// Branchless on purpose: a culled or overflowing command is written to the spare slot one past
// the live range (overwritten by the next command, never read). With ~100 inlined call sites per
// layout pass, removing the branch around the four writes keeps FXC's optimizer from crawling.
// Inside a batch fill (dlAt) the slot is fixed and already reserved, so a culled command is
// written there as an empty one instead.
bool dlPut(float4 bbox, float4 e1, float4 e2, float4 e3)
{
    float4 b = float4(max(bbox.xy, g_dlClip.xy), min(bbox.zw, g_dlClip.zw));
    bool visible = (b.z > b.x) && (b.w > b.y);
    bool at = g_dlAt != IL_DL_NONE;
    bool room = at ? (g_dlAt < g_dlAtEnd) : (g_dlCmd < IL_DL_MAXCMD - 1u);
    uint keep = (visible && room) ? 1u : 0u;
    uint slot = at ? min(g_dlAt, g_dlAtEnd - 1u) : min(g_dlCmd, IL_DL_MAXCMD - 1u);
    uint base = 1u + 4u * slot;
    DL[base + 0u] = visible ? b : float4(0.0, 0.0, 0.0, 0.0);
    DL[base + 1u] = e1;
    DL[base + 2u] = e2;
    DL[base + 3u] = visible ? e3 : float4(0.0, 0.0, 0.0, 0.0);
    g_dlCmd += at ? 0u : keep;
    g_dlAt += (at && keep != 0u) ? 1u : 0u;
    g_dlDropped += (visible && !room) ? 1u : 0u;
    return keep != 0u;
}

// ---------------------------------------------------------------- parallel batches
// Many records drawn as many primitives (ink points, keys, steps, notes): recording them on
// thread 0 serialises every record's memory reads on one GPU thread. Instead thread 0 RESERVES a
// contiguous run of slots at the right point in painter's order, and after dlSync every layout
// thread fills the run with the ordinary shape calls, routed by dlAt. Index order is painter's
// order, so the result is deterministic.
//
//     void layout() { ...; dlClip(pane); gBatch = dlBatch(records, firstRecord); ...; dlFinish(); }
//     main: if (gi == 0u) layout();
//           dlSync();
//           ILBatch b = dlGetBatch(0u);
//           [loop] for (uint i = gi; i < b.count; i += IL_LAYOUT_THREADS) { dlAt(b, i); drawRecord(b.user + i); }
//           dlEnd(gi);
//
// One primitive per slot (reserve k * records and use dlAt(b, i * k + j) for k each). dlAt
// clears its slot first, so a record that draws nothing leaves an empty command, never last
// cook's. Text works inside a batch too (its glyph range is reserved atomically), so long lists
// and tables - log rows, track names, ruler numbers - lay out in parallel.
struct ILBatch { uint first; uint count; uint user; float4 clip; };

// Thread 0 while recording. The batch inherits the current clip. Returns its id.
uint dlBatch(uint count, uint user)
{
    uint room = (IL_DL_MAXCMD - 1u) - min(g_dlCmd, IL_DL_MAXCMD - 1u);
    uint id = min(g_dlBatches, IL_DL_MAXBATCH - 1u);
    uint n = (g_dlBatches < IL_DL_MAXBATCH) ? min(count, room) : 0u;
    gsDlBatch[id] = uint4(g_dlCmd, n, user, 0u);
    gsDlBatchClip[id] = g_dlClip;
    g_dlCmd += n;
    g_dlDropped += count - n;
    g_dlBatches = min(g_dlBatches + 1u, IL_DL_MAXBATCH);
    return id;
}

// Every layout thread, after thread 0 has recorded (dlFinish) and before dlEnd.
void dlSync() { GroupMemoryBarrierWithGroupSync(); }

ILBatch dlGetBatch(uint id)
{
    ILBatch b;
    uint4 v = gsDlBatch[min(id, IL_DL_MAXBATCH - 1u)];
    b.first = v.x; b.count = v.y; b.user = v.z;
    b.clip = gsDlBatchClip[min(id, IL_DL_MAXBATCH - 1u)];
    return b;
}

// Record i of batch b owns slots [i*k, i*k + k): clear them and route the following shape and
// text calls into them in order (each visible primitive takes the next slot; a primitive past
// the k-th overwrites the last). Reserve dlBatch(records * k, ...) on thread 0.
void dlAtSpan(ILBatch b, uint i, uint k)
{
    uint s0 = b.first + min(i * k, b.count);
    uint s1 = b.first + min(i * k + k, b.count);
    [loop] for (uint sl = s0; sl < s1; sl++)
    {
        DL[1u + 4u * sl] = float4(0.0, 0.0, 0.0, 0.0);
        DL[1u + 4u * sl + 3u] = float4(0.0, 0.0, 0.0, 0.0);
    }
    bool empty = s1 <= s0;                       // past a clamped batch: write to the spare slot
    g_dlAt = empty ? IL_DL_MAXCMD - 1u : s0;
    g_dlAtEnd = empty ? IL_DL_MAXCMD : s1;
    g_dlClip = b.clip;
}
// One primitive per record.
void dlAt(ILBatch b, uint i) { dlAtSpan(b, i, 1u); }

// ---------------------------------------------------------------- shapes
void dlRect(float4 r, float3 fill, float alpha, float radius)
{
    dlPut(ilInset(r, -1.0), r, float4(fill, alpha), float4((float)DL_RECT, radius, 0.0, 0.0));
}
void dlRectEdged(float4 r, float3 fill, float alpha, float radius, float3 edge, float edgeW)
{
    dlPut(ilInset(r, -1.0), r, float4(fill, alpha), float4((float)DL_RECT, radius, edgeW, ilPack(edge)));
}
// Border only (fill alpha 0).
void dlBorderRect(float4 r, float radius, float3 edge, float edgeW)
{
    dlPut(ilInset(r, -1.0), r, float4(0.0, 0.0, 0.0, 0.0), float4((float)DL_RECT, radius, edgeW, ilPack(edge)));
}
void dlLine(float2 a, float2 b, float w, float3 c, float alpha)
{
    float m = 0.5 * w + 1.5;
    dlPut(float4(min(a, b) - m, max(a, b) + m), float4(a, b), float4(c, alpha), float4((float)DL_SEG, w, 0.0, 0.0));
}
void dlDashed(float2 a, float2 b, float w, float3 c, float alpha, float dash, float gap)
{
    float m = 0.5 * w + 1.5;
    dlPut(float4(min(a, b) - m, max(a, b) + m), float4(a, b), float4(c, alpha), float4((float)DL_SEG, w, dash, gap));
}
// Axis-aligned hairlines (the most common chrome).
void dlHLine(float y, float x0, float x1, float3 c) { dlRect(float4(x0, y - 0.5, x1, y + 0.5), c, 1.0, 0.0); }
void dlVLine(float x, float y0, float y1, float3 c) { dlRect(float4(x - 0.5, y0, x + 0.5, y1), c, 1.0, 0.0); }

void dlCircle(float2 c, float r, float3 col, float alpha)
{
    dlPut(float4(c - r - 1.5, c + r + 1.5), float4(c, r, 0.0), float4(col, alpha), float4((float)DL_CIRCLE, 0.0, 0.0, 0.0));
}
void dlRing(float2 c, float r, float w, float3 col, float alpha)
{
    float m = r + 0.5 * w + 1.5;
    dlPut(float4(c - m, c + m), float4(c, r, w), float4(col, alpha), float4((float)DL_CIRCLE, 0.0, 0.0, 0.0));
}
// Axis-aligned ellipse with radii r: filled (ring 0) or a ring of width `ring`, optionally dashed
// along its circumference (dash/gap in px). A circle in normalized image coordinates - the host's
// hit-test shape for param gestures - is this ellipse on any non-square frame.
void dlEllipse(float2 c, float2 r, float ring, float3 col, float alpha, float dash, float gap)
{
    float2 m = r + 0.5 * ring + 1.5;
    dlPut(float4(c - m, c + m), float4(c, r), float4(col, alpha), float4((float)DL_ELLIPSE, ring, dash, gap));
}
void dlDiamond(float2 c, float r, float ring, float3 col, float alpha)
{
    float m = r + ring + 1.5;
    dlPut(float4(c - m, c + m), float4(c, r, ring), float4(col, alpha), float4((float)DL_DIAMOND, 0.0, 0.0, 0.0));
}
// Triangle with apex at a, pointing dir (0 down, 1 up, 2 left, 3 right), half width hw, height h.
void dlTri(float2 a, float hw, float h, uint dir, float3 col, float alpha)
{
    float m = max(hw, h) + 1.5;
    dlPut(float4(a - m, a + m), float4(a, hw, h), float4(col, alpha), float4((float)DL_TRI, (float)dir, 0.0, 0.0));
}
// Arc of radius r and width w from a0 to a1 (radians, clockwise from 12 o'clock, a0 < a1).
void dlArc(float2 c, float r, float w, float a0, float a1, float3 col, float alpha)
{
    float m = r + 0.5 * w + 1.5;
    dlPut(float4(c - m, c + m), float4(c, r, w), float4(col, alpha), float4((float)DL_ARC, a0, a1, 0.0));
}
void dlImage(float4 r, float4 uv, float3 tint, float alpha)
{
    dlPut(r, r, uv, float4((float)DL_IMAGE, ilPack(tint), alpha, 0.0));
}
void dlHGrad(float4 r, float3 left, float3 right, float radius)
{
    dlPut(ilInset(r, -1.0), r, float4(left, 1.0), float4((float)DL_HGRAD, ilPack(right), radius, 0.0));
}

// ---------------------------------------------------------------- text
float ilTypeAdv(uint face, uint g) { return IL_TYPE_ADV[face * IL_TYPE_COUNT + min(g, IL_TYPE_COUNT - 1u)]; }
float ilBaseline(float midY, float size, uint face) { return midY + 0.5 * IL_TYPE_CAP[face] * size / IL_TYPE_EM; }
float ilCapH(float size) { return IL_TYPE_CAP[0] * size / IL_TYPE_EM; }
float ilAlignX(float x, float w, uint align) { return (align == IL_LEFT) ? x : ((align == IL_CENTER) ? x - 0.5 * w : x - w); }

// Line box of a run starting at x0 with width w (for clipping and binning).
float4 ilTextBox(float x0, float w, float midY, float size, uint face)
{
    float k = size / IL_TYPE_EM;
    float base = ilBaseline(midY, size, face);
    return float4(x0 - IL_TYPE_ORIGIN.x * k, base - IL_TYPE_ASC[face] * k, x0 + w + IL_TYPE_ORIGIN.x * k, base + IL_TYPE_DESC[face] * k);
}

// Record a text request and reserve n glyphs for it (only when the request survives clipping and
// the glyph store has room).
// Branchless like dlPut: an empty or over-capacity request gets an empty box, which dlPut culls.
// Serially (thread 0) the glyph range comes from the running count; inside a batch fill it is
// reserved with a groupshared atomic, so many threads can lay out text at once (the add is of 0
// on the serial path, where its result is ignored).
void dlTextReq(float4 box, float4 e1, float3 col, uint kind, uint n, float extra)
{
    bool at = g_dlAt != IL_DL_NONE;
    float4 cb = float4(max(box.xy, g_dlClip.xy), min(box.zw, g_dlClip.zw));
    bool vis = (n > 0u) && (cb.z > cb.x) && (cb.w > cb.y);
    uint gAt = 0u;
    InterlockedAdd(gsDlGlyph, (at && vis) ? n : 0u, gAt);
    uint g0 = at ? gAt : g_dlGlyph;
    bool fits = g0 + n <= IL_DL_MAXGLYPH;
    bool ok = (n > 0u) && fits;
    bool kept = dlPut(ok ? box : float4(0.0, 0.0, 0.0, 0.0), e1, float4(col, 1.0), float4((float)kind, (float)g0, (float)n, extra));
    g_dlGlyph += (!at && kept) ? n : 0u;
    g_dlDropped += (n > 0u && !fits) ? 1u : 0u;
}

#ifdef IL_LABEL_COUNT
uint  ilLbStart(uint id) { return IL_LB_INFO[id] & 0x3FFFu; }
uint  ilLbLen(uint id)   { return (IL_LB_INFO[id] >> 14) & 0x3Fu; }
uint  ilLbFace(uint id)  { return (IL_LB_INFO[id] >> 20) & 0x3u; }
uint  ilLbChar(uint i)   { return (IL_LB_CHARS[i >> 2] >> ((i & 3u) * 8u)) & 0xFFu; }
float ilLbOff(uint i)    { return (float)((IL_LB_OFFS[i >> 1] >> ((i & 1u) * 16u)) & 0xFFFFu) / 16.0; }

float ilLabelW(uint id, float size) { return ilLbOff(IL_LB_OFF0[id] + ilLbLen(id)) * size / IL_TYPE_EM; }
bool  ilLabelFits(uint id, float size, float room) { return ilLabelW(id, size) <= room; }

// Label `id` aligned about x, capitals centred on y. Returns its width.
float dlLabel(uint id, float x, float y, float size, float3 col, uint align)
{
    float w = ilLabelW(id, size);
    float x0 = ilAlignX(x, w, align);
    dlTextReq(ilTextBox(x0, w, y, size, ilLbFace(id)), float4(x0, y, size, (float)id), col, DL_REQ_LABEL, ilLbLen(id), 0.0);
    return w;
}
// Draw only when it fits; returns whether it was drawn. A caption that cannot fit is dropped,
// never squeezed into its neighbour.
bool dlLabelFit(uint id, float x, float y, float size, float3 col, uint align, float room)
{
    if (!ilLabelFits(id, size, room)) return false;
    dlLabel(id, x, y, size, col, align);
    return true;
}
#endif

// ---------------------------------------------------------------- numbers (mono glyphs)
// A number is described, not stored: the cell layout is computed, and each cell's character is a
// pure function of the value (no local arrays, so nothing forces an unroll).
struct ILNum { uint ip; uint fp; uint nd; uint dec; uint sign; uint n; };

// Rounded once in float, then everything in integers (see ilP10).
ILNum ilFormat(float v, int decimals, int minInt, bool plus)
{
    ILNum r;
    r.dec = (uint)clamp(decimals, 0, 6);
    uint scale = ilP10(r.dec);
    uint q = (uint)min(floor(abs(v) * (float)scale + 0.5), 4294967040.0);
    r.ip = q / scale;
    r.fp = q % scale;
    uint digits = 1u + (r.ip >= 10u ? 1u : 0u) + (r.ip >= 100u ? 1u : 0u) + (r.ip >= 1000u ? 1u : 0u)
                + (r.ip >= 10000u ? 1u : 0u) + (r.ip >= 100000u ? 1u : 0u) + (r.ip >= 1000000u ? 1u : 0u)
                + (r.ip >= 10000000u ? 1u : 0u) + (r.ip >= 100000000u ? 1u : 0u) + (r.ip >= 1000000000u ? 1u : 0u);
    r.nd = max(digits, (uint)max(minInt, 1));
    r.sign = (v < 0.0 && q > 0u) ? 1u : (plus ? 2u : 0u);
    r.n = min((r.sign != 0u ? 1u : 0u) + r.nd + (r.dec > 0u ? 1u + r.dec : 0u), 16u);
    return r;
}

uint ilNumChar(ILNum s, uint i)
{
    bool sg = s.sign != 0u;
    uint j = (sg && i > 0u) ? i - 1u : i;                 // the cell, counted after any sign
    uint k = (j > s.nd) ? j - s.nd - 1u : 0u;             // the fraction digit
    uint c = (j < s.nd) ? 48u + (s.ip / ilP10(s.nd - 1u - min(j, s.nd - 1u))) % 10u
           : ((j == s.nd) ? 46u : 48u + (s.fp / ilP10(s.dec - 1u - min(k, s.dec - 1u))) % 10u);
    if (sg && i == 0u) c = (s.sign == 1u) ? 45u : 43u;
    return c;
}

float ilNumW(uint cells, float size) { return (float)cells * IL_MONO_ADV * size / IL_TYPE_EM; }

float dlNumEx(float v, int decimals, int minInt, bool plus, float x, float y, float size, float3 col, uint align)
{
    ILNum f = ilFormat(v, decimals, minInt, plus);
    float w = ilNumW(f.n, size);
    float x0 = ilAlignX(x, w, align);
    uint fmt = (uint)clamp(decimals, 0, 6) | ((uint)clamp(minInt, 1, 9) << 8) | (plus ? (1u << 16) : 0u);
    dlTextReq(ilTextBox(x0, w, y, size, IL_MONO), float4(x0, y, size, v), col, DL_REQ_NUM, f.n, (float)fmt);
    return w;
}
float dlNum(float v, int decimals, float x, float y, float size, float3 col, uint align) { return dlNumEx(v, decimals, 1, false, x, y, size, col, align); }
float dlNumSigned(float v, int decimals, float x, float y, float size, float3 col, uint align) { return dlNumEx(v, decimals, 1, true, x, y, size, col, align); }
float dlInt(int v, int minDigits, float x, float y, float size, float3 col, uint align) { return dlNumEx((float)v, 0, minDigits, false, x, y, size, col, align); }

// ---------------------------------------------------------------- host panel labels
#ifdef SENTINEL_PANEL_TEXT
uint ilPanelByte(uint control, uint i) { return (_PanelLabels[control * PANEL_LABEL_WORDS + (i >> 2)] >> ((i & 3u) * 8u)) & 0xFFu; }

// A host control's label (renamable by a Script through panel.label), set in a lab face. Its width
// is only known at expansion, so the clip box is generous and this returns nothing.
void dlPanelLabel(uint control, float x, float y, float size, uint face, float3 col, uint align)
{
    uint n = min(_ViewportControlState[control].label, 48u);
    float reach = 0.62 * size * (float)n;
    float4 box = ilTextBox(x - reach, 2.0 * reach, y, size, face);
    dlTextReq(box, float4(x, y, size, (float)control), col, DL_REQ_PANEL, n, (float)(face | (align << 8)));
}
#endif

// ---------------------------------------------------------------- finish
// Thread 0, after recording: publish the counts to the group.
void dlFinish()
{
    gsDlCmd = g_dlCmd;
    gsDlGlyph = g_dlGlyph;
    gsDlDropped = g_dlDropped;
    gsDlW = g_dlRes.x;
}

void dlWriteGlyph(uint slot, float penX, uint code)
{
    DL[IL_DL_GLYPH0 + slot] = float4(penX, (float)(min(max(code, 32u), 126u) - IL_TYPE_FIRST), 0.0, 0.0);
}

// Expand one text request into its reserved glyph slots and rewrite it as DL_TEXT.
void dlExpandOne(uint c)
{
    uint base = 1u + 4u * c;
    float4 e3 = DL[base + 3u];
    uint kind = (uint)e3.x;
    if (kind < DL_REQ_LABEL) return;
    float4 e1 = DL[base + 1u];
    uint g0 = (uint)e3.y;
    uint n = (uint)e3.z;
    float size = e1.z;
    float k = size / IL_TYPE_EM;
    float x0 = e1.x;
    uint face = IL_MONO;
#ifdef IL_LABEL_COUNT
    if (kind == DL_REQ_LABEL)
    {
        uint id = (uint)e1.w;
        face = ilLbFace(id);
        uint o0 = IL_LB_OFF0[id];
        uint c0 = ilLbStart(id);
        [loop] for (uint i = 0u; i < n; i++)
            dlWriteGlyph(g0 + i, x0 + ilLbOff(o0 + i) * k, ilLbChar(c0 + i) + IL_TYPE_FIRST);
    }
#endif
    if (kind == DL_REQ_NUM)
    {
        uint fmt = (uint)e3.w;
        ILNum f = ilFormat(e1.w, (int)(fmt & 0xFFu), (int)((fmt >> 8) & 0xFFu), ((fmt >> 16) & 1u) != 0u);
        float adv = IL_MONO_ADV * k;
        [loop] for (uint i2 = 0u; i2 < n; i2++) dlWriteGlyph(g0 + i2, x0 + i2 * adv, ilNumChar(f, i2));
    }
#ifdef SENTINEL_PANEL_TEXT
    if (kind == DL_REQ_PANEL)
    {
        uint control = (uint)e1.w;
        face = (uint)e3.w & 0xFFu;
        uint align = ((uint)e3.w >> 8) & 0xFFu;
        float w = 0.0;
        [loop] for (uint i3 = 0u; i3 < n; i3++) w += ilTypeAdv(face, ilPanelByte(control, i3) - IL_TYPE_FIRST) * k;
        float pen = ilAlignX(e1.x, w, align);
        [loop] for (uint j3 = 0u; j3 < n; j3++)
        {
            uint ch3 = ilPanelByte(control, j3);
            dlWriteGlyph(g0 + j3, pen, ch3);
            pen += ilTypeAdv(face, ch3 - IL_TYPE_FIRST) * k;
        }
    }
#endif
    DL[base + 1u] = float4(ilBaseline(e1.y, size, face), size, (float)face, 0.0);
    DL[base + 3u] = float4((float)DL_TEXT, (float)g0, (float)n, 0.0);
}

// Every thread of the layout group, outside any branch: expand the text requests in parallel,
// then thread 0 writes the header (command count, glyph count, items dropped for capacity, width).
// A non-zero drop count means the layout outgrew IL_DL_MAXCMD / IL_DL_MAXGLYPH.
void dlEnd(uint gi)
{
    AllMemoryBarrierWithGroupSync();
    uint count = gsDlCmd;
    [loop] for (uint c = gi; c < count; c += IL_LAYOUT_THREADS) dlExpandOne(c);
    AllMemoryBarrierWithGroupSync();
    if (gi == 0u) DL[0] = float4((float)gsDlCmd, (float)min(gsDlGlyph, IL_DL_MAXGLYPH), (float)gsDlDropped, gsDlW);
}

#endif
