#!/usr/bin/env python3
"""SIMPLE STAGE construction model: a club stage of three flown truss lines, its 46 fixtures and their patch.

    python tools/ss_stage.py

The stage, as it reads from the dancefloor:
  - a 1 m deck with the DJ's booth at its front edge, the DJ behind it: the focal point;
  - the FRONT ROW, eight Halo Beams hung in a line under the front truss over the front of the deck, with a line of
    six Linear Strobes on the truss's audience face between them;
  - the BACK ROW, eight more Halo Beams hung under a higher truss behind the DJ, so the two rows stack in depth;
  - the WALL, twelve vertical pixel runs of four battens hung from an upstage truss: the backdrop behind the DJ;
  - a FLOOR line of six Linear Strobes standing along the back edge of the deck, at the foot of the wall.
Every truss line is flown from the ceiling steel on two chain hoists. Every moving head hangs below its truss.

One run solves the trusses from stock F34 parts, port to port (tools/truss_parts.py, the closure of truss_lab's part
model), places every fixture, audits the result and writes:

  modules/_shared/ss_stage.hlsli     the static tables SS_Stage publishes (truss members, solids, fixture mounts,
                                     pixel-run pieces), the stage bounds and the outline the canvases draw
  assets/simple_stage.mvr            the plot the Fixture Rig imports, with its GDTFs embedded
  assets/PATCH.md                    the patch sheet
  assets/stage.json                  the solved model, for the look compiler and the other tools
  scripts/show/fixture_catalog.luau  the programmer's slot table

Stage frame: metres, +Y up, +Z toward the audience, the deck centred on the origin. MVR is millimetres, Z up, and
a stage point (x, y, z) is MVR (x, -z, y). Geometry is checked here, never structurally rated: this is a visual
model of a rig, not a rigging plot.

Identity, for anything that maps a rig fixture back to the show (modules/_shared/ss_rig.hlsli):
  movers and strobes   FixtureID = slot + 1                    (slots 0-31 movers, 32-47 strobes)
  battens              FixtureID = 10000 + run * 100 + unit    (run = bar slot - 48, unit from 1 along the run)
                       CustomId  = where the unit starts along its run, in millimetres (CustomIdType 1)
Deterministic: a rerun is byte-identical.
"""
from __future__ import annotations

import io
import json
import math
import uuid
import zipfile
from pathlib import Path

import numpy as np

import ss_layout as L
import truss_parts as T

ROOT = Path(__file__).resolve().parents[1]
GDTF_DIR = ROOT / "assets" / "gdtf"
MVR = ROOT / "assets" / "simple_stage.mvr"
STAMP = (2026, 10, 4, 0, 0, 0)
NS = uuid.UUID("5e1a7c3b-2d94-4f0e-8b61-a3c9d07e4f25")

# ---------------------------------------------------------------- the stage (edit here)

SERIES = "F34"
SPAN = (3.0, 3.0, 3.0, 3.0)         # every truss line: four 3 m sections, 12 m
# The truss lines, each flown on two chain hoists: name, member kind, the truss axis's z and height. The back line
# flies higher than the front, so the two rows of heads stack in depth from the floor.
LINES = (("front", 1, 2.0, 5.6), ("back", 2, -0.5, 6.2), ("wall", 3, -3.3, 6.7))
HOIST_X = (-4.5, 4.5)
CEILING = 8.1                       # the club's ceiling steel (SS_Venue: floor + hall_height - 0.4)
DECK = (8.0, 1.0, 4.5)              # width, height, depth, centred on the origin
BOOTH = (2.4, 1.05, .8, 1.15)       # the DJ's booth: width, height, depth and the z of its centre, on the deck
DJ = (.45, 1.78)                    # the DJ: z behind the booth and height
HEADS_X = (-5.25, -3.75, -2.25, -.75, .75, 2.25, 3.75, 5.25)      # eight Halo Beams under each head truss
TRUSS_STROBES_X = (-4.5, -3.0, -1.5, 1.5, 3.0, 4.5)               # on the front truss's audience face, between heads
FLOOR_STROBES_X = (-3.5, -2.1, -.7, .7, 2.1, 3.5)                 # standing along the deck's back edge
FLOOR_STROBE_Z = -2.0
FLOOR_STROBE_TILT = 25.0            # degrees up from level, toward the dancefloor
WALL_X = tuple(-5.5 + i for i in range(12))                       # twelve pixel runs across the wall truss
WALL_UNITS = 4                      # one-metre battens per run, end to end
WALL_DROP = .25                     # a run's top below the wall truss's bottom chord
WALL_FORWARD = .1                   # the runs' strip line in front of the wall truss's axis
MOVER_SCALE = 1.7                   # the Halo Beam's model units to metres (its GDTF was written at this scale)
STROBE_LENGTH = 1.0

# Fixture hardware, metres.
HANG = .11                          # chord axis to a mover's mounting face (omega bracket and clamp)
STROBE_BACK = .135                  # a strobe's face to its housing back (GDTF origin), tools/phage_gdtf.py
STROBE_GAP = .03                    # chord surface to a strobe's housing back
STROBE_FOOT = .17                   # a standing strobe's face centre above the deck
BAR_BACK = .06                      # a batten's strip line to its body back (GDTF origin)
HEAD_SPACING = 1.2                  # movers on one truss at least this far apart
END_CLEAR = .5                      # fixtures keep this far in from a truss line's ends

# Kinds and families (SsMount.extra.x), the Surface's zones and the canvas's names.
FAMILIES = {0: ("FRONT ROW", "front"), 1: ("BACK ROW", "back"), 10: ("TRUSS STROBE", "front"),
            11: ("FLOOR STROBE", "back"), 20: ("WALL", "back")}
# extra.z, the GROUP chase order: front truss, back truss, the floor line, the wall.
GROUPS = ("FRONT TRUSS", "BACK TRUSS", "FLOOR", "WALL")
# Member kinds (SsMember.b.w) and their names on the canvas.
MEMBER_KINDS = {1: "FRONT TRUSS", 2: "BACK TRUSS", 3: "WALL TRUSS"}
SOLID_BOX, SOLID_FIGURE = 1, 3
MAT_TRUSS, MAT_STEEL, MAT_STAGE, MAT_MATTE = 0, 1, 2, 3

TYPES = {  # kind: (GDTF file, mode, footprint)
    0: ("Sentinel@Halo Beam.gdtf", "Standard 15ch", 15),
    1: ("Sentinel@Linear Strobe.gdtf", "Standard 7ch", 7),
    2: ("Sentinel@Pixel Batten 1000.gdtf", "Pixel 60ch", 60),
}
PATCH_FROM = {0: (1, 1), 1: (1, 241), 2: (2, 1)}     # where each kind's patch starts (universe, address)

V = T.V
ALONG_X = np.array([[0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [-1.0, 0.0, 0.0]])   # a straight's local +Z onto stage +X


def hash1(x: float) -> float:
    """ssHash1 of _shared/ss_rig.hlsli (the shuffle rank), in float32 like the GPU."""
    x = np.float32(x)
    s = np.float32(math.sin(np.float32(x * np.float32(12.9898) + np.float32(4.1414))))
    v = np.float32(s * np.float32(43758.5453))
    return float(v - np.floor(v))


# ---------------------------------------------------------------- the trusses

def solve():
    """Each truss line from stock straights, each joint mated port to port (truss_parts.Rig raises on a mismatch)."""
    r = T.Rig("Simple Stage flown trusses")
    for name, _, z, y in LINES:
        x0 = -sum(SPAN) / 2
        r.add(f"{name}-0", T.straight(SERIES, SPAN[0]), ALONG_X, (x0, y, z))
        for k, length in enumerate(SPAN[1:], 1):
            r.connect(f"{name}-{k - 1}", "B", f"{name}-{k}", T.straight(SERIES, length))
    return r


def chords(part):
    return [(V(m["a"]), V(m["b"])) for m in part.mounts]


# ---------------------------------------------------------------- the plot

def build():
    rig = solve()
    P = rig.parts
    d = (T.PROFILES[SERIES]["size"] - T.PROFILES[SERIES]["od"]) / 2      # chord offset from the truss axis
    rc = T.PROFILES[SERIES]["od"] / 2
    half = T.PROFILES[SERIES]["size"] / 2
    line = {name: (kind, z, y) for name, kind, z, y in LINES}

    members, solids = [], []
    for name, kind, z, y in LINES:
        for k in range(len(SPAN)):
            p = P[f"{name}-{k}"]
            members.append(dict(a=p.ports["A"]["p"], b=p.ports["B"]["p"], up=(0, 1, 0), kind=kind, section=k,
                                part=p.sku, id=f"{name}-{k}"))

    def box(c, h, mat, what, kind=SOLID_BOX, axes=((1, 0, 0), (0, 1, 0), (0, 0, 1))):
        solids.append(dict(c=tuple(float(v) for v in c), half=tuple(float(v) for v in h), mat=mat, what=what,
                           kind=kind, axes=axes))

    w, h, dd = DECK
    box((0, h / 2, 0), (w / 2, h / 2, dd / 2), MAT_STAGE, "deck")
    bw, bh, bd, bz = BOOTH
    box((0, h + bh / 2, bz), (bw / 2, bh / 2, bd / 2), MAT_MATTE, "the DJ's booth")
    box((0, h + bh + .02, bz - .05), (bw / 2 + .05, .02, bd / 2 + .08), MAT_STEEL, "the booth's top")
    # the DJ: feet on the deck behind the booth, facing the dancefloor (renderer solids.hlsl's figure)
    solids.append(dict(c=(0.0, h, DJ[0]), half=(.3, DJ[1], .2), mat=MAT_MATTE, what="the DJ", kind=SOLID_FIGURE,
                       axes=((1, 0, 0), (0, 1, 0), (0, 0, 1))))
    hoists = []
    for name, kind, z, y in LINES:
        for x in HOIST_X:
            top = y + half
            box((x, top + .14, z), (.11, .14, .11), MAT_STEEL, f"{name} hoist")
            box((x, (top + .28 + CEILING) / 2, z), (.012, (CEILING - top - .28) / 2, .012), MAT_STEEL, f"{name} chain")
            hoists.append((x, top, z))

    fixtures, clamps = [], []

    def clamp_on(point, what, half_size=(.03, .035, .03)):
        clamps.append(V(point))
        box(point, half_size, MAT_STEEL, what)

    # Halo Beams: two rows, every head hung below its truss from an omega bracket across the bottom chords.
    for row, name in enumerate(("front", "back")):
        _, z, y = line[name]
        for j, x in enumerate(HEADS_X):
            ych = y - d
            clamp_on((x, ych, z), "head bracket", (.04, .03, d + .03))
            fixtures.append(dict(slot=L.MOVER0 + row * len(HEADS_X) + j, kind=0, family=row, index=j, group=row,
                                 pos=(x, ych - HANG, z), up=(0, -1, 0), fwd=(0, 0, -1), hung=True,
                                 carry=[(x, ych, z - d), (x, ych, z + d)]))
    # Linear Strobes: a line on the front truss's audience face, tube level, hung from the top front chord...
    _, zf, yf = line["front"]
    n = 0
    for j, x in enumerate(TRUSS_STROBES_X):
        clamp_on((x, yf + d, zf + d), "strobe clamp")
        face = zf + d + rc + STROBE_GAP + STROBE_BACK
        fixtures.append(dict(slot=L.STROBE0 + n, kind=1, family=10, index=j, group=0, pos=(x, yf, face), up=(1, 0, 0),
                             fwd=(0, 0, 1), carry=[(x, yf + d, zf + d)]))
        n += 1
    # ...and a line standing along the deck's back edge, tilted up toward the dancefloor.
    t = math.radians(FLOOR_STROBE_TILT)
    fwd = (0.0, math.sin(t), math.cos(t))
    for j, x in enumerate(FLOOR_STROBES_X):
        pos = (x, h + STROBE_FOOT, FLOOR_STROBE_Z)
        box((x, h + .03, FLOOR_STROBE_Z - .08), (.45, .03, .09), MAT_STEEL, "floor strobe foot")
        fixtures.append(dict(slot=L.STROBE0 + n, kind=1, family=11, index=j, group=2, pos=pos, up=(1, 0, 0), fwd=fwd))
        n += 1
    # Pixel runs: the wall, each run four battens end to end, hung on a drop below the wall truss.
    _, zw, yw = line["wall"]
    top = yw - d - WALL_DROP
    bottom = top - WALL_UNITS
    zline = zw + WALL_FORWARD
    pieces = []
    for i, x in enumerate(WALL_X):
        a, e = V((x, bottom, zline)), V((x, top, zline))
        pieces.append(dict(run=i, k=0, a=a, b=e, n=(0, 0, 1), length=float(np.linalg.norm(e - a)), family=20))
        box((x, (yw - d + top) / 2, zw), (.012, (yw - d - top) / 2, .012), MAT_STEEL, "wall drop")
        fixtures.append(dict(slot=L.BAR0 + i, kind=2, family=20, index=i, group=3, pos=tuple((a + e) / 2), up=(0, 1, 0),
                             fwd=(0, 0, 1), run=i, units=WALL_UNITS, carry=[(x, yw - d, zw)]))
    for f in fixtures:
        f["pos"] = tuple(float(v) for v in f["pos"])
        f["rest"] = (*f["pos"], hash1(f["slot"] * 1.618 + .37))
        name, zone = FAMILIES[f["family"]]
        f["name"] = f"{name} {f['index'] + 1}"
        f["zone"] = zone
    return dict(rig=rig, lines=line, chord=d, members=members, solids=solids, fixtures=fixtures, pieces=pieces,
                clamps=clamps, hoists=hoists, wall=(bottom, top, zline), y0=line["front"][2])


# ---------------------------------------------------------------- audits

def audit(m):
    report = []
    rig = m["rig"]
    worst = max(j["gap_m"] for j in rig.joints)
    worst_chord = max(j["chord_error_m"] for j in rig.joints)
    assert worst < 1e-5 and worst_chord < 1e-5, "a truss joint does not mate"
    report.append(f"{len(rig.joints)} joints mate (worst gap {worst:.1e} m, chord {worst_chord:.1e} m)")
    straight = list(rig.parts.values())

    def on_chord(c):
        best = 1e9
        for p in straight:
            for a, b in chords(p):
                ab = b - a
                t = float(np.clip(np.dot(c - a, ab) / np.dot(ab, ab), 0, 1))
                best = min(best, float(np.linalg.norm(a + ab * t - c)))
        return best

    carried = 0
    for f in m["fixtures"]:
        for c in f.get("carry", []):
            c = V(c)
            if f["kind"] == 2:      # a wall run's drop meets the bottom chords' plane at the truss's axis
                assert any(abs(c[1] - (y - m["chord"])) < 1e-6 and abs(c[2] - z) < 1e-6 for _, z, y in
                           m["lines"].values()), f"{f['name']} hangs from no truss"
            else:
                assert on_chord(c) < 1e-6, f"{f['name']} is carried {on_chord(c):.3f} m off any chord"
            assert abs(c[0]) <= sum(SPAN) / 2 - END_CLEAR, f"{f['name']} is too near a truss end"
            carried += 1
    report.append(f"{carried} carry points on chords, every one {END_CLEAR} m or more in from a truss end")
    heads = [f for f in m["fixtures"] if f["kind"] == 0]
    gap = min(abs(a["pos"][0] - b["pos"][0]) for a in heads for b in heads if a is not b and a["group"] == b["group"])
    assert gap >= HEAD_SPACING, f"two heads {gap:.2f} m apart"
    assert all(f["up"][1] < 0 for f in heads), "every head hangs inverted below its truss"
    report.append(f"{len(heads)} heads in two rows, {gap:.2f} m apart, every one hung below its truss")
    strobes = [f for f in m["fixtures"] if f["kind"] == 1]
    for a in strobes:
        for b in strobes:
            if a is not b and a["family"] == b["family"]:
                assert abs(a["pos"][0] - b["pos"][0]) >= STROBE_LENGTH + .2, "two strobes overlap"
    for a in strobes:
        if a["family"] == 10:
            for hd in heads:
                if hd["family"] == 0:
                    assert abs(a["pos"][0] - hd["pos"][0]) >= STROBE_LENGTH / 2 + .2, "a truss strobe sits on a head"
    w, h, dd = DECK
    for f in strobes:
        if f["family"] == 11:
            assert abs(f["pos"][0]) + STROBE_LENGTH / 2 <= w / 2 and abs(f["pos"][2]) < dd / 2, "a floor strobe is off the deck"
    report.append(f"{len(strobes)} strobes: a truss line between the front heads, a floor line on the deck")
    bottom, top, _ = m["wall"]
    assert bottom > h + DJ[1] * 0 + .2, "the wall reaches the deck"
    report.append(f"the wall: {len(m['pieces'])} runs of {WALL_UNITS} m, {bottom:.2f}-{top:.2f} m")
    for x, ytop, z in m["hoists"]:
        assert ytop < CEILING - .5, "a truss flies into the ceiling"
    report.append(f"{len(m['hoists'])} chain hoists to the ceiling steel at {CEILING} m")
    assert len(m["solids"]) <= L.SOLID_COUNT and len(m["members"]) <= L.MEMBERS
    return report


# ---------------------------------------------------------------- MVR and patch

def sub(a, b): return [a[i] - b[i] for i in range(3)]
def add(a, b): return [a[i] + b[i] for i in range(3)]
def mul(a, s): return [c * s for c in a]
def dot(a, b): return sum(a[i] * b[i] for i in range(3))
def cross(a, b): return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def unitv(v):
    n = math.sqrt(dot(v, v))
    return [c / n for c in v]


def gframe(x, z):
    z = unitv(z)
    x = unitv(sub(x, mul(z, dot(x, z))))
    return x, cross(z, x), z


def to_mvr(v):
    return [v[0], -v[2], v[1]]


def fmt(v):
    return ",".join(("0" if abs(c) < 5e-7 else f"{c:.6f}".rstrip("0").rstrip(".")) for c in v)


def plot(m):
    """Every rig fixture with its GDTF axes and origin (the conventions of PHAGE's tools/phage_mvr.py)."""
    out = []
    for f in m["fixtures"]:
        up, fwd, pos = list(f["up"]), list(f["fwd"]), list(f["pos"])
        fam = FAMILIES[f["family"]][0].title()
        if f["kind"] == 0:
            axes = gframe(cross(up, fwd), mul(up, -1))
            out.append(dict(kind=0, slot=f["slot"], id=f["slot"] + 1, name=f"{fam} {f['index'] + 1}",
                            group=[fam], axes=axes, origin=pos))
        elif f["kind"] == 1:
            axes = gframe(up, mul(fwd, -1))
            out.append(dict(kind=1, slot=f["slot"], id=f["slot"] + 1, name=f"{fam} {f['index'] + 1}",
                            group=[fam + "s"], axes=axes, origin=sub(pos, mul(fwd, STROBE_BACK))))
    for p in m["pieces"]:
        a, b = list(p["a"]), list(p["b"])
        dvec = unitv(sub(b, a))
        axes = gframe(dvec, mul(list(p["n"]), -1))
        units = int(math.floor(p["length"] + 1e-6))
        s = (p["length"] - units) / 2
        name = f"Wall {p['run'] + 1}"
        for j in range(1, units + 1):
            c = add(a, mul(dvec, s + .5))
            out.append(dict(kind=2, slot=L.BAR0 + p["run"], id=10000 + p["run"] * 100 + j, name=f"{name}.{j}",
                            group=["Pixel Wall", name], axes=axes, origin=add(c, mul(axes[2], BAR_BACK)),
                            custom=int(round(s * 1000)), run=p["run"], unit=j))
            s += 1
    return out


def patch(fixtures):
    cursor = {}
    for f in fixtures:
        u, a = cursor.get(f["kind"], PATCH_FROM[f["kind"]])
        fp = TYPES[f["kind"]][2]
        if a + fp - 1 > 512:
            u, a = u + 1, 1
        f["universe"], f["address"] = u, a
        cursor[f["kind"]] = (u, a + fp)
    used = {}
    for f in fixtures:
        for ch in range(f["address"], f["address"] + TYPES[f["kind"]][2]):
            key = (f["universe"], ch)
            assert key not in used, f"{f['name']} overlaps {used[key]} at {key}"
            used[key] = f["name"]
    return fixtures


def write_mvr(fixtures):
    def u(name):
        return str(uuid.uuid5(NS, name)).upper()

    lines = ['<?xml version="1.0" encoding="UTF-8" standalone="no" ?>',
             '<!-- Generated by SIMPLE STAGE tools/ss_stage.py; edit the generator, not this file. -->',
             '<GeneralSceneDescription verMajor="1" verMinor="6" provider="Sentinel SIMPLE STAGE" providerVersion="2">',
             '  <UserData/>', '  <Scene>', '    <Layers>', f'      <Layer name="SIMPLE STAGE" uuid="{u("layer")}">',
             '        <ChildList>']
    open_groups: list[str] = []

    def indent():
        return "          " + "    " * len(open_groups)

    for f in fixtures:
        groups = f["group"]
        while open_groups and open_groups != groups[:len(open_groups)]:
            open_groups.pop()
            lines += [indent() + "  </ChildList>", indent() + "</GroupObject>"]
        for g in groups[len(open_groups):]:
            lines += [indent() + f'<GroupObject name="{g}" uuid="{u("group " + g)}">', indent() + "  <ChildList>"]
            open_groups.append(g)
        file, mode, _ = TYPES[f["kind"]]
        x, y, z = (to_mvr(c) for c in f["axes"])
        o = [c * 1000.0 for c in to_mvr(f["origin"])]
        pad = indent()
        lines += [pad + f'<Fixture name="{f["name"]}" uuid="{u("fixture " + str(f["id"]))}">',
                  pad + f'  <Matrix>{{{fmt(x)}}}{{{fmt(y)}}}{{{fmt(z)}}}{{{fmt(o)}}}</Matrix>',
                  pad + f'  <GDTFSpec>{file}</GDTFSpec>', pad + f'  <GDTFMode>{mode}</GDTFMode>',
                  pad + f'  <FixtureID>{f["id"]}</FixtureID>', pad + f'  <FixtureIDNumeric>{f["id"]}</FixtureIDNumeric>',
                  pad + f'  <UnitNumber>{f.get("unit", 0)}</UnitNumber>']
        if "custom" in f:
            lines += [pad + "  <CustomIdType>1</CustomIdType>", pad + f'  <CustomId>{f["custom"]}</CustomId>']
        lines += [pad + f'  <Addresses><Address break="0">{f["universe"]}.{f["address"]}</Address></Addresses>',
                  pad + "</Fixture>"]
    while open_groups:
        open_groups.pop()
        lines += [indent() + "  </ChildList>", indent() + "</GroupObject>"]
    lines += ['        </ChildList>', '      </Layer>', '    </Layers>', '  </Scene>', '</GeneralSceneDescription>', '']
    entries = [("GeneralSceneDescription.xml", "\n".join(lines).encode("utf-8"))]
    for file in sorted({TYPES[f["kind"]][0] for f in fixtures}):
        entries.append((file, (GDTF_DIR / file).read_bytes()))
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=STAMP)
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = 0o644 << 16
            zf.writestr(info, data)
    MVR.write_bytes(buf.getvalue())


def write_patch_sheet(fixtures, m):
    rows = []
    for f in fixtures:
        key = f["group"][0]
        if not rows or rows[-1]["group"] != key:
            rows.append(dict(group=key, first=f, last=f, count=0))
        rows[-1]["last"] = f
        rows[-1]["count"] += 1
    out = ["# SIMPLE STAGE patch", "",
           "Written by `tools/ss_stage.py` with `assets/simple_stage.mvr`. Universes are MVR numbers (Art-Net port",
           "address = universe - 1). The Fixture Rig node owns the patch once it has imported the plot; this sheet is",
           "the plot as generated.", "",
           f"- **Fixtures:** {len(fixtures)} ({sum(f['kind'] == 0 for f in fixtures)} Halo Beams, "
           f"{sum(f['kind'] == 1 for f in fixtures)} Linear Strobes, {sum(f['kind'] == 2 for f in fixtures)} "
           f"Pixel Batten 1000 in {len(m['pieces'])} wall runs)",
           f"- **Universes:** {max(f['universe'] for f in fixtures)}", "",
           "| Group | Type | Mode | Fixtures | FixtureIDs | Patch |", "|---|---|---|---|---|---|"]
    for r in rows:
        a, b = r["first"], r["last"]
        file, mode, fp = TYPES[a["kind"]]
        out.append(f"| {r['group']} | {file.split('@')[1][:-5]} | {mode} | {r['count']} | {a['id']}-{b['id']} | "
                   f"{a['universe']}.{a['address']} - {b['universe']}.{b['address'] + fp - 1} |")
    (ROOT / "assets" / "PATCH.md").write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")


# ---------------------------------------------------------------- the stage header

def f4(*v):
    return "float4(" + ",".join(("0" if abs(c) < 5e-7 else f"{c:.6f}".rstrip("0").rstrip(".")) for c in v) + ")"


def mount_record(slot, by_slot):
    """SsMount layout (_shared/ss_slots.hlsli): position, fixture_id, up, kind, fwd, active, extra, rest."""
    f = by_slot.get(slot)
    kind = 0 if slot < L.STROBE0 else 1 if slot < L.BAR0 else 2
    if f is None:
        return [f4(0, 0, 0, slot), f4(0, 1, 0, kind), f4(0, 0, 1, 0), f4(-1, 0, -1, 0), f4(0, 0, 0, hash1(slot * 1.618 + .37))]
    return [f4(*f["pos"], slot), f4(*f["up"], kind), f4(*f["fwd"], 1), f4(f["family"], f["index"], f["group"], 0),
            f4(*f["rest"])]


def outline(m):
    """The structure as line segments for the canvases: (a, b, style, view). Views: 0 front elevation, 1 plan,
    2 section (z across, y up). Styles: 0 truss, 1 the deck and the booth, 2 hoists and chains."""
    segs = []
    hw = sum(SPAN) / 2
    hb = T.PROFILES[SERIES]["size"] / 2
    for _, _, z, y in LINES:
        for s in (-1, 1):
            segs.append(((-hw, y + s * hb, z), (hw, y + s * hb, z), 0, 0))
            segs.append(((-hw, 0, z + s * hb), (hw, 0, z + s * hb), 0, 1))
            segs.append(((s * hw, y - hb, z), (s * hw, y + hb, z), 0, 0))
            segs.append(((s * hw, 0, z - hb), (s * hw, 0, z + hb), 0, 1))
            segs.append(((0, y + s * hb, z - hb), (0, y + s * hb, z + hb), 0, 2))
            segs.append(((0, y - hb, z + s * hb), (0, y + hb, z + s * hb), 0, 2))
        for x in HOIST_X:
            segs.append(((x, y + hb, z), (x, CEILING, z), 2, 0))
        segs.append(((0, y + hb, z), (0, CEILING, z), 2, 2))
    w, h, dd = DECK
    bw, bh, bd, bz = BOOTH
    for (cx, cy, cz), (hx, hy, hz) in (((0, h / 2, 0), (w / 2, h / 2, dd / 2)), ((0, h + bh / 2, bz), (bw / 2, bh / 2, bd / 2))):
        y0, y1 = cy - hy, cy + hy
        segs += [((cx - hx, y1, cz), (cx + hx, y1, cz), 1, 0), ((cx - hx, y0, cz), (cx - hx, y1, cz), 1, 0),
                 ((cx + hx, y0, cz), (cx + hx, y1, cz), 1, 0)]
        for s in (-1, 1):
            segs.append(((cx - hx, 0, cz + s * hz), (cx + hx, 0, cz + s * hz), 1, 1))
            segs.append(((cx + s * hx, 0, cz - hz), (cx + s * hx, 0, cz + hz), 1, 1))
        segs += [((0, y1, cz - hz), (0, y1, cz + hz), 1, 2), ((0, y0, cz - hz), (0, y1, cz - hz), 1, 2),
                 ((0, y0, cz + hz), (0, y1, cz + hz), 1, 2)]
    return segs


def write_header(m):
    by_slot = {f["slot"]: f for f in m["fixtures"]}
    members = m["members"]
    assert len(members) <= L.MEMBERS and len(m["solids"]) <= L.SOLID_COUNT
    lines = ["// Generated by tools/ss_stage.py; edit the generator, not this file.",
             "// SIMPLE STAGE's construction model: the solved truss lines, the solids, every fixture mount, the pixel-run",
             "// pieces and the outline the canvases draw. SS_Stage publishes the tables (Mounts, Bar Pieces, Structure);",
             "// nothing downstream re-derives a position. Stage metres, +Y up, +Z toward the audience.",
             "#ifndef SS_STAGE_HLSLI", "#define SS_STAGE_HLSLI", '#include "../_shared/ss_layout.hlsli"', ""]
    xs = [f["pos"][0] for f in m["fixtures"]]
    ys = [f["pos"][1] for f in m["fixtures"]]
    zs = [f["pos"][2] for f in m["fixtures"]]
    hb = T.PROFILES[SERIES]["size"] / 2
    ends = [p for r in members for p in (r["a"], r["b"])]
    span_x = max(abs(p[0]) for p in ends) + hb
    span_z = max(max(abs(p[2]) for p in ends) + hb, max(abs(z) for z in zs))
    top = max(p[1] for p in ends) + hb
    segs = outline(m)
    bottom, wtop, wz = m["wall"]
    lines += [f"#define SS_MOVER_SCALE {MOVER_SCALE}",
              f"#define SS_STROBE_LENGTH {STROBE_LENGTH}",
              f"#define SS_MEMBER_USED {len(members)}",
              f"#define SS_SOLID_USED {len(m['solids'])}",
              f"#define SS_TRUSS_Y {m['lines']['front'][2]:.6f}   // the front truss's axis height",
              "// The structure's half width, top and half depth; the fixtures' half width, half depth, lowest and highest",
              "// mount (the chase ranks are normalised by these).",
              f"static const float4 SS_BOUNDS={f4(span_x, top, span_z, 0)};",
              f"static const float4 SS_RANK={f4(max(map(abs, xs)), max(map(abs, zs)), min(ys), max(ys))};",
              "// The deck: half width, height, half depth; the booth: half width, height, half depth, z of its centre.",
              f"static const float4 SS_DECK={f4(DECK[0] / 2, DECK[1], DECK[2] / 2, 0)};",
              f"static const float4 SS_BOOTH={f4(BOOTH[0] / 2, BOOTH[1], BOOTH[2] / 2, BOOTH[3])};",
              "// The pixel wall: the runs' bottom and top, the z of their strip line, the half width of the wall.",
              f"static const float4 SS_WALL={f4(bottom, wtop, wz, max(abs(x) for x in WALL_X))};",
              "// The front of the stage the crowd stops at: the front truss's z and the deck's front edge.",
              f"static const float4 SS_FRONT={f4(m['lines']['front'][1], DECK[2] / 2, 0, 0)};", ""]
    lines.append("// The outline: a=(xyz, style) b=(xyz, view); views 0 front elevation, 1 plan, 2 section; styles 0 truss,")
    lines.append("// 1 the deck and the booth, 2 hoists and chains")
    lines.append(f"#define SS_OUTLINE_N {len(segs)}")
    lines.append(f"static const float4 SS_OUTLINE[{2 * len(segs)}]={{")
    for a, b, style, view in segs:
        lines.append(f" {f4(*a, style)},{f4(*b, view)},")
    lines.append("};")
    lines.append("// Members: a=(xyz, truss width) b=(xyz, kind) up=(xyz, profile 0 truss) meta=(-, -, -, section)")
    lines.append("// kinds: " + ", ".join(f"{k} {v}" for k, v in MEMBER_KINDS.items()))
    lines.append(f"static const float4 SS_MEMBER_DATA[{L.MEMBERS * 4}]={{")
    for i in range(L.MEMBERS):
        if i < len(members):
            r = members[i]
            wd = T.PROFILES[SERIES]["size"]
            lines.append(f" {f4(*r['a'], wd)},{f4(*r['b'], r['kind'])},{f4(*r['up'], 0)},{f4(0, 0, 0, r['section'])},"
                         f"   // {r['id']}: {r['part']}")
        else:
            lines.append(f" {f4(0, 0, 0, 0)},{f4(0, 0, 0, 0)},{f4(0, 1, 0, 0)},{f4(0, 0, 0, -1)},")
    lines.append("};")
    lines.append("// Solids: c=(centre, kind + 10 material) x/y/z=(axis, half extent); kind 1 box, 3 a figure (c its feet, y.w its")
    lines.append("// height); material 0 truss, 1 steel, 2 stage black, 3 matte")
    lines.append(f"static const float4 SS_SOLID_DATA[{L.SOLID_COUNT * 4}]={{")
    for i in range(L.SOLID_COUNT):
        if i < len(m["solids"]):
            s = m["solids"][i]
            h = s["half"]
            ax = s["axes"]
            lines.append(f" {f4(*s['c'], s['kind'] + 10 * s['mat'])},{f4(*ax[0], h[0])},{f4(*ax[1], h[1])},{f4(*ax[2], h[2])},"
                         f"   // {s['what']}")
        else:
            lines.append(f" {f4(0, 0, 0, 0)},{f4(1, 0, 0, 0)},{f4(0, 1, 0, 0)},{f4(0, 0, 1, 0)},")
    lines.append("};")
    lines.append("// Mounts, one per slot (SsMount): every slot the plot fills is active; the rest wait for a guest.")
    lines.append(f"static const float4 SS_MOUNT_DATA[{L.SLOTS * 5}]={{")
    for s in range(L.SLOTS):
        f = by_slot.get(s)
        lines.append(" " + ",".join(mount_record(s, by_slot)) + "," + (f"   // {s} {f['name']}" if f else ""))
    lines.append("};")
    lines.append("// Pixel-run pieces, SS_BAR_SEGS per run: a=(xyz, u0) b=(xyz, u1) n=(facing, run) w=(length, family, valid, piece)")
    lines.append(f"static const float4 SS_PIECE_DATA[{L.BARS * L.BAR_SEGS * 4}]={{")
    by_run = {}
    for p in m["pieces"]:
        by_run.setdefault(p["run"], []).append(p)
    for b in range(L.BARS):
        run = by_run.get(b, [])
        total = sum(p["length"] for p in run)
        before = 0.0
        for k in range(L.BAR_SEGS):
            if k < len(run):
                p = run[k]
                u0, u1 = before / total, (before + p["length"]) / total
                lines.append(f" {f4(*p['a'], u0)},{f4(*p['b'], u1)},{f4(*p['n'], b)},{f4(p['length'], p['family'], 1, k)},")
                before += p["length"]
            else:
                lines.append(f" {f4(0, 0, 0, 0)},{f4(0, 0, 0, 0)},{f4(0, 0, 1, b)},{f4(0, 0, 0, k)},")
    lines.append("};")
    lines += ["#endif", ""]
    (ROOT / "modules" / "_shared" / "ss_stage.hlsli").write_text("\n".join(lines), encoding="utf-8", newline="\n")


# ---------------------------------------------------------------- the programmer's catalog and the model

def write_catalog(m):
    by_slot = {f["slot"]: f for f in m["fixtures"]}
    lines = ["--!strict",
             "-- Generated by tools/ss_stage.py; edit the generator, not this file.",
             "-- One entry per Program slot: kind 0 mover, 1 strobe, 2 pixel run. family/index/group match SsMount.extra;",
             "-- x/y/z is the mount (m). unused: the plot has no fixture there (a guest the rig adds can take it).",
             "local F={"]
    for s in range(L.SLOTS):
        f = by_slot.get(s)
        kind = 0 if s < L.STROBE0 else 1 if s < L.BAR0 else 2
        if f:
            x, y, z = (round(v, 2) for v in f["pos"])
            lines.append(f'    {{slot={s},kind={kind},family={f["family"]},index={f["index"]},group={f["group"]},'
                         f'zone="{f["zone"]}",x={x},y={y},z={z},unused=false,name="{f["name"]}"}},')
        else:
            lines.append(f'    {{slot={s},kind={kind},family=-1,index=0,group=-1,zone="none",x=0,y=0,z=0,unused=true,'
                         f'name="SLOT {s}"}},')
    lines += ["}", "for _,f in ipairs(F) do f.id=tostring(f.slot);f.record=f.id;f.mover=f.kind==0 end", "return F", ""]
    (ROOT / "scripts" / "show" / "fixture_catalog.luau").write_text("\n".join(lines), encoding="utf-8", newline="\n")


def write_model(m, rig_fixtures):
    data = {
        "generator": "tools/ss_stage.py",
        "lines": {k: list(v) for k, v in m["lines"].items()}, "chord": m["chord"], "wall": list(m["wall"]),
        "fixtures": [{k: (list(v) if isinstance(v, tuple) else v) for k, v in f.items() if k != "carry"}
                     for f in m["fixtures"]],
        "pieces": [{k: (list(map(float, v)) if isinstance(v, (tuple, np.ndarray)) else v) for k, v in p.items()}
                   for p in m["pieces"]],
        "patch": [{"name": f["name"], "id": f["id"], "slot": f["slot"], "universe": f["universe"], "address": f["address"]}
                  for f in rig_fixtures],
    }
    (ROOT / "assets" / "stage.json").write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8", newline="\n")


def model():
    return build()


def main():
    m = build()
    for line in audit(m):
        print("  " + line)
    rig_fixtures = patch(plot(m))
    write_mvr(rig_fixtures)
    write_patch_sheet(rig_fixtures, m)
    write_header(m)
    write_catalog(m)
    write_model(m, rig_fixtures)
    print(f"{MVR.relative_to(ROOT)}: {len(rig_fixtures)} fixtures, {len(m['members'])} members, {len(m['solids'])} solids, "
          f"{MVR.stat().st_size} bytes")


if __name__ == "__main__":
    main()
