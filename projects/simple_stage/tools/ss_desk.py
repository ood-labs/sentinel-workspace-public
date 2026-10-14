"""Generate the SIMPLE STAGE desk: the looks and a full programmer on one panel, no Push 2 needed.

One control table drives the Module and the Surface, so they can never disagree:
    modules/SS_Desk/manifest.yaml       viewport panel controls (pads, faders, readouts), normalized rects
    modules/SS_Desk/desk_layout.hlsli   each control's kind, bank, tier / fixture type, slot, flags, glyph and draw
                                        budget, the panes and the fixture map's drawing, for layout.hlsl
    scripts/show/desk_layout.luau       control index -> id, kind, label and action, for desk_panel.luau
then regenerates the desk's type tables with tools/il_type.py (labels.txt -> _labels.generated.hlsli, and
_ui.generated.hlsli: control indices and rects stamped with the manifest hash).

The desk, top to bottom:
    transport and holds        TAP PLAY STOP SYNC, tempo, bar and beat, BLACKOUT and STROBE
    the looks                  FULL LOOKS | STATIC, EFFECTS | COLOR, SEQUENCES (RIG / BEAMS / STROBES / BATTENS) | LIVE
    the programmer             the fixture map (every light, where it hangs), the selection groups and layer filter,
                               the attribute banks and eight faders, STORE / UPDATE / UNDO / RESET / FX OFF / RELEASE

The fixture map is the plot seen from above, the audience at the bottom: the wall's twelve runs, the floor strobes,
the back row, the booth, the front row and the truss strobes. Its pads sit where the fixtures hang (tools/ss_stage.py),
so a click picks the light you are looking at.

ONE COLOUR LANGUAGE. Amber is what is live or picked: a lit look, the selection, the beat, a running clock, an armed
STORE. Red is BLACKOUT. Each look bank carries an identity hue, an effect's energy tier is a 1-4 step mark, and a
fixture pad shows the colour its programmed palette slot plays.

    python tools/ss_desk.py
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import ss_looks
import ss_show as S

ROOT = Path(__file__).resolve().parents[1]
W, H = 1600, 1000
KIND = {"pad": 0, "readout": 1, "header": 2, "status": 3, "tier": 4, "fader": 5, "fixture": 6, "group": 7, "tab": 8,
        "value": 9}
BANK = {"complete": 1, "static": 2, "effects": 3, "color": 4, "seq": 5}       # layout.hlsl bankHue()
# flags (layout.hlsl DF_*): the BLACKOUT hold (and a sequence bank's BLACKOUT pad), the STROBE hold, STORE, a white
# toggle (HIGHLIGHT)
ALARM, FLASH, ARM, TOGGLE = 2, 4, 8, 16
# glyphs (layout.hlsl DI_*)
ICON = {"play": 1, "stop": 2, "up": 3, "down": 4, "left": 5, "right": 6, "sync": 7, "beat": 8}
# Draw-list slots each control kind may use (layout.hlsl draws a control into its own run of slots).
BUDGET = {"pad": 10, "readout": 0, "header": 3, "status": 0, "tier": 7, "fader": 8, "fixture": 8, "group": 3,
          "tab": 3, "value": 2}

controls: list[dict] = []


def add(cid, kind, rect, label, action=None, bank=0, sub=0, slot=0, flags=0, icon=0):
    x0, y0, x1, y1 = rect
    assert x1 > x0 and y1 > y0, cid
    controls.append({"id": cid, "kind": kind, "rect": (x0 / W, y0 / H, x1 / W, y1 / H), "px": rect, "label": label,
                     "action": action, "bank": bank, "sub": sub, "slot": slot, "flags": flags, "icon": icon})


BUILT = ss_looks.build()
TITLES = {k: [name for name, _ in BUILT[k]] for k in ("static", "effects", "color", "complete", "sequence")}

# The desk's panes (drawn plates), in layout pixels, 12 px margins and 8 px gutters. Content sits 8 px inside.
PANES = [(12, 12, 1588, 96),
         (12, 104, 796, 270), (804, 104, 1588, 270),        # FULL LOOKS | STATIC
         (12, 278, 796, 444), (804, 278, 1588, 444),        # EFFECTS | COLOR
         (12, 452, 796, 618), (804, 452, 1588, 618),        # SEQUENCES | LIVE + CAMERA
         (12, 626, 1588, 988)]                              # PROGRAMMER
EXTRA = {"TITLE": (20, 20, 200, 88), "LIVE_HEAD": (812, 460, 1580, 484), "CAMERA": (812, 556, 902, 604)}

# --- transport and holds --------------------------------------------------------------------------------------------
TOP, TH = 20, 68
x = 216
for cid, label in (("tap", "TAP"), ("play", "PLAY"), ("stop", "STOP"), ("sync", "SYNC")):
    add(cid, "pad", (x, TOP, x + 104, TOP + TH), label, ("tempo", cid), icon=ICON["beat" if cid == "tap" else cid])
    x += 112
add("bpm", "readout", (672, TOP, 900, TOP + TH), "---.- BPM")
add("beat", "readout", (908, TOP, 1150, TOP + TH), "BAR - BEAT -")
add("blackout", "pad", (1236, TOP, 1404, TOP + TH), "BLACKOUT", ("hold", "blackout"), flags=ALARM)
add("strobe", "pad", (1412, TOP, 1580, TOP + TH), "STROBE", ("hold", "strobe"), flags=FLASH)

# --- the look banks ---------------------------------------------------------------------------------------------------
# Four banks of 16 and the sequences, each two rows of eight in two groups of four (a wider middle gutter), which is how
# the energy tiers fall.
COLS = {"left": 20, "right": 812}
COLW, GAP, MID, PADH = 768, 6, 18, 56
PADW = (COLW - 6 * GAP - MID) / 8


def tier(slot):
    return min(4, (slot - 1) // 4 + 1)            # 1 CALM, 2 GROOVE, 3 BUILD, 4 CRAZY


def bank(kind, header, col, top, titles, action, tier_of=lambda s: 0, flags_of=lambda s: 0, head_w=COLW):
    x0 = COLS[col]
    add(f"head_{kind}", "header", (x0, top + 8, x0 + head_w, top + 32), header, bank=BANK[kind])
    for slot in range(1, 17):
        r, c = divmod(slot - 1, 8)
        px, py = x0 + c * (PADW + GAP) + (MID - GAP if c >= 4 else 0), top + 40 + r * (PADH + GAP)
        add(f"{kind}_{slot}", "pad", (px, py, px + PADW, py + PADH), titles[slot - 1], action(slot), bank=BANK[kind],
            sub=tier_of(slot), slot=slot, flags=flags_of(slot))


def recall(kind):
    return lambda slot: ("preset", kind, str(slot))


bank("complete", "FULL LOOKS", "left", 104, TITLES["complete"], recall("complete"), tier)
bank("static", "STATIC", "right", 104, TITLES["static"], recall("static"))
tx = COLS["left"] + COLW - (4 * 104 + 3 * 6)
bank("effects", "EFFECTS", "left", 278, TITLES["effects"], recall("effects"), tier, head_w=tx - 6 - COLS["left"])
for i, name in enumerate(ss_looks.TIERS):
    add(f"tier_{name.lower()}", "tier", (tx + i * 110, 286, tx + i * 110 + 104, 310), name, sub=i + 1)
bank("color", "COLOR", "right", 278, TITLES["color"], recall("color"))
# SEQUENCES: one bank of pads, played on every fixture type (RIG) or one type's part (BEAMS, STROBES, BATTENS); the tabs
# in its header pick which. Slot 16 is BLACKOUT.
sx = COLS["left"] + COLW - (4 * 92 + 3 * 6)
bank("seq", "SEQUENCES", "left", 452, TITLES["sequence"], lambda s: ("seqpad", str(s)),
     lambda s: tier(s) if s < 16 else 0, lambda s: ALARM if s == 16 else 0, head_w=sx - 6 - COLS["left"])
for i, (cid, label) in enumerate((("rig", "RIG"), ("beams", "BEAMS"), ("strobes", "STROBES"), ("battens", "BATTENS"))):
    add(f"seqk_{cid}", "tab", (sx + i * 98, 455, sx + i * 98 + 92, 488), label, ("seqkind", cid), bank=BANK["seq"])

# --- LIVE: the look that is up, and the camera ------------------------------------------------------------------------
add("legend_full", "status", (812, 492, 1400, 548), "FULL LOOK = STATIC + EFFECTS + COLOR")
add("seq_live", "status", (1408, 492, 1580, 548), "none")
cam = [("cam_left", "<", "left"), ("cam_right", ">", "right"), ("cam_up", "UP", "up"), ("cam_down", "DOWN", "down"),
       ("cam_in", "IN", None), ("cam_out", "OUT", None), ("cam_home", "HOME", None)]
cw = (1580 - 910 - 6 * 6) / 7
for i, (cid, label, icon) in enumerate(cam):
    px = 910 + i * (cw + 6)
    add(cid, "pad", (px, 556, px + cw, 604), label, ("camera", cid[4:]), icon=ICON[icon] if icon else 0)

# --- the programmer ---------------------------------------------------------------------------------------------------
add("head_fixtures", "header", (20, 634, 560, 658), "FIXTURES")
add("head_select", "header", (572, 634, 932, 658), "SELECT")
add("head_program", "header", (944, 634, 1580, 658), "PROGRAM")

# The fixture map: the plot from above, the wall at the top, the audience below. x keeps the stage's own scale; each
# line of fixtures (tools/ss_stage.py's families) sits on its own row, in the order the stage runs back to front: the
# wall, the floor strobes along the deck's back edge, the back row, the booth, the front row and its strobes.
MAP = (20, 662, 560, 940)
MC = (MAP[0] + MAP[2]) / 2
# family: (row centre y, pad width, pad height, short-name prefix). Every pad is at least 32 px tall, the hit-target
# minimum at the desk's 1600 x 1000 layout.
ROWS = {20: (700, 34, 52, "W"), 11: (744, 54, 32, "FS"), 1: (790, 54, 34, "B"), 0: (870, 54, 34, "F"),
        10: (906, 58, 32, "TS")}
SX = (MAP[2] - MAP[0] - 24 - 54) / (2 * max(abs(f["pos"][0]) for f in S.LIGHTS))   # px per metre
SHORT = {}


def short(f):
    return ROWS[f["family"]][3] + str(f["index"] + 1)


for f in S.LIGHTS:
    cy, w, h, _ = ROWS[f["family"]]
    cx = MC + f["pos"][0] * SX
    name = short(f)
    SHORT[f["slot"]] = name
    add(f"fx_{f['slot']}", "fixture", (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), name, ("fixture", str(f["slot"])),
        sub=f["kind"], slot=f["slot"])
# The trusses the rows hang from (the wall, back and front lines), the deck and the booth, drawn under the pads.
HALF_SPAN = 6.0                                             # tools/ss_stage.py SPAN / 2
MAP_TRUSS_X = (MC - HALF_SPAN * SX, MC + HALF_SPAN * SX)
MAP_TRUSS_Y = (ROWS[20][0] - ROWS[20][2] / 2 - 4, ROWS[1][0], ROWS[0][0])
MAP_DECK = (MC - 4.0 * SX, ROWS[11][0] - 14, MC + 4.0 * SX, ROWS[0][0] + 26)     # ss_stage.hlsli SS_DECK
MAP_BOOTH = (MC - 1.2 * SX, 826, MC + 1.2 * SX, 846)                               # SS_BOOTH, between the rows
EXTRA["AUDIENCE"] = (MAP[0], 926, MAP[2], 940)

# Selection groups (static_rig in_group, SS_Lighting's canvas buttons) and the layer filter.
GROUPS = [("all", "ALL"), ("movers", "HEADS"), ("strobes", "STROBES"), ("bars", "WALL"),
          ("front_row", "FRONT ROW"), ("back_row", "BACK ROW"), ("truss_strobes", "TRUSS STROBES"),
          ("floor_strobes", "FLOOR STROBES"),
          ("left", "LEFT"), ("right", "RIGHT"), ("inner", "INNER"), ("outer", "OUTER"),
          ("odd", "ODD"), ("even", "EVEN"), ("middle", "MIDDLE"), ("none", "CLEAR")]
gw, gh = (360 - 3 * 6) / 4, (194 - 3 * 6) / 4
for i, (gid, label) in enumerate(GROUPS):
    r, c = divmod(i, 4)
    px, py = 572 + c * (gw + 6), 666 + r * (gh + 6)
    add(f"grp_{gid}", "group", (px, py, px + gw, py + gh), label, ("group", gid))
LAYERS = [("all", "ALL LAYERS"), ("move", "MOVE"), ("beam", "BEAM"), ("halo", "HALO"),
          ("tube", "TUBE"), ("plates", "PLATES"), ("pixels", "PIXELS"), ("chase", "CHASE")]
lh = (72 - 4) / 2
for i, (lid, label) in enumerate(LAYERS):
    r, c = divmod(i, 4)
    px, py = 572 + c * (gw + 6), 868 + r * (lh + 4)
    add(f"lay_{lid}", "group", (px, py, px + gw, py + lh), label, ("layer", lid), sub=1)

# Attribute banks (attribute_catalog banks, the Push's knob banks) and the faders that program them.
BANKS = ["POSITION", "LEVELS", "COLOR", "MOVE FX", "CHASE", "LOOK", "CLOCK"]
tw = (636 - 6 * 6) / 7
for i, label in enumerate(BANKS):
    px = 944 + i * (tw + 6)
    add(f"bank_{i + 1}", "tab", (px, 663, px + tw, 696), label, ("bank", str(i + 1)))
# Each fader: its attribute's name above (fcap), the fader (the host maps its whole rect, bottom 0 to top 1) and the
# selection's value below (fval). The Surface names and values them for the bank and the selection.
fw = (636 - 7 * 6) / 8
for i in range(8):
    px = 944 + i * (fw + 6)
    add(f"fcap_{i + 1}", "value", (px, 702, px + fw, 722), "--", sub=1, slot=i + 1)
for i in range(8):
    px = 944 + i * (fw + 6)
    add(f"fader_{i + 1}", "fader", (px, 726, px + fw, 880), f"FADER {i + 1}", ("fader", str(i + 1)), slot=i + 1)
for i in range(8):
    px = 944 + i * (fw + 6)
    add(f"fval_{i + 1}", "value", (px, 884, px + fw, 904), "--", slot=i + 1)
# STORE arms the next look pad; HIGHLIGHT (SS_Lighting's own) puts the selected fixtures at full open white so the one
# being programmed can be found on the rig.
ACTIONS = [("store", "STORE", ARM), ("update", "UPDATE", 0), ("undo", "UNDO", 0), ("reset", "RESET", 0),
           ("fxoff", "FX OFF", 0), ("highlight", "HIGHLIGHT", TOGGLE), ("release", "RELEASE", 0)]
aw = (636 - (len(ACTIONS) - 1) * 6) / len(ACTIONS)
for i, (aid, label, flags) in enumerate(ACTIONS):
    px = 944 + i * (aw + 6)
    add(f"act_{aid}", "pad", (px, 907, px + aw, 940), label, ("act", aid), flags=flags)
add("status", "status", (20, 948, 1100, 980), "DESK READY")
add("sel_info", "status", (1108, 948, 1580, 980), "NOTHING SELECTED")

# --- checks -------------------------------------------------------------------------------------------------------------
assert len(controls) <= 256, len(controls)
for c in controls:
    assert len(c["label"].encode()) <= 63, f"{c['id']} label over 63 bytes"
# The host hit-tests the first control under the pointer, so no two may overlap.
for i, a in enumerate(controls):
    for b in controls[i + 1:]:
        (ax0, ay0, ax1, ay1), (bx0, by0, bx1, by1) = a["rect"], b["rect"]
        assert ax1 <= bx0 or bx1 <= ax0 or ay1 <= by0 or by1 <= ay0, f"{a['id']} overlaps {b['id']}"
for c in controls:
    x0, y0, x1, y1 = c["px"]
    assert 0 <= x0 and x1 <= W and 0 <= y0 and y1 <= H, c["id"]
SPAN = []
_at = 0
for c in controls:
    SPAN.append(_at)
    _at += BUDGET[c["kind"]]
SPAN_TOTAL = _at
assert SPAN_TOTAL < 3600, SPAN_TOTAL           # il_draw IL_DL_MAXCMD 4096, with room for the layout's own plates


def manifest() -> str:
    lines = ["# Generated by tools/ss_desk.py; edit the generator, not this file.",
             "name: SIMPLE STAGE / Desk", "version: '1.0'", "mode: generator", f"resolution: [{W}, {H}]",
             "compile_optimization: fast_compile",
             "panel:", "  mode: canvas", "  output: Desk", "  resolution: follow_panel",
             "# IBM Plex Sans Condensed + IBM Plex Mono, SIL OFL 1.1 (_shared/type/IBM_PLEX_OFL.txt)",
             "assets:", "  - { name: type, type: texture, file: ../_shared/type/il_type.png, srgb: false }",
             "viewport:",
             '  hint: "Click a look to play it. Click fixtures on the map (or a group), pick a bank and drag the '
             'faders; STORE then a pad keeps it."',
             "  panel: true", "  controls:"]
    for c in controls:
        r = ", ".join(f"{v:.5f}" for v in c["rect"])
        if c["kind"] in ("pad", "fixture", "group", "tab"):
            lines.append(f'    - {{id: {c["id"]}, kind: pad, mode: momentary, rect: [{r}], label: "{c["label"]}"}}')
        elif c["kind"] == "fader":
            lines.append(f'    - {{id: {c["id"]}, kind: fader, rect: [{r}], label: "{c["label"]}"}}')
        else:
            lines.append(f'    - {{id: {c["id"]}, kind: readout, rect: [{r}], label: "{c["label"]}"}}')
    lines += ["buffers:", "  - { name: dl, structured: true, element_size: 16, element_count: 24577 }   # il_draw IL_DL_SIZE",
              "passes:",
              "  - name: layout", "    shader: layout.hlsl", "    target: cs_5_0", "    dispatch: [1, 1, 1]",
              "    thread_group_x: 64", "    thread_group_y: 1", '    output: "buffer:dl"',
              "  - name: raster", "    shader: raster.hlsl", "    target: cs_5_0", "    format: RGBA8",
              "    thread_group_x: 16", "    thread_group_y: 16", "    inputs:",
              '      - { slot: 0, source: "buffer:dl" }', '      - { slot: 1, source: "asset:type" }',
              "    output: output",
              "outputs:", "  - name: Desk", "    pass: raster", ""]
    return "\n".join(lines)


def norm(rect):
    x0, y0, x1, y1 = rect
    return f"float4({x0 / W:.5f}, {y0 / H:.5f}, {x1 / W:.5f}, {y1 / H:.5f})"


def hlsl() -> str:
    n = len(controls)
    rects = ",\n".join("    float4(" + ", ".join(f"{v:.5f}" for v in c["rect"]) + ")" for c in controls)

    def row(key):
        return ", ".join(str(c[key]) for c in controls)

    panes = ",\n".join("    " + norm(p) for p in PANES)
    return "\n".join(["// Generated by tools/ss_desk.py; edit the generator, not this file.",
                      f"static const uint DESK_COUNT = {n};", f"static const float2 DESK_SIZE = float2({W}, {H});",
                      f"static const float4 DESK_RECT[DESK_COUNT] = {{\n{rects}\n}};",
                      "// kind: 0 pad, 1 readout, 2 header, 3 status, 4 tier legend, 5 fader, 6 fixture, 7 group / layer,",
                      "// 8 tab (attribute bank, sequence target), 9 fader value",
                      f"static const uint DESK_KIND[DESK_COUNT] = {{{', '.join(str(KIND[c['kind']]) for c in controls)}}};",
                      "// bank: 0 none, 1 FULL LOOKS, 2 STATIC, 3 EFFECTS, 4 COLOR, 5 SEQUENCES",
                      f"static const uint DESK_BANK[DESK_COUNT] = {{{row('bank')}}};",
                      "// sub: a look's energy tier (1 CALM .. 4 CRAZY), a fixture's type (0 head, 1 strobe, 2 pixel run),",
                      "// 1 on a layer pad",
                      f"static const uint DESK_SUB[DESK_COUNT] = {{{row('sub')}}};",
                      "// slot: a look's pad number, a fixture's program slot, a fader's number",
                      f"static const uint DESK_SLOT[DESK_COUNT] = {{{row('slot')}}};",
                      "// flags: 2 BLACKOUT (the hold, a sequence bank's BLACKOUT pad), 4 the STROBE hold, 8 STORE, 16 a white toggle",
                      f"static const uint DESK_FLAGS[DESK_COUNT] = {{{row('flags')}}};",
                      "// glyph: 0 none, 1 play / pause, 2 stop, 3 up, 4 down, 5 left, 6 right, 7 sync, 8 beat lamp",
                      f"static const uint DESK_ICON[DESK_COUNT] = {{{row('icon')}}};",
                      "// draw-list slots: control i draws into [DESK_SPAN[i], DESK_SPAN[i] + DESK_K[i]) of the batch",
                      f"static const uint DESK_SPAN[DESK_COUNT] = {{{', '.join(str(s) for s in SPAN)}}};",
                      f"static const uint DESK_K[DESK_COUNT] = {{{', '.join(str(BUDGET[c['kind']]) for c in controls)}}};",
                      f"static const uint DESK_SLOTS = {SPAN_TOTAL};",
                      f"static const uint DESK_PANES = {len(PANES)};",
                      f"static const float4 DESK_PANE[DESK_PANES] = {{\n{panes}\n}};"]
                     + [f"static const float4 DESK_{k} = {norm(v)};" for k, v in EXTRA.items()]
                     + ["// the fixture map: its frame, the truss lines (x from, x to; y of the wall, back and front lines), the deck",
                        "// and the booth",
                        f"static const float4 DESK_MAP = {norm(MAP)};",
                        f"static const float2 DESK_TRUSS_X = float2({MAP_TRUSS_X[0] / W:.5f}, {MAP_TRUSS_X[1] / W:.5f});",
                        f"static const float3 DESK_TRUSS_Y = float3({MAP_TRUSS_Y[0] / H:.5f}, {MAP_TRUSS_Y[1] / H:.5f}, "
                        f"{MAP_TRUSS_Y[2] / H:.5f});",
                        f"static const float4 DESK_DECK = {norm(MAP_DECK)};",
                        f"static const float4 DESK_BOOTH = {norm(MAP_BOOTH)};", ""])


def luau() -> str:
    out = ["--!strict", "-- Generated by tools/ss_desk.py; edit the generator, not this file.",
           "-- SS_Desk control index (0-based, manifest order) -> id, kind, label and action (desk_panel.luau).",
           "return {"]
    for i, c in enumerate(controls):
        action = "{" + ",".join(f'"{a}"' for a in c["action"]) + "}" if c["action"] else "nil"
        out.append(f'    [{i}]={{id="{c["id"]}",kind="{c["kind"]}",label="{c["label"]}",action={action}}},')
    out += ["}", ""]
    return "\n".join(out)


def main():
    mod = ROOT / "modules" / "SS_Desk"
    mod.mkdir(parents=True, exist_ok=True)
    (mod / "manifest.yaml").write_text(manifest(), encoding="utf-8", newline="\n")
    (mod / "desk_layout.hlsli").write_text(hlsl(), encoding="utf-8", newline="\n")
    (ROOT / "scripts" / "show" / "desk_layout.luau").write_text(luau(), encoding="utf-8", newline="\n")
    kinds = {}
    for c in controls:
        kinds[c["kind"]] = kinds.get(c["kind"], 0) + 1
    print(f"SS_Desk: {len(controls)} controls {kinds}, {SPAN_TOTAL} draw slots")
    subprocess.run([sys.executable, str(ROOT / "tools" / "il_type.py"), "labels", "SS_Desk"], check=True)


if __name__ == "__main__":
    main()
