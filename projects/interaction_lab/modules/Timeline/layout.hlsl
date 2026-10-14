// Timeline / layout - the editor's panes: the stage (the picture, the selected layer's frame and
// handles, its motion path with a dot per frame - the spacing IS the speed - and onion ghosts), the
// inspector, the transport, the layer list, the ruler with the loop, the dope sheet and the graph.
//
// Grey carries the chrome; amber marks the selected keys, the primary key, whatever is held and the
// playhead (an established live reading). The stage is paper, so its overlay is drawn dark.
//
// 64 threads: thread 0 records the chrome and reserves three batches - the graph's curves, the motion
// path, and the dope sheet's keys - which every thread then fills.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "../_shared/ui/il_pane.hlsli"
#include "tl.hlsli"

#define GR_SEGS    160u                     // the active curve
#define GR_CTX     80u                      // each of the layer's other four channels
#define GRAPH_ITEMS (GR_SEGS + 4u * GR_CTX)
#define PATH_FRAMES 121u                    // the motion path: a segment and a frame dot per frame
#define PATH_ITEMS (PATH_FRAMES * 2u)
#define DOPE_ITEMS (TL_CH * TL_KMAX)        // a key slot each: its own row's diamond and its layer's
#define OV_DARK  float3(0.15, 0.15, 0.16)   // overlay ink on the paper stage
#define OV_MID   float3(0.45, 0.45, 0.46)

// Every value the layout draws is evaluated ONCE, at one call site, into these tables: tlValue (with
// its ease solver) inlined at a dozen call sites took FXC two minutes to compile.
#define J_NOW    0u                                   // the twenty channels at the playhead
#define J_ACT    (J_NOW + TL_CH)                      // the active curve, GR_SEGS + 1 samples
#define J_CTX    (J_ACT + GR_SEGS + 1u)               // the four context curves, GR_CTX + 1 each
#define J_PATH   (J_CTX + 4u * (GR_CTX + 1u))         // x, y of the selected layer at every frame
#define J_GHOST  (J_PATH + 2u * PATH_FRAMES)          // the onion ghosts: 4 frames x 5 attributes
#define J_COUNT  (J_GHOST + 4u * TL_ATTRS)
groupshared float gsJ[J_COUNT];
groupshared float2 gsRange[4];

static TlLayout g_L;
static float g_s;
static float2 g_res, g_ptr, g_tw, g_vw;
static uint g_mode, g_target, g_sel, g_attr;
static float g_play, g_frames, g_primCh, g_primF;
static bool g_onion;

void plate(float4 r) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * g_s); }
uint chA() { return g_sel * TL_ATTRS + g_attr; }
float2 stagePx(float2 q) { return tlStageToPx(g_L.stage, q); }
float stageUnit() { return g_L.stage.w - g_L.stage.y; }
float frameNow() { return clamp(round(g_play), 0.0, g_frames); }
bool keySel(uint ch, uint i) { return tlSel(tlKey(ch, i)); }
bool isPrimary(uint ch, float f) { return g_primCh >= 0.0 && (uint)g_primCh == ch && abs(g_primF - f) < 0.5; }

float nowV(uint ch) { return gsJ[J_NOW + ch]; }
float4 nowX(uint l) { uint c = l * TL_ATTRS; return float4(gsJ[J_NOW + c], gsJ[J_NOW + c + 1u], gsJ[J_NOW + c + 2u], gsJ[J_NOW + c + 3u]); }
float nowOp(uint l) { return saturate(gsJ[J_NOW + l * TL_ATTRS + 4u]); }
float2 pathAt(uint fi) { uint i = J_PATH + 2u * min(fi, PATH_FRAMES - 1u); return float2(gsJ[i], gsJ[i + 1u]); }
float ghostFrame(uint k) { int o = (int)k - 2; o += (o >= 0) ? 1 : 0; return round(g_play) + (float)o * (float)max(onion_step, 1); }
float2 sheetSpan() { return float2(max(g_tw.x, 0.0), min(g_tw.y, g_frames)); }

// which channel and frame table entry j holds
void job(uint j, out uint ch, out float f)
{
    float2 sp = sheetSpan();
    ch = 0u;
    f = g_play;
    if (j < J_ACT) { ch = j; }
    else if (j < J_CTX) { ch = chA(); f = lerp(sp.x, sp.y, (float)(j - J_ACT) / GR_SEGS); }
    else if (j < J_PATH)
    {
        uint o = (j - J_CTX) / (GR_CTX + 1u), i = (j - J_CTX) % (GR_CTX + 1u);
        ch = g_sel * TL_ATTRS + o + (o >= g_attr ? 1u : 0u);
        f = lerp(sp.x, sp.y, (float)i / GR_CTX);
    }
    else if (j < J_GHOST) { uint i = j - J_PATH; ch = g_sel * TL_ATTRS + (i & 1u); f = (float)(i / 2u); }
    else { uint i = j - J_GHOST; ch = g_sel * TL_ATTRS + i % TL_ATTRS; f = clamp(ghostFrame(i / TL_ATTRS), 0.0, g_frames); }
}

// the frontmost layer under a pixel at the playhead (from the table)
uint pickNow(float2 p, float slackPx)
{
    float2 q = tlPxToStage(g_L.stage, p);
    uint hit = 0xFFFFu;
    [loop] for (uint l = TL_LAYERS; l > 0u; l--)
        if (nowOp(l - 1u) >= 0.05 && tlSd(l - 1u, nowX(l - 1u), q) * (g_L.stage.w - g_L.stage.y) < slackPx) hit = l - 1u;
    return hit;
}

// ---------------------------------------------------------------- shapes on the stage
// a layer's outline at a pose (stage overlay): circles for the ring and the sun, rotated boxes for
// the block and the bar
void outline(uint layer, float4 x, float w, float3 col, float alpha, bool dashed)
{
    float u = stageUnit();
    float2 c = stagePx(x.xy);
    float sc = max(abs(x.z), 1e-3);
    if (layer == TL_RING || layer == TL_SUN)
    {
        float r = (layer == TL_RING ? TL_RING_R : TL_SUN_R) * sc * u;
        dlEllipse(c, float2(r, r), w, col, alpha, dashed ? 4.0 * g_s : 0.0, 3.0 * g_s);
        return;
    }
    float2 h = (layer == TL_BLOCK ? float2(TL_BLOCK_H, TL_BLOCK_H) : TL_BAR_HALF) * sc;
    float a = radians(x.w);
    float2 ex = float2(cos(a), -sin(a)), ey = float2(sin(a), cos(a));   // the layer's axes, stage units
    float2 p0 = stagePx(x.xy - ex * h.x - ey * h.y), p1 = stagePx(x.xy + ex * h.x - ey * h.y);
    float2 p2 = stagePx(x.xy + ex * h.x + ey * h.y), p3 = stagePx(x.xy - ex * h.x + ey * h.y);
    float dsh = dashed ? 4.0 * g_s : 0.0;
    dlDashed(p0, p1, w, col, alpha, dsh, 3.0 * g_s);
    dlDashed(p1, p2, w, col, alpha, dsh, 3.0 * g_s);
    dlDashed(p2, p3, w, col, alpha, dsh, 3.0 * g_s);
    dlDashed(p3, p0, w, col, alpha, dsh, 3.0 * g_s);
}

// ---------------------------------------------------------------- the header
void header()
{
    float s = g_s;
    float4 hd = g_L.head;
    float hy = ilMid(hd).y;
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    float4 hp = float4(hd.x, hd.y, hd.x + tw + sw + 40.0 * s, hd.w);
    plate(hp);
    dlLabel(LB_TITLE, hp.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hp.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float4 P0 = tlP0();
    float ww = ilLabelW(LB_FRAME, cap) + ilNumW(7u, val) + ilLabelW(LB_SLASH, val) + ilNumW(4u, val) + ilLabelW(LB_SEC, cap)
             + ilNumW(2u, val) + ilLabelW(LB_FPS, cap) + 64.0 * s;
    float4 cp = float4(hd.z - ww, hd.y, hd.z, hd.w);
    plate(cp);
    float x = cp.x + 12.0 * s;
    x += dlLabel(LB_FRAME, x, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    x += dlInt((int)frameNow(), 3, x, hy, val, IL_ACCENT, IL_LEFT);
    x += dlLabel(LB_SLASH, x, hy, val, IL_DIM, IL_LEFT);
    x += dlInt((int)g_frames, 3, x, hy, val, IL_DIM, IL_LEFT) + 14.0 * s;
    x += dlNum(g_play / max(P0.w, 1.0), 2, x, hy, val, IL_INK, IL_LEFT) + 3.0 * s;
    x += dlLabel(LB_SEC, x, hy, cap, IL_DIM, IL_LEFT) + 14.0 * s;
    x += dlInt((int)P0.w, 1, x, hy, val, IL_INK, IL_LEFT) + 4.0 * s;
    dlLabel(LB_FPS, x, hy, cap, IL_DIM, IL_LEFT);
}

// ---------------------------------------------------------------- the stage
void stage()
{
    float s = g_s;
    float4 st = g_L.stage;
    float x = g_L.top.x + 2.0 * s, ty = g_L.top.y + 10.0 * s;
    x += dlLabel(LB_STAGE, x, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    dlLabelFit(LB_STAGE_D, x, ty, IL_T_CAP * s, IL_DIM, IL_LEFT, g_L.stageArea.z - x);
    dlImage(st, st / g_res.xyxy, float3(1.0, 1.0, 1.0), 1.0);
    dlBorderRect(st, 0.0, IL_RULE, 1.0);
    // title safe (90 %)
    float4 ts = ilInset(st, 0.05 * (st.w - st.y));
    ts.xz = ilMid(st).x + (ts.xz - ilMid(st).x) * ((st.z - st.x) * 0.9 / max(ts.z - ts.x, 1.0));
    dlDashed(ts.xy, float2(ts.z, ts.y), 1.0, OV_MID, 0.35, 5.0 * s, 5.0 * s);
    dlDashed(float2(ts.z, ts.y), ts.zw, 1.0, OV_MID, 0.35, 5.0 * s, 5.0 * s);
    dlDashed(ts.zw, float2(ts.x, ts.w), 1.0, OV_MID, 0.35, 5.0 * s, 5.0 * s);
    dlDashed(float2(ts.x, ts.w), ts.xy, 1.0, OV_MID, 0.35, 5.0 * s, 5.0 * s);

    float f = frameNow();
    dlClip(st);
    // onion skin: the selected layer a few frames either side (past solid, future dashed)
    if (g_onion)
    {
        [loop] for (uint k = 0u; k < 4u; k++)
        {
            float fk = ghostFrame(k);
            if (fk < 0.0 || fk > g_frames) continue;
            uint gj = J_GHOST + k * TL_ATTRS;
            float4 gx = float4(gsJ[gj], gsJ[gj + 1u], gsJ[gj + 2u], gsJ[gj + 3u]);
            bool far = k == 0u || k == 3u;
            outline(g_sel, gx, 1.0 * s, OV_MID, far ? 0.45 : 0.7, k >= 2u);
        }
    }
    // hover: the layer under the pointer
    if (g_mode == DM_NONE && ilIn(g_ptr, st))
    {
        uint hl = pickNow(g_ptr, 4.0 * s);
        if (hl != 0xFFFFu && hl != g_sel) outline(hl, nowX(hl), 1.25 * s, OV_MID, 0.9, false);
    }
    dlClipReset();
}

// over the motion path batch: the selected layer's frame, its handles and its path keys
void stageOver()
{
    float s = g_s;
    float4 st = g_L.stage;
    float f = frameNow();
    dlClip(st);
    // the path's key dots: a key on x or y at that frame (amber when selected or primary)
    float pf[16];
    uint np = tlPathKeys(g_sel, pf);
    uint cx = g_sel * TL_ATTRS, cy = cx + 1u;
    [loop] for (uint z = 0u; z < np; z++)
    {
        float2 c = stagePx(pathAt((uint)round(pf[z])));
        uint ix = 0xFFFFu, iy = 0xFFFFu;
        [loop] for (uint i = 0u; i < tlCount(cx); i++) if (abs(tlKey(cx, i).x - pf[z]) < 0.5) ix = i;
        [loop] for (uint j = 0u; j < tlCount(cy); j++) if (abs(tlKey(cy, j).x - pf[z]) < 0.5) iy = j;
        bool on = (ix != 0xFFFFu && keySel(cx, ix)) || (iy != 0xFFFFu && keySel(cy, iy)) || isPrimary(cx, pf[z]) || isPrimary(cy, pf[z]);
        bool held = g_mode == DM_PATHKEY && abs((float)g_target - pf[z]) < 0.5;
        float4 r = float4(c - 4.0 * s, c + 4.0 * s);
        dlRectEdged(r, TL_PAPER, 1.0, 1.0 * s, (on || held) ? IL_ACCENT : OV_DARK, 1.5 * s);
    }
    // the selected layer: its outline and handles
    float4 px = nowX(g_sel);
    bool held = g_mode == DM_MOVE || g_mode == DM_SCALE || g_mode == DM_ROT;
    outline(g_sel, px, 1.5 * s, IL_ACCENT, held ? 1.0 : 0.85, false);
    float2 c = stagePx(px.xy);
    float2 hs = stagePx(tlScaleHandle(px, g_sel)), hr = stagePx(tlRotHandle(px, g_sel));
    float2 top = stagePx(px.xy + float2(sin(radians(px.w)), cos(radians(px.w))) * tlReach(g_sel, px.z));
    dlLine(top, hr, 1.0 * s, IL_ACCENT, 0.8);
    dlCircle(hr, 5.5 * s, TL_PAPER, 1.0);
    dlRing(hr, 5.5 * s, 1.5 * s, g_mode == DM_ROT ? IL_ACCENT : OV_DARK, 1.0);
    dlRectEdged(float4(hs - 5.0 * s, hs + 5.0 * s), TL_PAPER, 1.0, 1.0 * s, g_mode == DM_SCALE ? IL_ACCENT : OV_DARK, 1.5 * s);
    dlCircle(c, 2.5 * s, IL_ACCENT, 1.0);
    dlClipReset();
}

// ---------------------------------------------------------------- the inspector
void inspector()
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s, body = IL_T_BODY * s;
    float4 ip = g_L.insp;
    plate(ip);
    float ty = ip.y + 14.0 * s;
    float x = ip.x + 10.0 * s;
    x += dlLabel(LB_LAYER, x, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    x += dlLabel(LB_L_0 + g_sel, x, ty, body, IL_INK, IL_LEFT) + 8.0 * s;
    dlLabel(LB_K_0 + g_sel, x, ty, cap, IL_DIM, IL_LEFT);
    float f = frameNow();
    [loop] for (uint a = 0u; a < TL_ATTRS; a++)
    {
        uint ch = g_sel * TL_ATTRS + a;
        float4 fr = tlField(g_L, a, s);
        float y = ilMid(fr).y;
        bool live = g_mode == DM_FIELD && g_target == a;
        bool hot = g_mode == DM_NONE && ilIn(g_ptr, fr);
        dlLabel(LB_A_0 + a, ip.x + 12.0 * s, y, body, a == g_attr ? IL_INK : IL_MID, IL_LEFT);
        dlRectEdged(fr, hot ? IL_RAISE : IL_WELL, 1.0, 2.0 * s, live ? IL_ACCENT : IL_EDGE, 1.0);
        float v = nowV(ch);
        dlNumEx(v, a == TL_ROT ? 1 : 3, 1, a < 2u || a == TL_ROT, fr.z - 6.0 * s, y, val, live ? IL_ACCENT : IL_INK, IL_RIGHT);
        if (a == TL_ROT) dlLabel(LB_U_DEG, fr.x - 6.0 * s, y, cap, IL_DIM, IL_RIGHT);
        // the key toggle: filled = a key at this frame, hollow = keys elsewhere, a dot = none
        float2 kt = tlKeyToggle(g_L, a, s);
        uint n = tlCount(ch), here = 0xFFFFu;
        [loop] for (uint i = 0u; i < n; i++) if (abs(tlKey(ch, i).x - f) < 0.5) here = i;
        bool khot = g_mode == DM_NONE && length(g_ptr - kt) < 9.0 * s;
        if (here != 0xFFFFu) dlDiamond(kt, 5.5 * s, 0.0, keySel(ch, here) ? IL_ACCENT : IL_INK, 1.0);
        else if (n > 0u) dlDiamond(kt, 5.0 * s, 1.25 * s, khot ? IL_INK : IL_MID, 1.0);
        else dlCircle(kt, 1.5 * s, khot ? IL_INK : IL_DIM, 1.0);
    }

    // the primary key
    float ky = tlField(g_L, TL_ATTRS - 1u, s).w + 22.0 * s;
    dlHLine(ky - 10.0 * s, ip.x + 10.0 * s, ip.z - 10.0 * s, IL_EDGE);
    float kx = ip.x + 10.0 * s;
    kx += dlLabel(LB_KEY, kx, ky, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    uint pc = 0xFFFFu, pi = 0xFFFFu;
    if (g_primCh >= 0.0)
    {
        pc = (uint)g_primCh;
        [loop] for (uint i = 0u; i < tlCount(pc); i++) if (abs(tlKey(pc, i).x - g_primF) < 0.5) pi = i;
    }
    float4 md = tlModes(g_L, s);
    if (pi == 0xFFFFu)
    {
        dlLabelFit(LB_KEY_NONE, kx, ky, cap, IL_DIM, IL_LEFT, ip.z - kx - 8.0 * s);
        dlSegmented(md, s, LB_M_0, 5u, -1, -1);
        return;
    }
    float4 k = tlKey(pc, pi);
    kx += dlLabel(LB_L_0 + pc / TL_ATTRS, kx, ky, body, IL_INK, IL_LEFT) + 5.0 * s;
    kx += dlLabel(LB_A_0 + pc % TL_ATTRS, kx, ky, body, IL_INK, IL_LEFT) + 10.0 * s;
    kx += dlLabel(LB_AT, kx, ky, cap, IL_DIM, IL_LEFT) + 4.0 * s;
    kx += dlInt((int)k.x, 1, kx, ky, val, IL_ACCENT, IL_LEFT) + 10.0 * s;
    dlNumEx(k.y, (pc % TL_ATTRS == TL_ROT) ? 1 : 3, 1, true, ip.z - 10.0 * s, ky, val, IL_INK, IL_RIGHT);
    uint m = tlMode(k);
    int hotSeg = (g_mode == DM_NONE && ilIn(g_ptr, md)) ? (int)min((uint)((g_ptr.x - md.x) / ((md.z - md.x) / 5.0)), 4u) : -1;
    dlSegmented(md, s, LB_M_0, 5u, (int)m, hotSeg);
    // the parameters this mode has, and the segment's shape
    float2 prm = tlParams(k);
    uint np = (m == TL_EASE || m == TL_BACK) ? 2u : ((m == TL_SPRING) ? 1u : 0u);
    [loop] for (uint b = 0u; b < np; b++)
    {
        float4 pf = tlParamField(g_L, b, s);
        float y = ilMid(pf).y;
        uint lbl = (m == TL_EASE) ? LB_P_EASE0 + b : ((m == TL_SPRING) ? LB_P_SPRING : LB_P_BACK0 + b);
        bool live = g_mode == DM_PARAM && g_target == b;
        bool hot = g_mode == DM_NONE && ilIn(g_ptr, pf);
        dlLabelFit(lbl, ip.x + 12.0 * s, y, cap, IL_MID, IL_LEFT, pf.x - ip.x - 20.0 * s);
        dlRectEdged(pf, hot ? IL_RAISE : IL_WELL, 1.0, 2.0 * s, live ? IL_ACCENT : IL_EDGE, 1.0);
        dlNum((b == 0u ? prm.x : prm.y) * 100.0, 0, pf.z - 6.0 * s, y, val, live ? IL_ACCENT : IL_INK, IL_RIGHT);
        dlLabel(LB_PCT, pf.z + 4.0 * s, y, cap, IL_DIM, IL_LEFT);
    }
    if (np == 0u) dlLabel(LB_P_NONE, ip.x + 12.0 * s, ilMid(tlParamField(g_L, 0u, s)).y, cap, IL_DIM, IL_LEFT);
    // the segment's normalized curve, 0 at this key and 1 at the next
    float4 sp = tlParamField(g_L, 2u, s);
    float4 box = float4(ip.x + 12.0 * s, sp.y + 2.0 * s, ip.z - 12.0 * s, min(sp.y + 64.0 * s, ip.w - 10.0 * s));
    if (pi + 1u >= tlCount(pc)) dlLabelFit(LB_KEY_LAST, box.x, box.y + 10.0 * s, cap, IL_DIM, IL_LEFT, box.z - box.x);
    else if (box.w - box.y > 24.0 * s)
    {
        dlRect(box, IL_FIELD, 1.0, 2.0 * s);
        float y0 = lerp(box.w, box.y, 0.2), y1 = lerp(box.w, box.y, 0.8);
        dlHLine(y0, box.x, box.z, IL_GRID);
        dlHLine(y1, box.x, box.z, IL_GRID);
        if (m == TL_HOLD)
        {
            // it holds, then steps at the next key
            float xe = box.z - 6.0 * s;
            dlLine(float2(box.x, y0), float2(xe, y0), 1.25 * s, IL_INK, 1.0);
            dlLine(float2(xe, y0), float2(xe, y1), 1.25 * s, IL_INK, 1.0);
        }
        else
        {
            float2 prev = float2(box.x, y0);
            [loop] for (uint j = 1u; j <= 32u; j++)
            {
                float u = j / 32.0;
                float2 cur = float2(lerp(box.x, box.z, u), lerp(y0, y1, tlShape01(m, prm, u)));
                dlLine(prev, cur, 1.25 * s, IL_INK, 1.0);
                prev = cur;
            }
        }
    }
}

// ---------------------------------------------------------------- the transport
void transport()
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s, body = IL_T_BODY * s;
    float4 tr = g_L.transport;
    float y = ilMid(tr).y;
    bool playing = tlV0().y > 0.5;
    float4 pc = tlPlayChip(g_L, s);
    bool hot = g_mode == DM_NONE && ilIn(g_ptr, pc);
    dlRectEdged(pc, playing ? IL_RAISE * 1.9 : (hot ? IL_RAISE * 1.45 : IL_RAISE), 1.0, IL_RADIUS * s, playing ? IL_RULE : IL_EDGE, 1.0);
    float2 ic = float2(pc.x + 15.0 * s, y);
    if (playing)
    {
        dlRect(float4(ic.x - 4.0 * s, y - 5.0 * s, ic.x - 1.5 * s, y + 5.0 * s), IL_ACCENT, 1.0, 0.0);
        dlRect(float4(ic.x + 1.5 * s, y - 5.0 * s, ic.x + 4.0 * s, y + 5.0 * s), IL_ACCENT, 1.0, 0.0);
    }
    else dlTri(float2(ic.x + 5.0 * s, y), 5.0 * s, 8.0 * s, 3u, IL_INK, 1.0);
    dlLabel(playing ? LB_PAUSE : LB_PLAY, pc.x + 28.0 * s, y, cap, playing ? IL_INK : IL_MID, IL_LEFT);
    float x = pc.z + 14.0 * s;
    x += dlInt((int)frameNow(), 3, x, y, 15.0 * s, IL_ACCENT, IL_LEFT) + 4.0 * s;
    x += dlLabel(LB_SLASH, x, y, val, IL_DIM, IL_LEFT) + 2.0 * s;
    x += dlInt((int)g_frames, 3, x, y, val, IL_DIM, IL_LEFT) + 14.0 * s;
    float4 P0 = tlP0();
    x += dlLabel(LB_LOOP, x, y, cap, IL_DIM, IL_LEFT) + 4.0 * s;
    x += dlInt((int)P0.x, 1, x, y, val, IL_INK, IL_LEFT) + 3.0 * s;
    x += dlLabel(LB_DASH, x, y, val, IL_DIM, IL_LEFT) + 3.0 * s;
    dlInt((int)P0.y, 1, x, y, val, IL_INK, IL_LEFT);
    float4 sp = tlSpeeds(g_L, s);
    int hs = (g_mode == DM_NONE && ilIn(g_ptr, sp)) ? (int)min((uint)((g_ptr.x - sp.x) / ((sp.z - sp.x) / 4.0)), 3u) : -1;
    dlSegmented(sp, s, LB_S_0, 4u, (int)clamp(tlV0().z, 0.0, 3.0), hs);
    float4 oc = tlOnionChip(g_L, s);
    dlChip(oc, s, LB_ONION, g_onion, g_mode == DM_NONE && ilIn(g_ptr, oc), false);
    dlLabelFit(LB_TR_D, oc.z + 14.0 * s, y, cap, IL_DIM, IL_LEFT, tr.z - oc.z - 18.0 * s);
}

// ---------------------------------------------------------------- the list, ruler and dope rows
void sheet()
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s, body = IL_T_BODY * s;
    float f = frameNow();
    // the ruler: ticks on a nice step, the loop band, its markers
    float4 ru = g_L.ruler;
    dlRect(ru, IL_WELL, 1.0, 2.0 * s);
    float4 P0 = tlP0();
    float xa = tlX(g_L, g_tw, P0.x), xb = tlX(g_L, g_tw, P0.y);
    dlRect(float4(max(xa, ru.x), ru.y + 1.0, min(xb, ru.z), ru.w - 1.0), IL_RAISE, 1.0, 0.0);
    float pxPerF = (ru.z - ru.x) / max(g_tw.y - g_tw.x, 1.0);
    float major = max(ilNiceStep(pxPerF, 46.0 * s), 1.0), minor = max(major / 5.0, 1.0);
    dlClip(float4(g_L.area.x, ru.y, g_L.area.z, g_L.graph.w));
    float f0 = ceil(max(g_tw.x, 0.0) / minor) * minor;
    [loop] for (uint t = 0u; t < 160u; t++)
    {
        float ft = f0 + t * minor;
        if (ft > min(g_tw.y, g_frames) + 0.01) break;
        float xt = tlX(g_L, g_tw, ft);
        bool isMajor = abs(ft / major - round(ft / major)) < 1e-3;
        dlVLine(xt, ru.w - (isMajor ? 8.0 : 4.0) * s, ru.w, isMajor ? IL_RULE : IL_EDGE);
        if (isMajor)
        {
            dlInt((int)ft, 1, xt + 3.0 * s, ru.y + 8.0 * s, cap, IL_DIM, IL_LEFT);
            dlVLine(xt, g_L.dope.y, g_L.graph.w, IL_GRID);
        }
    }
    bool hotIn = g_mode == DM_NONE && length(g_ptr - tlLoopIn(g_L, g_tw)) < 8.0 * s;
    bool hotOut = g_mode == DM_NONE && length(g_ptr - tlLoopOut(g_L, g_tw)) < 8.0 * s;
    dlTri(float2(xa, ru.w - 1.0), 5.0 * s, 7.0 * s, 1u, (g_mode == DM_LOOPIN) ? IL_ACCENT : (hotIn ? IL_INK : IL_MID), 1.0);
    dlTri(float2(xb, ru.w - 1.0), 5.0 * s, 7.0 * s, 1u, (g_mode == DM_LOOPOUT) ? IL_ACCENT : (hotOut ? IL_INK : IL_MID), 1.0);
    dlClipReset();

    // the list column and the row bands
    dlLabel(LB_LAYERS, g_L.list.x + 2.0 * s, ilMid(ru).y, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    [loop] for (uint row = 0u; row < TL_ROWS; row++)
    {
        float4 r = tlRow(g_L, row);
        uint3 w = tlRowWhat(row, g_sel);
        float y = ilMid(r).y;
        float4 band = float4(g_L.area.x, r.y, g_L.area.z, r.w - 1.0);
        float4 cell = float4(g_L.list.x, r.y, g_L.list.z, r.w - 1.0);
        if (w.x == 1u)
        {
            bool on = w.y == g_sel;
            dlRect(cell, on ? IL_RAISE * 1.6 : IL_RAISE, 1.0, 2.0 * s);
            dlRect(band, on ? IL_RAISE : IL_WELL, 1.0, 0.0);
            if (on) dlRect(float4(cell.x, cell.y + 3.0 * s, cell.x + 2.0 * s, cell.w - 3.0 * s), IL_ACCENT, 1.0, 0.0);
            // the layer's ink on a chip of paper, in its own shape
            float2 ch = float2(cell.x + 16.0 * s, y);
            dlRect(float4(ch - 7.0 * s, ch + 7.0 * s), TL_PAPER, 1.0, 1.5 * s);
            float3 ink = tlInk(w.y);
            if (w.y == TL_RING) dlRing(ch, 4.0 * s, 1.25 * s, ink, 1.0);
            else if (w.y == TL_SUN) dlCircle(ch, 4.0 * s, ink, 1.0);
            else if (w.y == TL_BLOCK) dlRect(float4(ch - 3.5 * s, ch + 3.5 * s), ink, 1.0, 0.0);
            else dlRect(float4(ch.x - 5.5 * s, ch.y - 1.5 * s, ch.x + 5.5 * s, ch.y + 1.5 * s), ink, 1.0, 0.0);
            dlLabel(LB_L_0 + w.y, cell.x + 30.0 * s, y, body, on ? IL_INK : IL_MID, IL_LEFT);
            dlLabel(LB_K_0 + w.y, cell.z - 8.0 * s, y, cap, IL_DIM, IL_RIGHT);
        }
        else
        {
            bool act = w.z == g_attr;
            dlRect(cell, IL_WELL, 1.0, 2.0 * s);
            dlRect(band, IL_PANEL, 1.0, 0.0);
            if (act) dlRect(float4(cell.x + 12.0 * s, cell.y + 3.0 * s, cell.x + 14.0 * s, cell.w - 3.0 * s), IL_ACCENT, 1.0, 0.0);
            dlLabel(LB_A_0 + w.z, cell.x + 24.0 * s, y, cap, act ? IL_INK : IL_MID, IL_LEFT);
            uint ch = w.y * TL_ATTRS + w.z;
            dlNumEx(nowV(ch), w.z == TL_ROT ? 1 : 2, 1, w.z < 2u, cell.z - 8.0 * s, y, cap, act ? IL_INK : IL_DIM, IL_RIGHT);
            // the segments between keys: a solid bar where the value holds, a hairline where it moves
            uint n = tlCount(ch);
            [loop] for (uint i = 0u; i + 1u < n; i++)
            {
                float4 k0 = tlKey(ch, i), k1 = tlKey(ch, i + 1u);
                float x0 = tlX(g_L, g_tw, k0.x), x1 = tlX(g_L, g_tw, k1.x);
                if (tlMode(k0) == TL_HOLD || abs(k1.y - k0.y) < 1e-6) dlRect(float4(x0, y - 1.5 * s, x1, y + 1.5 * s), IL_EDGE * 1.4, 1.0, 0.0);
                else dlLine(float2(x0, y), float2(x1, y), 1.0 * s, IL_RULE, 1.0);
            }
        }
    }
    // the graph's caption in the list column
    float4 gl = float4(g_L.list.x, g_L.graph.y, g_L.list.z, g_L.graph.w);
    float gy = gl.y + 12.0 * s;
    dlLabel(LB_GRAPH, gl.x + 2.0 * s, gy, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    float gx = gl.x + 2.0 * s;
    gx += dlLabel(LB_L_0 + g_sel, gx, gy + 20.0 * s, body, IL_INK, IL_LEFT) + 5.0 * s;
    dlLabel(LB_A_0 + g_attr, gx, gy + 20.0 * s, body, IL_ACCENT, IL_LEFT);
    if (gl.w - gl.y > 86.0 * s)
    {
        dlLabelFit(LB_GRAPH_D, gl.x + 2.0 * s, gy + 40.0 * s, cap, IL_DIM, IL_LEFT, gl.z - gl.x - 6.0 * s);
        dlLabelFit(LB_GRAPH_D2, gl.x + 2.0 * s, gy + 55.0 * s, cap, IL_DIM, IL_LEFT, gl.z - gl.x - 6.0 * s);
    }
}

// ---------------------------------------------------------------- the graph's ground
void graphGround()
{
    float s = g_s;
    float cap = IL_T_CAP * s;
    float4 gr = g_L.graph;
    dlRect(gr, IL_FIELD, 1.0, 2.0 * s);
    dlBorderRect(gr, 2.0 * s, IL_EDGE, 1.0);
    float pxPerV = (gr.w - gr.y - 12.0) / max(g_vw.y - g_vw.x, 1e-6);
    float step = ilNiceStep(pxPerV, 30.0 * s);
    float v0 = ceil(g_vw.x / step) * step;
    dlClip(gr);
    [loop] for (uint i = 0u; i < 40u; i++)
    {
        float v = v0 + i * step;
        if (v > g_vw.y) break;
        float y = tlGY(g_L, g_vw, v);
        dlHLine(y, gr.x, gr.z, abs(v) < step * 0.01 ? IL_EDGE * 1.5 : IL_GRID);
        dlNumEx(v, step < 0.1 ? 2 : (step < 1.0 ? 1 : 0), 1, false, gr.x + 4.0 * s, y - 7.0 * s, cap, IL_DIM, IL_LEFT);
    }
    dlClipReset();
}

// over the curves: keys, the selected keys' handles, the playhead's reading
void graphOver()
{
    float s = g_s;
    float4 gr = g_L.graph;
    uint ch = chA(), n = tlCount(ch);
    dlClip(ilInset(gr, -6.0 * s));
    [loop] for (uint i = 0u; i < n; i++)
    {
        float4 k = tlKey(ch, i);
        float2 c = float2(tlX(g_L, g_tw, k.x), tlGY(g_L, g_vw, k.y));
        bool on = tlSel(k);
        if (on && tlHasOut(ch, i))
        {
            float2 tip = tlOutTip(g_L, g_tw, g_vw, ch, i);
            bool live = g_mode == DM_HANDLE && g_target == i * 2u + 1u;
            dlLine(c, tip, 1.0 * s, IL_MID, 1.0);
            dlCircle(tip, 3.5 * s, live ? IL_ACCENT : IL_INK, 1.0);
        }
        if (on && tlHasIn(ch, i))
        {
            float2 tip = tlInTip(g_L, g_tw, g_vw, ch, i);
            bool live = g_mode == DM_HANDLE && g_target == i * 2u;
            dlLine(c, tip, 1.0 * s, IL_MID, 1.0);
            dlCircle(tip, 3.5 * s, live ? IL_ACCENT : IL_INK, 1.0);
        }
        float4 r = float4(c - 4.0 * s, c + 4.0 * s);
        dlRectEdged(r, on ? IL_ACCENT : IL_FIELD, 1.0, 1.0 * s, on ? IL_ACCENT : IL_INK, 1.5 * s);
        if (isPrimary(ch, k.x)) dlBorderRect(ilInset(r, -3.0 * s), 2.0 * s, IL_ACCENT, 1.0);
    }
    float f = frameNow();
    float2 pc = float2(tlX(g_L, g_tw, g_play), tlGY(g_L, g_vw, nowV(ch)));
    dlCircle(pc, 3.0 * s, IL_ACCENT, 1.0);
    dlNumEx(nowV(ch), g_attr == TL_ROT ? 1 : 3, 1, true, pc.x + 7.0 * s, pc.y - 9.0 * s, IL_T_CAP * s, IL_ACCENT, IL_LEFT);
    dlClipReset();
}

// the playhead through the ruler, the sheet and the graph; the box select
void playhead()
{
    float s = g_s;
    float x = tlX(g_L, g_tw, g_play);
    if (x >= g_L.area.x && x <= g_L.area.z)
    {
        dlRect(float4(x - 0.75 * s, g_L.ruler.y, x + 0.75 * s, g_L.graph.w), IL_ACCENT, 0.9, 0.0);
        float4 tag = float4(x - 15.0 * s, g_L.ruler.y, x + 15.0 * s, g_L.ruler.y + 14.0 * s);
        dlRect(tag, IL_ACCENT, 1.0, 2.0 * s);
        dlInt((int)frameNow(), 1, x, ilMid(tag).y, IL_T_CAP * s, IL_FIELD, IL_CENTER);
    }
    if (g_mode == DM_BOX)
    {
        float2 a = S[TL_V2].xy, b = S[TL_V2].zw;
        float4 bx = float4(min(a, b), max(a, b));
        dlRectEdged(bx, IL_ACCENT, 0.08, 0.0, IL_ACCENT, 1.0);
    }
}

// ---------------------------------------------------------------- hint bar
void hints()
{
    float s = g_s;
    float kh = 18.0 * s;
    float bx = g_L.hint.x, by = ilMid(g_L.hint).y;
    float total = 0.0;
    [loop] for (uint a = 0u; a < 7u; a++)
        total += ilLabelW(LB_H_K0 + a, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(LB_H_D0 + a, IL_T_CAP * s) + 16.0 * s;
    plate(float4(bx, by - 15.0 * s, bx + total + 8.0 * s, by + 15.0 * s));
    bx += 10.0 * s;
    [loop] for (uint b = 0u; b < 7u; b++)
    {
        float kw = ilLabelW(LB_H_K0 + b, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(LB_H_D0 + b, IL_T_CAP * s);
        dlKeycap(float4(bx, by - kh * 0.5, bx + kw, by + kh * 0.5), s, LB_H_K0 + b);
        dlLabel(LB_H_D0 + b, bx + kw + 6.0 * s, by, IL_T_CAP * s, IL_DIM, IL_LEFT);
        bx += kw + 6.0 * s + dw + 16.0 * s;
    }
}

// ---------------------------------------------------------------- the batches
void graphItem(uint g)
{
    float s = g_s;
    float4 gr = g_L.graph;
    float2 sp = sheetSpan();
    if (g < GR_SEGS)
    {
        float a = lerp(sp.x, sp.y, (float)g / GR_SEGS), b = lerp(sp.x, sp.y, (float)(g + 1u) / GR_SEGS);
        dlLine(float2(tlX(g_L, g_tw, a), tlGY(g_L, g_vw, gsJ[J_ACT + g])), float2(tlX(g_L, g_tw, b), tlGY(g_L, g_vw, gsJ[J_ACT + g + 1u])), 1.5 * s, IL_INK, 1.0);
        return;
    }
    g -= GR_SEGS;
    uint other = g / GR_CTX, j = g % GR_CTX;
    uint ch = g_sel * TL_ATTRS + other + (other >= g_attr ? 1u : 0u);
    if (tlCount(ch) < 2u) return;
    float2 rg = gsRange[other];
    uint base = J_CTX + other * (GR_CTX + 1u);
    float a = lerp(sp.x, sp.y, (float)j / GR_CTX), b = lerp(sp.x, sp.y, (float)(j + 1u) / GR_CTX);
    float ya = lerp(gr.w - 10.0 * s, gr.y + 10.0 * s, (gsJ[base + j] - rg.x) / (rg.y - rg.x));
    float yb = lerp(gr.w - 10.0 * s, gr.y + 10.0 * s, (gsJ[base + j + 1u] - rg.x) / (rg.y - rg.x));
    dlLine(float2(tlX(g_L, g_tw, a), ya), float2(tlX(g_L, g_tw, b), yb), 1.0 * s, IL_RULE, 1.0);
}

void pathItem(uint g)
{
    float s = g_s;
    uint fi = g / 2u;
    if ((float)fi > g_frames) return;
    float2 c = stagePx(pathAt(fi));
    if ((g & 1u) == 0u)
    {
        if ((float)(fi + 1u) > g_frames) return;
        float2 d = stagePx(pathAt(fi + 1u));
        dlLine(c, d, 1.0 * s, OV_DARK, 0.55);
    }
    else
    {
        bool now = abs((float)fi - frameNow()) < 0.5;
        dlCircle(c, (now ? 3.0 : 1.6) * s, now ? IL_ACCENT : OV_DARK, now ? 1.0 : 0.8);
    }
}

void dopeItem(uint g, ILBatch b)
{
    float s = g_s;
    uint ch = g / TL_KMAX, i = g % TL_KMAX;
    dlAtSpan(b, g, 2u);
    if (i >= tlCount(ch)) return;
    float4 k = tlKey(ch, i);
    float x = tlX(g_L, g_tw, k.x);
    if (x < g_L.area.x - 6.0 * s || x > g_L.area.z + 6.0 * s) return;
    uint layer = ch / TL_ATTRS, attr = ch % TL_ATTRS;
    // the layer row's summary diamond
    float4 lr = tlRow(g_L, tlLayerRow(layer, g_sel));
    dlDiamond(float2(x, ilMid(lr).y), 3.5 * s, 0.0, tlSel(k) ? IL_ACCENT : IL_DIM, 1.0);
    // and its own channel row, when its layer is the selected one
    if (layer != g_sel) return;
    float4 r = tlRow(g_L, tlAttrRow(attr, g_sel));
    bool on = tlSel(k);
    bool prim = isPrimary(ch, k.x);
    dlDiamond(float2(x, ilMid(r).y), (prim ? 6.0 : 5.0) * s, 0.0, on ? IL_ACCENT : (attr == g_attr ? IL_INK : IL_MID), 1.0);
}

// ---------------------------------------------------------------- thread 0
void layout()
{
    dlBegin(g_res);
    header();
    plate(g_L.block);
    stage();
    dlClip(g_L.stage);
    dlBatch(PATH_ITEMS, 0u);                 // batch 0: the motion path
    dlClipReset();
    stageOver();
    inspector();
    transport();
    sheet();
    dlClip(float4(g_L.area.x, g_L.dope.y, g_L.area.z, g_L.dope.w));
    dlBatch(DOPE_ITEMS * 2u, 0u);            // batch 1: the dope sheet's keys
    dlClipReset();
    graphGround();
    dlClip(g_L.graph);
    dlBatch(GRAPH_ITEMS, 0u);                // batch 2: the curves
    dlClipReset();
    graphOver();
    playhead();
    // the splitters' grips, lit while hovered or held
    bool hv = g_mode == DM_SPLITV || (g_mode == DM_NONE && ilIn(g_ptr, g_L.gripV));
    bool hh = g_mode == DM_SPLITH || (g_mode == DM_NONE && ilIn(g_ptr, g_L.gripH));
    float2 mv = float2(ilMid(g_L.inner).x, g_L.splitVAt), mh = float2(ilMid(g_L.area).x, g_L.splitHAt);
    dlRect(float4(mv.x - 18.0 * g_s, mv.y - 1.5 * g_s, mv.x + 18.0 * g_s, mv.y + 1.5 * g_s), hv ? (g_mode == DM_SPLITV ? IL_ACCENT : IL_INK) : IL_RULE, 1.0, 1.5 * g_s);
    dlRect(float4(mh.x - 18.0 * g_s, mh.y - 1.5 * g_s, mh.x + 18.0 * g_s, mh.y + 1.5 * g_s), hh ? (g_mode == DM_SPLITH ? IL_ACCENT : IL_INK) : IL_RULE, 1.0, 1.5 * g_s);
    hints();
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_res = _Resolution.xy;
    g_s = ilCtx(g_res).s;
    float4 v1 = S[TL_V1], v3 = S[TL_V3], v4 = S[TL_V4], v6 = S[TL_V6];
    g_L = tlLayout(g_res, g_s, v4.xy);
    g_mode = (uint)v1.z;
    g_target = (uint)v1.w;
    g_sel = min((uint)v4.z, TL_LAYERS - 1u);
    g_attr = min((uint)v4.w, TL_ATTRS - 1u);
    g_tw = v3.xy;
    g_vw = v3.zw;
    g_play = tlPlayhead();
    g_frames = max(tlP0().z, 1.0);
    g_primCh = v6.y;
    g_primF = v6.z;
    g_onion = v6.x > 0.5;
    g_ptr = (g_mode != DM_NONE) ? S[TL_V2].zw : _ViewportPointerPosition * g_res;

    // 1. every value the panes draw, at one call site
    [loop] for (uint j = gi; j < J_COUNT; j += IL_LAYOUT_THREADS)
    {
        uint ch;
        float f;
        job(j, ch, f);
        gsJ[j] = tlValue(ch, f);
    }
    GroupMemoryBarrierWithGroupSync();
    if (gi < 4u)
    {
        float lo = 1e9, hi = -1e9;
        [loop] for (uint i = 0u; i <= GR_CTX; i++) { float v = gsJ[J_CTX + gi * (GR_CTX + 1u) + i]; lo = min(lo, v); hi = max(hi, v); }
        gsRange[gi] = float2(lo, max(hi, lo + 1e-3));
    }
    GroupMemoryBarrierWithGroupSync();

    // 2. the chrome; 3. the batches
    if (gi == 0u) layout();
    dlSync();

    ILBatch bp = dlGetBatch(0u);
    [loop] for (uint a = gi; a < bp.count; a += IL_LAYOUT_THREADS) { dlAt(bp, a); pathItem(a); }
    ILBatch bd = dlGetBatch(1u);
    [loop] for (uint d = gi; d < DOPE_ITEMS; d += IL_LAYOUT_THREADS) dopeItem(d, bd);
    ILBatch bg = dlGetBatch(2u);
    [loop] for (uint c = gi; c < bg.count; c += IL_LAYOUT_THREADS) { dlAt(bg, c); graphItem(c); }
    dlEnd(gi);
}
