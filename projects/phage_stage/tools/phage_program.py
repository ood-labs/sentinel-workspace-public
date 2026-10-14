"""Generate modules/Phage_Program (manifest.yaml + program.hlsl).

One program row per stable PHAGE slot: movers 0-127, strobes 128-175, pixel bars 176-239 and
kinetic axes 240-247, then each fixture type's further layers (studio_rig's layered programmer):
  rows   0-247  the base layer: MOVE (movers), TUBE (strobes), PIXELS (bars), the axes
  rows 248-375  BEAM, mover slot + 248
  rows 376-615  the second layer, slot + 376: HALO (movers 376-503), PLATES (strobes 504-551),
                CHASE (bars 552-615)
Every row carries the same 17 attributes; each layer reads the ones that mean something to it (see
ATTRIBUTES / FAMILY_USE and docs/PROGRAMMING.md). `layered` (live, hidden, written to extra.y of every row)
tells the readers to take each layer from its own row; at 0 they read the base row for everything, as before the
layers existed. It is an A/B switch: a look stored before the layers plays identically either way
(tools/phage_baseline.py ab). The Surface
uploads rows in batches and then bumps `commit_revision`; rows only change on a commit, so a
half-uploaded look is never visible. `master` and `pitch` stay live.

Usage: python tools/phage_program.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "modules" / "Phage_Program"
SLOTS = 248
BEAM0 = 248          # BEAM row of mover slot s: s + BEAM0
LAYER2 = 376         # HALO / PLATES / CHASE row of slot s: s + LAYER2
ROWS = 616
# every_frame on purpose: the sheet preview reads the persistent program buffer, which an on_dirty
# cook would only show one change late. The per-frame cost is one revision compare per row.
MAGIC = 260933

# key, (min, max) for the Surface catalog; the hidden manifest params accept -1000..1000.
ATTRIBUTES = [
    "pan", "tilt", "level", "ring",
    "beam_palette", "ring_palette", "move_lane", "int_lane",
    "color_lane", "pan_amp", "tilt_amp", "spread",
    "width", "offset", "reverse", "look",
    "order",
]


def family(i):
    if i < 128:
        return "mover"
    if i < 176:
        return "strobe"
    if i < 240:
        return "bar"
    return "axis"


def layer(r):
    """(fixture slot, layer name) of program row r."""
    if r < SLOTS:
        return r, {"mover": "move", "strobe": "tube", "bar": "pixels", "axis": "axis"}[family(r)]
    if r < LAYER2:
        return r - BEAM0, "beam"
    s = r - LAYER2
    return s, {"mover": "halo", "strobe": "plates", "bar": "chase"}[family(s)]


def defaults(r):
    """A row's power-on values: every layer of a fixture starts as its base row does."""
    i, _ = layer(r)
    d = dict(pan=0, tilt=0, level=1, ring=.6, beam_palette=0, ring_palette=1, move_lane=0, int_lane=0,
             color_lane=0, pan_amp=0, tilt_amp=0, spread=.45, width=.5, offset=0, reverse=0, look=0, order=0)
    f = family(i)
    if f == "strobe":
        d.update(level=0, ring=.35, beam_palette=0)
    elif f == "bar":
        d.update(level=1, beam_palette=0, ring_palette=1)
    elif f == "axis":
        d.update(level=0, ring=0)
    return d


def fmt(v):
    return ("%.6g" % v)


def manifest():
    lines = [
        "name: PHAGE / Fixture Programming",
        "version: '1.0'",
        "mode: generator",
        "resolution: [1280, 440]",
        "# IBM Plex Sans Condensed + IBM Plex Mono, SIL OFL 1.1 (_shared/type/IBM_PLEX_OFL.txt)",
        "assets:",
        "  - { name: type, type: texture, file: ../_shared/type/il_type.png, srgb: false }",
        # a full-bleed canvas at the panel's own size; the pointer only drives the hover inspector
        "panel:",
        "  mode: canvas",
        "  output: Programmer Sheet",
        "  resolution: follow_panel",
        "viewport:",
        "  hint: 'Point at a cell to read it: the fixture, the attribute and what its value means.'",
        "  interactions: [events]",
        "  input:",
        "    pointer: [left]",
        "parameters:",
        "  - {name: commit_revision, type: float, default: 0, min: 0, max: 10000000}",
        "  - {name: master, type: float, default: 1, min: 0, max: 1}",
        "  - {name: pitch, type: float, default: 0, min: -85, max: 85}",
    ]
    lines.append("  - {name: layered, type: float, default: 1, min: 0, max: 1, hidden: true}")
    for i in range(ROWS):
        d = defaults(i)
        for key in ATTRIBUTES:
            lines.append("  - {name: f%d_%s, type: float, default: %s, min: -1000, max: 1000, hidden: true}" % (i, key, fmt(d[key])))
    lines += [
        "buffers:",
        "  - {name: program, structured: true, element_size: 96, element_count: %d, persistent: true}" % ROWS,
        "  - {name: dl, structured: true, element_size: 16, element_count: 24577}   # il_draw IL_DL_SIZE",
        "passes:",
        "  - name: program",
        "    shader: program.hlsl",
        "    target: cs_5_0",
        "    dispatch: [%d, 1, 1]" % ROWS,
        "    output: buffer:program",
        # the sheet drawing (preview.hlsl), its type and chrome (layout.hlsl), and the shared UI
        # kit's rasterizer (ui.hlsl) drawing that type over the sheet
        "  - name: preview",
        "    shader: preview.hlsl",
        "    target: cs_5_0",
        "    inputs:",
        "      - {slot: 0, source: buffer:program}",
        "  - name: layout",
        "    shader: layout.hlsl",
        "    target: cs_5_0",
        "    dispatch: [1, 1, 1]",
        "    thread_group_x: 64",
        "    thread_group_y: 1",
        "    inputs:",
        "      - {slot: 0, source: 'buffer:program'}",
        "    output: buffer:dl",
        "  - name: ui",
        "    shader: ui.hlsl",
        "    target: cs_5_0",
        "    thread_group_x: 16",
        "    thread_group_y: 16",
        "    inputs:",
        "      - {slot: 0, source: buffer:dl}",
        "      - {slot: 1, source: 'asset:type'}",
        "      - {slot: 2, source: 'pass:preview'}",
        "data_outputs:",
        "  - name: Fixture Program",
        "    buffer: program",
        "    schema:",
        "      - {name: aim, type: float4}",
        "      - {name: routing, type: float4}",
        "      - {name: movement, type: float4}",
        "      - {name: timing, type: float4}",
        "      - {name: meta, type: float4}",
        "      - {name: extra, type: float4}",
        "outputs:",
        "  - name: Programmer Sheet",
        "    pass: ui",
    ]
    return "\n".join(lines) + "\n"


def shader():
    out = [
        "// Generated by tools/phage_program.py. Edit the generator, not this file.",
        "// Rows change only when commit_revision moves (or on first load); master, pitch and layered are live.",
        '#include "../_shared/phage_show.hlsli"',
        "RWStructuredBuffer<PhProgram>P:register(u0);",
        "[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=%d)return;PhProgram r=P[i];" % ROWS,
        "if(r.meta.x!=commit_revision||r.meta.w!=%d){" % MAGIC,
    ]
    for i in range(ROWS):
        f = lambda k: "f%d_%s" % (i, k)
        body = ("r.aim=float4(%s,%s,%s,%s);r.routing=float4(%s,%s,%s,%s);r.movement=float4(%s,%s,%s,%s);"
                "r.timing=float4(%s,%s,%s,%s);r.extra=float4(%s,0,0,0);") % tuple(f(k) for k in ATTRIBUTES)
        out.append(("if" if i == 0 else "else if") + "(i==%d){%s}" % (i, body))
    out += [
        "}",
        "r.meta=float4(commit_revision,master,pitch,%d);r.extra.y=layered;P[i]=r;}" % MAGIC,
    ]
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "manifest.yaml").write_text(manifest(), encoding="utf-8")
    (OUT / "program.hlsl").write_text(shader(), encoding="utf-8")
    print("Phage_Program: %d rows (%d slots and their layers) x %d attributes" % (ROWS, SLOTS, len(ATTRIBUTES)))
