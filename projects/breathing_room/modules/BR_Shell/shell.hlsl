// BR_Shell / shell.hlsl -- the architecture authority. ONE thread, once per cook.
//
//   1. resolve the room and its openings from parameters + persistent hand edits
//   2. consume this cook's viewport events (each exactly once, by sequence) into those edits
//   3. resolve again, measure alarms, publish records 0..12
//
// EDITS ARE DELTAS over a procedural base, never a replacement: a dragged window keeps its
// offset when the room is resized from Properties, and a style change re-derives every default
// without throwing the user's work away. R clears one record's edits, 0 clears them all.
#include "../_shared/br_records.hlsli"
#include "shell_layout.hlsli"

RWStructuredBuffer<BRRec> Shell : register(u0);

#define PLAN_VERSION 3.0

#define H_NONE 0
#define H_MOVE 1
#define H_ALO  2
#define H_AHI  3
#define H_TOP  4
#define H_BOT  5
#define H_WALL 6
#define H_CEIL 7

#define SEL_NONE 0
#define SEL_OPEN 1
#define SEL_WALL 2
#define SEL_CEIL 3

#define REC_FROZEN 14

struct OpenDelta
{
    float da, dw, dh, dsill;
    int kindOv, wallOv, curtainOv, activeOv;
    float edited;
};

float sane(float v) { return (abs(v) < 1e4) ? v : 0.0; }

OpenDelta readDelta(BRRec r)
{
    OpenDelta d;
    d.da = sane(r.dims.x); d.dw = sane(r.dims.y); d.dh = sane(r.dims.z); d.dsill = sane(r.dims.w);
    d.kindOv = (int)clamp(round(sane(r.look.x)), 0, OPEN_KIND_COUNT - 1);
    d.wallOv = (int)clamp(round(sane(r.look.y)), 0, 4);
    d.curtainOv = (int)clamp(round(sane(r.look.z)), 0, 2);
    d.activeOv = (int)clamp(round(sane(r.look.w)), 0, 2);
    d.edited = sane(r.meta.x);
    return d;
}

BRRec writeDelta(OpenDelta d)
{
    BRRec r;
    r.head = float4(ROLE_DELTA, 0, 0, 0);
    r.dims = float4(d.da, d.dw, d.dh, d.dsill);
    r.look = float4(d.kindOv, d.wallOv, d.curtainOv, d.activeOv);
    bool any = abs(d.da) + abs(d.dw) + abs(d.dh) + abs(d.dsill) > 1e-5 || d.kindOv != 0 || d.wallOv != 0 || d.curtainOv != 0 || d.activeOv != 0;
    r.meta = float4(any ? 1.0 : 0.0, 0, 0, 0);
    return r;
}

OpenDelta zeroDelta()
{
    OpenDelta d;
    d.da = 0; d.dw = 0; d.dh = 0; d.dsill = 0;
    d.kindOv = 0; d.wallOv = 0; d.curtainOv = 0; d.activeOv = 0; d.edited = 0;
    return d;
}

float snapTo(float v, float step) { return (step > 1e-4) ? round(v / step) * step : v; }

// --------------------------------------------------------------------------------------------
// PROCEDURAL BASE

int styleWindowKind(int st)
{
    return (st == 1) ? OPEN_CASEMENT : (st == 2) ? OPEN_CASEMENT : (st == 3) ? OPEN_PICTURE : OPEN_DOUBLEHUNG;
}

void kindDims(int kind, int st, out float w, out float h, out float sill, out float cols, out float rows, out float depth)
{
    depth = 0.0;
    w = 1.0; h = 1.8; sill = 0.6; cols = 1; rows = 1;
    if (kind == OPEN_DOUBLEHUNG) { w = 1.05; h = 1.82; sill = 0.55; cols = 2; rows = 1; }
    else if (kind == OPEN_CASEMENT)
    {
        if (st == 1)      { w = 1.60; h = 2.35; sill = 0.42; cols = 3; rows = 4; }
        else if (st == 2) { w = 0.95; h = 1.30; sill = 0.85; cols = 2; rows = 3; }
        else              { w = 1.20; h = 1.75; sill = 0.65; cols = 2; rows = 3; }
    }
    else if (kind == OPEN_PICTURE)   { w = 2.20; h = 2.05; sill = 0.38; cols = 1; rows = 1; }
    else if (kind == OPEN_FRENCH)    { w = 1.40; h = 2.35; sill = 0.0;  cols = 1; rows = 5; }
    else if (kind == OPEN_DOOR)      { w = 0.85; h = 2.10; sill = 0.0;  cols = 2; rows = 3; }
    else if (kind == OPEN_ARCH)      { w = 1.30; h = 2.35; sill = 0.0;  cols = 0; rows = 0; }
    else if (kind == OPEN_FIREPLACE) { w = 1.80; h = 1.24; sill = 0.0;  cols = 0.86; rows = 0.80; depth = 0.36; }
}

BRRoom baseRoom(BRRec rd)
{
    BRRoom r;
    float hw = room_width * 0.5, hd = room_depth * 0.5;
    r.x0 = -hw + sane(rd.dims.x); r.x1 = hw + sane(rd.dims.y);
    r.z0 = -hd + sane(rd.dims.z); r.z1 = hd + sane(rd.dims.w);
    // never let a drag invert or crush the room
    if (r.x1 - r.x0 < 3.0) { float c = (r.x0 + r.x1) * 0.5; r.x0 = c - 1.5; r.x1 = c + 1.5; }
    if (r.z1 - r.z0 < 3.0) { float c = (r.z0 + r.z1) * 0.5; r.z0 = c - 1.5; r.z1 = c + 1.5; }
    r.H = clamp(ceiling + sane(rd.look.x), 2.3, 4.6);
    r.T = wall_thickness;
    r.baseH = baseboard;
    r.crown = (crown != 0) ? ((style == 0) ? 0.13 : 0.08) : 0.0;
    r.railH = (picture_rail != 0) ? min(rail_height, r.H - r.crown - 0.12) : 0.0;
    r.plankW = plank_width;
    r.style = style;
    r.floorPattern = floor_pattern;
    r.flags = ((crown != 0) ? ROOM_FLAG_CROWN : 0) | ((picture_rail != 0) ? ROOM_FLAG_RAIL : 0)
            | ((radiators != 0) ? ROOM_FLAG_RADIATORS : 0) | ((curtains != 0) ? ROOM_FLAG_CURTAINS : 0);
    return r;
}

float wallCentre(BRRoom r, int w) { float2 e = brWallExtent(r, w); return (e.x + e.y) * 0.5; }

// The corner coordinate of wall w where it meets wall `other` (along w's axis).
float cornerA(BRRoom r, int w, int other)
{
    if (brWallAlongX(w)) return (other == WALL_E) ? r.x1 : r.x0;
    return (other == WALL_N) ? r.z1 : r.z0;
}

void baseOpening(int slot, BRRoom r, out int kind, out int wall, out float a, out bool active)
{
    int ww = window_wall;
    int fw = (ww + 3) % 4;          // to the right of the window wall
    int dw = (ww + 2) % 4;          // facing the windows
    int aw = (fw + 2) % 4;          // facing the fireplace
    kind = OPEN_NONE; wall = ww; a = wallCentre(r, ww); active = false;
    if (slot < 3)
    {
        int n = clamp(window_count, 1, 3);
        float w, h, s, c, ro, dp;
        kind = styleWindowKind(style);
        kindDims(kind, style, w, h, s, c, ro, dp);
        float L = brWallLength(r, ww);
        float pitch = clamp(L / (float)n, w + 0.45, 2.8);
        a = wallCentre(r, ww) + ((float)slot - (float)(n - 1) * 0.5) * pitch;
        active = slot < n;
    }
    else if (slot == 3)
    {
        kind = OPEN_FIREPLACE; wall = fw; a = wallCentre(r, fw); active = fireplace != 0;
    }
    else if (slot == 4)
    {
        kind = OPEN_DOOR; wall = dw;
        float c = cornerA(r, dw, fw);
        float centre = wallCentre(r, dw);
        a = c + sign(centre - c) * (0.32 + 0.425);
        active = door != 0;
    }
    else if (slot == 5)
    {
        kind = OPEN_ARCH; wall = aw;
        float c = cornerA(r, aw, dw);
        float centre = wallCentre(r, aw);
        a = c + sign(centre - c) * (0.55 + 0.65);
        active = archway != 0;
    }
}

BROpening resolveOpening(int slot, BRRoom r, OpenDelta d)
{
    int bk, bw; float ba; bool bact;
    baseOpening(slot, r, bk, bw, ba, bact);
    BROpening o;
    o.slot = slot;
    o.kind = (d.kindOv > 0) ? d.kindOv : bk;
    o.wall = (d.wallOv > 0) ? (d.wallOv - 1) : bw;
    o.active = (d.activeOv == 1) ? true : ((d.activeOv == 2) ? false : bact);
    if (o.kind == OPEN_NONE) o.active = false;
    float w, h, s, c, ro, dp;
    kindDims(o.kind, style, w, h, s, c, ro, dp);
    float baseA = (d.wallOv > 0) ? wallCentre(r, o.wall) : ba;
    float L = brWallLength(r, o.wall);
    o.width = clamp(w + d.dw, 0.40, max(L - 0.05, 0.5));
    o.sill = brOpenToFloor(o.kind) ? 0.0 : clamp(s + d.dsill, 0.0, r.H - 0.6);
    if (o.kind == OPEN_FIREPLACE) o.sill = 0.0;
    o.height = clamp(h + d.dh, 0.5, max(r.H - o.sill - 0.02, 0.5));
    float2 e = brWallExtent(r, o.wall);
    float half = o.width * 0.5;
    o.a = clamp(baseA + d.da, e.x + half, e.y - half);
    o.cols = c; o.rows = ro; o.depth = dp;
    bool wantCurt = (curtains != 0) && brOpenIsGlazed(o.kind);
    o.curtains = (d.curtainOv == 1) ? true : ((d.curtainOv == 2) ? false : wantCurt);
    if (!brOpenIsGlazed(o.kind)) o.curtains = false;
    o.radiator = (radiators != 0) && brOpenIsWindow(o.kind) && o.sill >= 0.38;
    o.edited = d.edited > 0.5;
    o.alarms = 0;
    return o;
}

// --------------------------------------------------------------------------------------------
// PICKING -- in exactly the pixel space the canvas draws in.

struct Pick { int sel; int index; int handle; int surface; float grab; };   // surface: 0 plan, 1+w elevation

Pick pickAt(float2 px, ShellLayout L, BRRoom r, BROpening ops[SHELL_OPEN_MAX], int selType, int selIndex)
{
    Pick p; p.sel = SEL_NONE; p.index = -1; p.handle = H_NONE; p.surface = 0; p.grab = 0;
    float tol = 7.0;

    // 1. edge handles of the selected opening, in its own elevation
    if (selType == SEL_OPEN && selIndex >= 0 && selIndex < SHELL_OPEN_MAX)
    {
        BROpening o = ops[selIndex];
        if (o.active)
        {
            float4 er = shellOpenElevRect(L, o.wall, o.a, o.width, o.sill, o.height);
            float2 ay = shellElevAY(L, o.wall, px);
            if (shellInRect(px, er, tol))
            {
                float2 lo = shellElevPx(L, o.wall, o.a - o.width * 0.5, o.sill + o.height * 0.5);
                float2 hi = shellElevPx(L, o.wall, o.a + o.width * 0.5, o.sill + o.height * 0.5);
                float2 top = shellElevPx(L, o.wall, o.a, o.sill + o.height);
                float2 bot = shellElevPx(L, o.wall, o.a, o.sill);
                bool vertWall = (o.wall == WALL_N || o.wall == WALL_S);
                float dLo = vertWall ? abs(px.x - lo.x) : abs(px.y - lo.y);
                float dHi = vertWall ? abs(px.x - hi.x) : abs(px.y - hi.y);
                float dTop = vertWall ? abs(px.y - top.y) : abs(px.x - top.x);
                float dBot = vertWall ? abs(px.y - bot.y) : abs(px.x - bot.x);
                float best = tol; int h = H_NONE;
                if (dLo < best) { best = dLo; h = H_ALO; }
                if (dHi < best) { best = dHi; h = H_AHI; }
                if (dTop < best) { best = dTop; h = H_TOP; }
                if (dBot < best && !brOpenToFloor(o.kind) && o.kind != OPEN_FIREPLACE) { best = dBot; h = H_BOT; }
                if (h != H_NONE)
                {
                    p.sel = SEL_OPEN; p.index = selIndex; p.handle = h; p.surface = 1 + o.wall; p.grab = 0;
                    return p;
                }
            }
        }
    }

    // 2. opening bodies in the elevations, smallest first
    float bestArea = 1e12;
    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = ops[i];
        if (!o.active) continue;
        float4 er = shellOpenElevRect(L, o.wall, o.a, o.width, o.sill, o.height);
        float area = (er.z - er.x) * (er.w - er.y);
        if (shellInRect(px, er, 2.0) && area < bestArea)
        {
            bestArea = area;
            p.sel = SEL_OPEN; p.index = i; p.handle = H_MOVE; p.surface = 1 + o.wall;
            p.grab = shellElevAY(L, o.wall, px).x - o.a;
        }
    }
    if (p.sel != SEL_NONE) return p;

    // 3. opening cuts in the plan (through the wall band, plus the fireplace breast)
    [loop] for (int j = 0; j < SHELL_OPEN_MAX; j++)
    {
        BROpening o = ops[j];
        if (!o.active) continue;
        float depthIn = (o.kind == OPEN_FIREPLACE) ? o.depth + 0.5 : 0.25;
        float4 pr = shellPlanBand(L, r, o.wall, o.a - o.width * 0.5, o.a + o.width * 0.5, depthIn, -r.T);
        if (shellInRect(px, pr, 3.0))
        {
            float2 w = shellPlanWorld(L, px);
            p.sel = SEL_OPEN; p.index = j; p.handle = H_MOVE; p.surface = 0;
            p.grab = (brWallAlongX(o.wall) ? w.x : w.y) - o.a;
            return p;
        }
    }

    // 4. ceiling lines in the elevations
    [loop] for (int k = 0; k < 4; k++)
    {
        float2 span = shellWallSpan(L, k);
        float2 c0 = shellElevPx(L, k, span.x, L.H), c1 = shellElevPx(L, k, span.y, L.H);
        float4 cr = shellRectOf(c0, c1);
        if (shellInRect(px, cr, tol))
        {
            p.sel = SEL_CEIL; p.index = k; p.handle = H_CEIL; p.surface = 1 + k; p.grab = 0;
            return p;
        }
    }

    // 5. wall faces in the plan (interior face line through the wall band)
    [loop] for (int m = 0; m < 4; m++)
    {
        float2 span = shellWallSpan(L, m);
        float4 band = shellPlanBand(L, r, m, span.x, span.y, 0.0, -r.T);
        if (shellInRect(px, band, tol))
        {
            p.sel = SEL_WALL; p.index = m; p.handle = H_WALL; p.surface = 0; p.grab = 0;
            return p;
        }
    }
    return p;
}

// Which wall's surface (elevation or plan band) is under the pointer, and where along it.
bool wallUnder(float2 px, ShellLayout L, BRRoom r, out int wall, out float a, out float y, out bool elev)
{
    wall = -1; a = 0; y = 0; elev = false;
    [loop] for (int w = 0; w < 4; w++)
    {
        float4 er = shellElevRect(L, w);
        if (shellInRect(px, er, 4.0))
        {
            float2 ay = shellElevAY(L, w, px);
            wall = w; a = ay.x; y = ay.y; elev = true;
            return true;
        }
    }
    float2 wp = shellPlanWorld(L, px);
    float best = 0.6;     // metres from an interior face
    [loop] for (int k = 0; k < 4; k++)
    {
        float plane = brWallPlane(r, k);
        float along = brWallAlongX(k) ? wp.x : wp.y;
        float2 e = brWallExtent(r, k);
        float perp = brWallAlongX(k) ? abs(wp.y - plane) : abs(wp.x - plane);
        if (perp < best && along > e.x - 0.2 && along < e.y + 0.2)
        {
            best = perp; wall = k; a = along; y = 1.0;
        }
    }
    return wall >= 0;
}


// --------------------------------------------------------------------------------------------
// VERBS -- one implementation, two triggers: the key shortcuts and the inspector chips.
#define V_NONE      0
#define V_KIND      1
#define V_TOGGLE    2
#define V_CURTAIN   3
#define V_RESET     4
#define V_RESET_ALL 5
#define V_ADD_AT    6      // at a pointer position
#define V_ADD_WALL  7      // centred on the selected wall

int chipVerb(int chip, int selType)
{
    if (selType == SEL_OPEN) return (chip == 0) ? V_KIND : (chip == 1) ? V_TOGGLE : (chip == 2) ? V_CURTAIN : (chip == 3) ? V_RESET : V_NONE;
    if (selType == SEL_WALL) return (chip == 0) ? V_ADD_WALL : (chip == 3) ? V_RESET : V_NONE;
    if (selType == SEL_CEIL) return (chip == 3) ? V_RESET : V_NONE;
    return (chip == 3) ? V_RESET_ALL : V_NONE;
}

void applyVerb(int verb, inout OpenDelta deltas[SHELL_OPEN_MAX], inout BRRec roomDelta, inout int selType, inout int selIndex,
               BROpening ops[SHELL_OPEN_MAX], BRRoom room, ShellLayout L, float2 pointerPx)
{
    if (verb == V_RESET_ALL)
    {
        [unroll] for (int i = 0; i < SHELL_OPEN_MAX; i++) deltas[i] = zeroDelta();
        roomDelta.dims = 0; roomDelta.look = 0;
        return;
    }
    if (verb == V_ADD_AT || verb == V_ADD_WALL)
    {
        int uw = -1; float ua = 0, uy = 0; bool ue = false;
        bool ok = false;
        if (verb == V_ADD_AT) ok = wallUnder(pointerPx, L, room, uw, ua, uy, ue);
        else if (selType == SEL_WALL && selIndex >= 0) { uw = selIndex; ua = wallCentre(room, uw); ok = true; }
        if (!ok) return;
        int slot = -1;
        [loop] for (int si = SHELL_OPEN_MAX - 1; si >= 0; si--) if (!ops[si].active) slot = si;
        if (slot < 0) return;
        OpenDelta d = zeroDelta();
        d.kindOv = styleWindowKind(style);
        d.wallOv = uw + 1;
        d.activeOv = 1;
        d.da = snapTo(ua, snap) - wallCentre(room, uw);
        deltas[slot] = d;
        selType = SEL_OPEN; selIndex = slot;
        return;
    }
    if (selType == SEL_OPEN && selIndex >= 0 && selIndex < SHELL_OPEN_MAX)
    {
        OpenDelta d = deltas[selIndex];
        BROpening o = ops[selIndex];
        if (verb == V_KIND)
        {
            int k = o.kind + 1; if (k >= OPEN_KIND_COUNT) k = 1;
            d.kindOv = k; d.dw = 0; d.dh = 0; d.dsill = 0;
        }
        else if (verb == V_TOGGLE)  d.activeOv = o.active ? 2 : 1;
        else if (verb == V_CURTAIN) d.curtainOv = o.curtains ? 2 : 1;
        else if (verb == V_RESET)   d = zeroDelta();
        deltas[selIndex] = d;
        return;
    }
    if ((selType == SEL_WALL || selType == SEL_CEIL) && verb == V_RESET)
    {
        roomDelta.dims = 0; roomDelta.look = 0;
    }
}

// --------------------------------------------------------------------------------------------

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = (_Resolution.x >= 64.0) ? _Resolution.xy : float2(1280.0, 800.0);

    // ---- persistent state: editor + deltas (sanitised, initialised once per version)
    BRRec ed = Shell[SHELL_EDITOR];
    BRRec frozenRec = Shell[REC_FROZEN];
    bool fresh = !(abs(ed.head.x - ROLE_SHELL_ED) < 0.5) || abs(sane(ed.head.w) - PLAN_VERSION) > 0.01;
    if (fresh)
    {
        BRRec z; z.head = float4(ROLE_DELTA, 0, 0, 0); z.dims = 0; z.look = 0; z.meta = 0;
        [loop] for (int i = SHELL_DELTA_ROOM; i < SHELL_RECORDS; i++) Shell[i] = z;
        ed.head = float4(ROLE_SHELL_ED, SEL_NONE, -1, PLAN_VERSION);
        ed.dims = 0; ed.look = 0; ed.meta = 0;
        frozenRec.head = float4(ROLE_SHELL_ED, 0, 0, 0); frozenRec.dims = 0; frozenRec.look = 0; frozenRec.meta = 0;
    }
    BRRec roomDelta = Shell[SHELL_DELTA_ROOM];
    roomDelta.dims = float4(sane(roomDelta.dims.x), sane(roomDelta.dims.y), sane(roomDelta.dims.z), sane(roomDelta.dims.w));
    roomDelta.look.x = sane(roomDelta.look.x);
    OpenDelta deltas[SHELL_OPEN_MAX];
    [unroll] for (int di = 0; di < SHELL_OPEN_MAX; di++) deltas[di] = readDelta(Shell[SHELL_DELTA_OPEN0 + di]);

    int selType = (int)round(sane(ed.head.y));
    int selIndex = (int)round(sane(ed.head.z));
    int dragActive = (int)round(sane(ed.dims.x));
    int handle = (int)round(sane(ed.dims.y));
    int surface = (int)round(sane(ed.dims.z));
    float grab = sane(ed.dims.w);
    float4 startVals = float4(sane(ed.look.x), sane(ed.look.y), sane(ed.look.z), sane(ed.look.w));
    float2 startPx = float2(sane(frozenRec.look.x), sane(frozenRec.look.y));
    float4 frozen = float4(sane(frozenRec.dims.x), sane(frozenRec.dims.y), sane(frozenRec.dims.z), sane(frozenRec.dims.w));
    float2 frozenRef = float2(sane(frozenRec.look.z), sane(frozenRec.look.w));
    uint lastSeq = asuint(ed.meta.x);
    float handled = sane(ed.meta.y);

    // ---- resolve current state (before this cook's events) for picking
    BRRoom room = baseRoom(roomDelta);
    BROpening ops[SHELL_OPEN_MAX];
    [unroll] for (int oi = 0; oi < SHELL_OPEN_MAX; oi++) ops[oi] = resolveOpening(oi, room, deltas[oi]);
    ShellLayout L = shellLayout(res, room, (handle != H_NONE) ? frozen : float4(0, 0, 0, 0), frozenRef);

    // ---- events, each consumed once by sequence (with the host-counter-reset guard)
    uint n = _ViewportEventCount;
    uint ringMax = 0u;
    [loop] for (uint ri = 0u; ri < n; ri++) ringMax = max(ringMax, _ViewportEvents[ri].sequence);
    if (n > 0u && ringMax < lastSeq) lastSeq = 0u;
    uint newLast = lastSeq;
    BRRec diag = Shell[13];

    [loop] for (uint ei = 0u; ei < n; ei++)
    {
        // One exit per event: FXC silently drops stores made before a mid-body `continue`.
        ViewportEvent ev = _ViewportEvents[ei];
        bool isFresh = ev.sequence > lastSeq || (lastSeq - ev.sequence) > (1u << 20);
        if (isFresh)
        {
            newLast = (ev.sequence > lastSeq) ? max(newLast, ev.sequence) : ev.sequence;
            handled += 1.0;
            // diagnostics: the most recent fresh event, as delivered
            diag.head = float4(ROLE_NONE, ev.type, ev.code, ev.phase);
            diag.dims = float4(ev.flags, ev.sequence, ev.modifiers, ev.value);
            if (ev.type == 4u) diag.look = float4(ev.code, ev.phase, ev.flags, ev.sequence);
            float2 px = ev.position * res;
            bool rep = (ev.flags & VIEWPORT_EVENT_FLAG_REPEAT) != 0u || ev.phase == 2u;

            // ---- left press: pick, select, arm a drag
            if (ev.type == 2u && ev.code == 0u && ev.phase == 1u)
            {
                ShellLayout Lfit = shellLayout(res, room, float4(0, 0, 0, 0), float2(0, 0));
                int chip = shellChipAt(Lfit, px);
                if (chip >= 0)
                {
                    applyVerb(chipVerb(chip, selType), deltas, roomDelta, selType, selIndex, ops, room, Lfit, px);
                    handle = H_NONE; dragActive = 0;
                    room = baseRoom(roomDelta);
                    [unroll] for (int rc = 0; rc < SHELL_OPEN_MAX; rc++) ops[rc] = resolveOpening(rc, room, deltas[rc]);
                }
                else
                {
                    Pick pk = pickAt(px, Lfit, room, ops, selType, selIndex);
                    selType = pk.sel; selIndex = pk.index;
                    handle = pk.handle; surface = pk.surface; grab = pk.grab;
                    dragActive = 0;
                    startPx = px;
                    frozen = float4(1.0, Lfit.s, Lfit.o.x, Lfit.o.y);
                    frozenRef = float2(Lfit.xRef, Lfit.zRef);
                    if (pk.sel == SEL_OPEN)
                    {
                        BROpening o = ops[pk.index];
                        startVals = float4(o.a, o.width, o.height, o.sill);
                    }
                    else if (pk.sel == SEL_WALL)
                    {
                        int w = pk.index;
                        float v = (w == WALL_S) ? roomDelta.dims.z : (w == WALL_E) ? roomDelta.dims.y : (w == WALL_N) ? roomDelta.dims.w : roomDelta.dims.x;
                        startVals = float4(v, 0, 0, 0);
                    }
                    else if (pk.sel == SEL_CEIL)
                    {
                        startVals = float4(roomDelta.look.x, 0, 0, 0);
                    }
                }
            }
            // ---- left release without a drag: a click, disarm
            else if (ev.type == 2u && ev.code == 0u && ev.phase == 3u)
            {
                if (dragActive == 0) { handle = H_NONE; frozen.x = 0; }
            }
            // ---- drag gesture: begin arms, update/end apply, end/cancel release
            else if (ev.type == 5u && ev.code == 3u)
            {
                if (ev.phase == 5u && handle != H_NONE) dragActive = 1;
                if ((ev.phase == 6u || ev.phase == 7u) && dragActive > 0)
                {
                    ShellLayout Ld = shellLayout(res, room, frozen, frozenRef);
                    if (selType == SEL_OPEN && selIndex >= 0)
                    {
                        int i = selIndex;
                        OpenDelta d = deltas[i];
                        BROpening o = ops[i];
                        int bk, bw; float ba; bool bact;
                        baseOpening(i, room, bk, bw, ba, bact);
                        float kw, kh, ks, kc, kr, kd;
                        kindDims(o.kind, style, kw, kh, ks, kc, kr, kd);
                        if (handle == H_MOVE)
                        {
                            int tw = o.wall; float ta = 0; float ty = 0; bool onElev = false;
                            int uw; float ua, uy; bool ue;
                            if (wallUnder(px, Ld, room, uw, ua, uy, ue)) { tw = uw; onElev = ue; }
                            float2 ay = (surface > 0 || onElev) ? shellElevAY(Ld, tw, px) : float2(0, 0);
                            if (surface == 0 && !onElev)
                            {
                                float2 wp = shellPlanWorld(Ld, px);
                                ay = float2(brWallAlongX(tw) ? wp.x : wp.y, 0.0);
                            }
                            ta = snapTo(ay.x - grab, snap);
                            if (tw != o.wall)
                            {
                                // Re-host. The vertical slide restarts from where the pointer
                                // entered the new wall: the old wall's elevation frame means
                                // nothing here, and reusing it throws the sill across the room.
                                d.wallOv = tw + 1;
                                grab = 0.0;
                                surface = onElev ? 1 + tw : 0;
                                startPx = px;
                                startVals.w = o.sill;
                            }
                            float baseA = (d.wallOv > 0) ? wallCentre(room, tw) : ba;
                            d.da = ta - baseA;
                            // in an elevation, a window also slides vertically (its sill)
                            if (surface > 0 && onElev && tw == o.wall && !brOpenToFloor(o.kind) && o.kind != OPEN_FIREPLACE)
                            {
                                float2 ay0 = shellElevAY(Ld, o.wall, startPx);
                                float newSill = snapTo(startVals.w + (ay.y - ay0.y), snap);
                                d.dsill = newSill - ks;
                            }
                        }
                        else if (handle == H_ALO || handle == H_AHI)
                        {
                            float2 ay = shellElevAY(Ld, o.wall, px);
                            float edgeA = snapTo(ay.x, snap);
                            float lo = startVals.x - startVals.y * 0.5, hi = startVals.x + startVals.y * 0.5;
                            if (handle == H_ALO) lo = min(edgeA, hi - 0.4); else hi = max(edgeA, lo + 0.4);
                            float baseA = (d.wallOv > 0) ? wallCentre(room, o.wall) : ba;
                            d.dw = (hi - lo) - kw;
                            d.da = (lo + hi) * 0.5 - baseA;
                        }
                        else if (handle == H_TOP)
                        {
                            float2 ay = shellElevAY(Ld, o.wall, px);
                            float head = snapTo(ay.y, snap);
                            d.dh = (head - o.sill) - kh;
                        }
                        else if (handle == H_BOT)
                        {
                            float2 ay = shellElevAY(Ld, o.wall, px);
                            float head = startVals.w + startVals.z;
                            float sill = clamp(snapTo(ay.y, snap), 0.0, head - 0.5);
                            d.dsill = sill - ks;
                            d.dh = (head - sill) - kh;
                        }
                        deltas[i] = d;
                    }
                    else if (selType == SEL_WALL && selIndex >= 0)
                    {
                        float2 w0 = shellPlanWorld(Ld, startPx), w1 = shellPlanWorld(Ld, px);
                        int w = selIndex;
                        if (w == WALL_E || w == WALL_W)
                        {
                            float v = snapTo(startVals.x + (w1.x - w0.x), snap);
                            if (w == WALL_E) roomDelta.dims.y = v; else roomDelta.dims.x = v;
                        }
                        else
                        {
                            float v = snapTo(startVals.x + (w1.y - w0.y), snap);
                            if (w == WALL_N) roomDelta.dims.w = v; else roomDelta.dims.z = v;
                        }
                    }
                    else if (selType == SEL_CEIL && selIndex >= 0)
                    {
                        float2 a0 = shellElevAY(Ld, selIndex, startPx), a1 = shellElevAY(Ld, selIndex, px);
                        roomDelta.look.x = snapTo(startVals.x + (a1.y - a0.y), snap);
                    }
                    // re-resolve so the next event in this cook sees the edit
                    room = baseRoom(roomDelta);
                    [unroll] for (int ri2 = 0; ri2 < SHELL_OPEN_MAX; ri2++) ops[ri2] = resolveOpening(ri2, room, deltas[ri2]);
                }
                if (ev.phase == 7u || ev.phase == 8u) { dragActive = 0; handle = H_NONE; frozen.x = 0; }
            }
            // ---- keys (non-repeat presses)
            else if (ev.type == 4u && ev.phase == 1u && !rep)
            {
                uint key = ev.code;
                int verb = V_NONE;
                if (key == 48u) { selType = SEL_NONE; selIndex = -1; }                 // Escape
                else if (key == 32u) verb = V_RESET_ALL;                               // 0
                else if (key == 1u)  verb = V_ADD_AT;                                  // A
                else if (key == 11u) verb = V_KIND;                                    // K
                else if (key == 24u) verb = V_TOGGLE;                                  // X
                else if (key == 3u)  verb = V_CURTAIN;                                 // C
                else if (key == 18u) verb = V_RESET;                                   // R
                applyVerb(verb, deltas, roomDelta, selType, selIndex, ops, room, L, _ViewportPointerPosition * res);
                room = baseRoom(roomDelta);
                [unroll] for (int ri4 = 0; ri4 < SHELL_OPEN_MAX; ri4++) ops[ri4] = resolveOpening(ri4, room, deltas[ri4]);
            }
        }
    }

    // ---- final resolve + alarms
    room = baseRoom(roomDelta);
    [unroll] for (int fi = 0; fi < SHELL_OPEN_MAX; fi++) ops[fi] = resolveOpening(fi, room, deltas[fi]);
    int wallAlarms[4] = { 0, 0, 0, 0 };
    int wallCount[4] = { 0, 0, 0, 0 };
    int alarmTotal = 0;
    [loop] for (int ai = 0; ai < SHELL_OPEN_MAX; ai++)
    {
        BROpening o = ops[ai];
        if (!o.active) continue;
        int al = 0;
        float2 e = brWallExtent(room, o.wall);
        float lo = o.a - o.width * 0.5, hi = o.a + o.width * 0.5;
        float trimClear = (o.kind == OPEN_FIREPLACE) ? 0.05 : 0.12;
        if (lo - e.x < trimClear || e.y - hi < trimClear) al |= ALARM_CORNER;
        float headLimit = room.H - max(room.crown, 0.02) - 0.03;
        if (o.sill + o.height > headLimit) al |= ALARM_HEAD;
        if (o.width > brWallLength(room, o.wall) - 0.25) al |= ALARM_TOO_WIDE;
        [loop] for (int bj = 0; bj < SHELL_OPEN_MAX; bj++)
        {
            if (bj == ai) continue;
            BROpening q = ops[bj];
            if (!q.active || q.wall != o.wall) continue;
            float gap = abs(q.a - o.a) - (q.width + o.width) * 0.5;
            if (gap < 0.10) al |= ALARM_OVERLAP;
        }
        ops[ai].alarms = al;
        wallAlarms[o.wall] |= al;
        wallCount[o.wall] += 1;
        if (al != 0) alarmTotal += 1;
    }

    // ---- publish
    BRRec rr;
    rr.head = float4(ROLE_ROOM, room.style, room.floorPattern, room.flags);
    rr.dims = float4(room.x0, room.x1, room.z0, room.z1);
    rr.look = float4(room.H, room.T, room.baseH, room.crown);
    rr.meta = float4(room.railH, room.plankW, PLAN_VERSION, handled);
    Shell[SHELL_ROOM] = rr;

    [unroll] for (int wi = 0; wi < 4; wi++)
    {
        BRRec wr;
        float2 e = brWallExtent(room, wi);
        float2 nn = brWallNormal(wi), tt = brWallTangent(wi);
        wr.head = float4(ROLE_WALL, wi, -1, 0);
        wr.dims = float4(e.x, e.y, brWallPlane(room, wi), e.y - e.x);
        wr.look = float4(nn.x, nn.y, tt.x, tt.y);
        wr.meta = float4(wallCount[wi], wallAlarms[wi], 0, 1);
        Shell[SHELL_WALL0 + wi] = wr;
    }

    [unroll] for (int pi = 0; pi < SHELL_OPEN_MAX; pi++)
    {
        BROpening o = ops[pi];
        BRRec orr;
        orr.head = float4(ROLE_OPEN, o.kind, o.wall, pi);
        orr.dims = float4(o.a, o.width, o.height, o.sill);
        orr.look = float4(o.cols, o.rows, o.depth, o.curtains ? 1.0 : 0.0);
        orr.meta = float4(o.radiator ? 1.0 : 0.0, o.edited ? 1.0 : 0.0, o.active ? 1.0 : 0.0, o.alarms);
        Shell[SHELL_OPEN0 + pi] = orr;
        Shell[SHELL_DELTA_OPEN0 + pi] = writeDelta(deltas[pi]);
    }

    diag.head.x = ROLE_NONE;
    Shell[13] = diag;

    frozenRec.head = float4(ROLE_SHELL_ED, 1, 0, 0);
    frozenRec.dims = (handle != H_NONE) ? frozen : float4(0, 0, 0, 0);
    frozenRec.look = float4(startPx, frozenRef);
    frozenRec.meta = float4(res, alarmTotal, 0);
    Shell[REC_FROZEN] = frozenRec;

    ed.head = float4(ROLE_SHELL_ED, selType, selIndex, PLAN_VERSION);
    ed.dims = float4(dragActive, handle, surface, grab);
    ed.look = startVals;
    ed.meta = float4(asfloat(newLast), handled, (float)n, (float)alarmTotal);
    Shell[SHELL_EDITOR] = ed;

    roomDelta.head = float4(ROLE_DELTA, 1, 0, 0);
    roomDelta.meta = float4((abs(roomDelta.dims.x) + abs(roomDelta.dims.y) + abs(roomDelta.dims.z) + abs(roomDelta.dims.w) + abs(roomDelta.look.x)) > 1e-5 ? 1.0 : 0.0, 0, 0, 0);
    Shell[SHELL_DELTA_ROOM] = roomDelta;
}
