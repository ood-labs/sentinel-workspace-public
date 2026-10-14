// Kit / layout - records the specimen into the draw list (one thread).
//
// Left: the type system and palette, laid out from the live extent, and - when the extent has the
// height - the widget states. Right: every host-owned control kind, drawn at its manifest rect
// (UI_RECT_*, scaled by the extent) from the host's own report in _ViewportControlState - so what
// you see is what the host holds.
//
// Under the XY pad the same value is printed three ways - stored parameter, published control
// output, host control state - with a verdict. That row is the pad authority's standing proof.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

StructuredBuffer<float4> KitState : register(t0);

float3 ladder(int i)
{
    if (i == 0) return IL_FIELD; if (i == 1) return IL_WELL; if (i == 2) return IL_PANEL;
    if (i == 3) return IL_RAISE; if (i == 4) return IL_GRID; if (i == 5) return IL_EDGE;
    if (i == 6) return IL_RULE;  if (i == 7) return IL_DIM;  if (i == 8) return IL_MID;
    return IL_INK;
}
uint ladderName(int i)
{
    if (i == 0) return LB_C_FIELD; if (i == 1) return LB_C_WELL; if (i == 2) return LB_C_PANEL;
    if (i == 3) return LB_C_RAISE; if (i == 4) return LB_C_GRID; if (i == 5) return LB_C_EDGE;
    if (i == 6) return LB_C_RULE;  if (i == 7) return LB_C_DIM;  if (i == 8) return LB_C_MID;
    return LB_C_INK;
}

static const float RAMP[8] = { 9.0, 11.0, 13.0, 16.0, 20.0, 26.0, 34.0, 44.0 };

// Body heights each pane's content needs, in ui units (times s): the left column stacks three
// panes only when all three fit whole.
static const float TYPE_NEED   = 266.0;   // + 1.15 * type_size for the live line
static const float PAL_NEED    = 134.0;
static const float STATES_NEED = 252.0;

void drawType(float4 body, float s)
{
    float pad = 14.0 * s;
    float x = body.x + pad;
    float room = body.z - body.x - 2.0 * pad;
    float y = body.y + 20.0 * s;
    float capS = 10.0 * s, sampS = 15.0 * s, block = 44.0 * s;
    uint caps[3] = { LB_T_SANS_CAP, LB_T_BOLD_CAP, LB_T_MONO_CAP };
    uint samp[3] = { LB_T_SANS, LB_T_BOLD, LB_T_MONO };
    [loop] for (int i = 0; i < 3; i++)
    {
        if (y + block > body.w) return;
        dlLabel(caps[i], x, y, capS, IL_DIM, IL_LEFT);
        dlLabelFit(samp[i], x, y + 19.0 * s, sampS, IL_INK, IL_LEFT, room);
        y += block;
    }

    // size ramp on one shared baseline, each size printed under its sample
    float rampH = 76.0 * s;
    if (y + rampH > body.w) return;
    dlLabel(LB_T_RAMP_CAP, x, y, capS, IL_DIM, IL_LEFT);
    float base = y + 14.0 * s + 44.0 * s * 0.72;
    float cx = x;
    [loop] for (int k = 0; k < 8; k++)
    {
        float sz = RAMP[k] * s;
        float w = ilLabelW(LB_T_AA, sz);
        if (cx + w > x + room) break;
        dlLabel(LB_T_AA, cx, base - 0.5 * ilCapH(sz), sz, IL_INK, IL_LEFT);
        dlInt((int)RAMP[k], 1, cx + 0.5 * w, base + 13.0 * s, 9.5 * s, IL_DIM, IL_CENTER);
        cx += w + 16.0 * s;
    }
    y += rampH + 8.0 * s;

    // live size: driven by type_size; continuous because every glyph is a distance field
    float liveS = type_size * s;
    if (y + 16.0 * s + liveS * 1.15 > body.w) return;
    float cw = dlLabel(LB_T_LIVE_CAP, x, y, capS, IL_DIM, IL_LEFT);
    dlNum(type_size, 1, x + cw + 10.0 * s, y, capS, IL_ACCENT, IL_LEFT);
    float liveMid = y + 14.0 * s + 0.62 * liveS;
    float lw = dlLabel(LB_T_LIVE, x, liveMid, liveS, IL_INK, IL_LEFT);
    dlLabelFit(LB_T_NOTE, x + lw + 24.0 * s, liveMid, 11.0 * s, IL_DIM, IL_LEFT, room - lw - 24.0 * s);
}

void drawPalette(float4 body, float s)
{
    float4 r = ilInset2(body, float2(14.0 * s, 12.0 * s));
    float w = (r.z - r.x) / 10.0;
    float sh = min(34.0 * s, (r.w - r.y) * 0.32);
    float ty = 0.0;
    [loop] for (int i = 0; i < 10; i++)
    {
        float4 sw = float4(r.x + i * w + 2.0 * s, r.y + 6.0 * s, r.x + (i + 1) * w - 2.0 * s, r.y + 6.0 * s + sh);
        dlRectEdged(sw, ladder(i), 1.0, 2.0 * s, IL_EDGE, 1.0);
        ty = sw.w + 12.0 * s;
        dlLabelFit(ladderName(i), sw.x, ty, 11.0 * s, IL_MID, IL_LEFT, w - 4.0 * s);
        dlNum(ilLum(ladder(i)), 3, sw.x, ty + 15.0 * s, 10.0 * s, IL_DIM, IL_LEFT);
    }

    // reserved hues + the identity set
    float y2 = ty + 42.0 * s;
    if (y2 + 14.0 * s > r.w) return;
    float cw = (r.z - r.x) / 3.0;
    uint heads[3] = { LB_C_ACCENT, LB_C_ALARM, LB_C_ID };
    uint descs[3] = { LB_C_ACCENT_D, LB_C_ALARM_D, LB_C_ID_D };
    [loop] for (int j = 0; j < 3; j++)
    {
        float x0 = r.x + j * cw;
        float cz = x0 + 18.0 * s;
        if (j < 2) dlRect(float4(x0, y2 - 9.0 * s, cz, y2 + 9.0 * s), j == 0 ? IL_ACCENT : IL_ALARM, 1.0, 2.0 * s);
        else
        {
            [loop] for (int k = 0; k < 4; k++)
                dlRect(float4(x0 + k * 11.0 * s, y2 - 9.0 * s, x0 + k * 11.0 * s + 8.0 * s, y2 + 9.0 * s), ptId(k), 1.0, 1.5 * s);
            cz = x0 + 41.0 * s;
        }
        float tx = cz + 9.0 * s;
        dlLabel(heads[j], tx, y2 - 6.0 * s, 11.0 * s, IL_INK, IL_LEFT);
        dlLabelFit(descs[j], tx, y2 + 8.0 * s, 10.5 * s, IL_DIM, IL_LEFT, x0 + cw - tx - 6.0 * s);
    }
}

// The widgets a module draws itself, each in the states it has (il_ui.hlsli: hot is one value
// step up and never a hue, down puts the accent on the grabbed part, on is ink on a lifted face
// with an accent tick); a short rule marks a state the widget does not have. The values are this
// Kit's own host parameters - amount, level, mode - so the specimens move with the controls.
void drawStates(float4 body, float s)
{
    float pad = 14.0 * s;
    float x0 = body.x + pad, x1 = body.z - pad;
    float capW = 104.0 * s;
    float colW = (x1 - x0 - capW) / 4.0;
    float y = body.y + 16.0 * s;
    // each set of labels is consecutive in labels.txt (REST..ON, their notes, the rows, the captions)
    [loop] for (uint c = 0u; c < 4u; c++)
    {
        float hx = x0 + capW + (c + 0.5) * colW;
        dlLabel(LB_S_REST + c, hx, y, IL_T_CAP * s, IL_MID, IL_CENTER);
        dlLabelFit(LB_S_REST_D + c, hx, y + 14.0 * s, IL_T_CAP * s, IL_DIM, IL_CENTER, colW - 8.0 * s);
    }
    y += 30.0 * s;

    // the states each row's widget has, a nibble per row (chip, slider, knob, toggle), bit k =
    // column k: the chip has all four, the slider rest/hot/down, the knob rest/down, the toggle
    // rest/hot/on
    static const uint HAS = 0xB57Fu;
    float rowH = 32.0 * s;
    [loop] for (uint r = 0u; r < 4u; r++)
    {
        dlHLine(y, x0, x1, IL_GRID);
        float cy = y + 0.5 * rowH;
        dlLabel(LB_S_CHIP + r, x0, cy, IL_T_BODY * s, IL_MID, IL_LEFT);
        [loop] for (uint k = 0u; k < 4u; k++)
        {
            float mx = x0 + capW + (k + 0.5) * colW;
            if (((HAS >> (4u * r + k)) & 1u) == 0u)
            {
                dlHLine(cy, mx - 8.0 * s, mx + 8.0 * s, IL_EDGE * 1.5);
                continue;
            }
            bool hot = k == 1u, down = k == 2u, on = k == 3u;
            float h2 = 11.0 * s;
            if (r == 0u)      dlChip(float4(mx - 30.0 * s, cy - h2, mx + 30.0 * s, cy + h2), s, LB_S_CHIP_L, on, hot, down);
            else if (r == 1u) dlSlider(float4(mx - 0.5 * colW + 14.0 * s, cy - h2, mx + 0.5 * colW - 14.0 * s, cy + h2), s, k_amount, hot, down);
            else if (r == 2u) dlKnob(float2(mx, cy), 12.0 * s, s, k_level, down);
            else              dlToggle(float4(mx - 20.0 * s, cy - 8.0 * s, mx + 20.0 * s, cy + 8.0 * s), s, on, hot);
        }
        y += rowH;
    }
    dlHLine(y, x0, x1, IL_GRID);
    y += 12.0 * s;

    // readouts and furniture, one of each, live
    float sw = (x1 - x0) / 4.0;
    [loop] for (uint j = 0u; j < 4u; j++)
        dlLabelFit(LB_S_SEG_CAP + j, x0 + j * sw, y, IL_T_CAP * s, IL_DIM, IL_LEFT, sw - 10.0 * s);
    // a band tall enough for the meter's segments; the others sit on its middle
    float wy = y + 12.0 * s, bandH = 42.0 * s, wh = 24.0 * s;
    float wm = wy + 0.5 * bandH;
    dlSegmented(float4(x0, wm - 0.5 * wh, x0 + min(sw - 14.0 * s, 132.0 * s), wm + 0.5 * wh), s, LB_S_SEG_A, 3u, k_mode, -1);
    float mx0 = x0 + sw;
    dlMeter(float4(mx0, wy, mx0 + 12.0 * s, wy + bandH), s, k_level, KitState[2].z);
    dlNum(k_level, 2, mx0 + 22.0 * s, wm, IL_T_VALUE * s, IL_INK, IL_LEFT);
    float kx = x0 + 2.0 * sw;
    [loop] for (uint q = 0u; q < 2u; q++)     // Space, Z
    {
        float kw = ilLabelW(LB_S_KEY_SPACE + q, IL_T_CAP * s) + 16.0 * s;
        dlKeycap(float4(kx, wm - 10.0 * s, kx + kw, wm + 10.0 * s), s, LB_S_KEY_SPACE + q);
        kx += kw + 6.0 * s;
    }
    dlValueRow(float4(x0 + 3.0 * sw, wm - 0.5 * wh, x1, wm + 0.5 * wh), s, LB_S_AMOUNT, k_amount, 3, true);
}

void caption(float4 rect, float s, uint id) { dlLabel(id, rect.x, rect.y - 10.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT); }

void drawControls(float2 res, float s)
{
    float4 ra = ilCtlRect(UI_RECT_AMOUNT, res);
    caption(ra, s, LB_K_AMOUNT);
    dlNum(k_amount, 3, ra.z, ra.y - 10.0 * s, 11.5 * s, IL_INK, IL_RIGHT);
    dlSlider(ra, s, ilCtlValue(UI_AMOUNT), ilCtlHot(UI_AMOUNT), ilCtlDown(UI_AMOUNT));

    float4 re = ilCtlRect(UI_RECT_ENABLED, res);
    caption(re, s, LB_K_ENABLED);
    dlToggle(re, s, k_enabled != 0, ilCtlHot(UI_ENABLED));

    float4 rf = ilCtlRect(UI_RECT_FIRE, res);
    caption(rf, s, LB_K_FIRE);
    dlNum(KitState[1].x, 0, rf.z, rf.y - 10.0 * s, 11.5 * s, IL_INK, IL_RIGHT);
    caption(ilCtlRect(UI_RECT_MODE_A, res), s, LB_K_MODE);
    caption(ilCtlRect(UI_RECT_HOLD, res), s, LB_K_HOLD);

    // Six show pads through ONE call site: repeated widgets go in a data-driven loop so the
    // widget is inlined once, not once per instance (compile time grows superlinearly otherwise).
    uint padId[6] = { UI_FIRE, UI_MODE_A, UI_MODE_B, UI_MODE_C, UI_HOLD, UI_LATCH };
    float4 padRect[6] = { UI_RECT_FIRE, UI_RECT_MODE_A, UI_RECT_MODE_B, UI_RECT_MODE_C, UI_RECT_HOLD, UI_RECT_LATCH };
    uint lit = (k_mode == 0 ? 2u : 0u) | (k_mode == 1 ? 4u : 0u) | (k_mode == 2 ? 8u : 0u) | (k_hold != 0 ? 16u : 0u) | (k_latch != 0 ? 32u : 0u);
    [loop] for (uint i = 0u; i < 6u; i++)
        dlShowPad(ilCtlRect(padRect[i], res), s, padId[i], ((lit >> i) & 1u) != 0u);

    float4 rp = ilCtlRect(UI_RECT_POINT, res);
    caption(rp, s, LB_K_POINT);
    dlPadXY(rp, s, k_point, ilCtlDown(UI_POINT));

    float4 rl = ilCtlRect(UI_RECT_LEVEL, res);
    caption(rl, s, LB_K_LEVEL);
    dlFader(rl, s, ilCtlValue(UI_LEVEL), ilCtlHot(UI_LEVEL), ilCtlDown(UI_LEVEL));
    dlNum(k_level, 2, ilMid(rl).x, rl.w + 11.0 * s, 11.0 * s, IL_INK, IL_CENTER);

    // the authority proof: stored parameter / published output / host control state
    float2 vals[3];
    vals[0] = k_point;
    vals[1] = KitState[0].xy;
    vals[2] = KitState[3].xy;
    uint names[3] = { LB_K_STORED, LB_K_PUBLISHED, LB_K_HOST };
    float rowH = 15.0 * s;
    float y0 = rp.w + 16.0 * s;
    float xV = rp.x + 64.0 * s;
    [loop] for (int r = 0; r < 3; r++)
    {
        float y = y0 + r * rowH;
        if (y > res.y - 8.0 * s) break;
        dlLabel(names[r], rp.x, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
        dlLabel(LB_K_X, xV, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
        dlNum(vals[r].x, 3, xV + 12.0 * s, y, 11.0 * s, IL_INK, IL_LEFT);
        dlLabel(LB_K_Y, xV + 64.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
        dlNum(vals[r].y, 3, xV + 76.0 * s, y, 11.0 * s, IL_INK, IL_LEFT);
    }
    float2 dA = abs(vals[0] - vals[1]), dB = abs(vals[0] - vals[2]);
    bool agree = max(max(dA.x, dA.y), max(dB.x, dB.y)) < 0.0015;
    float vx = xV + 136.0 * s, vy = y0 + rowH;
    float4 badge = float4(vx, vy - 8.0 * s, vx + 54.0 * s, vy + 8.0 * s);
    dlRectEdged(badge, agree ? IL_RAISE * 1.6 : IL_ALARM * 0.35, 1.0, 2.0 * s, agree ? IL_MID : IL_ALARM, 1.0);
    dlLabel(agree ? LB_K_AGREE : LB_K_DRIFT, ilMid(badge).x, vy, 10.0 * s, agree ? IL_INK : IL_ALARM, IL_CENTER);
}

void layout()
{
    float2 res = _Resolution.xy;
    ILCtx cx = ilCtx(res);
    float s = cx.s;
    dlBegin(res);

    // header: title, subtitle, and the live extent / ui scale (real numbers, not decoration)
    float4 head = float4(0.02, 0.02, 0.98, 0.085) * res.xyxy;
    float hy = ilMid(head).y;
    float tw = dlLabel(LB_TITLE, head.x, hy, 15.0 * s, IL_INK, IL_LEFT);
    float rx = head.z;
    rx -= dlNum(s, 2, rx, hy, 11.5 * s, IL_INK, IL_RIGHT) + 6.0 * s;
    rx -= dlLabel(LB_SCALE, rx, hy, 11.0 * s, IL_DIM, IL_RIGHT) + 18.0 * s;
    rx -= dlNum(res.y, 0, rx, hy, 11.5 * s, IL_INK, IL_RIGHT) + 5.0 * s;
    rx -= dlLabel(LB_K_X, rx, hy, 11.0 * s, IL_DIM, IL_RIGHT) + 5.0 * s;
    rx -= dlNum(res.x, 0, rx, hy, 11.5 * s, IL_INK, IL_RIGHT) + 8.0 * s;
    rx -= dlLabel(LB_EXTENT, rx, hy, 11.0 * s, IL_DIM, IL_RIGHT);
    float sx = head.x + tw + 14.0 * s;
    dlLabelFit(LB_SUBTITLE, sx, hy, 12.0 * s, IL_DIM, IL_LEFT, rx - sx - 16.0 * s);
    dlHLine(head.w, head.x, head.z, IL_EDGE);

    // left column: type and palette share it, as before, unless the extent is tall enough for the
    // widget states as well - then type and palette take what their content needs and the states
    // pane takes the rest
    float4 rType = float4(0.02, 0.105, 0.595, 0.60) * res.xyxy;
    float4 rPal  = float4(0.02, 0.62, 0.595, 0.98) * res.xyxy;
    float4 rStates = rPal;
    float gap = 0.02 * res.y;
    float typeH = (IL_HEADER + TYPE_NEED + 1.15 * type_size) * s;
    float palH = (IL_HEADER + PAL_NEED) * s;
    bool roomy = rPal.w - rType.y >= typeH + palH + (IL_HEADER + STATES_NEED) * s + 2.0 * gap;
    if (roomy)
    {
        rType.w = rType.y + typeH;
        rPal.y = rType.w + gap;
        rPal.w = rPal.y + palH;
        rStates.y = rPal.w + gap;
    }
    float4 rCtl  = float4(0.615, 0.105, 0.98, 0.98) * res.xyxy;
    drawType(dlPane(rType, s, LB_P_TYPE, false), s);
    drawPalette(dlPane(rPal, s, LB_P_PALETTE, false), s);
    if (roomy) drawStates(dlPane(rStates, s, LB_P_STATES, false), s);
    dlPane(rCtl, s, LB_P_CONTROLS, false);
    drawControls(res, s);
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();     // one thread records the list...
    dlEnd(gi);                  // ...every thread expands its text
}
