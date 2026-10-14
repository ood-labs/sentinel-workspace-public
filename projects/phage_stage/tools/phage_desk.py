"""Generate the PHAGE desk: a Push-free performance panel for the Surface.

One layout table drives the Module and the Surface, so they can never disagree:
    modules/Phage_Desk/manifest.yaml       viewport panel controls (pads / readouts), normalized rects
    modules/Phage_Desk/desk_layout.hlsli   each control's kind, bank, energy tier, slot, flags and icon,
                                           plus the desk's panes, for layout.hlsl
    scripts/show/desk_layout.luau          control index -> id, label and rig_commands action
then regenerates the desk's type tables with tools/il_type.py: labels.txt -> _labels.generated.hlsli,
and _ui.generated.hlsli (control indices and rects, stamped with the manifest hash the example
validator checks).

The drawing is hand-written: modules/Phage_Desk/layout.hlsl records a draw list, raster.hlsl is the
shared rasterizer (the Interaction Lab kit in modules/_shared/ui/).

The control list is the Surface's contract: its order, ids, kinds, labels and actions are what
scripts/show/desk_layout.luau carries, so a layout change moves rects only and leaves that file
byte-identical. Pad titles come from tools/phage_looks.py, so renaming a look renames its pad.

ONE COLOUR LANGUAGE. Amber is only ever what is live (lit pads, the beat on TAP, a running clock).
Red is BLACKOUT. Each bank carries an identity hue (FULL LOOKS, STATIC, EFFECTS, COLOR) and an
effect's energy tier is a 1-4 step mark, not a colour.

    python tools/phage_desk.py
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import phage_looks

ROOT = Path(__file__).resolve().parents[1]
W, H = 1600, 760
KIND = {"pad": 0, "readout": 1, "header": 2, "status": 3, "tier": 4}
BANK = {"complete": 1, "static": 2, "effects": 3, "color": 4}          # layout.hlsl bankHue()
# flags (layout.hlsl DF_*): a truss pose, the BLACKOUT hold, the STROBE hold
POSE, ALARM, FLASH = 1, 2, 4
# glyphs (layout.hlsl DI_*)
ICON = {"play": 1, "stop": 2, "up": 3, "down": 4, "left": 5, "right": 6, "sync": 7, "beat": 8}

controls: list[dict] = []


def add(cid, kind, rect, label, action=None, bank=0, tier=0, slot=0, flags=0, icon=0):
    x0, y0, x1, y1 = rect
    controls.append({"id": cid, "kind": kind, "rect": (x0 / W, y0 / H, x1 / W, y1 / H), "label": label,
                     "action": action, "bank": bank, "tier": tier, "slot": slot, "flags": flags, "icon": icon})


def titles(kind):
    return [name for name, _ in phage_looks.build()[kind]]


BUILT = {k: titles(k) for k in ("static", "effects", "color", "complete")}

# The desk's panes (drawn plates), in layout pixels, 12 px margins and 8 px gutters: transport, the four
# banks, camera, live, programmer. Content sits 8 px inside its pane.
PANES = [(12, 12, 1588, 104),
         (12, 112, 796, 298), (804, 112, 1588, 298), (12, 306, 796, 492), (804, 306, 1588, 492),
         (12, 500, 548, 748), (556, 500, 1588, 628), (556, 636, 1588, 748)]
# Rects layout.hlsl draws into that are not controls: the title block, the LIVE header, camera captions.
EXTRA = {"TITLE": (20, 20, 200, 96), "LIVE_HEAD": (564, 508, 1580, 532),
         "ORBIT": (20, 716, 277, 738), "ZOOM": (370, 716, 452, 738)}

# Transport and holds.
TOP, TH = 20, 76
x = 216
for cid, label in (("tap", "TAP"), ("play", "PLAY"), ("stop", "STOP"), ("sync", "SYNC")):
    icon = ICON["beat" if cid == "tap" else cid]
    add(cid, "pad", (x, TOP, x + 104, TOP + TH), label, ("tempo", cid), icon=icon)
    x += 112
add("bpm", "readout", (680, TOP, 920, TOP + TH), "---.- BPM")
add("beat", "readout", (928, TOP, 1200, TOP + TH), "BAR - BEAT -")
add("blackout", "pad", (1236, TOP, 1404, TOP + TH), "BLACKOUT", ("hold", "blackout"), flags=ALARM)
add("strobe", "pad", (1412, TOP, 1580, TOP + TH), "STROBE", ("hold", "strobe"), flags=FLASH)

# Four banks of 16: FULL LOOKS / STATIC on top, EFFECTS / COLOR below. Each row splits into two groups of
# four (a wider middle gutter), which is how the energy tiers and the truss poses fall.
COLS = {"left": 20, "right": 812}
COLW, GAP, MID, PADH = 768, 6, 18, 66
PADW = (COLW - 6 * GAP - MID) / 8


def bank(kind, header, col, top, tier_of=lambda slot: 0, flags_of=lambda slot: 0, head_w=COLW):
    x0 = COLS[col]
    add(f"head_{kind}", "header", (x0, top, x0 + head_w, top + 24), header, bank=BANK[kind])
    for slot in range(1, 17):
        r, c = divmod(slot - 1, 8)
        px, py = x0 + c * (PADW + GAP) + (MID - GAP if c >= 4 else 0), top + 32 + r * (PADH + GAP)
        add(f"{kind}_{slot}", "pad", (px, py, px + PADW, py + PADH), BUILT[kind][slot - 1],
            ("preset", "recall", kind, str(slot)), bank=BANK[kind], tier=tier_of(slot), slot=slot,
            flags=flags_of(slot))


def tier(slot):
    return (slot - 1) // 4 + 1                 # 1 CALM, 2 GROOVE, 3 BUILD, 4 CRAZY


bank("complete", "FULL LOOKS", "left", 120, tier)
# Tier legends share their bank's header row, so those headers stop short of them (no overlapping controls).
bank("static", "STATIC", "right", 120, flags_of=lambda s: POSE if s > 12 else 0, head_w=COLW - 256)
add("tier_static", "tier", (COLS["right"] + COLW - 250, 120, COLS["right"] + COLW, 144), "13-16 TRUSS POSES",
    flags=POSE)
tx = COLS["left"] + COLW - (4 * 104 + 3 * 6)
bank("effects", "EFFECTS", "left", 314, tier, head_w=tx - 6 - COLS["left"])
for i, name in enumerate(("CALM", "GROOVE", "BUILD", "CRAZY")):
    add(f"tier_{name.lower()}", "tier", (tx + i * 110, 314, tx + i * 110 + 104, 338), name, tier=i + 1)
bank("color", "COLOR", "right", 314)

# Camera orbit (same moves as the Push arrows), the live equation and the programmer's status line.
add("head_camera", "header", (20, 508, 540, 532), "CAMERA")
cam = [("cam_up", "UP", 1, 0, "up"), ("cam_left", "<", 0, 1, "left"), ("cam_down", "DOWN", 1, 1, "down"),
       ("cam_right", ">", 2, 1, "right"), ("cam_in", "IN", 4, 0, None), ("cam_out", "OUT", 4, 1, None),
       ("cam_home", "HOME", 5, 0, None)]
for cid, label, c, r, icon in cam:
    px, py = 20 + c * 87.6, 540 + r * 88
    add(cid, "pad", (px, py, px + 82, py + 82), label, ("camera", cid[4:]), icon=ICON[icon] if icon else 0)
add("head_status", "header", (564, 644, 1580, 668), "PROGRAMMER")
add("status", "status", (564, 674, 1580, 740), "DESK READY")
# legend_full is drawn as the live equation (which look is up, made of which parts); legend_fx as its caption.
add("legend_full", "status", (564, 538, 1580, 598), "FULL LOOK = STATIC + TRUSS POSE + EFFECTS + COLOR")
add("legend_fx", "status", (564, 602, 1580, 622), "EFFECTS: CALM / GROOVE / BUILD (16 BEATS) / CRAZY")


for c in controls:
    assert len(c["label"].encode()) <= 63, f"{c['id']} label over 63 bytes"
# The host hit-tests the first control under the pointer, so no two may overlap.
for i, a in enumerate(controls):
    for b in controls[i + 1:]:
        (ax0, ay0, ax1, ay1), (bx0, by0, bx1, by1) = a["rect"], b["rect"]
        assert ax1 <= bx0 or bx1 <= ax0 or ay1 <= by0 or by1 <= ay0, f"{a['id']} overlaps {b['id']}"


def manifest() -> str:
    lines = ["# Generated by tools/phage_desk.py; edit the generator, not this file.",
             "name: PHAGE / Desk", "version: '1.0'", "mode: generator", f"resolution: [{W}, {H}]",
             "compile_optimization: fast_compile",
             "panel:", "  mode: canvas", "  output: Desk", "  resolution: follow_panel",
             "# IBM Plex Sans Condensed + IBM Plex Mono, SIL OFL 1.1 (_shared/type/IBM_PLEX_OFL.txt)",
             "assets:", "  - { name: type, type: texture, file: ../_shared/type/il_type.png, srgb: false }",
             "viewport:",
             '  hint: "Click a look to recall it: a FULL LOOK lights its four parts. Hold BLACKOUT or STROBE. '
             'The arrows orbit the camera."',
             "  panel: true", "  controls:"]
    for c in controls:
        r = ", ".join(f"{v:.5f}" for v in c["rect"])
        if c["kind"] == "pad":
            lines.append(f'    - {{id: {c["id"]}, kind: pad, mode: momentary, rect: [{r}], label: "{c["label"]}"}}')
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
    return "\n".join(["// Generated by tools/phage_desk.py; edit the generator, not this file.",
                      f"static const uint DESK_COUNT = {n};", f"static const float2 DESK_SIZE = float2({W}, {H});",
                      f"static const float4 DESK_RECT[DESK_COUNT] = {{\n{rects}\n}};",
                      "// kind: 0 pad, 1 readout, 2 header, 3 status, 4 tier legend",
                      f"static const uint DESK_KIND[DESK_COUNT] = {{{', '.join(str(KIND[c['kind']]) for c in controls)}}};",
                      "// bank: 0 none, 1 FULL LOOKS, 2 STATIC, 3 EFFECTS, 4 COLOR",
                      f"static const uint DESK_BANK[DESK_COUNT] = {{{row('bank')}}};",
                      "// energy tier: 0 none, 1 CALM, 2 GROOVE, 3 BUILD, 4 CRAZY",
                      f"static const uint DESK_TIER[DESK_COUNT] = {{{row('tier')}}};",
                      f"static const uint DESK_SLOT[DESK_COUNT] = {{{row('slot')}}};",
                      "// flags: 1 truss pose, 2 the BLACKOUT hold, 4 the STROBE hold",
                      f"static const uint DESK_FLAGS[DESK_COUNT] = {{{row('flags')}}};",
                      "// glyph: 0 none, 1 play / pause, 2 stop, 3 up, 4 down, 5 left, 6 right, 7 sync, 8 beat lamp",
                      f"static const uint DESK_ICON[DESK_COUNT] = {{{row('icon')}}};",
                      f"static const uint DESK_PANES = {len(PANES)};",
                      f"static const float4 DESK_PANE[DESK_PANES] = {{\n{panes}\n}};"]
                     + [f"static const float4 DESK_{k} = {norm(v)};" for k, v in EXTRA.items()] + [""])


def luau() -> str:
    out = ["--!strict", "-- Generated by tools/phage_desk.py; edit the generator, not this file.",
           "-- Phage_Desk control index (0-based, manifest order) -> id and rig_command action.", "return {"]
    for i, c in enumerate(controls):
        kind = {"tier": "readout", "status": "status"}.get(c["kind"], c["kind"])
        action = "{" + ",".join(f'"{a}"' for a in c["action"]) + "}" if c["action"] else "nil"
        out.append(f'    [{i}]={{id="{c["id"]}",kind="{kind}",label="{c["label"]}",action={action}}},')
    out += ["}", ""]
    return "\n".join(out)


def main():
    mod = ROOT / "modules" / "Phage_Desk"
    mod.mkdir(parents=True, exist_ok=True)
    (mod / "manifest.yaml").write_text(manifest(), newline="\n")
    (mod / "desk_layout.hlsli").write_text(hlsl(), newline="\n")
    (ROOT / "scripts" / "show" / "desk_layout.luau").write_text(luau(), newline="\n")
    print(f"Phage_Desk: {len(controls)} controls, {sum(c['kind'] == 'pad' for c in controls)} pads")
    subprocess.run([sys.executable, str(ROOT / "tools" / "il_type.py"), "labels", "Phage_Desk"], check=True)


if __name__ == "__main__":
    main()
