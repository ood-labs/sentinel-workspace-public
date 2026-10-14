"""PHAGE look compiler: static, effects, colour and full looks -> the Surface's native preset JSON.

Looks are authored here as geometry and intent (where beams go, which lane drives what) and compiled
against the real mount frames captured from Phage_Kinetics (tools/mounts_rest.json), with the same
aim inverse the GPU uses (phAimAngles). Output, in the packed bank format the Surface recalls:

    presets/phage_stage_{static,effects,color,complete,rhythm}.json
    presets/phage_stage_{move,beam,halo,heads,tube,plates,strobes,pixels,chase,battens}.json   (fixture banks)
    scripts/show/preset_titles.luau            (pad names for the Push, Desk and Surface window)

    python tools/phage_looks.py                every bank
    python tools/phage_looks.py fixtures       only the fixture banks (pad pages 2-4) and the pad names

Layering (what each bank owns, so banks mix):
  STATIC   movers pan/tilt/level/ring and pixel-bar level (12 beam shapes); truss axes pan/tilt only
           (4 poses). Strobes are never touched by a static look.
  EFFECTS  every effect attribute of every fixture, plus the show strobe clock. Tiered by energy:
           1-4 CALM, 5-8 GROOVE, 9-12 BUILD (16-beat BUILD lane from the recall), 13-16 CRAZY.
  COLOR    the 8-palette library, the active palette, and palette routing (A/B/C) for every fixture.
  FULL     one static + truss pose + effects + colour, with renderer globals, rhythm, pitch, master.
"""
from __future__ import annotations

import colorsys
import json
import math
from pathlib import Path

from phage_rig import ROOT, aim_angles, fixtures

FX = fixtures()
SLOTS = len(FX)
STATE = "/sentinel/pipelines/Phage_Surface/state/"
STATIC_F = ["pan", "tilt", "level", "ring", "beam_palette", "ring_palette"]
EFFECT_F = ["move_lane", "int_lane", "color_lane", "pan_amp", "tilt_amp", "spread", "width", "offset",
            "reverse", "look", "order"]
DEFAULT = {"pan": 0, "tilt": 0, "level": 1, "ring": .6, "beam_palette": 0, "ring_palette": 1, "move_lane": 0,
           "int_lane": 0, "color_lane": 0, "pan_amp": 0, "tilt_amp": 0, "spread": .45, "width": .5, "offset": 0,
           "reverse": 0, "look": 0, "order": 0}
LIMIT = {"pan": (-270, 270), "tilt": (-135, 135), "level": (0, 1), "ring": (0, 1), "beam_palette": (0, 2),
         "ring_palette": (0, 2), "move_lane": (0, 5), "int_lane": (0, 5), "color_lane": (0, 5),
         "pan_amp": (-180, 180), "tilt_amp": (-90, 90), "spread": (0, .95), "width": (.01, 1),
         "offset": (-1, 1), "reverse": (0, 1), "look": (0, 63), "order": (0, 7)}
BANKS = math.ceil(SLOTS / 32)

# Lanes, chase orders and LOOK codes (phage_show.hlsli, led_patterns.hlsli, optics.hlsl).
OFF, KICK, SNARE, HAT, BUILD, PHRASE = range(6)
AROUND, MIRROR, OUTWARD, UP, FRONT, SIDE, SHUFFLE, LEG = range(8)
BAR = {n: i for i, n in enumerate(["SOLID", "CHASE", "PULSE", "SEGMENTS", "SCATTER", "COMET", "TWIN", "FILL",
                                   "SCANNER", "BARCODE", "PLASMA", "SPARKLE", "HEARTBEAT", "CLIMB", "STROBE", "RIPPLE"])}
STROBE = {"PULSE": 0, "STROBE": 1, "SPARKLE": 2, "BLINDER": 3, "GLOW": 4, "OFF": 5}


def mov(repeats=1, rnd=False, jump=False, step=False):
    """Mover/axis FX code 16-47: chase repeats x1-x8, RND gate, JMP random points, STEP point sequence."""
    return 16 + {1: 0, 2: 1, 4: 2, 8: 3}[repeats] + (4 if rnd else 0) + (8 if jump else 0) + (16 if step else 0)


def spin(rate):
    """Continuous pan rotation: one turn per lane cycle x 1/4, 1/2, 1 or 2."""
    return {.25: 48, .5: 49, 1: 50, 2: 51}[rate]


def glide(repeats=1, rnd=False, group=False):
    """GLIDE code 52-63: eased moves between positions, a new one every lane cycle x repeats; the five-point figure, a
    random position per head (rnd) or one per group (group: the group moves as a formation). On a Halo Beam the pan
    size leans the beam across the stage (world X) and the tilt size raises it (motors.hlsl)."""
    return 52 + {1: 0, 2: 1, 4: 2, 8: 3}[repeats] + (8 if group else 4 if rnd else 0)


# --- geometry --------------------------------------------------------------------------------------
UPW = (0.0, 1.0, 0.0)


def add(*vs): return tuple(sum(v[i] for v in vs) for i in range(3))
def mul(v, k): return (v[0] * k, v[1] * k, v[2] * k)
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def norm(v):
    n = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2) or 1.0
    return (v[0] / n, v[1] / n, v[2] / n)
def radial(p):
    n = math.hypot(p[0], p[2])
    return (p[0] / n, 0.0, p[2] / n) if n > 1e-3 else (0.0, 0.0, 1.0)
def turn(v, deg):
    """Rotate about +y (counter-clockwise seen from above, x toward -z)."""
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return (c * v[0] + s * v[2], v[1], -s * v[0] + c * v[2])
def to(f, target): return norm(sub(target, f["pos"]))


MOVERS = [f for f in FX if f["kind"] == 0 and not f["unused"]]
STROBES = [f for f in FX if f["kind"] == 1 and not f["unused"]]
BARS = [f for f in FX if f["kind"] == 2 and not f["unused"]]
AXES = [f for f in FX if f["kind"] == 3]


def leg_point(family, leg):
    pts = [f["pos"] for f in FX if f["family"] == family and f["leg"] == leg]
    return tuple(sum(p[i] for p in pts) / len(pts) for i in range(3))


KNEE = {leg: leg_point(3, leg) for leg in range(6)}
FOOT = {leg: leg_point(6, leg) for leg in range(6)}
HANGING = lambda f: f["up"][1] < -.3          # plate, collar, booth heads hang under their truss
LEG_AZ = {leg: math.degrees(math.atan2(FOOT[leg][0], FOOT[leg][2])) for leg in range(6)}


# --- STATIC looks ------------------------------------------------------------------------------------
# A beam shape gives each mover (direction, level, ring) or None to leave it untouched, and a level
# for the pixel bars. Family codes: 0/1 plate outer/inner, 2 capsid, 3 knee, 4 collar, 5 booth, 6 foot.
def shape_origin(f):
    o, ov, fam = radial(f["pos"]), mul(f["fwd"], -1), f["family"]
    if fam <= 1: d = add(mul(o, .55), mul(UPW, -1))
    elif fam == 2: d = add(f["up"], mul(UPW, .9))
    elif fam == 3: d = add(mul(ov, .25), UPW)
    elif fam == 4: d = add(o, mul(UPW, -.35))
    elif fam == 5: d = add(o, mul(UPW, -.25))
    else: d = add(mul(ov, -.45), UPW)
    return d, 1, .6


def shape_cathedral(f):
    fam, o = f["family"], radial(f["pos"])
    if fam == 2: return add(mul(o, .12), UPW), 1, .3
    if fam in (3, 6): return UPW, 1, .3
    if fam <= 1: return mul(UPW, -1), .9, .3
    if fam == 4: return add(o, mul(UPW, .25)), .8, .3
    return mul(UPW, -1), .5, .2                                  # booth pools straight down


def shape_sunburst(f):
    fam, o = f["family"], radial(f["pos"])
    if fam == 2: return f["up"], 1, .8
    if fam <= 1: return add(o, mul(UPW, -.35)), 1, .8
    if fam in (3, 4): return add(o, mul(UPW, .05)), 1, .8
    if fam == 5: return add(o, mul(UPW, -.6)), .8, .8
    return add(o, UPW), 1, .8


APEX = (0.0, 36.0, 0.0)


def shape_crown(f):
    fam = f["family"]
    if fam in (2, 3, 4, 6): return to(f, APEX), 1, .9
    return None if fam == 5 else (mul(UPW, -1), 0, .15)         # plate beams off; booth untouched


def shape_fibers(f):
    fam, leg = f["family"], f["leg"]
    if fam == 3:                                                 # knees: one beam down the leg, one up it
        return (to(f, FOOT[leg]) if f["index"] % 2 == 0 else to(f, (0.0, 6.0, 0.0))), 1, .8
    if fam == 6: return to(f, KNEE[leg]), 1, .8
    if fam <= 1:                                                 # plate beams run out under the nearest leg
        az = min(LEG_AZ.values(), key=lambda a: abs((math.degrees(math.atan2(f["pos"][0], f["pos"][2])) - a + 180) % 360 - 180))
        a = math.radians(az)
        return to(f, (math.sin(a) * 24, 0.0, math.cos(a) * 24)), 1, .6
    if fam == 2: return add(mul(radial(f["pos"]), .2), UPW), .7, .5
    return None


def _hands():
    """HELIX's twist per head: alternating round each ring so neighbours cross, and mirrored left to right so the
    lattice reads the same from either side of the stage; heads on the centre line (front and back) do not twist."""
    rings = {}
    for f in MOVERS:
        rings.setdefault((f["family"], round(f["pos"][1], 1)), []).append(f)
    hand = {}
    for ring in rings.values():
        for side in (1, -1):
            heads = sorted((f for f in ring if f["pos"][0] * side > .3),
                           key=lambda f: (abs(math.atan2(f["pos"][0], f["pos"][2])), f["index"]))
            for k, f in enumerate(heads): hand[f["slot"]] = (1 if k % 2 == 0 else -1) * side
        for f in ring: hand.setdefault(f["slot"], 0)
    return hand


HAND = _hands()


def shape_helix(f):
    """A double helix: every ring twists both ways at once, neighbours crossing, so the beams weave a lattice tower
    (rising through the capsid, knees and feet, falling through the plates and booth) with no turn to it."""
    fam, o = f["family"], radial(f["pos"])
    rise = {0: -1.1, 1: -1.1, 2: 1.0, 3: 1.2, 4: .3, 5: -.8, 6: 1.6}[fam]
    return add(turn(o, 50 * HAND[f["slot"]]), mul(UPW, rise)), 1, .7


def shape_cage(f):
    """Bars of light round the crowd: long diagonals from the head to the floor, knee beams lacing
    across to the next leg's foot, foot beams closing on the capsid."""
    fam, p, o = f["family"], f["pos"], radial(f["pos"])
    if fam == 2: return to(f, (o[0] * 30, 0.0, o[2] * 30)), 1, .5
    if fam == 3: return to(f, FOOT[(f["leg"] + 1) % 6]), 1, .5
    if fam == 6: return to(f, (0.0, 20.0, 0.0)), 1, .5
    if fam <= 1: return to(f, (o[0] * 19, 0.0, o[2] * 19)), .8, .4
    if fam == 4: return add(o, mul(UPW, -.15)), .8, .4
    return mul(UPW, -1), .4, .2


def shape_front(f):
    p = f["pos"]
    return to(f, (p[0] * .5, 0.0, 22.0 + p[2] * .25)), 1, .7      # a fan landing on the front crowd


def shape_needles(f):
    fam = f["family"]
    if fam == 2: return UPW, 1, 0
    return (mul(UPW, -1) if HANGING(f) else UPW), 1, 0


def shape_xfire(f):
    fam, p = f["family"], f["pos"]
    side = -1 if p[0] > 0 else 1
    if fam in (3, 6): return to(f, (side * 11.0, 16.0 if fam == 6 else 3.0, p[2] * .3)), 1, .6
    if fam <= 1: return to(f, (side * 16.0, 0.0, p[2] * 1.4)), 1, .6
    if fam == 2: return to(f, (side * 22.0, 30.0, p[2])), 1, .6
    if fam == 4: return to(f, (side * 20.0, 3.0, p[2])), 1, .6
    return to(f, (side * 8.0, 0.0, p[2])), .6, .4


def shape_halo(f):
    """Rings of light at every tier: level beams running round each ring toward the front, mirrored left to right, so
    the two sides meet and cross in front of the stage; the centre line's heads throw straight out."""
    fam, p, o = f["family"], f["pos"], radial(f["pos"])
    t = o if abs(p[0]) < .3 else max(turn(o, 90), turn(o, -90), key=lambda v: v[2])
    tilt = {0: -.12, 1: -.12, 2: .0, 3: .02, 4: .0, 5: -.1, 6: .05}[fam]
    return add(t, mul(UPW, tilt)), .9, 1


SPOT = (0.0, 0.9, 11.0)


def shape_pinpoint(f):
    if f["family"] == 2: return to(f, (0.0, 44.0, 0.0)), .6, .2
    return to(f, SPOT), 1, .2


# (name, shape, bar level)
BEAM_SHAPES = [
    ("ORIGIN", shape_origin, .85), ("CATHEDRAL", shape_cathedral, .45), ("SUNBURST", shape_sunburst, 1.0),
    ("CROWN", shape_crown, .6), ("FIBERS", shape_fibers, 1.0), ("HELIX", shape_helix, .8),
    ("CAGE", shape_cage, .7), ("FRONT", shape_front, .9), ("NEEDLES", shape_needles, .25),
    ("X-FIRE", shape_xfire, .8), ("HALO", shape_halo, .7), ("PINPOINT", shape_pinpoint, .3),
]
# Truss poses: axis program pan/tilt (degrees) -> Kinetics mapAxis:
#   body (240): tilt -> height (x2.4/90 m, -2.4..2), pan -> yaw (-30..30 deg)
#   capsid (241): pan -> spin (deg), tilt -> sheath contract (x2.4/90 m, -1.2..2.4)
#   legs (242-247): pan -> swing (x2.5/90 m), tilt -> foot lift (x4/90 m, 0..4.5)
POSES = [
    ("REST", lambda k: (0, 0)),
    ("RISE", lambda k: (0, 75) if k == 0 else (0, -45) if k == 1 else (0, 22)),
    ("INJECT", lambda k: (0, -90) if k == 0 else (0, 90) if k == 1 else (0, 0)),
    ("BLOOM", lambda k: (8, 38) if k == 0 else (36, 20) if k == 1 else ((45 if k % 2 else -45), (40 if k % 2 else 0))),
]


# A Halo Beam cannot throw its beam more than 45 deg below its mounting plane, toward its own base, at any pan (its
# GDTF tilt is +-135 deg; PHAGE tilt is the GDTF's plus 90). A shape that asks for that cone is refit per head.
TILT_MIN = -45.0
CLAMP_DEG = 12.0      # out of reach by no more than this: clamped to the limit, the beam lands within a few degrees


def fit(f, d, level, ring, vertical=False):
    """A head's aim inside its reach. Out of reach by a little: clamped to the limit. In a look of vertical lines
    (NEEDLES, CATHEDRAL) a head that cannot throw its line up or down throws the other one. Further out it could not
    join the shape: its beam is dark in this look (as CROWN's plate beams are), held at the limit, and its ring keeps
    the look's glow."""
    pan, tilt = aim_angles(f["up"], f["fwd"], d)
    if tilt >= TILT_MIN:
        return pan, tilt, level, ring
    n = norm(d)
    if vertical and abs(n[1]) > .97:
        flip_pan, flip_tilt = aim_angles(f["up"], f["fwd"], mul(n, -1))
        if flip_tilt >= TILT_MIN:
            return flip_pan, flip_tilt, level, ring
    if TILT_MIN - tilt <= CLAMP_DEG:
        return pan, TILT_MIN, level, ring
    return pan, TILT_MIN, 0, ring


CAPSID_AXIS = 241                     # the capsid's truss axis row; its level is its HEADING: 1 FREE, 0 FRONT


def turns_with_capsid(shape_fn, deg=40.0):
    """True when the shape's capsid beams are the same shape at any spin: aiming each head as if the capsid had turned
    gives the beams it would carry round with it. False for a shape aimed at the room (FRONT, X-FIRE) or mirrored
    about the stage's centre line (HALO, HELIX), which only reads facing front."""
    for f in MOVERS:
        if f["family"] != 2: continue
        r = shape_fn(f)
        if r is None: continue
        g = {**f, "pos": turn(f["pos"], deg), "up": turn(f["up"], deg), "fwd": turn(f["fwd"], deg)}
        a, b = norm(turn(r[0], deg)), norm(shape_fn(g)[0])
        if sum(x * y for x, y in zip(a, b)) < math.cos(math.radians(1.0)):
            return False
    return True


def static_rows(shape_fn, bar_level, vertical=False):
    """A beam shape's rows. A shape that only reads with the capsid facing front sets the capsid's HEADING to FRONT,
    so the capsid stops spinning and turns back to the heading it was aimed for; any other shape frees it."""
    rows = {}
    for f in MOVERS:
        r = shape_fn(f)
        if r is None: continue
        pan, tilt, level, ring = fit(f, *r, vertical=vertical)
        rows[f["slot"]] = {"pan": pan, "tilt": tilt, "level": level, "ring": ring}
    for f in BARS:
        rows[f["slot"]] = {"level": bar_level}
    rows[CAPSID_AXIS] = {"level": 1.0 if turns_with_capsid(shape_fn) else 0.0}
    return rows


def pose_rows(pose_fn):
    return {f["slot"]: dict(zip(("pan", "tilt"), pose_fn(f["slot"] - 240))) for f in AXES}


VERTICAL = {"CATHEDRAL", "NEEDLES"}          # looks made of vertical lines (fit)
STATIC = [(name, static_rows(fn, bars, name in VERTICAL)) for name, fn, bars in BEAM_SHAPES] + \
         [(name, pose_rows(fn)) for name, fn in POSES]


# --- COLOR looks ----------------------------------------------------------------------------------------
# The 8-palette library (A, B, C) shared by every colour and full look, as 0xRRGGBB.
PALETTES = [
    ("ICE", [(70, 180, 255), (228, 244, 255), (20, 50, 255)]),
    ("PHAGE", [(0, 255, 185), (255, 30, 150), (120, 40, 255)]),
    ("INFRARED", [(255, 25, 8), (255, 115, 0), (150, 0, 40)]),
    ("SODIUM", [(255, 140, 30), (255, 214, 150), (255, 60, 0)]),
    ("VIRAL", [(150, 255, 10), (0, 255, 80), (0, 150, 135)]),
    ("UV", [(115, 20, 255), (255, 0, 190), (25, 0, 170)]),
    ("SUNSET", [(255, 36, 118), (255, 150, 20), (140, 30, 255)]),
    ("WHITE", [(255, 255, 255), (255, 232, 200), (200, 224, 255)]),
]
A, B, C = 0, 1, 2
CAPSID_FAM = {2, 14, 25, 26}
LEG_FAM = {3, 6, 12, 13, 20, 21}


def route_mono(f): return (A, B)
def route_zones(f):
    fam = f["family"]
    if fam in CAPSID_FAM: return (C, A)
    if fam in LEG_FAM: return (B, A)
    return (A, B)
def route_updown(f): return (A, C) if f["rest"][1] > 9 else (C, A)
def route_lowup(f): return (B, A) if f["rest"][1] > 9 else (A, B)
def route_sides(f): return (A, B) if f["rest"][0] < -.05 else (B, A) if f["rest"][0] > .05 else (C, C)
def route_alt(f): return (A, C) if f["index"] % 2 else (C, A)
def route_rings(f): return (A, C)
def route_glacier(f): return (B, A) if f["rest"][1] > 9 else (C, A)


COLORS = [  # (name, palette, routing)
    ("WHITE", 7, route_mono), ("ICE", 0, route_mono), ("PHAGE", 1, route_zones), ("INFRARED", 2, route_mono),
    ("SODIUM", 3, route_mono), ("VIRAL", 4, route_mono), ("UV", 5, route_mono), ("ROSE", 6, route_mono),
    ("GLACIER", 0, route_glacier), ("BIOLUME", 1, route_mono), ("MAGMA", 2, route_lowup), ("DUSK", 6, route_lowup),
    ("TOXIC", 4, route_zones), ("UV SPLIT", 5, route_sides), ("CORAL", 6, route_alt), ("SPLIT", 1, route_sides),
]


def color_rows(route):
    rows = {}
    for f in FX:
        if f["unused"] or f["kind"] == 3: continue
        beam, ring = route(f)
        rows[f["slot"]] = {"beam_palette": beam, "ring_palette": ring}
    return rows


def packed(rgb): return rgb[0] << 16 | rgb[1] << 8 | rgb[2]


def palette_records(active):
    rec = {}
    for p, (_, cols) in enumerate(PALETTES):
        for s, key in enumerate("abc"): rec[f"pal{p}{key}"] = float(packed(cols[s]))
    rec["palette"] = float(active)
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in PALETTES[active][1][0]))
    rec.update({"hue": round(h, 4), "sat": round(s, 4), "val": round(v, 4)})
    return rec


# --- FULL looks, globals, rhythm ---------------------------------------------------------------------------
RHYTHM = {"rhythm_1_mode": 0.0, "rhythm_1_cycle": 1.0, "rhythm_1_rest": 0.0, "rhythm_1_offset": 0.0,      # KICK: every beat
          "rhythm_2_mode": 0.0, "rhythm_2_cycle": 1.0, "rhythm_2_rest": 1.0, "rhythm_2_offset": 1.0,      # SNARE: 2 and 4
          "rhythm_3_mode": 0.0, "rhythm_3_cycle": .5, "rhythm_3_rest": .5, "rhythm_3_offset": .5}         # HI-HAT: the offbeat
GLOBAL_DEFAULT = {"master": 1.0, "exposure": 1.0, "bloom": .12, "sensor_white_start": 2.0,
                  "sensor_white_response": .16, "streak_strength": .005, "streak_length": .08, "haze": .03}
# --- packing ------------------------------------------------------------------------------------------------
def fmt(key, value):
    lo, hi = LIMIT[key]
    v = min(hi, max(lo, value))
    s = "%.7g" % (round(v, 3) if key in ("pan", "tilt", "pan_amp", "tilt_amp") else round(v, 4))
    return "0" if s == "-0" else s


def pack(rows, keys):
    """8 banks of 32 slots: '1;row;row' with '_' where a look leaves a value untouched."""
    banks = []
    for b in range(BANKS):
        out = ["1"]
        for slot in range(b * 32, min(SLOTS, b * 32 + 32)):
            row = rows.get(slot, {})
            out.append(",".join(fmt(k, row[k]) if k in row else "_" for k in keys))
        text = ";".join(out)
        assert len(text) < 4096, f"bank {b} is {len(text)} chars"
        banks.append(text)
    return banks


def banks_snapshot(prefix, rows, keys):
    return {f"{STATE}saved_{prefix}_bank_{b}": t for b, t in enumerate(pack(rows, keys))}


def merge(*layers):
    rows = {}
    for layer in layers:
        for slot, row in layer.items(): rows.setdefault(slot, {}).update(row)
    return rows


def effects_snapshot(rows):
    """An effects bank in the layered format: one partition per 32 slots."""
    return {f"{STATE}saved_effects_bank_{b}": pack_part(rows, EFFECT_F, part) for b, part in enumerate(PARTS)}


def group(kind, presets):
    paths = sorted({p for _, snap in presets for p in snap})
    return {"id": f"phage_stage_{kind}", "paths": paths,
            "presets": [{"id": f"phage_stage_{kind}:{kind} {i}", "name": f"{kind} {i}", "revision": 1,
                         "snapshot": snap} for i, (_, snap) in enumerate(presets, 1)]}


# --- fixture banks (Push pad pages 2-4) ---------------------------------------------------------------------
# Each fixture type is programmed as layers, one program row each (tools/phage_program.py): a mover's MOVE (its base
# row), BEAM (slot + 248) and HALO (slot + 376); a strobe's TUBE (base) and PLATES (slot + 376); a pixel bar's PIXELS
# (base) and CHASE (slot + 376). A bank partition k holds slots 32k..32k+31's base rows, then their BEAM rows, then
# their second-layer rows (scripts/show/rig_codec.luau), and each row stores only the fields its layer owns
# (attribute_catalog kinds). A layer bank stores that layer's effect rows; a whole-fixture bank all its type's layers
# with their aim and levels (static_rig FX_FAMILIES / FX_STATIC).
BEAM0, LAYER2 = 248, 376
BASE_LAYER = {0: "move", 1: "tube", 2: "pixels", 3: "axis"}
SECOND_LAYER = {0: "halo", 1: "plates", 2: "chase"}
OWNS = {
    "move": {"pan", "tilt", "move_lane", "pan_amp", "tilt_amp", "spread", "offset", "reverse", "look", "order", "width"},
    "beam": {"level", "beam_palette", "int_lane", "color_lane", "width", "spread", "offset", "reverse", "look", "order"},
    "halo": {"ring", "ring_palette", "int_lane", "color_lane", "width", "spread", "offset", "reverse", "look", "order"},
    "tube": {"level", "int_lane", "width", "spread", "offset", "reverse", "look", "order"},
    "plates": {"ring", "beam_palette", "int_lane", "color_lane", "width", "spread", "offset", "reverse", "look", "order"},
    "pixels": {"level", "beam_palette", "ring_palette", "int_lane", "color_lane", "spread", "width", "offset", "reverse",
               "look", "order"},
    "chase": {"level", "int_lane", "width", "spread", "offset", "reverse", "look", "order"},
    "axis": {"pan", "tilt", "level", "move_lane", "pan_amp", "tilt_amp", "spread", "offset", "reverse", "look", "order",
             "width"},                                     # an axis row's level is its HEADING
}
FX_FAMILIES = {"move": {"move"}, "beam": {"beam"}, "halo": {"halo"}, "heads": {"move", "beam", "halo"},
               "tube": {"tube"}, "plates": {"plates"}, "strobes": {"tube", "plates"},
               "pixels": {"pixels"}, "chase": {"chase"}, "battens": {"pixels", "chase"},
               # SEQUENCES (pad page 5): the whole rig, then each fixture type's part of the same sequences
               "sequence": {"move", "beam", "halo", "tube", "plates", "pixels", "chase"},
               "seq_heads": {"move", "beam", "halo"}, "seq_strobes": {"tube", "plates"},
               "seq_battens": {"pixels", "chase"}}
FX_STATIC = {"heads", "strobes", "battens", "sequence", "seq_heads", "seq_strobes", "seq_battens"}
CLOCKED = {"tube", "pixels", "chase"}       # layers that run on the show's strobe clock (the plates never flash on it)
STATIC_MASK = {"pan", "tilt", "level", "ring"}           # a whole-fixture bank's aim and levels (palettes stay COLOR's)


def partitions():
    parts = []
    for b in range(BANKS):
        first, last = b * 32, min(SLOTS, b * 32 + 32)
        part = [(s, BASE_LAYER[FX[s]["kind"]]) for s in range(first, last)]
        part += [(BEAM0 + s, "beam") for s in range(first, last) if FX[s]["kind"] == 0]
        part += [(LAYER2 + s, SECOND_LAYER[FX[s]["kind"]]) for s in range(first, last) if FX[s]["kind"] in SECOND_LAYER]
        parts.append(part)
    return parts


PARTS = partitions()


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


def fixture_snapshot(kind, rows, rate, duty, clock=True):
    """A fixture preset: the partitions that hold its family's rows, plus the strobe clock when a layer runs on it and
    the pad uses it."""
    family = FX_FAMILIES[kind]
    snap = {}
    for b, part in enumerate(PARTS):
        own = {row: rows[row] for row, layer in part if layer in family and row in rows}
        if not any(layer in family for _, layer in part):
            continue
        snap[f"{STATE}saved_effects_bank_{b}"] = pack_part(own, EFFECT_F, part)
        if kind in FX_STATIC:
            snap[f"{STATE}saved_static_bank_{b}"] = pack_part(own, STATIC_F, part, STATIC_MASK)
    if family & CLOCKED and clock:
        snap[f"{STATE}show_strobe_rate"] = float(rate)
        snap[f"{STATE}show_strobe_duty"] = float(duty)
    return snap


def light_code(code):
    """A mover FX code as a light layer reads it: repeats and RND kept, JMP and STEP (movement only) dropped."""
    return 16 + ((int(round(code)) - 16) & 7) if 15.5 < code < 47.5 else code


def layer_rows(slot_rows):
    """Program rows (base and layer) from per-slot rows: every layer of a fixture starts from its slot's row, as a look
    stored before the layers recalls (rig_codec upgrade). CHASE rows hold no lane (x1)."""
    rows = {}
    for s, row in slot_rows.items():
        kind = FX[s]["kind"]
        rows[s] = dict(row)
        if kind == 0:   # a beam or halo takes its mover's chase bits only: JMP and STEP move heads (24-27 is HOLD on light)
            light = {**row, "look": light_code(row.get("look", 0))}
            rows[BEAM0 + s] = light
            rows[LAYER2 + s] = dict(light)
        if kind == 1: rows[LAYER2 + s] = dict(row)
        if kind == 2: rows[LAYER2 + s] = {**{k: DEFAULT[k] for k in EFFECT_F}, "level": 1}
    return rows


# --- MOVE FX and BEAM FX: choreographed per group ----------------------------------------------------------------
# The Halo Beams hang in seven groups, and every pad gives each group its own part: what it does, on which lane, when
# in the step it sets off (offset) and how a move or a pulse runs through it (order, spread). A group a pad does not
# name holds still (MOVE) or burns steady (BEAM). Nothing circles and nothing twists round a ring: movement is a GLIDE
# (a lean across the stage and a rise, the same for every head of a group), a nod or the build's lift, and every move is
# eased.
# Halo Beam move sizes per group (pan = lean across the stage, rise), for GLIDE parts in MOVE FX and the EFFECTS looks.
BIG = {"capsid": (40, 24), "collar": (34, 18), "plate": (28, 18), "knee": (30, 26), "booth": (20, 10), "foot": (26, 28)}
MID = {"capsid": (26, 16), "collar": (24, 12), "plate": (20, 12), "knee": (22, 18), "booth": (15, 8), "foot": (20, 18)}
GROUPS = {"plate": {0, 1}, "plate_out": {0}, "plate_in": {1}, "capsid": {2}, "knee": {3}, "collar": {4}, "booth": {5},
          "foot": {6}}


def group_part(f, parts):
    """The part a pad gives this head's group: the most specific group named (plate_out before plate)."""
    hit = None
    for name, attrs in parts.items():
        if f["family"] in GROUPS[name] and (hit is None or len(GROUPS[name]) < len(GROUPS[hit[0]])):
            hit = (name, attrs)
    return hit[1] if hit else {}


MOVE_REST = dict(move_lane=OFF, pan_amp=0, tilt_amp=0, spread=0, offset=0, reverse=0, look=0, order=AROUND, width=.5)


def move_rows(parts):
    """MOVE rows: `rise` is tilt toward the sky (signed per mount), `glide` the share of a step a move takes."""
    rows = {}
    for f in MOVERS:
        part = group_part(f, parts)
        row = dict(MOVE_REST)
        for k, v in part.items():
            if k == "rise": row["tilt_amp"] = -v if HANGING(f) else v
            elif k == "pan": row["pan_amp"] = v
            elif k == "glide": row["width"] = v
            elif k == "lane": row["move_lane"] = v
            else: row[k] = v
        rows[f["slot"]] = row
    return rows


# lane, pan, rise and the GLIDE share, per group. Lanes at a typical 124-200 BPM: PHRASE is 16 beats, x2 8, x4 4.
def _turns(repeats, glide_share, offsets, amps, group=True, spread=0.0, order=AROUND):
    return {g: dict(lane=PHRASE, look=glide(repeats, group=group, rnd=not group), glide=glide_share, spread=spread,
                    order=order, offset=offsets.get(g, 0), pan=amps[g][0], rise=amps[g][1]) for g in amps}


STAGE6 = {"capsid": 0, "collar": 1 / 6, "knee": 2 / 6, "plate": 3 / 6, "booth": 4 / 6, "foot": 5 / 6}
MOVE_FX = [
    # ---- calm: still, drifting, breathing
    ("HOLD", {}),
    ("DRIFT", {g: dict(lane=PHRASE, look=glide(1, rnd=True), glide=.95, spread=.9, order=SHUFFLE, pan=a[0], rise=a[1])
               for g, a in {"capsid": (24, 14), "collar": (22, 12), "plate": (18, 10), "knee": (18, 14),
                            "booth": (14, 7), "foot": (18, 14)}.items()}),
    ("BREATH", {g: dict(lane=PHRASE, pan=0, rise=r, spread=.5, order=UP)
                for g, r in {"capsid": 8, "collar": 10, "plate": 10, "knee": 8, "booth": 6, "foot": 8}.items()}),
    ("WAVE", {**{g: dict(lane=PHRASE, pan=0, rise=12, spread=.95, order=AROUND) for g in ("capsid", "collar", "plate")},
              "booth": dict(lane=PHRASE, pan=0, rise=6, spread=.95, order=AROUND),
              "knee": dict(lane=PHRASE, pan=0, rise=10, spread=.95, order=LEG),
              "foot": dict(lane=PHRASE, pan=0, rise=10, spread=.95, order=LEG, offset=.5)}),
    # ---- groove: sweeps and positions walking through the rig
    ("SCAN", {"plate_out": dict(lane=PHRASE, look=glide(2), glide=.85, pan=28, rise=0, spread=.5, order=MIRROR),
              "plate_in": dict(lane=PHRASE, look=glide(2), glide=.85, pan=22, rise=0, spread=.5, order=MIRROR,
                               reverse=1),
              "booth": dict(lane=PHRASE, look=glide(2), glide=.85, pan=20, rise=0, spread=.5, order=SIDE,
                            offset=.25)}),
    ("SCISSOR", {"plate_out": dict(lane=PHRASE, look=glide(2), glide=.85, pan=25, rise=0, order=MIRROR),
                 "plate_in": dict(lane=PHRASE, look=glide(2), glide=.85, pan=-25, rise=0, order=MIRROR),
                 "collar": dict(lane=PHRASE, look=glide(2), glide=.85, pan=20, rise=0, offset=.25, order=MIRROR),
                 "knee": dict(lane=PHRASE, pan=0, rise=15),
                 "foot": dict(lane=PHRASE, pan=0, rise=15, offset=.5)}),
    ("AROUND", {**_turns(2, .5, {}, {g: MID[g] for g in ("capsid", "collar", "plate", "booth")}, group=False, spread=1),
                **_turns(2, .5, {}, {g: MID[g] for g in ("knee", "foot")}, group=False, spread=1, order=LEG)}),
    ("CASCADE", _turns(2, .6, {}, MID, group=False, spread=.9, order=UP)),
    # ---- build: groups taking turns, formations, the lift
    ("LEGS", {"knee": dict(lane=PHRASE, look=glide(2, group=True), glide=.5, spread=.5, order=LEG, pan=30, rise=26),
              "foot": dict(lane=PHRASE, look=glide(2, group=True), glide=.5, spread=.5, order=LEG, offset=.25, pan=26,
                           rise=28)}),
    ("STAGES", _turns(1, .25, STAGE6, BIG)),
    ("FORMATIONS", _turns(2, .5, {g: o * .9 for g, o in STAGE6.items()}, BIG, spread=.3)),
    ("RISE", {g: dict(lane=BUILD, pan=0, rise=r)
              for g, r in {"capsid": 20, "collar": 35, "plate": 40, "knee": 30, "booth": 30, "foot": 35}.items()}),
    # ---- crazy: unison shifts, storms, riots, shatters
    ("SHIFT", _turns(1, .7, {}, BIG, group=False)),
    ("STORM", {**_turns(2, .6, {}, {"capsid": (40, 25), "collar": (35, 20), "plate": (25, 15), "booth": (10, 5)},
                        group=False, spread=.9, order=SHUFFLE)}),
    ("RIOT", _turns(2, .55, {"capsid": 0, "collar": .25, "plate": .5, "knee": .75, "booth": .5, "foot": .75},
                    {**BIG, "capsid": (45, 25), "collar": (40, 20)}, group=False, spread=.15)),
    ("SHATTER", _turns(2, .3, {"capsid": 0, "knee": .5, "collar": .25, "plate": .75, "booth": .5, "foot": 0}, BIG)),
]

MOVE_SIZE = 1.5       # MOVE FX sizes over the shared ones: a pad is a move on its own, so it moves more than an EFFECTS look
MOVE_FX = [(name, {g: {**p, **{k: p[k] * MOVE_SIZE for k in ("pan", "rise") if k in p}} for g, p in parts.items()})
           for name, parts in MOVE_FX]

BEAM_REST = dict(int_lane=OFF, color_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=0, order=AROUND)


def beam_rows(parts):
    """BEAM rows (slot + 248): a group the pad does not name burns steady at its level."""
    rows = {}
    for f in MOVERS:
        row = dict(BEAM_REST)
        for k, v in group_part(f, parts).items():
            row["int_lane" if k == "lane" else k] = v
        rows[BEAM0 + f["slot"]] = row
    return rows


def _each(groups, **attrs):
    return {g: dict(attrs) for g in groups}


ALL = ("capsid", "collar", "plate", "knee", "booth", "foot")
RINGS = ("capsid", "collar", "plate", "booth")
LIMBS = ("knee", "foot")
BEAM_FX = [
    # ---- calm
    ("STEADY", {}),
    ("BREATHE", _each(ALL, lane=PHRASE, width=.95, spread=.35, order=UP)),
    ("TURNS", {g: dict(lane=PHRASE, width=.22, spread=.05, offset=-o) for g, o in STAGE6.items()}),
    ("RISE", _each(ALL, lane=PHRASE, look=mov(2), width=.5, spread=.9, order=UP)),
    # ---- groove: one group on the kick, the others answering or holding
    ("CROWN", _each(("capsid", "knee"), lane=KICK, width=.45)),
    ("CALL", {**_each(("capsid", "collar"), lane=KICK, width=.45), **_each(("plate", "booth"), lane=SNARE, width=.5)}),
    ("AROUND", {**_each(RINGS, lane=PHRASE, look=mov(4), width=.45, spread=.9, order=AROUND),
                **_each(LIMBS, lane=PHRASE, look=mov(4), width=.45, spread=.9, order=LEG)}),
    ("OUTWARD", _each(ALL, lane=PHRASE, look=mov(2), width=.5, spread=.9, order=OUTWARD)),
    # ---- build: walks, runs and the ramp
    ("LEGS", _each(LIMBS, lane=PHRASE, look=mov(2), width=.35, spread=1, order=LEG)),
    ("COLLAR RUN", {"collar": dict(lane=SNARE, width=.5, spread=.9, order=AROUND),
                    "capsid": dict(lane=PHRASE, width=.9, spread=.3, order=UP)}),
    ("ROLL", {g: dict(lane=KICK, width=.3, offset=-o) for g, o in
              {"capsid": 0, "collar": .25, "plate": .5, "booth": .75}.items()}),
    ("BUILD", _each(ALL, lane=BUILD, width=.5, spread=.8, order=UP)),
    # ---- crazy: still per group, never everything at once
    ("STAGGER", {**_each(("capsid", "plate"), lane=KICK, width=.4), **_each(("collar", "booth"), lane=KICK, width=.4,
                                                                             offset=-.5)}),
    ("SPARK", _each(ALL, lane=PHRASE, look=mov(4, rnd=True), width=.5)),
    ("STORM", {"capsid": dict(lane=KICK, look=mov(1, rnd=True), width=.5),
               "collar": dict(lane=SNARE, look=mov(1, rnd=True), width=.5),
               "plate": dict(lane=PHRASE, look=mov(4, rnd=True), width=.5),
               "knee": dict(lane=PHRASE, look=mov(2, rnd=True), width=.5, order=LEG),
               "foot": dict(lane=PHRASE, look=mov(2, rnd=True), width=.5, order=LEG)}),
    ("SUPERNOVA", _each(ALL, lane=KICK, width=.6, spread=.9, order=OUTWARD)),
]


# --- TUBE FX and PLATES FX: the Linear Strobes choreographed per group ------------------------------------------------
# 47 strobes in six groups, each a white tube between two colour plates. TUBE FX is the white accent and PLATES FX the
# colour; in both a group a pad does not name stays dark. Restraint is the point: most pads name one or two groups, and
# inside a group the tubes take turns (a narrow WIDTH with the SPREAD near 1 lights one at a time in the ORDER: AROUND a
# ring, LEG by leg, UP the rig, SIDE to side, SHUFFLE at random), so only WASH, DROP and WHITEOUT light much at once.
# A part names the look (STROBE: PULSE, STROBE at the clock, SPARKLE, BLINDER), the lane, and how it runs through and
# between the groups (width, spread, order, offset). The clock is per beat: RATE 2 at 124-200 BPM is 4-7 flashes a
# second, 4 is 8-13.
STROBE_GROUPS = {"collar": 10, "plate": 11, "knee": 12, "foot": 13, "capsid": 14, "booth": 15}
TUBE_REST = dict(int_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=STROBE["OFF"], order=AROUND)
PLATES_REST = dict(int_lane=OFF, color_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=STROBE["OFF"],
                   order=AROUND)


def strobe_rows(parts, rest, layer):
    """TUBE rows (the strobe's base row) or PLATES rows (slot + 376) from per-group parts; `lane` is the chase lane."""
    rows = {}
    for f in STROBES:
        g = next(n for n, fam in STROBE_GROUPS.items() if f["family"] == fam)
        rows[layer + f["slot"]] = {**rest, **{("int_lane" if k == "lane" else k): v for k, v in parts.get(g, {}).items()}}
    return rows


def _st(look, lane=OFF, **kw): return dict(look=STROBE[look] if isinstance(look, str) else look, lane=lane, **kw)


S_ALL = ("capsid", "collar", "knee", "plate", "foot", "booth")
S_STAGE = {"capsid": 0, "collar": 1 / 6, "knee": 2 / 6, "plate": 3 / 6, "foot": 4 / 6, "booth": 5 / 6}
# Left to right across the legs: SIDE ranks by x over the whole rig, so each group needs its own spread for its two sides
# to land half a cycle apart (knees span x +-11.5 m, feet +-17.7 m).
SWING = {"knee": .83, "foot": .55}
TUBE_FX = [   # (name, parts, clock rate per beat, duty)
    # ---- breakdown: almost nothing, one group or one tube at a time
    ("DARK", {}, 2, .3),
    ("PING", {g: _st(mov(4, rnd=True), PHRASE, width=.12, spread=.95, order=SHUFFLE) for g in ("capsid", "collar", "knee")},
     2, .3),
    ("HEARTBEAT", {"capsid": _st("PULSE", KICK, width=.25)}, 2, .3),
    ("SUNRISE", {"booth": _st("BLINDER", PHRASE), "capsid": _st("BLINDER", PHRASE, offset=.5)}, 2, .3),
    # ---- groove: a pattern each, on one or two groups
    ("SWEEP", {g: _st("PULSE", KICK, width=.25, spread=sp, order=SIDE) for g, sp in SWING.items()}, 2, .3),
    ("WALKER", {"plate": _st(mov(4), PHRASE, width=.08, spread=.95, order=AROUND)}, 2, .3),
    ("STRIDE", {g: _st(mov(4), PHRASE, width=.15, spread=.95, order=LEG) for g in ("knee", "foot")}, 2, .3),
    ("HATS", {"foot": _st("PULSE", HAT, width=.3, spread=.95, order=SHUFFLE)}, 2, .3),
    # ---- build: the BUILD lane ramps over 16 beats from the recall, pulses doubling
    ("LADDER", {g: _st("PULSE", BUILD, width=.1, spread=.95, order=UP) for g in S_ALL}, 2, .3),
    ("ROLL", {g: _st("PULSE", BUILD, width=.12, offset=-o) for g, o in
              {"capsid": 0, "collar": .2, "knee": .4, "plate": .6, "foot": .8}.items()}, 2, .3),
    ("CONVERGE", {g: _st("PULSE", BUILD, width=.1, spread=.95, order=OUTWARD, reverse=1) for g in S_ALL}, 2, .3),
    ("RISER", {g: _st("STROBE", BUILD, width=.6) for g in ("capsid", "collar")}, 4, .4),
    # ---- drop: the hits, still aimed
    ("DROP", {g: _st("STROBE", KICK, width=.35) for g in ("plate", "booth")}, 4, .4),
    ("CROSSFIRE", {g: _st("STROBE", KICK, width=.3, spread=sp, order=SIDE) for g, sp in SWING.items()}, 4, .4),
    ("STORM", {g: _st("SPARKLE", KICK) for g in ("plate", "booth", "foot")}, 2, .25),
    ("WHITEOUT", {g: _st("STROBE") for g in S_ALL}, 4, .4),
]
PLATES_FX = [
    # ---- calm
    ("WASH", {g: _st("PULSE") for g in S_ALL}),
    ("EMBERS", {g: _st(mov(2, rnd=True), PHRASE, width=.35, spread=.95, order=SHUFFLE) for g in S_ALL}),
    ("TIDE", {g: _st("PULSE", PHRASE, width=.35, spread=.95, order=UP, color_lane=PHRASE) for g in S_ALL}),
    ("ISOLATE", {"booth": _st("PULSE"), "capsid": _st("PULSE", PHRASE, width=.95)}),
    # ---- groove
    ("SEESAW", {g: _st(mov(4), PHRASE, width=.45, spread=sp, order=SIDE) for g, sp in SWING.items()}),
    ("CALL", {**{g: _st("PULSE", KICK, width=.4) for g in ("capsid", "collar")}, "booth": _st("PULSE", SNARE, width=.5)}),
    ("ORBIT", {g: _st(mov(4), PHRASE, width=.15, spread=.95, order=AROUND, color_lane=PHRASE) for g in ("plate", "collar")}),
    ("STRIDE", {g: _st(mov(4), PHRASE, width=.25, spread=.95, order=LEG) for g in ("knee", "foot")}),
    # ---- build
    ("TURNS", {g: _st("PULSE", PHRASE, width=.2, spread=.05, offset=-o) for g, o in S_STAGE.items()}),
    ("ROLL", {g: _st("PULSE", KICK, width=.3, offset=-o) for g, o in
              {"capsid": 0, "collar": .25, "plate": .5, "booth": .75}.items()}),
    ("RISE", {g: _st("PULSE", BUILD, width=.15, spread=.95, order=UP) for g in S_ALL}),
    ("BLOOM", {g: _st("PULSE", KICK, width=.2, spread=.95, order=OUTWARD) for g in S_ALL}),
    # ---- crazy
    ("STAGGER", {**{g: _st("PULSE", KICK, width=.3) for g in ("capsid", "plate")},
                 **{g: _st("PULSE", KICK, width=.3, offset=-.5) for g in ("collar", "booth")}}),
    ("SPARK", {g: _st(mov(2, rnd=True), KICK, width=.2, spread=.95, order=SHUFFLE) for g in S_ALL}),
    ("BLINDERS", {"plate": _st("BLINDER", KICK), "capsid": _st("BLINDER", SNARE)}),
    ("SUPERNOVA", {g: _st("PULSE", KICK, width=.6, spread=.9, order=OUTWARD) for g in S_ALL}),
]
# STROBES, the whole Linear Strobe (page 3): a TUBE FX pad over a PLATES FX pad, tubes and plates at full, the tube
# pad's clock; then BLACKOUT.
STROBE_LOOKS = [
    ("AMBIENT", "DARK", "EMBERS"), ("TWINKLE", "PING", "TIDE"), ("PULSAR", "HEARTBEAT", "ISOLATE"),
    ("DAWN", "SUNRISE", "WASH"),
    ("SWEEPER", "SWEEP", "SEESAW"), ("ORBITAL", "WALKER", "ORBIT"), ("STRIDER", "STRIDE", "STRIDE"),
    ("SHIMMER", "HATS", "CALL"),
    ("LADDER", "LADDER", "RISE"), ("DRUMROLL", "ROLL", "ROLL"), ("IMPLODE", "CONVERGE", "TURNS"),
    ("RISER", "RISER", "SPARK"),
    ("DROP", "DROP", "BLOOM"), ("CROSSFIRE", "CROSSFIRE", "STAGGER"), ("WHITEOUT", "WHITEOUT", "SUPERNOVA"),
]


def strobe_look_rows(tube, plates):
    rows = strobe_rows(dict((n, p) for n, p, *_ in TUBE_FX)[tube], TUBE_REST, 0)
    rows.update(strobe_rows(dict(PLATES_FX)[plates], PLATES_REST, LAYER2))
    for f in STROBES:
        rows[f["slot"]]["level"] = 1.0
        rows[LAYER2 + f["slot"]]["ring"] = 1.0
    return rows


# --- PIXEL FX, CHASE FX and BATTENS: the Pixel Battens choreographed through the phage --------------------------------
# 47 bars in eight groups that follow the phage's anatomy: the SHEATH (5 rings stacked up the core, 6.6-10.4 m), the
# COLLAR (2 rings), the CAPSID struts and its three LINK rings (13-19 m), the PLATE edge (6 bars round the base plate),
# the legs' UPPER bars (hip out and up to the knee) and LOWER bars (knee out and down to the ankle), and the BOOTH.
# On the legs a bar's pixels run outward (u 0 at the hip, 1 at the ankle), so a CHASE with DIRECTION forward runs out
# the legs and reverse runs in.
#   PIXEL FX is what each group shows: a content pattern, how many times per lane cycle it runs (x1-x8, codes +16), its
#     direction and colour lane. A pad names every group, a composition.
#   CHASE FX is when each group shows: a PULSE dip, or HOLD (codes 24-27), a window of each lane cycle outside which the
#     group is dark. HOLD windows hand the light from group to group, so a CHASE pad is a sequence through the anatomy:
#     IGNITION runs the core, out the legs, round the plate, up through the collar into the capsid, and bursts.
#   BATTENS pairs a content with a sequence.
BAR_GROUPS = {"upper": 20, "lower": 21, "plate": 22, "sheath": 23, "collar": 24, "capsid": 25, "link": 26, "booth": 27}
B_ALL = tuple(BAR_GROUPS)
B_LEGS = ("upper", "lower")
PIXELS_REST = dict(int_lane=OFF, color_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=BAR["SOLID"], order=AROUND)
CHASE_OPEN = dict(int_lane=OFF, color_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=0, order=AROUND)


def px(pattern, lane=OFF, speed=1, **kw):
    """A PIXEL FX part: the content, run x1-x8 per lane cycle."""
    return dict(look=BAR[pattern] + 16 * {1: 0, 2: 1, 4: 2, 8: 3}[speed], lane=lane, **kw)


def bar_rank(f, order, reverse=0):
    """phRank (phage_show.hlsli) on a bar's rest position."""
    x, y, z = f["pos"]
    around = (math.atan2(x, z) / (2 * math.pi) + 1) % 1 if abs(x) + abs(z) > 1e-4 else 0.0
    r = {MIRROR: lambda: abs(around - .5) * 2, OUTWARD: lambda: min(1.0, math.hypot(x, z) / 19),
         UP: lambda: min(1.0, max(0.0, y / 22)), FRONT: lambda: min(1.0, max(0.0, (16 - z) / 32)),
         SIDE: lambda: min(1.0, max(0.0, (x + 19) / 38)),
         SHUFFLE: lambda: (math.sin((f["slot"] * 1.618 + .37) * 12.9898 + 4.1414) * 43758.5453) % 1,   # phHash1
         LEG: lambda: (f["leg"] + .5) / 6 if f["leg"] >= 0 else around}.get(order, lambda: around)()
    return 1 - r if reverse > .5 else r


def window(fixtures, lane, start, length, repeats=1, spread=0.0, order=AROUND, reverse=0):
    """A HOLD window (codes 24-27, any light layer): the fixtures show from `start` for `length` of each lane cycle
    (x repeats; both in fractions of the repeated cycle), opening one after another by rank x spread from `start` on."""
    lo = min(bar_rank(f, order, reverse) for f in fixtures)
    return dict(look=24 + {1: 0, 2: 1, 4: 2, 8: 3}[repeats], lane=lane, width=length, spread=spread, order=order,
                reverse=reverse, offset=(-start + lo * spread) / repeats)


def hold(group, *args, **kw):
    """A batten group's HOLD window."""
    return window([f for f in BARS if f["family"] == BAR_GROUPS[group]], *args, **kw)


DARK_WINDOW = dict(look=24, lane=PHRASE, width=.01)     # HOLD at its narrowest never opens: the group stays dark


def chase_part(look, lane, **kw): return dict(look=STROBE[look] if isinstance(look, str) else look, lane=lane, **kw)


def bar_rows(parts, rest, layer):
    """PIXELS rows (the bar's base row) or CHASE rows (slot + 376) from per-group parts; `lane` is the lane."""
    rows = {}
    for f in BARS:
        g = next(n for n, fam in BAR_GROUPS.items() if f["family"] == fam)
        rows[layer + f["slot"]] = {**rest, **{("int_lane" if k == "lane" else k): v for k, v in parts.get(g, {}).items()}}
    return rows


# The journey content: the core and the plate lit, the legs carrying a pulse outward once every 2 beats of the phrase
# (lined up with the HOLD windows of IGNITION and INJECT, which open on odd 2-beat marks), the collar spinning, the
# capsid bursting on the kick and the booth strobing.
JOURNEY = {"sheath": px("SOLID"), "plate": px("SOLID"), "link": px("SOLID"), "booth": px("STROBE", KICK),
           "upper": px("CHASE", PHRASE, 8, width=.5, offset=-.5), "lower": px("CHASE", PHRASE, 8, width=.5, offset=-.5),
           "collar": px("CHASE", PHRASE, 8, width=.4), "capsid": px("RIPPLE", KICK, width=.4)}
PIXEL_FX = [   # (name, parts, clock rate per beat, duty or None when nothing in it runs on the clock)
    # ---- calm
    ("GLOW", {g: px("SOLID") for g in B_ALL}, None),
    ("PLASMA", {g: px("PLASMA", PHRASE, spread=.5) for g in B_ALL}, None),
    ("EMBERS", {**{g: px("SPARKLE") for g in ("upper", "lower", "plate", "capsid")},
                "sheath": px("PULSE", PHRASE, 4, spread=.5, order=UP), "collar": px("PULSE", PHRASE, 4, offset=.5),
                "link": px("PULSE", PHRASE, 2, spread=.5, order=UP), "booth": px("SOLID")}, None),
    ("TIDE", {g: px("CLIMB", PHRASE, width=.5) for g in B_ALL}, None),
    # ---- groove
    ("VEINS", {**{g: px("CHASE", KICK, width=.4) for g in B_LEGS},
               "sheath": px("CHASE", PHRASE, 8), "collar": px("CHASE", PHRASE, 8, reverse=1),
               "plate": px("COMET", PHRASE, 4, spread=.95, order=AROUND), "capsid": px("COMET", KICK),
               "link": px("CHASE", KICK), "booth": px("PULSE", KICK)}, None),
    ("JOURNEY", JOURNEY, (4, .4)),
    ("SCANNER", {**{g: px("SCANNER", SNARE) for g in B_LEGS}, "sheath": px("SEGMENTS", KICK, spread=.5, order=UP),
                 "collar": px("SEGMENTS", KICK), "plate": px("SCANNER", KICK, spread=.95, order=AROUND),
                 "capsid": px("TWIN", KICK), "link": px("TWIN", SNARE), "booth": px("SCANNER", KICK)}, None),
    ("HEART", {**{g: px("HEARTBEAT", KICK) for g in ("sheath", "capsid", "link", "booth")},
               **{g: px("CHASE", KICK, width=.5, spread=.5, order=LEG) for g in B_LEGS},
               "collar": px("PULSE", KICK), "plate": px("PULSE", KICK)}, None),
    # ---- build (the BUILD lane from the recall, its cycle halving as it builds)
    ("CHARGE", {**{g: px("CHASE", BUILD, 8, width=.5, reverse=1) for g in B_LEGS},
                **{g: px("SOLID") for g in ("sheath", "plate", "link", "booth")},
                "collar": px("CHASE", BUILD, 8), "capsid": px("STROBE", BUILD)}, (4, .4)),
    ("SPIRAL", {"plate": px("CHASE", PHRASE, 4, spread=.95, order=AROUND),
                **{g: px("CHASE", PHRASE, 4, width=.4, spread=.95, order=LEG) for g in B_LEGS},
                "sheath": px("CHASE", PHRASE, 8, spread=.5, order=UP), "collar": px("CHASE", PHRASE, 8),
                "link": px("CHASE", PHRASE, 4, spread=.5, order=UP),
                "capsid": px("COMET", PHRASE, 4, spread=.95, order=AROUND), "booth": px("COMET", PHRASE, 4)}, None),
    ("RISER", {g: px("STROBE", BUILD, spread=.9, order=UP) for g in B_ALL}, (4, .4)),
    ("FILL", {**{g: px("FILL", BUILD, reverse=1) for g in B_LEGS},
              **{g: px("FILL", BUILD, spread=.5, order=UP) for g in ("sheath", "link")},
              **{g: px("FILL", BUILD) for g in ("collar", "capsid", "plate", "booth")}}, None),
    # ---- crazy
    ("RIPPLE", {g: px("RIPPLE", KICK, width=.4) for g in B_ALL}, None),
    ("SHRAPNEL", {**{g: px("COMET", KICK, 2) for g in B_LEGS}, "sheath": px("SCATTER", KICK),
                  "plate": px("SCATTER", KICK), "capsid": px("STROBE", KICK), "link": px("BARCODE", KICK),
                  "collar": px("BARCODE", KICK), "booth": px("STROBE", KICK)}, (4, .4)),
    ("BARCODE", {**{g: px("BARCODE", KICK) for g in ("upper", "lower", "plate", "collar", "link")},
                 "sheath": px("SEGMENTS", KICK, 2, spread=.5, order=UP), "capsid": px("SCATTER", KICK),
                 "booth": px("BARCODE", KICK)}, (4, .4)),
    ("OVERLOAD", {"capsid": px("RIPPLE", KICK, width=.4), "link": px("STROBE", KICK), "sheath": px("CHASE", KICK, 4),
                  "collar": px("CHASE", KICK, 4), **{g: px("COMET", KICK, 4) for g in B_LEGS},
                  "plate": px("RIPPLE", KICK, width=.4), "booth": px("STROBE", KICK)}, (4, .4)),
]


def windows(parts, rest=DARK_WINDOW):
    """A sequence: every group not given a window stays dark."""
    return {g: parts.get(g, rest) for g in B_ALL}


CHASE_FX = [   # (name, parts, clock or None)
    # ---- calm: open, a swell, or one part of the body alone
    ("OPEN", {}, None),
    ("SWELL", {g: chase_part("PULSE", PHRASE, width=.9, spread=.5, order=UP) for g in B_ALL}, None),
    ("SPINE", windows({g: dict(CHASE_OPEN) for g in ("sheath", "collar", "link", "capsid", "booth")}), None),
    ("LIMBS", windows({g: dict(CHASE_OPEN) for g in ("upper", "lower", "plate")}), None),
    # ---- groove
    ("KICK DIP", {g: chase_part("PULSE", KICK, width=.45) for g in B_ALL}, None),
    ("ANSWER", {**{g: chase_part("PULSE", KICK, width=.4) for g in ("upper", "lower", "plate")},
                **{g: chase_part("PULSE", SNARE, width=.5) for g in ("sheath", "collar", "link", "capsid", "booth")}},
     None),
    ("LEG WAVE", windows({g: hold(g, PHRASE, 0, .17, 4, spread=.95, order=LEG) for g in B_LEGS}), None),
    ("TIERS", windows({g: hold(g, PHRASE, k / 8, 1 / 8, 2) for k, g in
                       enumerate(("booth", "lower", "plate", "upper", "sheath", "collar", "link", "capsid"))}), None),
    # ---- sequences through the anatomy (a 16-beat phrase; CHARGE rides the BUILD lane and quickens with it)
    ("IGNITION", windows({"sheath": hold("sheath", PHRASE, 0, 3 / 16, spread=.6, order=UP),
                          "upper": hold("upper", PHRASE, 3 / 16, 2 / 16), "lower": hold("lower", PHRASE, 5 / 16, 2 / 16),
                          "plate": hold("plate", PHRASE, 7 / 16, 1 / 16), "collar": hold("collar", PHRASE, 8 / 16, 2 / 16),
                          "link": hold("link", PHRASE, 10 / 16, 2 / 16, spread=.4, order=UP),
                          "capsid": hold("capsid", PHRASE, 12 / 16, 4 / 16),
                          "booth": hold("booth", PHRASE, 12 / 16, 4 / 16)}), None),
    ("INJECT", windows({"capsid": hold("capsid", PHRASE, 0, 3 / 16),
                        "link": hold("link", PHRASE, 2 / 16, 2 / 16, spread=.4, order=UP, reverse=1),
                        "collar": hold("collar", PHRASE, 4 / 16, 1 / 16),
                        "sheath": hold("sheath", PHRASE, 5 / 16, 3 / 16, spread=.6, order=UP, reverse=1),
                        "plate": hold("plate", PHRASE, 8 / 16, 1 / 16), "upper": hold("upper", PHRASE, 9 / 16, 2 / 16),
                        "lower": hold("lower", PHRASE, 11 / 16, 2 / 16), "booth": hold("booth", PHRASE, 13 / 16, 3 / 16)}),
     None),
    ("CASCADE", windows({"capsid": hold("capsid", PHRASE, 0, .14, 4), "link": hold("link", PHRASE, .1, .12, 4),
                         "collar": hold("collar", PHRASE, .22, .1, 4),
                         "sheath": hold("sheath", PHRASE, .3, .2, 4, spread=.6, order=UP, reverse=1),
                         "plate": hold("plate", PHRASE, .48, .08, 4), "upper": hold("upper", PHRASE, .55, .15, 4),
                         "lower": hold("lower", PHRASE, .7, .15, 4), "booth": hold("booth", PHRASE, .85, .15, 4)}), None),
    ("CHARGE", windows({"lower": hold("lower", BUILD, 0, .125), "upper": hold("upper", BUILD, .125, .125),
                        "plate": hold("plate", BUILD, .25, .05),
                        "sheath": hold("sheath", BUILD, .25, .2, spread=.6, order=UP),
                        "collar": hold("collar", BUILD, .45, .1), "link": hold("link", BUILD, .55, .15, spread=.45, order=UP),
                        "capsid": hold("capsid", BUILD, .7, .3), "booth": hold("booth", BUILD, .7, .3)}), None),
    # ---- crazy
    ("DETONATE", windows({"capsid": hold("capsid", KICK, 0, .15),
                          "link": hold("link", KICK, .08, .12, spread=.4, order=UP, reverse=1),
                          "collar": hold("collar", KICK, .18, .1),
                          "sheath": hold("sheath", KICK, .25, .2, spread=.6, order=UP, reverse=1),
                          "plate": hold("plate", KICK, .4, .1), "upper": hold("upper", KICK, .45, .2),
                          "lower": hold("lower", KICK, .62, .25), "booth": hold("booth", KICK, .85, .15)}), None),
    ("STROBE", {g: chase_part("STROBE", KICK, width=.5) for g in B_ALL}, (4, .4)),
    ("FLICKER", {g: chase_part(mov(2, rnd=True), HAT, width=.3, spread=.95, order=SHUFFLE) for g in B_ALL}, None),
    ("HEARTBEAT", {**{g: chase_part("PULSE", KICK, width=.3) for g in ("sheath", "collar", "link", "capsid", "booth")},
                   **{g: chase_part("BLINDER", SNARE) for g in ("upper", "lower", "plate")}}, None),
]
# BATTENS, the whole Pixel Batten (page 4): a PIXEL FX content under a CHASE FX sequence, bars at full; then BLACKOUT.
BATTEN_LOOKS = [
    ("AMBIENT", "PLASMA", "OPEN"), ("EMBERS", "EMBERS", "SWELL"), ("TIDE", "TIDE", "OPEN"), ("VIGIL", "PLASMA", "SPINE"),
    ("VEINS", "VEINS", "OPEN"), ("HEARTBEAT", "HEART", "HEARTBEAT"), ("WALKER", "VEINS", "LEG WAVE"),
    ("SCANNER", "SCANNER", "ANSWER"),
    ("IGNITION", "JOURNEY", "IGNITION"), ("INJECT", "JOURNEY", "INJECT"), ("CHARGE", "CHARGE", "CHARGE"),
    ("STAIRS", "SPIRAL", "TIERS"),
    ("DETONATE", "OVERLOAD", "DETONATE"), ("CASCADE", "JOURNEY", "CASCADE"), ("SHOCKWAVE", "RIPPLE", "KICK DIP"),
]


def batten_look_rows(content, sequence):
    rows = bar_rows(dict((n, p) for n, p, _ in PIXEL_FX)[content], PIXELS_REST, 0)
    rows.update(bar_rows(dict((n, p) for n, p, _ in CHASE_FX)[sequence], CHASE_OPEN, LAYER2))
    for f in BARS:
        rows[f["slot"]]["level"] = 1.0
        rows[LAYER2 + f["slot"]]["level"] = 1.0
    return rows


def clock_of(*clocks):
    """The clock a pad stores: the first of its parts that runs on it, else none (it leaves the show's clock alone)."""
    return next((c for c in clocks if c), None)


# --- HALO FX: the Halo Beams' rings choreographed per group ------------------------------------------------------------
# The 24-cell ring round every lens, in the movers' seven groups. A group a pad does not name stays dark, so a pad is a
# glow, a chase or a sequence on the groups it names; GLOW lights them all. The sequences carry the battens' names and
# timing (a phrase, BUILD for CHARGE, the kick for DETONATE), so IGNITION on HALO FX and on BATTENS run through the rig
# together: the inner plate under the body, out the knees and feet, the outer plate, round the collar and up the capsid.
HALO_REST = dict(int_lane=PHRASE, color_lane=OFF, width=.01, spread=0, offset=0, reverse=0, look=24, order=AROUND)
HALO_GLOW = dict(int_lane=OFF, color_lane=OFF, width=.5, spread=0, offset=0, reverse=0, look=0, order=AROUND)
M_ALL = ("capsid", "collar", "plate_in", "plate_out", "knee", "foot", "booth")


def mover_window(group, *args, **kw):
    """A Halo Beam group's HOLD window."""
    return window([f for f in MOVERS if f["family"] in GROUPS[group]], *args, **kw)


def halo_rows(parts):
    """HALO rows (slot + 376) from per-group parts; `lane` is the chase lane."""
    rows = {}
    for f in MOVERS:
        part = group_part(f, parts)
        rows[LAYER2 + f["slot"]] = {**HALO_REST, **{("int_lane" if k == "lane" else k): v for k, v in part.items()}}
    return rows


def _mw(*args, **kw):
    return {"lane" if k == "int_lane" else k: v for k, v in mover_window(*args, **kw).items()}


HALO_FX = [
    # ---- calm
    ("GLOW", {g: dict(HALO_GLOW) for g in M_ALL}),
    ("BREATHE", {g: dict(lane=PHRASE, look=0, width=.95, spread=.5, order=UP) for g in M_ALL}),
    ("CROWN", {g: dict(HALO_GLOW) for g in ("capsid", "collar")}),
    ("TIDE", {g: dict(HALO_GLOW, color_lane=PHRASE, spread=.9, order=UP) for g in M_ALL}),
    # ---- groove
    ("ANSWER", {g: dict(lane=SNARE, look=0, width=.45) for g in M_ALL}),
    ("ORBIT", {**{g: _mw(g, PHRASE, 0, .12, 4, spread=.95, order=AROUND) for g in ("capsid", "collar", "plate_in",
                                                                                  "plate_out", "booth")},
               **{g: _mw(g, PHRASE, 0, .17, 4, spread=.95, order=LEG) for g in ("knee", "foot")}}),
    ("LEG WAVE", {g: _mw(g, PHRASE, 0, .17, 4, spread=.95, order=LEG) for g in ("knee", "foot")}),
    ("HEARTBEAT", {g: dict(lane=KICK, look=0, width=.25) for g in ("capsid", "collar")}),
    # ---- sequences through the rig (as the battens')
    ("IGNITION", {"plate_in": _mw("plate_in", PHRASE, 0, 3 / 16, spread=.12, order=AROUND),
                  "knee": _mw("knee", PHRASE, 3 / 16, 2 / 16), "foot": _mw("foot", PHRASE, 5 / 16, 2 / 16),
                  "plate_out": _mw("plate_out", PHRASE, 7 / 16, 1 / 16),
                  "collar": _mw("collar", PHRASE, 8 / 16, 2 / 16, spread=.08, order=AROUND),
                  "capsid": _mw("capsid", PHRASE, 10 / 16, 6 / 16, spread=.25, order=UP),
                  "booth": _mw("booth", PHRASE, 12 / 16, 4 / 16)}),
    ("INJECT", {"capsid": _mw("capsid", PHRASE, 0, 4 / 16, spread=.25, order=UP, reverse=1),
                "collar": _mw("collar", PHRASE, 4 / 16, 1 / 16), "plate_in": _mw("plate_in", PHRASE, 5 / 16, 3 / 16),
                "plate_out": _mw("plate_out", PHRASE, 8 / 16, 1 / 16), "knee": _mw("knee", PHRASE, 9 / 16, 2 / 16),
                "foot": _mw("foot", PHRASE, 11 / 16, 2 / 16), "booth": _mw("booth", PHRASE, 13 / 16, 3 / 16)}),
    ("CASCADE", {"capsid": _mw("capsid", PHRASE, 0, .15, 4, spread=.2, order=UP, reverse=1),
                 "collar": _mw("collar", PHRASE, .15, .1, 4), "plate_in": _mw("plate_in", PHRASE, .25, .1, 4),
                 "plate_out": _mw("plate_out", PHRASE, .35, .1, 4), "knee": _mw("knee", PHRASE, .5, .15, 4),
                 "foot": _mw("foot", PHRASE, .65, .15, 4), "booth": _mw("booth", PHRASE, .85, .15, 4)}),
    ("CHARGE", {"foot": _mw("foot", BUILD, 0, .12), "knee": _mw("knee", BUILD, .12, .13),
                "plate_out": _mw("plate_out", BUILD, .25, .1), "plate_in": _mw("plate_in", BUILD, .35, .1),
                "collar": _mw("collar", BUILD, .45, .15, spread=.1, order=AROUND),
                "capsid": _mw("capsid", BUILD, .6, .4, spread=.3, order=UP), "booth": _mw("booth", BUILD, .7, .3)}),
    # ---- crazy
    ("DETONATE", {"capsid": _mw("capsid", KICK, 0, .15), "collar": _mw("collar", KICK, .12, .12),
                  "plate_in": _mw("plate_in", KICK, .22, .12), "plate_out": _mw("plate_out", KICK, .3, .15),
                  "knee": _mw("knee", KICK, .42, .2), "foot": _mw("foot", KICK, .6, .25),
                  "booth": _mw("booth", KICK, .8, .2)}),
    ("SPARKLE", {g: dict(lane=KICK, look=mov(4, rnd=True), width=.25, spread=.95, order=SHUFFLE) for g in M_ALL}),
    ("STAGGER", {**{g: dict(lane=KICK, look=0, width=.3) for g in ("capsid", "plate")},
                 **{g: dict(lane=KICK, look=0, width=.3, offset=-.5) for g in ("collar", "booth")}}),
    ("BURST", {g: dict(lane=KICK, look=0, width=.5, spread=.9, order=OUTWARD) for g in M_ALL}),
]


# --- SEQUENCES: the whole rig in one movement (pad page 5) ---------------------------------------------------------------
# Fifteen sequences played by every fixture type at once, phrase-locked, then BLACKOUT. The RIG bank recalls a sequence
# on the Halo Beams, the strobes and the battens together; BEAMS, STROBES and BATTENS hold each type's part of the same
# sequences, so the same slot on each is the same moment and they mix (battens IGNITION under strobes DETONATE).
# Two kinds of movement through the rig:
#   journeys, group by group through the anatomy (IGNITION, INJECT, CASCADE, CHARGE, DETONATE), as the battens' CHASE FX
#     and HALO FX sequences; on the strobes the plates carry the colour through each window and the tube hits white as
#     the light arrives;
#   sweeps, one HOLD window ranked on the whole rig at once (UP, SIDE, AROUND, OUTWARD), so a band, a plane, a sector or
#     a shockwave crosses every fixture type together, a white tube edge leading it.
ALL_LIGHTS = MOVERS + STROBES + BARS
CLOSED = dict(lane=PHRASE, look=24, width=.01)            # a HOLD that never opens


def gwin(lane, start, length, repeats=1, spread=.95, order=UP, reverse=0):
    """A window ranked on the whole rig: every fixture of every type in one band, plane, sector or shockwave."""
    return window(ALL_LIGHTS, lane, start, length, repeats, spread=spread, order=order, reverse=reverse)


def every(part, groups): return {g: dict(part) for g in groups}


def sweep(lane, length, repeats=1, order=UP, reverse=0, edge=.04, spread=.95):
    """A sweep on every light layer: beams, rings, plates and battens in the band, the tubes on its leading edge."""
    band = gwin(lane, 0, length, repeats, spread=spread, order=order, reverse=reverse)
    lead = gwin(lane, 0, edge, repeats, spread=spread, order=order, reverse=reverse)
    return dict(beam=every(band, M_ALL), halo=every(band, M_ALL), plates=every(band, S_ALL), tube=every(lead, S_ALL),
                pixels=every(px("SOLID"), B_ALL), chase=every(band, B_ALL))


def strobe_window(group, *args, **kw):
    return window([f for f in STROBES if f["family"] == STROBE_GROUPS[group]], *args, **kw)


def strobe_journey(table, lane, repeats=1, hit=.03):
    """A journey on the strobes: the plates hold each group's window, the tube hits white as it opens."""
    plates = {g: strobe_window(g, lane, t0, n, repeats, **kw) for g, (t0, n, kw) in table.items()}
    tube = {g: strobe_window(g, lane, t0, hit, repeats, **kw) for g, (t0, n, kw) in table.items()}
    return dict(plates=plates, tube=tube)


UPS = dict(spread=.25, order=UP)
STROBE_JOURNEYS = {
    "IGNITION": (PHRASE, 1, .03, {"plate": (0, 3 / 16, dict(spread=.12, order=AROUND)), "knee": (3 / 16, 2 / 16, {}),
                                  "foot": (5 / 16, 2 / 16, {}), "collar": (8 / 16, 2 / 16, {}),
                                  "capsid": (10 / 16, 6 / 16, UPS), "booth": (12 / 16, 4 / 16, {})}),
    "INJECT": (PHRASE, 1, .03, {"capsid": (0, 4 / 16, dict(UPS, reverse=1)), "collar": (4 / 16, 1 / 16, {}),
                                "plate": (5 / 16, 3 / 16, {}), "knee": (9 / 16, 2 / 16, {}), "foot": (11 / 16, 2 / 16, {}),
                                "booth": (13 / 16, 3 / 16, {})}),
    "CASCADE": (PHRASE, 4, .06, {"capsid": (0, .15, dict(spread=.2, order=UP, reverse=1)), "collar": (.15, .1, {}),
                                 "plate": (.3, .15, {}), "knee": (.5, .15, {}), "foot": (.65, .15, {}),
                                 "booth": (.85, .15, {})}),
    "CHARGE": (BUILD, 1, .05, {"foot": (0, .12, {}), "knee": (.12, .13, {}), "plate": (.3, .15, {}),
                               "collar": (.45, .15, {}), "capsid": (.6, .4, dict(spread=.3, order=UP)),
                               "booth": (.7, .3, {})}),
    "DETONATE": (KICK, 1, .1, {"capsid": (0, .15, {}), "collar": (.12, .12, {}), "plate": (.25, .15, {}),
                               "knee": (.42, .2, {}), "foot": (.6, .25, {}), "booth": (.8, .2, {})}),
}


def journey(name, content):
    """A journey on every type: the rings' and beams' windows (HALO FX), the strobes', the battens' (CHASE FX)."""
    lane, repeats, hit, table = STROBE_JOURNEYS[name]
    halo = dict(HALO_FX)[name]
    return dict(beam=halo, halo=halo, **strobe_journey(table, lane, repeats, hit),
                pixels=dict((n, q) for n, q, _ in PIXEL_FX)[content], chase=dict((n, q) for n, q, _ in CHASE_FX)[name])


CORE_M, LIMBS_M = ("capsid", "collar", "plate_in"), ("knee", "foot", "plate_out", "booth")
CORE_S, LIMBS_S = ("capsid", "collar", "plate"), ("knee", "foot", "booth")
CORE_B, LIMBS_B = ("sheath", "collar", "link", "capsid"), ("upper", "lower", "plate", "booth")
_swell = dict(lane=PHRASE, look=0, width=.9, spread=.5, order=UP)
SEQUENCES = [   # (name, shape, MOVE FX, parts, clock)
    # ---- calm: the whole rig breathing, a tide, an orbit, a heartbeat
    ("BREATH", "ORIGIN", "BREATH", dict(beam=every(_swell, M_ALL), halo=every(_swell, M_ALL), plates=every(_swell, S_ALL),
                                        tube={}, pixels=every(px("PLASMA", PHRASE, spread=.5), B_ALL),
                                        chase=every(_swell, B_ALL)), None),
    ("TIDE", "CATHEDRAL", "BREATH", sweep(PHRASE, .3, order=UP), None),
    ("ORBIT", "SUNBURST", {}, sweep(PHRASE, .22, 4, order=AROUND), None),
    ("HEARTBEAT", "CROWN", {}, dict(
        beam={**every(dict(lane=KICK, look=0, width=.3), ("capsid", "collar")), **every(CLOSED, LIMBS_M + ("plate_in",))},
        halo=every(dict(lane=KICK, look=0, width=.3), ("capsid", "collar")),
        tube={"capsid": _st("PULSE", KICK, width=.2)},
        plates=every(_st("PULSE", KICK, width=.3), ("capsid", "collar")),
        pixels=dict((n, q) for n, q, _ in PIXEL_FX)["HEART"], chase=dict((n, q) for n, q, _ in CHASE_FX)["HEARTBEAT"]), None),
    # ---- groove: a plane crossing the stage, the walk, call and answer, a band falling every bar
    ("SCAN", "FRONT", "SCAN", sweep(PHRASE, .15, 2, order=SIDE, edge=.03), None),
    ("WALK", "FIBERS", "LEGS", dict(
        beam={**every(gwin(PHRASE, 0, .17, 4, order=LEG), ("knee", "foot")), **every(CLOSED, CORE_M + ("plate_out", "booth"))},
        halo=every(gwin(PHRASE, 0, .17, 4, order=LEG), ("knee", "foot")),
        plates=every(gwin(PHRASE, 0, .17, 4, order=LEG), ("knee", "foot")),
        tube=every(gwin(PHRASE, 0, .04, 4, order=LEG), ("knee", "foot")),
        pixels=dict((n, q) for n, q, _ in PIXEL_FX)["VEINS"],
        chase=every(gwin(PHRASE, 0, .17, 4, order=LEG), B_LEGS)), None),
    ("ANSWER", "SUNBURST", "SCISSOR", dict(
        beam={**every(dict(lane=KICK, look=0, width=.35), CORE_M), **every(dict(lane=SNARE, look=0, width=.4), LIMBS_M)},
        halo={**every(dict(lane=KICK, look=0, width=.35), CORE_M), **every(dict(lane=SNARE, look=0, width=.4), LIMBS_M)},
        tube={**every(_st("PULSE", KICK, width=.2), CORE_S), **every(_st("PULSE", SNARE, width=.2), LIMBS_S)},
        plates={**every(_st("PULSE", KICK, width=.35), CORE_S), **every(_st("PULSE", SNARE, width=.4), LIMBS_S)},
        pixels=every(px("SOLID"), B_ALL),
        chase={**every(chase_part("PULSE", KICK, width=.35), CORE_B), **every(chase_part("PULSE", SNARE, width=.4), LIMBS_B)}),
     None),
    ("FALL", "NEEDLES", {}, sweep(PHRASE, .18, 4, order=UP, reverse=1), None),
    # ---- build: journeys through the anatomy, and a band climbing with the build
    ("IGNITION", "SUNBURST", {}, journey("IGNITION", "JOURNEY"), (4, .4)),
    ("INJECT", "CATHEDRAL", {}, journey("INJECT", "JOURNEY"), (4, .4)),
    ("CHARGE", "NEEDLES", "RISE", journey("CHARGE", "CHARGE"), (4, .4)),
    ("RISER", "CATHEDRAL", "RISE", {**sweep(BUILD, .25, order=UP), "tube": every(_st("STROBE", BUILD, width=.6),
                                                                                  ("capsid", "collar"))}, (4, .4)),
    # ---- crazy
    ("DETONATE", "SUNBURST", "SHATTER", journey("DETONATE", "OVERLOAD"), (4, .4)),
    ("SHOCKWAVE", "SUNBURST", "STORM", {**sweep(KICK, .25, order=OUTWARD, edge=.08),
                                        "pixels": every(px("RIPPLE", KICK, width=.4), B_ALL)}, None),
    ("CASCADE", "X-FIRE", "FORMATIONS", journey("CASCADE", "JOURNEY"), (4, .4)),
]


def seq_rows(shape, move, parts):
    """Every program row of a sequence: the shape's aim and levels, the MOVE FX, each light layer's parts, strobes and
    bars at full, and the capsid's HEADING."""
    static = dict(STATIC)[shape]
    rows = layer_rows({f["slot"]: {**{k: DEFAULT[k] for k in EFFECT_F}, **static.get(f["slot"], {})} for f in MOVERS})
    for r, v in move_rows(dict(MOVE_FX)[move] if isinstance(move, str) else move).items(): rows[r].update(v)
    for r, v in beam_rows(parts["beam"]).items(): rows[r].update(v)
    for r, v in halo_rows(parts["halo"]).items(): rows[r].update(v)
    rows.update(strobe_rows(parts["tube"], TUBE_REST, 0))
    rows.update(strobe_rows(parts["plates"], PLATES_REST, LAYER2))
    rows.update(bar_rows(parts["pixels"], PIXELS_REST, 0))
    rows.update(bar_rows(parts["chase"], CHASE_OPEN, LAYER2))
    for f in STROBES: rows[f["slot"]]["level"] = 1.0; rows[LAYER2 + f["slot"]]["ring"] = 1.0
    for f in BARS: rows[f["slot"]]["level"] = 1.0; rows[LAYER2 + f["slot"]]["level"] = 1.0
    rows[CAPSID_AXIS] = static[CAPSID_AXIS]
    return rows


def merge_text(base, patch):
    """Overlay a packed partition's set cells onto another's (rig_codec merge)."""
    a, b2 = base.split(";"), patch.split(";")
    out = [a[0]]
    for x, y in zip(a[1:], b2[1:]):
        out.append(",".join(q if q != "_" else p for p, q in zip(x.split(","), y.split(","))))
    return ";".join(out)


def seq_snapshot(kind, rows, clock):
    """A sequence pad: its family's partitions (and the strobe clock when it uses it); a pad that moves the Halo Beams
    carries the capsid's HEADING too, merged into the axes' partition."""
    snap = fixture_snapshot(kind, rows, *(clock or (4, .3)), clock=clock is not None)
    if "move" in FX_FAMILIES[kind]:
        key = f"{STATE}saved_static_bank_{CAPSID_PART}"
        heading = pack_part({CAPSID_AXIS: rows[CAPSID_AXIS]}, STATIC_F, PARTS[CAPSID_PART], {"level"})
        snap[key] = merge_text(snap[key], heading) if key in snap else heading
    return snap


SEQ_FIXTURES = {"sequence": ALL_LIGHTS, "seq_heads": MOVERS, "seq_strobes": STROBES, "seq_battens": BARS}


# --- EFFECTS and FULL LOOKS: the whole rig, built from the choreography ------------------------------------------------
# An EFFECTS look is every effect row of the rig at once (the Halo Beams' MOVE, BEAM and HALO, the strobes' TUBE and
# PLATES, the battens' PIXELS and CHASE, the truss axes) and the strobe clock; never aim, levels or colour, so it plays on
# any STATIC shape, truss pose and COLOR. They are built from the fixture banks and the SEQUENCES: the sweeps and
# journeys light the rig, the heads move with the light (a group glides to a new formation as the light reaches it), and
# the truss moves with it, eased and never spinning: the legs walk leg by leg, lift as the light runs out of them, the
# sheath contracts as INJECT pushes down the core, the body rises with the build. Tiered by energy: 1-4 CALM, 5-8
# GROOVE, 9-12 BUILD (journeys and the BUILD lane from the recall), 13-16 CRAZY.
TIERS = [("CALM", 0), ("GROOVE", 4), ("BUILD", 8), ("CRAZY", 12)]


def axis_rows(body=None, capsid=None, legs=None):
    """Truss axis effect rows: `lane` the move lane, `glide` a GLIDE's share of a step, sizes in the axes' own units
    (body pan yaw / tilt height, capsid pan spin / tilt sheath contraction, legs pan swing / tilt foot lift)."""
    rows = {}
    for f in AXES:
        k = f["slot"] - 240
        attrs = body if k == 0 else capsid if k == 1 else legs
        row = {key: DEFAULT[key] for key in EFFECT_F}
        for key, v in (attrs or {}).items():
            row["move_lane" if key == "lane" else "width" if key == "glide" else key] = v
        rows[f["slot"]] = row
    return rows


def look_rows(parts):
    """Every effect row of an EFFECTS look from its layers' parts."""
    rows = {f["slot"]: {k: DEFAULT[k] for k in EFFECT_F} for f in MOVERS}
    for r, v in move_rows(parts["move"]).items(): rows[r].update(v)
    rows.update(beam_rows(parts["beam"]))
    rows.update(halo_rows(parts["halo"]))
    rows.update(strobe_rows(parts["tube"], TUBE_REST, 0))
    rows.update(strobe_rows(parts["plates"], PLATES_REST, LAYER2))
    rows.update(bar_rows(parts["pixels"], PIXELS_REST, 0))
    rows.update(bar_rows(parts["chase"], CHASE_OPEN, LAYER2))
    rows.update(axis_rows(**parts.get("axes", {})))
    return rows


def _bank(table, name): return dict((n, q) for n, q, *_ in table)[name]


def layers(move="HOLD", beam="STEADY", halo="GLOW", tube="DARK", plates="WASH", pixels="GLOW", chase="OPEN", axes=None):
    """An EFFECTS look from fixture-bank pads by name (or parts given directly)."""
    pick = lambda table, v: _bank(table, v) if isinstance(v, str) else v
    return dict(move=pick(MOVE_FX, move), beam=pick(BEAM_FX, beam), halo=pick(HALO_FX, halo), tube=pick(TUBE_FX, tube),
                plates=pick(PLATES_FX, plates), pixels=pick(PIXEL_FX, pixels), chase=pick(CHASE_FX, chase),
                axes=axes or {})


def from_sequence(name, move=None, axes=None):
    """An EFFECTS look from a SEQUENCE: its light on every type, its MOVE FX (or another), the truss part given."""
    _, shape, seq_move, parts, clock = next(q for q in SEQUENCES if q[0] == name)
    m = move if move is not None else seq_move
    return dict(parts, move=_bank(MOVE_FX, m) if isinstance(m, str) else m, axes=axes or {})


# The heads move with a journey: each group glides to a new formation as the light reaches it, over its window.
MOVE_JOURNEYS = {
    "IGNITION": (PHRASE, 1, {"plate_in": (0, 3 / 16), "knee": (3 / 16, 2 / 16), "foot": (5 / 16, 2 / 16),
                             "plate_out": (7 / 16, 1 / 16), "collar": (8 / 16, 2 / 16), "capsid": (10 / 16, 6 / 16),
                             "booth": (12 / 16, 4 / 16)}),
    "INJECT": (PHRASE, 1, {"capsid": (0, 4 / 16), "collar": (4 / 16, 1 / 16), "plate_in": (5 / 16, 3 / 16),
                           "plate_out": (8 / 16, 1 / 16), "knee": (9 / 16, 2 / 16), "foot": (11 / 16, 2 / 16),
                           "booth": (13 / 16, 3 / 16)}),
    # CASCADE's light falls every bar; its heads re-form every other bar, down the rig in the same order
    "CASCADE": (PHRASE, 2, {"capsid": (0, .15), "collar": (.15, .1), "plate_in": (.25, .1), "plate_out": (.35, .1),
                            "knee": (.5, .15), "foot": (.65, .15), "booth": (.85, .15)}),
}


def move_journey(name, sizes=MID, scale=1.0):
    lane, repeats, table = MOVE_JOURNEYS[name]
    size = lambda g: tuple(v * scale for v in sizes["plate" if g.startswith("plate") else g])
    # a phrase journey glides over the group's window; a per-bar one (CASCADE) takes at least a third of the bar, so
    # its heads ease rather than snap (a short window every bar is a fast move)
    return {g: dict(lane=lane, look=glide(repeats, group=True), glide=max(.1 if repeats == 1 else .35, n), offset=t0,
                    pan=size(g)[0] * MOVE_SIZE, rise=size(g)[1] * MOVE_SIZE) for g, (t0, n) in table.items()}


def journey_look(name, content, axes, scale=1.0):
    return dict(journey(name, content), move=move_journey(name, scale=scale), axes=axes)


# Truss parts. A nod (plain circle with pan 0) on PHRASE peaks at -offset of the phrase; GLIDE eases between positions.
def nod(lane, tilt, peak=0.0, **kw): return dict(lane=lane, look=0, pan_amp=0, tilt_amp=tilt, offset=-peak, **kw)
def tglide(lane, repeats, glide_share, pan=0, tilt=0, rnd=False, **kw):
    return dict(lane=lane, look=glide(repeats, rnd=rnd), glide=glide_share, pan_amp=pan, tilt_amp=tilt, **kw)


GAIT = tglide(PHRASE, 4, .5, pan=25, tilt=55, spread=.95, order=LEG)      # the legs step one after another, a bar a lap
EFFECTS = [   # (name, parts, clock rate per beat, duty)
    # ---- CALM: the rig breathing, a tide, an orbit, a heartbeat
    ("AWAKEN", layers(move="DRIFT", beam="BREATHE", halo="TIDE", plates="EMBERS", pixels="PLASMA", chase="SWELL",
                      axes=dict(body=tglide(PHRASE, 1, .9, pan=6), capsid=tglide(PHRASE, 1, .9, tilt=12),
                                legs=nod(PHRASE, 10, spread=.5, order=LEG))), 2, .3),
    ("TIDE", from_sequence("TIDE", axes=dict(capsid=nod(PHRASE, 12, .5), legs=nod(PHRASE, 14, .2, spread=.3,
                                                                                    order=LEG))), 2, .3),
    ("ORBIT", from_sequence("ORBIT", move="WAVE", axes=dict(capsid=tglide(PHRASE, 2, .8, pan=30),
                                                             legs=tglide(PHRASE, 4, .5, tilt=12, spread=.95,
                                                                         order=LEG))), 2, .3),
    ("HEARTBEAT", from_sequence("HEARTBEAT", move="BREATH", axes=dict(capsid=tglide(PHRASE, 2, .5, tilt=15))), 2, .3),
    # ---- GROOVE: a plane crossing the stage, the walk, call and answer, a band falling
    ("SCAN", from_sequence("SCAN", axes=dict(body=tglide(PHRASE, 2, .8, pan=12))), 2, .3),
    ("WALK", from_sequence("WALK", axes=dict(body=tglide(PHRASE, 4, .5, tilt=6), legs=GAIT)), 2, .3),
    ("ANSWER", from_sequence("ANSWER", axes=dict(capsid=tglide(PHRASE, 2, .6, pan=20),
                                                 legs=tglide(PHRASE, 2, .5, tilt=18, spread=.5, order=LEG))), 2, .3),
    ("FALL", from_sequence("FALL", move="CASCADE", axes=dict(body=tglide(PHRASE, 4, .6, tilt=12))), 2, .3),
    # ---- BUILD: the journeys, the heads and the truss moving with the light; the build itself
    ("IGNITION", journey_look("IGNITION", "JOURNEY", dict(legs=nod(PHRASE, 25, 5 / 16),
                                                          capsid=nod(PHRASE, 20, 13 / 16))), 4, .4),
    ("INJECT", journey_look("INJECT", "JOURNEY", dict(capsid=nod(PHRASE, 30, 6 / 16),
                                                      legs=nod(PHRASE, 15, 11 / 16))), 4, .4),
    ("CHARGE", from_sequence("CHARGE", axes=dict(body=dict(lane=BUILD, tilt_amp=60), capsid=dict(lane=BUILD, tilt_amp=-30),
                                                 legs=dict(lane=BUILD, tilt_amp=35))), 4, .4),
    ("RISER", from_sequence("RISER", axes=dict(body=dict(lane=BUILD, tilt_amp=75), capsid=dict(lane=BUILD, tilt_amp=-40),
                                               legs=dict(lane=BUILD, tilt_amp=25))), 4, .4),
    # ---- CRAZY
    ("DETONATE", from_sequence("DETONATE", axes=dict(body=tglide(PHRASE, 2, .35, tilt=18),
                                                     capsid=tglide(PHRASE, 2, .35, pan=30, tilt=15, rnd=True),
                                                     legs=tglide(PHRASE, 2, .35, pan=30, tilt=35, rnd=True, spread=.3,
                                                                 order=LEG, offset=.2))), 4, .4),
    ("SHOCKWAVE", from_sequence("SHOCKWAVE", axes=dict(body=tglide(PHRASE, 4, .3, tilt=10),
                                                       legs=tglide(PHRASE, 2, .4, pan=25, tilt=30, rnd=True))), 2, .3),
    ("CASCADE", journey_look("CASCADE", "JOURNEY", dict(legs=tglide(PHRASE, 4, .4, tilt=20, spread=.95, order=LEG)),
                             scale=.7), 4, .4),
    ("SUPERNOVA", layers(move="RIOT", beam="SUPERNOVA", halo="BURST", tube="WHITEOUT", plates="SUPERNOVA",
                         pixels="OVERLOAD", chase="DETONATE",
                         axes=dict(body=tglide(PHRASE, 2, .35, tilt=20),
                                   capsid=tglide(PHRASE, 2, .35, pan=35, tilt=20, rnd=True),
                                   legs=tglide(PHRASE, 2, .35, pan=35, tilt=40, rnd=True, spread=.3, order=LEG))), 4, .4),
]

FULL = [  # (name, static, pose, effects, colour, global overrides)
    ("GENESIS", "ORIGIN", "REST", "AWAKEN", "PHAGE", {}),
    ("TIDEWATER", "CATHEDRAL", "RISE", "TIDE", "ICE", {"haze": .04}),
    ("CAROUSEL", "SUNBURST", "REST", "ORBIT", "UV", {"haze": .04}),
    ("PULSE", "CROWN", "REST", "HEARTBEAT", "INFRARED", {"haze": .045}),
    ("RADAR", "FRONT", "REST", "SCAN", "VIRAL", {}),
    ("PROCESSION", "FIBERS", "BLOOM", "WALK", "BIOLUME", {}),
    ("DIALOGUE", "HELIX", "RISE", "ANSWER", "CORAL", {}),
    ("DESCENT", "NEEDLES", "REST", "FALL", "WHITE", {}),
    ("IGNITION", "SUNBURST", "REST", "IGNITION", "SODIUM", {}),
    ("INJECTION", "CATHEDRAL", "INJECT", "INJECT", "TOXIC", {}),
    ("CHARGE", "NEEDLES", "RISE", "CHARGE", "GLACIER", {}),
    ("ASCENT", "CAGE", "RISE", "RISER", "MAGMA", {}),
    ("DETONATION", "X-FIRE", "BLOOM", "DETONATE", "INFRARED", {"bloom": .16}),
    ("SHOCKWAVE", "SUNBURST", "REST", "SHOCKWAVE", "SPLIT", {"bloom": .16}),
    ("CASCADE", "HALO", "REST", "CASCADE", "DUSK", {"bloom": .16}),
    ("SUPERNOVA", "SUNBURST", "RISE", "SUPERNOVA", "UV SPLIT", {"bloom": .2}),
]


def full_static_rows(static_name, pose_name, color_name):
    """A FULL look's aim, levels and palettes per slot: everything at its default level, strobes full, then the shape,
    the truss pose and the colour routing."""
    base = {f["slot"]: dict(DEFAULT) for f in FX if not f["unused"]}
    for f in STROBES: base[f["slot"]].update(level=1, ring=1)
    return merge(base, dict(STATIC)[static_name], dict(STATIC)[pose_name],
                 color_rows(dict((n, r) for n, _, r in COLORS)[color_name]))


# HALO BEAMS, the whole Halo Beam (page 2): each pad is a beam shape (aim and levels), a MOVE FX pad, a BEAM FX pad and
# what the rings do: GLOW steady at the shape's ring level, ECHO the beam's chase, or ANSWER it half a step later. A pad
# built on a shape that holds the capsid facing front holds it too (the capsid's HEADING travels with the pad).
HEADS = [
    # ---- calm
    ("MIST", "ORIGIN", "DRIFT", "BREATHE", "GLOW"),
    ("NAVE", "CATHEDRAL", "BREATH", "TURNS", "GLOW"),
    ("RIPPLE", "HALO", "WAVE", "BREATHE", "ECHO"),
    ("SPIRE", "NEEDLES", "HOLD", "RISE", "ANSWER"),
    # ---- groove
    ("SWEEP", "FRONT", "SCAN", "CALL", "ANSWER"),
    ("CROSSFIRE", "X-FIRE", "SCISSOR", "AROUND", "GLOW"),
    ("STRIDE", "FIBERS", "LEGS", "LEGS", "ECHO"),
    ("WEAVE", "HELIX", "CASCADE", "RISE", "GLOW"),
    # ---- build
    ("RELAY", "SUNBURST", "STAGES", "TURNS", "ECHO"),
    ("TIERS", "CAGE", "FORMATIONS", "ROLL", "ANSWER"),
    ("CORONA", "CROWN", "AROUND", "COLLAR RUN", "GLOW"),
    ("LIFTOFF", "PINPOINT", "RISE", "BUILD", "ECHO"),
    # ---- crazy
    ("SURGE", "X-FIRE", "SHIFT", "STAGGER", "ANSWER"),
    ("TEMPEST", "CAGE", "STORM", "STORM", "ECHO"),
    ("NOVA", "SUNBURST", "SHATTER", "SUPERNOVA", "ECHO"),
]                                                    # pad 16: BLACKOUT


def heads_rows(shape, move, beam, ring):
    """A HALO BEAMS pad's program rows: the shape's aim and levels on every layer, its MOVE FX on the MOVE rows, its
    BEAM FX on the BEAM rows and the rings' part on the HALO rows; plus the capsid's HEADING row."""
    static = dict(STATIC)[shape]
    rows = layer_rows({f["slot"]: {**{k: DEFAULT[k] for k in EFFECT_F}, **static.get(f["slot"], {})} for f in MOVERS})
    for s, r in move_rows(dict(MOVE_FX)[move]).items(): rows[s].update(r)
    beams = beam_rows(dict(BEAM_FX)[beam])
    for r, v in beams.items(): rows[r].update(v)
    for f in MOVERS:
        b = beams[BEAM0 + f["slot"]]
        rows[LAYER2 + f["slot"]].update(dict(BEAM_REST) if ring == "GLOW" else dict(b) if ring == "ECHO" else
                                        {**b, "offset": b["offset"] + .5})
    rows[CAPSID_AXIS] = static[CAPSID_AXIS]
    return rows


CAPSID_PART = next(b for b, part in enumerate(PARTS) if any(row == CAPSID_AXIS for row, _ in part))


def heads_snapshot(rows):
    """A HALO BEAMS pad: the Halo Beams' partitions, plus the capsid's HEADING alone from the axes' partition."""
    snap = fixture_snapshot("heads", rows, 4, .3)
    snap[f"{STATE}saved_static_bank_{CAPSID_PART}"] = pack_part({CAPSID_AXIS: rows[CAPSID_AXIS]}, STATIC_F,
                                                               PARTS[CAPSID_PART], {"level"})
    return snap


# The bottom-right pad of every fixture page (slot 16 of its whole-fixture bank) blacks the type out: every level and ring
# at 0, its aim and effects left as they are, so the next look of that type brings it back where it was.
BLACKOUT = "BLACKOUT"
DARK_ROWS = {0: {BEAM0: {"level": 0.0}, LAYER2: {"ring": 0.0}},      # Halo Beam: the beam and the ring
             1: {0: {"level": 0.0}, LAYER2: {"ring": 0.0}},          # Linear Strobe: the tube and the plates
             2: {0: {"level": 0.0}}}                                 # Pixel Batten: the content


def blackout_snapshot(kind, fixtures_of):
    rows = {offset + f["slot"]: dict(v) for f in fixtures_of for offset, v in DARK_ROWS[f["kind"]].items()}
    family = FX_FAMILIES[kind]
    return {f"{STATE}saved_static_bank_{b}": pack_part({r: rows[r] for r, layer in part if layer in family and r in rows},
                                                        STATIC_F, part, STATIC_MASK)
            for b, part in enumerate(PARTS) if any(layer in family for _, layer in part)}


def fixture_banks():
    """Seed pads for the fixture pages: MOVE FX and BEAM FX are their own choreography (above) and HALO BEAMS is built
    from them (HEADS); HALO FX holds the movers' chase of the 16 EFFECTS looks, TUBE FX and PLATES FX the strobes',
    PIXEL FX the bars' content; CHASE FX the batten chases above; and STROBES and BATTENS their type's part of the 16
    FULL looks: aim, levels and every layer's effects."""
    out = {"move": [(name, fixture_snapshot("move", move_rows(parts), 4, .3)) for name, parts in MOVE_FX],
           "beam": [(name, fixture_snapshot("beam", beam_rows(parts), 4, .3)) for name, parts in BEAM_FX]}
    out["tube"] = [(name, fixture_snapshot("tube", strobe_rows(parts, TUBE_REST, 0), rate, duty))
                   for name, parts, rate, duty in TUBE_FX]
    out["plates"] = [(name, fixture_snapshot("plates", strobe_rows(parts, PLATES_REST, LAYER2), 4, .3))
                     for name, parts in PLATES_FX]
    clock = {n: (r, d) for n, _, r, d in TUBE_FX}
    out["strobes"] = [(name, fixture_snapshot("strobes", strobe_look_rows(t, p), *clock[t]))
                      for name, t, p in STROBE_LOOKS] + [(BLACKOUT, blackout_snapshot("strobes", STROBES))]
    out["halo"] = [(name, fixture_snapshot("halo", halo_rows(parts), 4, .3)) for name, parts in HALO_FX]
    out["pixels"] = [(name, fixture_snapshot("pixels", bar_rows(parts, PIXELS_REST, 0), *(clock or (4, .3)),
                                              clock=clock is not None)) for name, parts, clock in PIXEL_FX]
    out["chase"] = [(name, fixture_snapshot("chase", bar_rows(parts, CHASE_OPEN, LAYER2), *(clock or (4, .3)),
                                             clock=clock is not None)) for name, parts, clock in CHASE_FX]
    clocks = {n: c for n, _, c in PIXEL_FX + CHASE_FX}
    out["battens"] = [(name, fixture_snapshot("battens", batten_look_rows(c, q), *(clock_of(clocks[c], clocks[q]) or (4, .3)),
                                               clock=clock_of(clocks[c], clocks[q]) is not None))
                      for name, c, q in BATTEN_LOOKS] + [(BLACKOUT, blackout_snapshot("battens", BARS))]
    built = [(name, seq_rows(shape, move, parts), clock) for name, shape, move, parts, clock in SEQUENCES]
    for kind, fixtures_of in SEQ_FIXTURES.items():
        out[kind] = [(name, seq_snapshot(kind, rows, clock)) for name, rows, clock in built] + \
                    [(BLACKOUT, blackout_snapshot(kind, fixtures_of))]
    out["heads"] = [(name, heads_snapshot(heads_rows(*parts))) for name, *parts in HEADS] + \
                   [(BLACKOUT, blackout_snapshot("heads", MOVERS))]
    return out


def build():
    out = {}
    out["static"] = [(n, banks_snapshot("static", rows, STATIC_F)) for n, rows in STATIC]
    out["effects"] = [(n, {**effects_snapshot(look_rows(parts)),
                          f"{STATE}show_strobe_rate": float(rate), f"{STATE}show_strobe_duty": float(duty)})
                      for n, parts, rate, duty in EFFECTS]
    out["color"] = [(n, {**banks_snapshot("static", color_rows(route), STATIC_F),
                        **{STATE + k: v for k, v in palette_records(pal).items()}})
                    for n, pal, route in COLORS]
    full = []
    slot = {kind: {n: i for i, (n, *_) in enumerate(table, 1)} for kind, table in
            (("static", STATIC), ("effects", EFFECTS), ("color", COLORS))}
    effects = {n: (parts, rate, duty) for n, parts, rate, duty in EFFECTS}
    for name, st, pose, ef, col, glob in FULL:
        rows = full_static_rows(st, pose, col)
        parts, rate, duty = effects[ef]
        pal = dict((n, p) for n, p, _ in COLORS)[col]
        snap = {**banks_snapshot("static", rows, STATIC_F), **effects_snapshot(look_rows(parts)),
                **{STATE + k: v for k, v in palette_records(pal).items()},
                **{STATE + k: v for k, v in RHYTHM.items()},
                **{f"{STATE}global_{k}": float(v) for k, v in {**GLOBAL_DEFAULT, **glob}.items()},
                f"{STATE}static_pitch": 0.0, f"{STATE}lighting_master": 1.0,
                f"{STATE}show_strobe_rate": float(rate), f"{STATE}show_strobe_duty": float(duty),
                # The pads this look is built from; the Surface lights them after the recall.
                f"{STATE}look_parts": f"static=static {slot['static'][st]};pose=static {slot['static'][pose]};"
                                      f"effects=effects {slot['effects'][ef]};color=color {slot['color'][col]}"}
        full.append((name, snap))
    out["complete"] = full
    out["rhythm"] = [("STANDARD", {STATE + k: v for k, v in RHYTHM.items()})]
    out.update(fixture_banks())
    return out


def write_titles(built):
    def names(kind): return "{" + ",".join(f'"{n}"' for n, _ in built[kind]) + "}"
    text = "\n".join([
        "--!strict",
        "-- Generated by tools/phage_looks.py; edit the generator, not this file.",
        "-- Pad names for the preset banks; index = pad slot. Effects run CALM 1-4, GROOVE 5-8, BUILD 9-12, CRAZY 13-16.",
        "return {",
        f"    static={names('static')},",
        f"    effects={names('effects')},",
        f"    color={names('color')},",
        f"    complete={names('complete')},",
        "    -- fixture banks (Push pad pages 2-4): layers of the EFFECTS looks, batten chases, types of the FULL looks",
        *[f"    {kind}={names(kind)}," for kind in FX_FAMILIES],
        "}", ""])
    path = ROOT / "scripts" / "show" / "preset_titles.luau"
    path.write_text(text, newline="\n")
    return path


def main(only_fixtures=False):
    """Write every bank, or with `fixtures` only the fixture banks (pages 2-4) and the pad names: the whole-rig banks
    shipped in presets/ are left as they are."""
    built = build()
    (ROOT / "presets").mkdir(exist_ok=True)
    for kind, presets in built.items():
        if only_fixtures and kind not in FX_FAMILIES:
            continue
        path = ROOT / "presets" / f"phage_stage_{kind}.json"
        path.write_text(json.dumps(group(kind, presets), indent=1), newline="\n")
        print(f"{path.relative_to(ROOT)}: {len(presets)} looks, {path.stat().st_size // 1024} KB")
    print(write_titles(built).relative_to(ROOT))
    # Report what the static shapes do to the beams, so a bad aim shows up before a capture does.
    for name, rows in STATIC[:12]:
        tilts = [r["tilt"] for s, r in rows.items() if "tilt" in r]
        lit = sum(1 for s, r in rows.items() if FX[s]["kind"] == 0 and r.get("level", 0) > 0)
        heading = "FREE" if rows[CAPSID_AXIS]["level"] > .5 else "FRONT"
        print(f"  static {name:10s} movers lit {lit:3d}  tilt {min(tilts):7.1f}..{max(tilts):6.1f}  capsid {heading}")


if __name__ == "__main__":
    import sys
    main(only_fixtures="fixtures" in sys.argv[1:])
