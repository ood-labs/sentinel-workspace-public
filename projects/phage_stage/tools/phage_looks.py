"""PHAGE look compiler: static, effects, colour and full looks -> the Surface's native preset JSON.

Looks are authored here as geometry and intent (where beams go, which lane drives what) and compiled
against the real mount frames captured from Phage_Kinetics (tools/mounts_rest.json), with the same
aim inverse the GPU uses (phAimAngles). Output, in the packed bank format the Surface recalls:

    presets/phage_stage_{static,effects,color,complete,rhythm}.json
    scripts/show/preset_titles.luau            (pad names for the Push, Desk and Surface window)

    python tools/phage_looks.py

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
         "offset": (-1, 1), "reverse": (0, 1), "look": (0, 51), "order": (0, 7)}
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


def shape_helix(f):
    fam, o = f["family"], radial(f["pos"])
    t = turn(o, 62)
    rise = {0: -.55, 1: -.55, 2: .6, 3: .85, 4: 0.0, 5: -.5, 6: 1.6}[fam]
    return add(t, mul(UPW, rise)), 1, .7


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
    fam, o = f["family"], radial(f["pos"])
    t = turn(o, 90)                                              # tangential, level: rings of light at every tier
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


def static_rows(shape_fn, bar_level):
    rows = {}
    for f in MOVERS:
        r = shape_fn(f)
        if r is None: continue
        d, level, ring = r
        pan, tilt = aim_angles(f["up"], f["fwd"], d)
        rows[f["slot"]] = {"pan": pan, "tilt": tilt, "level": level, "ring": ring}
    for f in BARS:
        rows[f["slot"]] = {"level": bar_level}
    return rows


def pose_rows(pose_fn):
    return {f["slot"]: dict(zip(("pan", "tilt"), pose_fn(f["slot"] - 240))) for f in AXES}


STATIC = [(name, static_rows(fn, bars)) for name, fn, bars in BEAM_SHAPES] + \
         [(name, pose_rows(fn)) for name, fn in POSES]


# --- EFFECTS looks -----------------------------------------------------------------------------------
# Each effect gives attribute dicts per role; movers' "rise" is signed toward the sky per mount
# (hanging heads tilt down with +tilt, upright ones up). Roles: movers, strobes, bars, body, capsid, legs.
def fx(movers=None, strobes=None, bars=None, body=None, capsid=None, legs=None, rate=4, duty=.3, calm=False):
    return {"movers": movers or {}, "strobes": strobes or {}, "bars": bars or {}, "body": body or {},
            "capsid": capsid or {}, "legs": legs or {}, "rate": rate, "duty": duty}


EFFECTS = [
    # ---------------- CALM: long lanes, slow drift, strobe tubes dark ----------------
    ("DRIFT", fx(movers=dict(move_lane=PHRASE, pan_amp=14, rise=6, spread=.9, order=AROUND, look=mov()),
                 strobes=dict(look=STROBE["GLOW"], int_lane=PHRASE, width=.9, spread=.7, order=AROUND),
                 bars=dict(look=BAR["PLASMA"], color_lane=PHRASE, spread=.5),
                 body=dict(move_lane=PHRASE, pan_amp=8, tilt_amp=18),
                 capsid=dict(move_lane=PHRASE, look=spin(.25)),
                 legs=dict(move_lane=PHRASE, pan_amp=16, spread=.9, order=AROUND), rate=2, duty=.5)),
    ("TIDE", fx(movers=dict(move_lane=PHRASE, rise=12, spread=.6, order=UP, int_lane=PHRASE, width=.95),
                strobes=dict(look=STROBE["OFF"]),
                bars=dict(look=BAR["CLIMB"], int_lane=PHRASE, width=.4, order=UP),
                body=dict(move_lane=PHRASE, tilt_amp=16),
                capsid=dict(move_lane=PHRASE, tilt_amp=22),
                legs=dict(move_lane=PHRASE, tilt_amp=26, spread=.9, order=AROUND), rate=2, duty=.5)),
    ("BREATHE", fx(movers=dict(int_lane=PHRASE, width=.92, spread=.3, order=OUTWARD),
                   strobes=dict(look=STROBE["GLOW"], int_lane=PHRASE, width=.9, spread=.3, order=OUTWARD),
                   bars=dict(look=BAR["PULSE"], int_lane=PHRASE, spread=.5, order=OUTWARD),
                   body=dict(move_lane=PHRASE, tilt_amp=30),
                   capsid=dict(move_lane=PHRASE, tilt_amp=30, offset=.5), rate=2, duty=.5)),
    ("EMBER", fx(movers=dict(int_lane=KICK, look=mov(2, rnd=True, step=True), width=.75, spread=.95, order=SHUFFLE,
                             move_lane=PHRASE, pan_amp=20, rise=10),
                 strobes=dict(look=STROBE["GLOW"], int_lane=KICK, width=.7, spread=.95, order=SHUFFLE),
                 bars=dict(look=BAR["SPARKLE"], color_lane=PHRASE, width=.3),
                 capsid=dict(move_lane=PHRASE, look=spin(.25)), rate=2, duty=.5)),
    # ---------------- GROOVE: kick / snare / hat, contained motion ----------------
    ("PULSE", fx(movers=dict(int_lane=KICK, width=.5, spread=0),
                 strobes=dict(look=STROBE["GLOW"], int_lane=KICK, width=.4, spread=0),
                 bars=dict(look=BAR["SEGMENTS"], int_lane=KICK, width=.3, order=LEG),
                 body=dict(move_lane=KICK, tilt_amp=8),
                 capsid=dict(move_lane=PHRASE, look=spin(.5)), rate=4, duty=.3)),
    ("WALK", fx(movers=dict(move_lane=KICK, pan_amp=18, spread=.5, order=LEG),
                strobes=dict(look=STROBE["GLOW"], int_lane=HAT, width=.6, spread=.2),
                bars=dict(look=BAR["CHASE"], int_lane=KICK, width=.3, spread=.5, order=LEG),
                capsid=dict(move_lane=PHRASE, look=spin(.5)),
                legs=dict(move_lane=KICK, pan_amp=22, spread=.5, order=AROUND), rate=4, duty=.3)),
    ("SWAY", fx(movers=dict(move_lane=KICK, pan_amp=10, rise=10, spread=.25, order=MIRROR),
                strobes=dict(look=STROBE["BLINDER"], int_lane=SNARE, spread=0),
                bars=dict(look=BAR["SCANNER"], int_lane=HAT, width=.3),
                body=dict(move_lane=PHRASE, pan_amp=12),
                capsid=dict(move_lane=SNARE, tilt_amp=12),
                legs=dict(move_lane=SNARE, tilt_amp=20, spread=.5, order=AROUND), rate=4, duty=.3)),
    ("ORBIT", fx(movers=dict(move_lane=KICK, pan_amp=25, rise=12, spread=.9, order=AROUND,
                             int_lane=KICK, look=mov(2), width=.4),
                 strobes=dict(look=STROBE["GLOW"], int_lane=KICK, width=.4, spread=.9, order=AROUND),
                 bars=dict(look=BAR["COMET"], int_lane=KICK, spread=.9, order=AROUND),
                 body=dict(move_lane=PHRASE, pan_amp=20),
                 capsid=dict(move_lane=PHRASE, look=spin(1)), rate=4, duty=.3)),
    # ---------------- BUILD: the BUILD lane ramps over 16 beats from the recall, pulses doubling ----------------
    ("ASCEND", fx(movers=dict(move_lane=BUILD, pan_amp=30, rise=40, int_lane=BUILD, width=.6, spread=.3, order=UP),
                  strobes=dict(look=STROBE["STROBE"], int_lane=BUILD, width=.3, order=UP),
                  bars=dict(look=BAR["CLIMB"], int_lane=BUILD, order=UP),
                  body=dict(move_lane=BUILD, tilt_amp=75),
                  capsid=dict(move_lane=BUILD, tilt_amp=80),
                  legs=dict(move_lane=BUILD, tilt_amp=60, spread=.3, order=AROUND), rate=4, duty=.3)),
    ("TENSION", fx(movers=dict(int_lane=BUILD, look=mov(4), width=.35, spread=.95, order=SHUFFLE, move_lane=BUILD, pan_amp=15),
                   strobes=dict(look=STROBE["SPARKLE"], int_lane=BUILD),
                   bars=dict(look=BAR["SEGMENTS"], int_lane=BUILD, width=.2),
                   body=dict(move_lane=BUILD, tilt_amp=-60),
                   capsid=dict(move_lane=PHRASE, look=spin(.5)),
                   legs=dict(move_lane=BUILD, look=mov(step=True), pan_amp=40, tilt_amp=40), rate=8, duty=.3)),
    ("LAUNCH", fx(movers=dict(move_lane=BUILD, look=mov(2, step=True), pan_amp=25, rise=15, int_lane=BUILD, width=.5, spread=0),
                  strobes=dict(look=STROBE["PULSE"], int_lane=BUILD, width=.4),
                  bars=dict(look=BAR["FILL"], int_lane=BUILD),
                  body=dict(move_lane=BUILD, tilt_amp=75),
                  capsid=dict(move_lane=BUILD, tilt_amp=90),
                  legs=dict(move_lane=BUILD, tilt_amp=90), rate=8, duty=.3)),
    ("COUNTDOWN", fx(movers=dict(int_lane=BUILD, width=.5, spread=.8, order=UP, move_lane=BUILD, rise=30),
                     strobes=dict(look=STROBE["STROBE"], int_lane=BUILD, spread=.8, order=UP),
                     bars=dict(look=BAR["STROBE"], int_lane=BUILD, spread=.8, order=UP),
                     body=dict(move_lane=BUILD, tilt_amp=-90),
                     capsid=dict(move_lane=BUILD, tilt_amp=90), rate=8, duty=.3)),
    # ---------------- CRAZY: everything on, tubes firing, the truss thrown around ----------------
    ("RIOT", fx(movers=dict(move_lane=KICK, look=mov(jump=True), pan_amp=50, rise=30, int_lane=KICK, width=.85, spread=.2),
                strobes=dict(look=STROBE["STROBE"], int_lane=KICK, width=.35),
                bars=dict(look=BAR["STROBE"], int_lane=HAT),
                body=dict(move_lane=KICK, tilt_amp=20),
                capsid=dict(move_lane=KICK, look=spin(.5)),
                legs=dict(move_lane=KICK, look=mov(jump=True), pan_amp=60, tilt_amp=60), rate=8, duty=.3)),
    ("STORM", fx(movers=dict(int_lane=KICK, look=mov(8, rnd=True), width=.9, spread=.95, order=SHUFFLE,
                             move_lane=PHRASE, pan_amp=40, rise=25),
                 strobes=dict(look=STROBE["SPARKLE"], int_lane=KICK, width=.35),
                 bars=dict(look=BAR["SPARKLE"], int_lane=KICK),
                 body=dict(move_lane=PHRASE, pan_amp=25),
                 capsid=dict(move_lane=PHRASE, look=spin(2)),
                 legs=dict(move_lane=KICK, tilt_amp=40, spread=.5, order=AROUND), rate=12, duty=.2)),
    ("SHATTER", fx(movers=dict(move_lane=SNARE, look=mov(2, step=True), pan_amp=45, rise=30, int_lane=KICK, width=.6),
                   strobes=dict(look=STROBE["BLINDER"], int_lane=SNARE),
                   bars=dict(look=BAR["BARCODE"], int_lane=HAT, width=.6),
                   body=dict(move_lane=SNARE, look=mov(jump=True), pan_amp=20, tilt_amp=40),
                   capsid=dict(move_lane=KICK, look=spin(.5)),
                   legs=dict(move_lane=SNARE, look=mov(step=True), pan_amp=50, tilt_amp=50), rate=6, duty=.35)),
    ("SUPERNOVA", fx(movers=dict(move_lane=KICK, pan_amp=35, rise=20, spread=.9, order=AROUND,
                                 int_lane=KICK, look=mov(4), width=.6),
                     strobes=dict(look=STROBE["STROBE"], int_lane=KICK, width=.9),
                     bars=dict(look=BAR["STROBE"]),
                     body=dict(move_lane=KICK, tilt_amp=25),
                     capsid=dict(move_lane=KICK, look=spin(2)),
                     legs=dict(move_lane=KICK, look=mov(jump=True), pan_amp=70, tilt_amp=70), rate=12, duty=.25)),
]
TIERS = [("CALM", 0), ("GROOVE", 4), ("BUILD", 8), ("CRAZY", 12)]


def effect_rows(spec):
    rows = {}
    def put(f, attrs):
        row = {k: DEFAULT[k] for k in EFFECT_F}
        for k, v in attrs.items():
            if k == "rise": row["tilt_amp"] = -v if HANGING(f) else v
            else: row[k] = v
        rows[f["slot"]] = row
    for f in MOVERS: put(f, spec["movers"])
    for f in STROBES: put(f, spec["strobes"])
    for f in BARS: put(f, spec["bars"])
    for f in AXES:
        k = f["slot"] - 240
        put(f, spec["body"] if k == 0 else spec["capsid"] if k == 1 else spec["legs"])
    return rows


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
FULL = [  # (name, static, pose, effects, colour, global overrides)
    ("GENESIS", "ORIGIN", "REST", "DRIFT", "PHAGE", {}),
    ("LULL", "CATHEDRAL", "RISE", "TIDE", "ICE", {"haze": .04}),
    ("DEEP", "HALO", "REST", "BREATHE", "UV", {"haze": .045}),
    ("EMBERS", "FRONT", "RISE", "EMBER", "SODIUM", {}),
    ("HEARTBEAT", "SUNBURST", "REST", "PULSE", "INFRARED", {}),
    ("PROCESSION", "FIBERS", "BLOOM", "WALK", "VIRAL", {}),
    ("SWELL", "CROWN", "RISE", "SWAY", "ROSE", {}),
    ("CAROUSEL", "HELIX", "REST", "ORBIT", "BIOLUME", {}),
    ("ASCENT", "CATHEDRAL", "REST", "ASCEND", "GLACIER", {}),
    ("PRESSURE", "CAGE", "INJECT", "TENSION", "MAGMA", {}),
    ("IGNITION", "X-FIRE", "REST", "LAUNCH", "DUSK", {}),
    ("ZERO", "NEEDLES", "REST", "COUNTDOWN", "WHITE", {}),
    ("RIOT", "X-FIRE", "BLOOM", "RIOT", "INFRARED", {"bloom": .16}),
    ("STORM", "PINPOINT", "INJECT", "STORM", "ICE", {"bloom": .16}),
    ("SHATTER", "CAGE", "REST", "SHATTER", "TOXIC", {"bloom": .16}),
    ("SUPERNOVA", "SUNBURST", "RISE", "SUPERNOVA", "SPLIT", {"bloom": .2}),
]


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


def full_rows(static_name, pose_name, color_name, effect_name):
    base = {f["slot"]: dict(DEFAULT) for f in FX if not f["unused"]}
    for f in STROBES: base[f["slot"]].update(level=1, ring=1)
    static = dict(STATIC)[static_name]
    pose = dict(STATIC)[pose_name]
    color = color_rows(dict((n, r) for n, _, r in COLORS)[color_name])
    effect = effect_rows(dict(EFFECTS)[effect_name])
    return merge(base, static, pose, color, effect)


def group(kind, presets):
    paths = sorted({p for _, snap in presets for p in snap})
    return {"id": f"phage_stage_{kind}", "paths": paths,
            "presets": [{"id": f"phage_stage_{kind}:{kind} {i}", "name": f"{kind} {i}", "revision": 1,
                         "snapshot": snap} for i, (_, snap) in enumerate(presets, 1)]}


def build():
    out = {}
    out["static"] = [(n, banks_snapshot("static", rows, STATIC_F)) for n, rows in STATIC]
    out["effects"] = [(n, {**banks_snapshot("effects", effect_rows(spec), EFFECT_F),
                          f"{STATE}show_strobe_rate": float(spec["rate"]), f"{STATE}show_strobe_duty": float(spec["duty"])})
                      for n, spec in EFFECTS]
    out["color"] = [(n, {**banks_snapshot("static", color_rows(route), STATIC_F),
                        **{STATE + k: v for k, v in palette_records(pal).items()}})
                    for n, pal, route in COLORS]
    full = []
    slot = {kind: {n: i for i, (n, *_) in enumerate(table, 1)} for kind, table in
            (("static", STATIC), ("effects", EFFECTS), ("color", COLORS))}
    for name, st, pose, ef, col, glob in FULL:
        rows = full_rows(st, pose, col, ef)
        spec = dict(EFFECTS)[ef]
        pal = dict((n, p) for n, p, _ in COLORS)[col]
        snap = {**banks_snapshot("static", rows, STATIC_F), **banks_snapshot("effects", rows, EFFECT_F),
                **{STATE + k: v for k, v in palette_records(pal).items()},
                **{STATE + k: v for k, v in RHYTHM.items()},
                **{f"{STATE}global_{k}": float(v) for k, v in {**GLOBAL_DEFAULT, **glob}.items()},
                f"{STATE}static_pitch": 0.0, f"{STATE}lighting_master": 1.0,
                f"{STATE}show_strobe_rate": float(spec["rate"]), f"{STATE}show_strobe_duty": float(spec["duty"]),
                # The pads this look is built from; the Surface lights them after the recall.
                f"{STATE}look_parts": f"static=static {slot['static'][st]};pose=static {slot['static'][pose]};"
                                      f"effects=effects {slot['effects'][ef]};color=color {slot['color'][col]}"}
        full.append((name, snap))
    out["complete"] = full
    out["rhythm"] = [("STANDARD", {STATE + k: v for k, v in RHYTHM.items()})]
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
        "}", ""])
    path = ROOT / "scripts" / "show" / "preset_titles.luau"
    path.write_text(text, newline="\n")
    return path


def main():
    built = build()
    (ROOT / "presets").mkdir(exist_ok=True)
    for kind, presets in built.items():
        path = ROOT / "presets" / f"phage_stage_{kind}.json"
        path.write_text(json.dumps(group(kind, presets), indent=1), newline="\n")
        print(f"{path.relative_to(ROOT)}: {len(presets)} looks, {path.stat().st_size // 1024} KB")
    print(write_titles(built).relative_to(ROOT))
    # Report what the static shapes do to the beams, so a bad aim shows up before a capture does.
    for name, rows in STATIC[:12]:
        tilts = [r["tilt"] for s, r in rows.items() if "tilt" in r]
        lit = sum(1 for s, r in rows.items() if FX[s]["kind"] == 0 and r.get("level", 0) > 0)
        print(f"  static {name:10s} movers lit {lit:3d}  tilt {min(tilts):7.1f}..{max(tilts):6.1f}")


if __name__ == "__main__":
    main()
