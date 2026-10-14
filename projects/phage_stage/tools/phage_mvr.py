#!/usr/bin/env python3
"""Write PHAGE's rig as an MVR plot: assets/phage_rig.mvr, with its patch sheet assets/PATCH.md.

    python tools/phage_mvr.py

Every light PHAGE draws becomes a patched fixture of the types tools/phage_gdtf.py writes, at its REST pose:
the movers are Halo Beams, the strobes Linear Strobes, and each pixel run is a chain of one metre Pixel Battens
butted end to end along every straight piece of the run, as many whole bars as the piece holds, centred so the
slack splits between its two ends. Positions come from the Kinetics captures at drive=Rest (tools/mounts_rest.json, tools/pieces_rest.json);
re-capture both after changing the anatomy, then rerun this. The GDTFs are embedded, so the plot opens anywhere.

The Fixture Rig node imports this file and owns the types and the patch from then on. Kinetics still owns where
the fixtures are while the creature moves: the plot is where they hang at rest.

Identity, for anything that maps a rig fixture back to PHAGE:
  movers and strobes   FixtureID = PHAGE slot + 1                 (slots 0-127 movers, 128-175 strobes)
  battens              FixtureID = 10000 + run * 100 + unit       (run = bar slot - 176, unit from 1 along the run)
                       CustomId  = where the unit starts along its run, in millimetres (CustomIdType 1)

Frames: the stage is metres, +Y up; MVR is millimetres, Z up, and a stage point (x, y, z) is MVR (x, -z, y).
A fixture's GDTF axes in PHAGE's mount frame (side = up x fwd):
  Halo Beam      X = side, Y = fwd, Z = -up; origin = the mount (the base's mounting face)
  Linear Strobe  X = up (the tube), Z = -fwd (emission), Y = Z x X; origin = the housing's back, 135 mm behind the mount
  Pixel Batten   X = along the piece, Z = -facing, Y = Z x X; origin = the body's back, 60 mm behind the strip line
Deterministic: a rerun is byte-identical.
"""
from __future__ import annotations

import io
import json
import math
import uuid
import zipfile
from pathlib import Path

from phage_gdtf import BAR_SECTION, STROBE_HOUSING
from phage_rig import FAMILY

ROOT = Path(__file__).resolve().parents[1]
GDTF_DIR = ROOT / "assets" / "gdtf"
MVR = ROOT / "assets" / "phage_rig.mvr"
STAMP = (2026, 10, 3, 0, 0, 0)
NS = uuid.UUID("c4a1e0d2-6b3f-4e8a-9d17-5f2b8c0e7a31")

TYPES = {  # kind: (GDTF file, mode, footprint)
    "mover": ("Sentinel@Halo Beam.gdtf", "Standard 15ch", 15),
    "strobe": ("Sentinel@Linear Strobe.gdtf", "Standard 7ch", 7),
    1.0: ("Sentinel@Pixel Batten 1000.gdtf", "Pixel 60ch", 60),
}
STROBE_BACK = STROBE_HOUSING[2] + STROBE_HOUSING[1]        # mount point to the housing's back
BAR_BACK = 2 * BAR_SECTION[1]                               # strip line to the body's back
BAR0 = 176
BAR_FAMILY = {20: "Leg Upper", 21: "Leg Lower", 22: "Plate Edge", 23: "Sheath", 24: "Collar", 25: "Capsid Square",
              26: "Capsid Link", 27: "Booth"}


# ---------------------------------------------------------------- vectors

def sub(a, b): return [a[i] - b[i] for i in range(3)]
def add(a, b): return [a[i] + b[i] for i in range(3)]
def mul(a, s): return [c * s for c in a]
def dot(a, b): return sum(a[i] * b[i] for i in range(3))
def cross(a, b): return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def unit(v):
    l = math.sqrt(dot(v, v))
    return [c / l for c in v]


def frame(x, z, what):
    """Right-handed GDTF axes from an exact Z and an approximate X; a mount whose X runs along its Z is an anatomy
    bug (the renderer would draw it with a NaN width), so it stops the build."""
    z = unit(z)
    x = sub(x, mul(z, dot(x, z)))
    if dot(x, x) < 1e-6:
        raise ValueError(f"{what}: its mount frame is degenerate (the long axis runs along the emission)")
    x = unit(x)
    return x, cross(z, x), z


def to_mvr(v):
    return [v[0], -v[2], v[1]]


def fmt(v):
    return ",".join(("0" if abs(c) < 5e-7 else f"{c:.6f}".rstrip("0").rstrip(".")) for c in v)


# ---------------------------------------------------------------- the plot

def family_name(code):
    return FAMILY[int(code)][0].title()


def plot():
    mounts = json.loads((ROOT / "tools" / "mounts_rest.json").read_text())["mounts"]
    pieces = json.loads((ROOT / "tools" / "pieces_rest.json").read_text())["pieces"]
    fixtures = []
    for slot, m in enumerate(mounts):
        if m["active"] < .5 or int(round(m["kind"])) not in (0, 1):
            continue
        up, fwd, pos = m["up"], m["fwd"], m["position"]
        fam = family_name(m["extra"][0])
        if int(round(m["kind"])) == 0:
            x, y, z = frame(cross(up, fwd), mul(up, -1), f"slot {slot}")
            fixtures.append({"kind": "mover", "slot": slot, "id": slot + 1, "name": f"{fam} {int(m['extra'][1]) + 1}",
                             "group": [f"{fam} Movers"], "axes": (x, y, z), "origin": pos})
        else:
            x, y, z = frame(up, mul(fwd, -1), f"slot {slot}")
            fixtures.append({"kind": "strobe", "slot": slot, "id": slot + 1, "name": f"{fam.replace(' Stb', '')} Strobe {int(m['extra'][1]) + 1}",
                             "group": [f"{fam.replace(' Stb', '')} Strobes"], "axes": (x, y, z),
                             "origin": sub(pos, mul(fwd, STROBE_BACK))})
    runs = {}
    for p in pieces:
        if p["w"][2] > .5:
            runs.setdefault(int(round(p["n"][3])), []).append(p)
    # Runs grouped by family (each family one MVR group, patched together), in PHAGE's bar order within it.
    order = sorted(runs, key=lambda b: (int(round(runs[b][0]["w"][1])), b))
    seen: dict[int, int] = {}
    for b in order:
        run = sorted(runs[b], key=lambda p: p["w"][3])
        total = sum(p["w"][0] for p in run)
        code = int(round(run[0]["w"][1]))
        fam = BAR_FAMILY[code]
        seen[code] = seen.get(code, 0) + 1
        n = seen[code]
        j, before = 0, 0.0
        for p in run:
            a, c, length = p["a"][:3], p["b"][:3], p["w"][0]
            d = unit(sub(c, a))
            x, y, z = frame(d, mul(p["n"][:3], -1), f"bar run {b}")
            units = [1.0] * int(math.floor(length + 1e-6))
            s = (length - sum(units)) / 2
            for u in units:
                j += 1
                centre = add(a, mul(d, s + u / 2))
                fixtures.append({"kind": u, "slot": BAR0 + b, "id": 10000 + b * 100 + j, "name": f"{fam} {n}.{j}",
                                 "group": [f"{fam} Pixels", f"{fam} {n}"], "axes": (x, y, z),
                                 "origin": add(centre, mul(z, BAR_BACK)), "custom": int(round((before + s) * 1000)),
                                 "run": b, "run_length": total})
                s += u
            before += length
    return fixtures


def patch(fixtures):
    """Movers from universe 1, then strobes, then battens, each section on a fresh universe; a fixture never spans
    two universes."""
    universe, address, section = 1, 1, None
    for f in fixtures:
        kind = f["kind"] if isinstance(f["kind"], str) else "bar"
        footprint = TYPES[f["kind"]][2]
        if section is not None and (kind != section or address + footprint - 1 > 512):
            universe, address = universe + 1, 1
        section = kind
        f["universe"], f["address"] = universe, address
        address += footprint
    return fixtures


# ---------------------------------------------------------------- MVR

def write_mvr(fixtures):
    def u(name):
        return str(uuid.uuid5(NS, name)).upper()

    lines = ['<?xml version="1.0" encoding="UTF-8" standalone="no" ?>',
             '<!-- Generated by PHAGE tools/phage_mvr.py from the Kinetics rest captures; edit the generator, not this file. -->',
             '<GeneralSceneDescription verMajor="1" verMinor="6" provider="Sentinel PHAGE" providerVersion="1">',
             '  <UserData/>', '  <Scene>', '    <Layers>', f'      <Layer name="PHAGE" uuid="{u("layer")}">', '        <ChildList>']
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
                  pad + f'  <UnitNumber>{f["id"] % 100 if "custom" in f else 0}</UnitNumber>']
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


def write_patch_sheet(fixtures):
    rows, current = [], None
    for f in fixtures:
        key = f["group"][0]
        if current is None or current["group"] != key:
            current = {"group": key, "type": TYPES[f["kind"]][0].split("@")[1][:-5], "mode": TYPES[f["kind"]][1], "first": f, "last": f,
                       "count": 0, "types": set()}
            rows.append(current)
        current["last"] = f
        current["count"] += 1
        current["types"].add(TYPES[f["kind"]][0].split("@")[1][:-5])
    bars = [f for f in fixtures if not isinstance(f["kind"], str)]
    universes = max(f["universe"] for f in fixtures)
    out = ["# PHAGE patch", "",
           "Written by `tools/phage_mvr.py` with `assets/phage_rig.mvr`. Universes are MVR numbers (Art-Net port address",
           "= universe - 1). The Fixture Rig node owns the patch once it has imported the plot; this sheet is the plot as",
           "generated.", "",
           f"- **Fixtures:** {len(fixtures)} ({sum(f['kind'] == 'mover' for f in fixtures)} Halo Beams, "
           f"{sum(f['kind'] == 'strobe' for f in fixtures)} Linear Strobes, {len(bars)} Pixel Batten 1000 in "
           f"{len({f['run'] for f in bars})} runs)",
           f"- **Pixels:** {sum(int(round(f['kind'] / .05)) for f in bars)} RGB pixels on "
           f"{sum(f['kind'] for f in bars):.1f} m of batten (the runs measure {sum({f['run']: f['run_length'] for f in bars}.values()):.1f} m)",
           f"- **Universes:** {universes}", "",
           "| Group | Type | Mode | Fixtures | FixtureIDs | Patch |", "|---|---|---|---|---|---|"]
    for r in rows:
        a, b = r["first"], r["last"]
        out.append(f"| {r['group']} | {' + '.join(sorted(r['types'], reverse=True))} | {r['mode'] if len(r['types']) == 1 else 'Pixel'} | {r['count']} | "
                   f"{a['id']}-{b['id']} | {a['universe']}.{a['address']} - {b['universe']}.{b['address'] + TYPES[b['kind']][2] - 1} |")
    (ROOT / "assets" / "PATCH.md").write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    return universes


def main():
    fixtures = patch(plot())
    write_mvr(fixtures)
    universes = write_patch_sheet(fixtures)
    print(f"{MVR.relative_to(ROOT)}: {len(fixtures)} fixtures, {universes} universes, {MVR.stat().st_size} bytes")


if __name__ == "__main__":
    main()
