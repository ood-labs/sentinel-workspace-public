"""SIMPLE STAGE look machinery: the fixture table, the aim inverse, program rows per layer, packing and the preset
snapshots the Surface recalls. Generic (forked from PHAGE's tools/phage_looks.py); the looks themselves are designed
in tools/ss_looks.py.

The rig comes from tools/ss_stage.py's solved model, the same tables SS_Stage publishes, so a look aims at exactly the
mounts the GPU plays. Program rows follow tools/ss_layout.py: a slot's base row (MOVE, TUBE or PIXELS), a mover's
BEAM row (slot + BEAM0) and every fixture's second layer (HALO, PLATES or CHASE, slot + LAYER2). Each row stores only
the fields its layer owns (scripts/show/attribute_catalog.luau kinds), packed per partition of 32 slots
(scripts/show/rig_codec.luau).
"""
from __future__ import annotations

import colorsys
import json
import math

import ss_layout as L
import ss_stage

ROOT = ss_stage.ROOT
STATE = "/sentinel/pipelines/SS_Surface/state/"
BEAM0, LAYER2, SLOTS = L.BEAM0, L.LAYER2, L.SLOTS

# --- the fixtures -----------------------------------------------------------------------------------------------------
_MODEL = ss_stage.build()
_BY_SLOT = {f["slot"]: f for f in _MODEL["fixtures"]}


def _catalog():
    out = []
    for s in range(SLOTS):
        f = _BY_SLOT.get(s)
        kind = 0 if s < L.STROBE0 else 1 if s < L.BAR0 else 2
        if f is None:
            out.append(dict(slot=s, kind=kind, family=-1, index=0, group=-1, unused=True, pos=(0.0, 0.0, 0.0),
                            up=(0.0, 1.0, 0.0), fwd=(0.0, 0.0, 1.0), rest=(0.0, 0.0, 0.0, 0.0), name=f"SLOT {s}"))
        else:
            out.append(dict(f, unused=False))
    return out


FX = _catalog()
MOVERS = [f for f in FX if f["kind"] == 0 and not f["unused"]]
STROBES = [f for f in FX if f["kind"] == 1 and not f["unused"]]
BARS = [f for f in FX if f["kind"] == 2 and not f["unused"]]
LIGHTS = MOVERS + STROBES + BARS
RANK = (max(abs(f["pos"][0]) for f in LIGHTS), max(abs(f["pos"][2]) for f in LIGHTS),
        min(f["pos"][1] for f in LIGHTS), max(f["pos"][1] for f in LIGHTS))     # ss_stage.hlsli SS_RANK

# --- codes (ss_show.hlsli, led_patterns.hlsli, optics.hlsl) ------------------------------------------------------------
OFF, KICK, SNARE, HAT, BUILD, PHRASE = range(6)
AROUND, MIRROR, OUT, UP, FRONT, SIDE, SHUFFLE, GROUP = range(8)
BAR = {n: i for i, n in enumerate(["SOLID", "CHASE", "PULSE", "SEGMENTS", "RAIN", "COMET", "TWIN", "CHEVRON",
                                   "SCANNER", "EQ", "PLASMA", "SPARKLE", "HEARTBEAT", "CLIMB", "STROBE", "RIPPLE"])}
STROBE = {"PULSE": 0, "STROBE": 1, "SPARKLE": 2, "BLINDER": 3, "GLOW": 4, "OFF": 5}


def mov(repeats=1, rnd=False, jump=False, step=False):
    """Movement / pulse FX code 16-47: repeats x1-x8, RND gate, JMP random points, STEP point sequence."""
    return 16 + {1: 0, 2: 1, 4: 2, 8: 3}[repeats] + (4 if rnd else 0) + (8 if jump else 0) + (16 if step else 0)


def glide(repeats=1, rnd=False, group=False):
    """GLIDE 52-63: eased moves between positions, a new one every lane cycle x repeats; the five-point figure, a random
    position per head (rnd) or one per group (group). The pan size leans the beam across the stage (world X) and the
    tilt size raises it (motors.hlsl)."""
    return 52 + {1: 0, 2: 1, 4: 2, 8: 3}[repeats] + (8 if group else 4 if rnd else 0)


def hold_code(repeats=1):
    """HOLD 24-27 on a light layer: a window instead of a pulse."""
    return 24 + {1: 0, 2: 1, 4: 2, 8: 3}[repeats]


def px(pattern, repeats=1):
    """A PIXELS content code: the pattern, run x1-x8 per lane cycle."""
    return BAR[pattern] + 16 * {1: 0, 2: 1, 4: 2, 8: 3}[repeats]


# --- geometry and the aim inverse (ss_fixture.hlsli) -------------------------------------------------------------------
UPW = (0.0, 1.0, 0.0)


def add(*vs): return tuple(sum(v[i] for v in vs) for i in range(3))
def mul(v, k): return (v[0] * k, v[1] * k, v[2] * k)
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(v):
    n = math.sqrt(dot(v, v)) or 1.0
    return (v[0] / n, v[1] / n, v[2] / n)


def to(f, target): return norm(sub(target, f["pos"]))


def aim_angles(up, fwd, direction):
    """World beam direction -> (pan, tilt) degrees for a mount frame. Inverse of ssHeadNormal(0,0,-1)."""
    d = norm(direction)
    x = cross(up, fwd)
    q = (dot(d, x), dot(d, up), dot(d, fwd))
    tilt = math.degrees(math.asin(max(-1.0, min(1.0, q[1]))))
    pan = 0.0 if math.hypot(q[0], q[2]) < 1e-4 else math.degrees(math.atan2(-q[0], -q[2]))
    return pan, tilt


def beam_direction(up, fwd, pan_deg, tilt_deg):
    """Forward model: (pan, tilt) -> world beam direction (ssHeadNormal of local -z)."""
    p, t = math.radians(pan_deg), math.radians(tilt_deg)
    v = (0.0, math.sin(t), -math.cos(t))
    v = (math.sin(p) * v[2], v[1], math.cos(p) * v[2])
    x = cross(up, fwd)
    return tuple(x[i] * v[0] + up[i] * v[1] + fwd[i] * v[2] for i in range(3))


# A Halo Beam cannot throw its beam more than 45 deg past its mounting plane toward its own base (its GDTF tilt is +-135;
# the show's tilt is the GDTF's plus 90): a hung head cannot reach above 45 deg up, a standing one below 45 deg down.
TILT_MIN = -45.0
CLAMP_DEG = 12.0


def fit(f, d, level, ring):
    """A head's aim inside its reach: out of reach by a little, clamped to the limit; further, dark at the limit."""
    pan, tilt = aim_angles(f["up"], f["fwd"], d)
    if tilt >= TILT_MIN:
        return pan, tilt, level, ring
    if TILT_MIN - tilt <= CLAMP_DEG:
        return pan, TILT_MIN, level, ring
    return pan, TILT_MIN, 0.0, ring


def rank(f, order, reverse=0):
    """ssRank (ss_show.hlsli) on a fixture's rest position."""
    x, y, z = f["pos"]
    around = (math.atan2(x, z) / (2 * math.pi) + 1) % 1 if abs(x) + abs(z) > 1e-4 else 0.0
    r = {MIRROR: lambda: abs(around - .5) * 2, OUT: lambda: min(1.0, abs(x) / RANK[0]),
         UP: lambda: min(1.0, max(0.0, (y - RANK[2]) / max(RANK[3] - RANK[2], .1))),
         FRONT: lambda: min(1.0, max(0.0, (RANK[1] - z) / (2 * RANK[1]))),
         SIDE: lambda: min(1.0, max(0.0, (x + RANK[0]) / (2 * RANK[0]))),
         SHUFFLE: lambda: f["rest"][3],
         GROUP: lambda: (f["group"] + .5) / 6 if f["group"] >= 0 else around}.get(order, lambda: around)()
    return 1 - r if reverse > .5 else r


# --- rows and fields ---------------------------------------------------------------------------------------------------
STATIC_F = ["pan", "tilt", "level", "ring", "beam_palette", "ring_palette"]
EFFECT_F = ["move_lane", "int_lane", "color_lane", "pan_amp", "tilt_amp", "spread", "width", "offset", "reverse", "look",
            "order"]
DEFAULT = {"pan": 0, "tilt": 0, "level": 1, "ring": .6, "beam_palette": 0, "ring_palette": 1, "move_lane": 0,
           "int_lane": 0, "color_lane": 0, "pan_amp": 0, "tilt_amp": 0, "spread": .45, "width": .5, "offset": 0,
           "reverse": 0, "look": 0, "order": 0}
LIMIT = {"pan": (-270, 270), "tilt": (-135, 135), "level": (0, 1), "ring": (0, 1), "beam_palette": (0, 2),
         "ring_palette": (0, 2), "move_lane": (0, 5), "int_lane": (0, 5), "color_lane": (0, 5),
         "pan_amp": (-180, 180), "tilt_amp": (-90, 90), "spread": (0, .95), "width": (.01, 1),
         "offset": (-1, 1), "reverse": (0, 1), "look": (0, 63), "order": (0, 7)}
BASE_LAYER = {0: "move", 1: "tube", 2: "pixels"}
SECOND_LAYER = {0: "halo", 1: "plates", 2: "chase"}
# What each layer's row stores (attribute_catalog kinds, aliases resolved).
OWNS = {
    "move": {"pan", "tilt", "move_lane", "pan_amp", "tilt_amp", "spread", "offset", "reverse", "look", "order", "width"},
    "beam": {"level", "beam_palette", "int_lane", "color_lane", "width", "spread", "offset", "reverse", "look", "order"},
    "halo": {"ring", "ring_palette", "int_lane", "color_lane", "width", "spread", "offset", "reverse", "look", "order"},
    "tube": {"level", "int_lane", "width", "spread", "offset", "reverse", "look", "order"},
    "plates": {"ring", "beam_palette", "int_lane", "color_lane", "width", "spread", "offset", "reverse", "look", "order"},
    "pixels": {"level", "beam_palette", "ring_palette", "int_lane", "color_lane", "spread", "width", "offset", "reverse",
               "look", "order"},
    "chase": {"level", "int_lane", "width", "spread", "offset", "reverse", "look", "order"},
}
# The sequence banks (static_rig FX_FAMILIES): which layers each holds.
FX_FAMILIES = {"sequence": {"move", "beam", "halo", "tube", "plates", "pixels", "chase"},
               "seq_heads": {"move", "beam", "halo"}, "seq_strobes": {"tube", "plates"},
               "seq_battens": {"pixels", "chase"}}
CLOCKED = {"tube", "pixels", "chase"}       # layers that run on the show's strobe clock
STATIC_MASK = {"pan", "tilt", "level", "ring"}


def fmt(key, value):
    lo, hi = LIMIT[key]
    v = min(hi, max(lo, value))
    s = "%.7g" % (round(v, 3) if key in ("pan", "tilt", "pan_amp", "tilt_amp") else round(v, 4))
    return "0" if s == "-0" else s


def partitions():
    """static_rig's partitions: slots 32k..32k+31's base rows, then their BEAM rows, then their second-layer rows."""
    parts = []
    for b in range(L.BANKS):
        first, last = b * L.PARTITION, min(SLOTS, b * L.PARTITION + L.PARTITION)
        part = [(s, BASE_LAYER[FX[s]["kind"]]) for s in range(first, last)]
        part += [(BEAM0 + s, "beam") for s in range(first, last) if FX[s]["kind"] == 0]
        part += [(LAYER2 + s, SECOND_LAYER[FX[s]["kind"]]) for s in range(first, last)]
        parts.append(part)
    return parts


PARTS = partitions()
LAYER_OF = {row: layer for part in PARTS for row, layer in part}


def pack_part(rows, keys, part, mask=None):
    """One partition as the Surface packs it: '_' for a row not in `rows`, a field its layer does not own or one
    outside `mask`."""
    out = ["1"]
    for row, layer in part:
        r = rows.get(row)
        out.append(",".join(fmt(k, r[k]) if r is not None and k in r and k in OWNS[layer] and (mask is None or k in mask)
                            else "_" for k in keys))
    text = ";".join(out)
    assert len(text) < 4096, f"partition is {len(text)} chars"
    return text


def static_snapshot(rows, mask=None):
    return {f"{STATE}saved_static_bank_{b}": pack_part(rows, STATIC_F, part, mask) for b, part in enumerate(PARTS)}


def effects_snapshot(rows):
    return {f"{STATE}saved_effects_bank_{b}": pack_part(rows, EFFECT_F, part) for b, part in enumerate(PARTS)}


def family_snapshot(kind, rows, clock=None):
    """A sequence bank pad: the partitions holding its family's rows, aim and levels with the effects; the strobe clock
    when it uses it."""
    family = FX_FAMILIES[kind]
    snap = {}
    for b, part in enumerate(PARTS):
        if not any(layer in family for _, layer in part):
            continue
        own = {row: rows[row] for row, layer in part if layer in family and row in rows}
        snap[f"{STATE}saved_effects_bank_{b}"] = pack_part(own, EFFECT_F, part)
        snap[f"{STATE}saved_static_bank_{b}"] = pack_part(own, STATIC_F, part, STATIC_MASK)
    if clock and family & CLOCKED:
        snap[f"{STATE}show_strobe_rate"] = float(clock[0])
        snap[f"{STATE}show_strobe_duty"] = float(clock[1])
    return snap


def group(kind, presets):
    paths = sorted({p for _, snap in presets for p in snap})
    return {"id": f"simple_stage_{kind}", "paths": paths,
            "presets": [{"id": f"simple_stage_{kind}:{kind} {i}", "name": f"{kind} {i}", "revision": 1,
                         "snapshot": snap} for i, (_, snap) in enumerate(presets, 1)]}


def merge(*layers):
    rows = {}
    for layer in layers:
        for r, row in layer.items():
            rows.setdefault(r, {}).update(row)
    return rows


# --- layer rows from intent --------------------------------------------------------------------------------------------
def aim_rows(shape):
    """A beam shape -> layer rows: each head's pan / tilt (MOVE), level (BEAM) and ring (HALO); `shape(f)` gives
    (direction, level, ring) or None to leave the head untouched."""
    rows = {}
    for f in MOVERS:
        r = shape(f)
        if r is None:
            continue
        pan, tilt, level, ring = fit(f, *r)
        rows[f["slot"]] = {"pan": pan, "tilt": tilt}
        rows[BEAM0 + f["slot"]] = {"level": level}
        rows[LAYER2 + f["slot"]] = {"ring": ring}
    return rows


def level_rows(fixtures, level=None, ring=None):
    """Levels for strobes (TUBE level, PLATES ring) or battens (PIXELS level, CHASE level)."""
    rows = {}
    for f in fixtures:
        if f["kind"] == 1:
            if level is not None: rows[f["slot"]] = {"level": level}
            if ring is not None: rows[LAYER2 + f["slot"]] = {"ring": ring}
        elif f["kind"] == 2:
            if level is not None: rows[f["slot"]] = {"level": level}
            rows[LAYER2 + f["slot"]] = {"level": 1.0}
    return rows


def palette_rows(route):
    """Colour routing: `route(f)` gives (A/B/C for the beam, plates or content; A/B/C for the ring or second colour)."""
    rows = {}
    for f in LIGHTS:
        a, b = route(f)
        if f["kind"] == 0:
            rows[BEAM0 + f["slot"]] = {"beam_palette": a}
            rows[LAYER2 + f["slot"]] = {"ring_palette": b}
        elif f["kind"] == 1:
            rows[LAYER2 + f["slot"]] = {"beam_palette": a}
        else:
            rows[f["slot"]] = {"beam_palette": a, "ring_palette": b}
    return rows


REST = {
    "move": dict(move_lane=OFF, pan_amp=0, tilt_amp=0, spread=0, offset=0, reverse=0, look=0, order=AROUND, width=.5),
    "beam": dict(int_lane=OFF, color_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=0, order=AROUND),
    "halo": dict(int_lane=OFF, color_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=0, order=AROUND),
    "tube": dict(int_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=STROBE["OFF"], order=AROUND),
    "plates": dict(int_lane=OFF, color_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=STROBE["GLOW"],
                   order=AROUND),
    "pixels": dict(int_lane=OFF, color_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=BAR["SOLID"],
                   order=AROUND),
    "chase": dict(int_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=0, order=AROUND),
}
LAYER_FIXTURES = {"move": MOVERS, "beam": MOVERS, "halo": MOVERS, "tube": STROBES, "plates": STROBES, "pixels": BARS,
                  "chase": BARS}
LAYER_ROW = {"move": 0, "beam": BEAM0, "halo": LAYER2, "tube": 0, "plates": LAYER2, "pixels": 0, "chase": LAYER2}


def layer_part(layer, f, part):
    """A layer row from intent keys: `lane` is the move lane on MOVE rows and the chase lane on light rows, `rise` a
    tilt toward the sky (signed per mount), `pan` the lean, `glide` a GLIDE's share of a step, `clane` the colour lane."""
    row = dict(REST[layer])
    for k, v in part.items():
        if k == "lane": row["move_lane" if layer == "move" else "int_lane"] = v
        elif k == "rise": row["tilt_amp"] = -v if f["up"][1] < -.3 else v
        elif k == "pan": row["pan_amp"] = v
        elif k == "glide": row["width"] = v
        elif k == "clane": row["color_lane"] = v
        else: row[k] = v
    return row


def effect_rows(layers):
    """Every effect row of the rig from per-layer intent: `layers[layer]` is a function of a fixture giving its part
    (a dict, or None for the layer's rest)."""
    rows = {}
    for layer, fixtures in LAYER_FIXTURES.items():
        fn = layers.get(layer)
        for f in fixtures:
            part = (fn(f) if fn else None) or {}
            rows[LAYER_ROW[layer] + f["slot"]] = layer_part(layer, f, part)
    return rows


def window(fixtures, lane, start, length, repeats=1, spread=0.0, order=AROUND, reverse=0):
    """A HOLD window (codes 24-27, any light layer): the fixtures show from `start` for `length` of each lane cycle
    (x repeats), opening one after another by rank x spread from `start` on."""
    lo = min(rank(f, order, reverse) for f in fixtures) if fixtures else 0.0
    return dict(look=hold_code(repeats), lane=lane, width=length, spread=spread, order=order, reverse=reverse,
                offset=(-start + lo * spread) / repeats)


CLOSED = dict(lane=PHRASE, look=24, width=.01)            # a HOLD at its narrowest never opens: dark


def gwin(lane, start, length, repeats=1, spread=.95, order=UP, reverse=0):
    """A window ranked on the whole rig: every light of every type in one band, plane, sector or shockwave."""
    return window(LIGHTS, lane, start, length, repeats, spread=spread, order=order, reverse=reverse)


# --- colour ------------------------------------------------------------------------------------------------------------
def packed(rgb): return rgb[0] << 16 | rgb[1] << 8 | rgb[2]


def to_dmx(rgb):
    """A palette colour as it should look -> the DMX the fixtures need. A fixture's RGB channels are LED output, linear
    light (the renderer decodes them so, as a real emitter is), so a colour authored as it should appear on screen is
    linearised: (255, 40, 10) sent raw shows orange, its linear (255, 4, 0) shows the red it was picked as."""
    return tuple(int(round(255 * (c / 255) ** 2.2)) for c in rgb)


def palette_records(palettes, active):
    rec = {}
    for p, (_, cols) in enumerate(palettes):
        for s, key in enumerate("abc"): rec[f"pal{p}{key}"] = float(packed(to_dmx(cols[s])))
    rec["palette"] = float(active)
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in to_dmx(palettes[active][1][0])))
    rec.update({"hue": round(h, 4), "sat": round(s, 4), "val": round(v, 4)})
    return rec


# --- blackout ----------------------------------------------------------------------------------------------------------
def blackout_rows(fixtures):
    """Every level and ring of the fixtures at 0: the next look of theirs brings them back where they were."""
    rows = {}
    for f in fixtures:
        if f["kind"] == 0:
            rows[BEAM0 + f["slot"]] = {"level": 0.0}
            rows[LAYER2 + f["slot"]] = {"ring": 0.0}
        elif f["kind"] == 1:
            rows[f["slot"]] = {"level": 0.0}
            rows[LAYER2 + f["slot"]] = {"ring": 0.0}
        else:
            rows[f["slot"]] = {"level": 0.0}
    return rows


def blackout_snapshot(kind):
    family = FX_FAMILIES[kind]
    rows = blackout_rows(LIGHTS)
    return {f"{STATE}saved_static_bank_{b}": pack_part({r: rows[r] for r, layer in part if layer in family and r in rows},
                                                        STATIC_F, part, STATIC_MASK)
            for b, part in enumerate(PARTS) if any(layer in family for _, layer in part)}


def write_group(kind, presets):
    path = ROOT / "presets" / f"simple_stage_{kind}.json"
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(group(kind, presets), indent=1) + "\n", encoding="utf-8", newline="\n")
    return path
