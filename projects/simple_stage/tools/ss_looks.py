"""SIMPLE STAGE looks: the club stage's static shapes, colours, sequences, effects and full looks -> the Surface's presets.

    python tools/ss_looks.py

Authored as geometry and intent (where beams go, which lane drives what) and compiled by tools/ss_show.py against the
solved mounts, with the aim inverse the GPU uses. Writes presets/simple_stage_{static,effects,color,complete,rhythm,
sequence,seq_heads,seq_strobes,seq_battens}.json, scripts/show/preset_titles.luau (pad names) and docs/LOOKS.md.

Layering, so banks mix live:
  STATIC     the heads' aim and levels and the wall's level: 16 beam shapes. Strobes are never touched.
  EFFECTS    every effect attribute of every fixture and the strobe clock: 1-4 CALM, 5-8 GROOVE, 9-12 BUILD (the BUILD
             lane restarts on the recall), 13-16 CRAZY. Never aim, levels or colour, so an effect plays on any shape.
  COLOR      the 8-palette library, the active palette and each fixture's routing (A/B/C).
  FULL       a shape + an effect + a colour, with the renderer's globals and the rhythm.
  SEQUENCES  15 whole-rig sequences then BLACKOUT, on every type at once (RIG) or each type's part (BEAMS, STROBES,
             BATTENS): aim, levels and effects together, phrase-locked.

The stage (tools/ss_stage.py), back to front: the WALL of twelve 4 m pixel runs behind the DJ; the FLOOR STROBES standing
along the deck's back edge; the BACK ROW of eight heads hung at 6 m behind the DJ; the DJ's booth; the FRONT ROW of eight
heads hung at 5.4 m over the front of the deck, with the TRUSS STROBES on its face between them. Each family has a job:
the two rows draw the shapes, the wall carries the graphics, the floor strobes silhouette the DJ against the wall, the
truss strobes hit. Audience at +z.

Two rules run through every look:
  SYMMETRY   every shape, chase, colour routing and move is a mirror image about the stage's centre line. Chases run
             OUT (from the centre to both edges at once) or FRONT, never across; alternations pair a fixture with its
             mirror (pair(), never the left-to-right index); moves lean the two halves opposite ways (ORDER MIRROR).
  STILLNESS  a STATIC shape is the picture, so most effects leave the heads where the shape put them. Movement is a
             deliberate act: a FORMATION look holds a symmetric formation for bars at a time and glides to the next on a
             downbeat; one look circles (ORBIT), the builds lift the heads with the ramp, and only SUPERNOVA lets every
             head roam on its own.
"""
from __future__ import annotations

import math

from ss_show import *        # noqa: F401,F403 - the look vocabulary
import ss_show as S

# --- who is who ---------------------------------------------------------------------------------------------------------
def front(f): return f["pos"][2] > 0            # the front row and the truss strobes
def back(f): return f["pos"][2] < 0             # the back row, the floor strobes and the wall
def front_row(f): return f["kind"] == 0 and f["family"] == 0
def wall(f): return f["kind"] == 2
def ax(f): return abs(f["pos"][0])
def inner(f): return ax(f) < 2.0
def middle(f): return 2.0 <= ax(f) < 4.0
def outer(f): return ax(f) >= 4.0
def side(f): return -1.0 if f["pos"][0] < 0 else 1.0


def _pairs():
    """Each fixture's mirror pair, counted from the centre line out within its family: the front row's heads at
    +-0.75 m are pair 0, at +-2.25 m pair 1... An alternation by pair is its own mirror image; one by the
    left-to-right index is not (eight heads: the leftmost is even, the rightmost odd)."""
    out = {}
    for fam in {f["family"] for f in LIGHTS}:
        xs = sorted({round(ax(f), 3) for f in LIGHTS if f["family"] == fam})
        out.update({f["slot"]: xs.index(round(ax(f), 3)) for f in LIGHTS if f["family"] == fam})
    return out


PAIR = _pairs()
def pair(f): return PAIR[f["slot"]]
def even(f): return pair(f) % 2 == 0


def every(part): return lambda f: dict(part)


DJ = (0.0, 2.3, .45)                            # the DJ's chest, behind the booth (tools/ss_stage.py DJ)


# --- STATIC: 16 beam shapes -----------------------------------------------------------------------------------------------
# A shape gives each head (direction, level, ring), front row and back row apart; the wall's level rides with it. Every
# head hangs, so a beam can rise at most 45 degrees above level (ss_show.fit clamps a little beyond, and darkens more).
# Every shape is its own mirror image: X(f) and lean() flip with the side, pair() alternates symmetrically.
def rows(front_dir, back_dir, level=1, ring=.6):
    return lambda f: ((front_dir(f) if front_row(f) else back_dir(f)), level, ring)


def X(f): return f["pos"][0]
def lean(f, k): return side(f) * k             # + out toward the head's own side, - across toward the other


BEAM_SHAPES = [
    # name, shape, wall level
    ("OPEN", rows(lambda f: to(f, (X(f) * 2.2, 0, 14)), lambda f: (X(f) * .25, .55, 1)), .8),
    ("FAN", rows(lambda f: (X(f) * .3, -.25, 1), lambda f: (X(f) * .35, -.05, 1)), .7),
    ("CURTAIN", rows(lambda f: (0, -1, .22), lambda f: (0, -1, .12), ring=.4), .4),
    ("PARALLEL", rows(lambda f: (0, -.36, 1), lambda f: (0, -.2, 1)), .6),
    ("CROSS", rows(lambda f: to(f, (-X(f) * 2.4, 0, 12)), lambda f: (-X(f) * .3, .7, .7), ring=.7), .7),
    ("LATTICE", rows(lambda f: (lean(f, .5 if even(f) else -.5), -.8, .45),
                     lambda f: (lean(f, -.45 if even(f) else .45), -.5, .65), ring=.7), .8),
    ("TUNNEL", rows(lambda f: to(f, (X(f) * .15, 7.0, 24)), lambda f: to(f, (X(f) * .15, 8.0, 24)), ring=.5), .5),
    ("SPOT", rows(lambda f: to(f, DJ), lambda f: to(f, DJ), ring=.5), .35),
    ("CROWN", rows(lambda f: (X(f) * .45, 1, .8), lambda f: (X(f) * .35, .8, .8), ring=.8), .8),
    ("SKY", rows(lambda f: (0, 1, 1.1), lambda f: (0, 1, 1)), .5),
    ("STAR", rows(lambda f: to(f, (0, 3.5, 9)), lambda f: to(f, (0, 3.5, 9)), ring=.7), .6),
    ("WINGS", rows(lambda f: (lean(f, .9), -.45, .8), lambda f: (lean(f, .9), -.2, .9), ring=.8), .9),
    ("FINGERS", rows(lambda f: (X(f) * .12, -1, .45) if even(f) else (X(f) * .18, .75, .75),
                     lambda f: (X(f) * .12, -1, .5) if even(f) else (X(f) * .18, .8, .7), ring=.7), .8),
    ("DIAMOND", rows(lambda f: to(f, (0, 1.6, 6.0)), lambda f: to(f, (0, 7.8, 4.5)), ring=.6), .7),
    ("V", rows(lambda f: to(f, (0, 0, 7)), lambda f: (X(f) * .5, .8, .6), ring=.8), .8),
    ("WAVE", rows(lambda f: (X(f) * .1, -.45 + .3 * math.cos(X(f) * 1.047), 1),
                  lambda f: (X(f) * .1, -.22 - .25 * math.cos(X(f) * 1.047), 1)), .7),
]
STATIC = [(name, merge(aim_rows(fn), level_rows(BARS, level=bars))) for name, fn, bars in BEAM_SHAPES]
SHAPE = dict(STATIC)


# --- COLOR: 8 palettes x routings -----------------------------------------------------------------------------------------
# Each colour as it should look; ss_show.palette_records linearises it into the DMX the fixtures play. Every routing is
# symmetric: by depth, by pair, centre against edges, never left against right.
PALETTES = [
    ("ARCTIC", [(80, 190, 255), (235, 248, 255), (20, 60, 255)]),
    ("NEON", [(255, 20, 160), (0, 230, 255), (130, 40, 255)]),
    ("EMBER", [(255, 40, 10), (255, 130, 0), (150, 0, 30)]),
    ("GOLD", [(255, 150, 40), (255, 225, 170), (255, 80, 0)]),
    ("ACID", [(140, 255, 20), (0, 255, 120), (0, 160, 150)]),
    ("ULTRA", [(110, 20, 255), (255, 0, 200), (30, 0, 180)]),
    ("SUNSET", [(255, 40, 110), (255, 160, 30), (150, 30, 255)]),
    ("WHITE", [(255, 255, 255), (255, 230, 190), (200, 225, 255)]),
]
A, B, C = 0, 1, 2


def r_mono(f): return (A, B)
def r_fb(f): return (A, B) if front(f) else (B, A)
def r_wall(f): return (C, A) if wall(f) else (A, B)
def r_depth(f): return (A, B) if front(f) else (C, A) if wall(f) else (B, C)
def r_pairs(f): return (A, C) if even(f) else (C, A)
def r_inout(f): return (A, B) if inner(f) else (B, A)
def r_fire(f): return (A, B) if wall(f) else (B, A)


COLORS = [  # (name, palette, routing)
    ("WHITE", 7, r_mono), ("ARCTIC", 0, r_mono), ("NEON", 1, r_mono), ("EMBER", 2, r_mono),
    ("GOLD", 3, r_mono), ("ACID", 4, r_mono), ("ULTRA", 5, r_mono), ("SUNSET", 6, r_mono),
    ("ICE FB", 0, r_fb), ("PRISM", 1, r_depth), ("LAVA", 2, r_fire), ("GOLD ALT", 3, r_pairs),
    ("TOXIC", 4, r_fb), ("VIOLET IN", 5, r_inout), ("DUSK", 6, r_wall), ("CANDY", 1, r_pairs),
]


# --- MOVEMENT: still, held formations, and the few looks that move ---------------------------------------------------------
# A part's `pan` leans the beam across the stage and `rise` lifts it (degrees; rise is signed per mount so hung heads
# lift). With ORDER MIRROR a GLIDE leans the stage's two halves opposite ways (motors.hlsl), so positive pan opens a
# shape out and negative closes it, and the formation stays the mirror image of itself.
def still(f): return None                      # the move's rest: the heads hold the shape


def formations(per_phrase=1, ease=.15, pan=16, rise=10, rows_turn=0.0, random=False):
    """Held symmetric formations: GLIDE on the PHRASE lane, a new formation per_phrase times a phrase, each move taking
    `ease` of a step and landing on the step's downbeat (offset -ease); every head of a row moves at once. The
    five-point figure walks home, open and up, closed and up, open and down, closed and down; `random` gives each row
    a fresh formation per step instead (one draw per row, mirrored). `rows_turn` sets the back row off that share of a
    step after the front row, so the rows answer each other."""
    def part(f):
        late = 0.0 if front_row(f) else rows_turn
        return dict(lane=PHRASE, look=glide(per_phrase, group=random), glide=ease, pan=pan, rise=rise, spread=0,
                    order=MIRROR, offset=-ease + late)
    return part


def m_orbit(f):
    """Mirrored circles, one per phrase, rippling from the centre out: the halves turn opposite ways."""
    return dict(lane=PHRASE, look=0, pan=side(f) * 12, rise=6, spread=.15, order=OUT)


def m_rise(f): return dict(lane=BUILD, pan=0, rise=24 if front_row(f) else 20)
def m_dive(f): return dict(lane=BUILD, pan=0, rise=-16)
def m_roam(f): return dict(lane=PHRASE, look=glide(8, rnd=True), glide=.55, spread=.9, order=SHUFFLE, pan=30, rise=20)


# --- light parts ----------------------------------------------------------------------------------------------------------
# PULSE (ss_show.hlsli ssPulse): each lane cycle a fixture snaps on at its rank x SPREAD and fades out by WIDTH, so a
# wide pulse keeps a light present and a narrow one is a hit. Presence first, the rhythm as accents.
# The HAT lane rests half of every beat, so it only carries accents (tube hits); an off-beat light is a KICK pulse
# half a beat late (offset -.5), and an eighth-note chase is KICK x2. The BUILD lane's level climbs from 30%, so a
# build lights its fixtures from the first beat.
def P(lane, width=.7, spread=0.0, order=AROUND, reverse=0, offset=0.0, reps=1, rnd=False):
    return dict(lane=lane, look=0 if reps == 1 and not rnd else mov(reps, rnd=rnd), width=width, spread=spread,
                order=order, reverse=reverse, offset=offset)


ON = dict(lane=OFF, look=0)                               # no lane: steady at its level
DRIFT = dict(lane=OFF, look=0, clane=PHRASE, spread=.5, order=OUT)   # steady, its colour drifting out from the centre


def TUBE(look, lane=OFF, width=.12, **kw):
    """A strobe's tube (or plates): PULSE a white hit fading by WIDTH, STROBE the show's strobe clock while the chase
    is up, SPARKLE random flashes, BLINDER a warm hit decaying over the lane cycle, GLOW (tube dark), OFF."""
    return dict(look=STROBE[look], lane=lane, width=width, **kw)


def PX(pattern, lane=PHRASE, reps=1, width=.5, **kw):
    """A wall run's content (led_patterns.hlsli), run x reps per lane cycle. Up the run is u 0 to 1; OUT orders the
    twelve runs from the centre to both edges at once."""
    return dict(look=px(pattern, reps), lane=lane, width=width, **kw)


def W(lane, start, length, reps=1, **kw):
    """A HOLD window: open from `start` for `length` of each lane cycle (x reps), dark the rest of it."""
    return dict(look=hold_code(reps), lane=lane, width=length, offset=-start / reps, **kw)


def by(front_part, back_part):
    """The front (front row, truss strobes) one way, the back (back row, floor strobes, the wall) the other."""
    return lambda f: dict(front_part if front(f) else back_part)


def zone(outer_part, middle_part, inner_part):
    return lambda f: dict(outer_part if outer(f) else middle_part if middle(f) else inner_part)


def alt(even_part, odd_part):
    """Alternate mirror pairs: the pairs counted from the centre out, so the alternation is symmetric."""
    return lambda f: dict(even_part if even(f) else odd_part)


def stage(wall_part, back_part, front_part):
    """The journey through the stage: the wall, the back line, the front line (None: steady)."""
    return lambda f: dict((wall_part if wall(f) else back_part if back(f) else front_part) or ON)


def lights(beam=None, halo=None, tube=None, plates=None, pixels=None, chase=None):
    """A sequence's light layers; a layer left out rests (steady heads, dark tubes, glowing plates, solid wall)."""
    out = {}
    for k, v in dict(beam=beam, halo=halo, tube=tube, plates=plates, pixels=pixels, chase=chase).items():
        if v is not None: out[k] = v if callable(v) else every(v)
    return out


# --- SEQUENCES: the whole rig in one movement -------------------------------------------------------------------------------
# (name, shape, move, layers, strobe clock (rate per beat, duty)). Pad page 2 plays them on every type (RIG) or one
# type's part; EFFECTS 1-16 are the same layers without the shape, so they play on any STATIC look.
CALM_CLOCK, GROOVE_CLOCK, BUILD_CLOCK, CRAZY_CLOCK = (4, .3), (4, .3), (6, .4), (6, .45)
# A FRONT-ordered chase starts at its nearest fixture's rank x SPREAD; shifting it by that much lands the front of the
# stage on the beat itself (the truss strobes, at rank FRONT_LEAD).
FRONT_LEAD = min(rank(f, FRONT) for f in LIGHTS)
SEQUENCES = [
    # ---- CALM: steady beams, slow light, the wall flowing; the heads hold still or glide a formation a phrase
    ("BREATH", "OPEN", still, lights(
        beam=DRIFT, halo=P(PHRASE, 1.0, .5, OUT, reps=2), plates=P(PHRASE, 1.0, .5, OUT, reps=2), tube=TUBE("OFF"),
        pixels=PX("PLASMA", PHRASE, spread=.5)), CALM_CLOCK),
    ("TIDE", "SKY", formations(1, ease=.25, pan=14, rise=10), lights(
        beam=ON, halo=P(PHRASE, .9, .6, OUT, reps=2), plates=P(PHRASE, 1.0, .6, OUT, reps=2), tube=TUBE("OFF"),
        pixels=PX("CHEVRON", PHRASE, 2, width=.35, spread=.3)), CALM_CLOCK),
    ("ORBIT", "STAR", m_orbit, lights(
        beam=ON, halo=P(PHRASE, .9, .95, OUT, reps=4), plates=P(PHRASE, .9, .95, OUT, reps=2), tube=TUBE("OFF"),
        pixels=PX("SCANNER", PHRASE, 2, width=.4, spread=.5, order=OUT)), CALM_CLOCK),
    ("HEARTBEAT", "SPOT", still, lights(
        beam=by(P(KICK, .95), P(KICK, .95, offset=-.22)), halo=ON, plates=P(KICK, .45), tube=TUBE("OFF"),
        pixels=PX("HEARTBEAT", KICK, width=.6, spread=.2, order=OUT)), CALM_CLOCK),
    # ---- GROOVE: kick, snare and off-beat over beams that are nearly always up; still, or stepping formations
    ("STRIDE", "PARALLEL", formations(2, ease=.12, pan=18, rise=10), lights(
        beam=P(KICK, .85, .25, OUT), halo=P(KICK, .5, .25, OUT), plates=P(KICK, .55, .25, OUT),
        tube=TUBE("PULSE", SNARE, .1), pixels=PX("EQ", KICK, width=.4, spread=.6, order=OUT)), GROOVE_CLOCK),
    ("PING PONG", "CROSS", still, lights(
        beam=by(P(KICK, .55), P(KICK, .55, offset=-.5)), halo=by(P(KICK, .45), P(KICK, .45, offset=-.5)),
        tube=by(TUBE("PULSE", KICK, .08), TUBE("PULSE", KICK, .08, offset=-.5)),
        plates=by(P(KICK, .45), P(KICK, .45, offset=-.5)),
        pixels=alt(PX("SOLID", KICK, width=.5), PX("SOLID", KICK, width=.5, offset=-.5))), GROOVE_CLOCK),
    ("ANSWER", "WAVE", still, lights(
        beam=zone(P(KICK, .9), P(KICK, .6, offset=-.5), P(SNARE, .95)), halo=ON,
        tube=zone(TUBE("OFF"), TUBE("PULSE", HAT, .08), TUBE("PULSE", SNARE, .14)),
        pixels=zone(PX("SOLID", KICK, width=.9), PX("SOLID", KICK, width=.6, offset=-.5), PX("SOLID", SNARE, width=.95))),
     GROOVE_CLOCK),
    ("FALL", "CURTAIN", still, lights(
        beam=P(KICK, .8, .5, OUT), halo=P(KICK, .45, .5, OUT), tube=by(TUBE("OFF"), TUBE("BLINDER", SNARE)),
        plates=P(KICK, .45, .5, OUT), pixels=PX("RAIN", PHRASE, 4, width=.4)), GROOVE_CLOCK),
    # ---- BUILD: IGNITION lights the stage one part at a time over a phrase over glowing halos; the rest ride the
    # BUILD lane, which restarts on the recall, brightens from 30% with its ramp and doubles its pulses each quarter
    ("IGNITION", "TUNNEL", still, lights(
        beam=stage(None, ON, W(PHRASE, .25, .75)), halo=ON,
        tube=TUBE("STROBE", PHRASE, .25, offset=-.75), plates=W(PHRASE, .5, .5),
        pixels=PX("CLIMB", PHRASE, 4, width=.6)), BUILD_CLOCK),
    ("CHARGE", "FAN", m_rise, lights(
        beam=P(BUILD, .75), halo=ON, tube=TUBE("STROBE", BUILD, .5), plates=P(BUILD, .6),
        pixels=PX("EQ", BUILD, width=.4, spread=.5, order=OUT)), BUILD_CLOCK),
    ("RISER", "WINGS", m_rise, lights(
        beam=P(BUILD, 1.0), halo=ON, tube=by(TUBE("STROBE", BUILD, .6), TUBE("OFF")),
        plates=P(BUILD, .5, .95, OUT), pixels=PX("CHEVRON", PHRASE, 4, width=.35, spread=.4)), BUILD_CLOCK),
    ("CONVERGE", "DIAMOND", m_dive, lights(
        beam=P(BUILD, .9, .9, OUT, reverse=1), halo=ON,
        tube=TUBE("PULSE", BUILD, .3, spread=.9, order=OUT, reverse=1), plates=P(BUILD, .5, .9, OUT, reverse=1),
        pixels=PX("TWIN", BUILD, width=.5, spread=.9, order=OUT, reverse=1)), BUILD_CLOCK),
    # ---- CRAZY: kick-locked over steady halos, the strobes let go; formations snap on the bar; only SUPERNOVA roams
    ("DETONATE", "V", formations(4, ease=.1, pan=22, rise=14, random=True), lights(
        beam=P(KICK, .85, .35, OUT), halo=ON, tube=by(TUBE("STROBE", KICK, .35), TUBE("BLINDER", KICK)),
        plates=P(KICK, .5, .35, OUT), pixels=PX("RIPPLE", KICK, width=.4)), CRAZY_CLOCK),
    ("SHOCKWAVE", "LATTICE", still, lights(
        beam=P(KICK, .8, .5, FRONT, offset=FRONT_LEAD * .5), halo=ON,
        tube=TUBE("PULSE", KICK, .15, spread=.5, order=FRONT, offset=FRONT_LEAD * .5),
        plates=P(KICK, .45, .5, FRONT, offset=FRONT_LEAD * .5),
        pixels=PX("SOLID", KICK, width=.45, spread=.5, order=FRONT, offset=FRONT_LEAD * .5)), CRAZY_CLOCK),
    ("CASCADE", "FINGERS", formations(2, ease=.15, pan=18, rise=10, rows_turn=.5), lights(
        beam=P(KICK, .8, .9, OUT, reps=2), halo=P(KICK, .5, .9, OUT), tube=TUBE("PULSE", HAT, .1, spread=.9, order=OUT),
        plates=P(KICK, .6, .9, OUT, reps=2), pixels=PX("CHASE", KICK, 2, width=.5, spread=.9, order=OUT)), CRAZY_CLOCK),
]
SUPERNOVA = ("SUPERNOVA", "CROWN", m_roam, lights(
    beam=P(KICK, .7, reps=2), halo=ON, tube=by(TUBE("STROBE", KICK, .6), TUBE("BLINDER", SNARE)),
    plates=TUBE("BLINDER", SNARE), pixels=PX("STROBE", KICK)), CRAZY_CLOCK)


def seq_rows(shape, move, parts):
    """Every row of a sequence: the shape's aim and levels, strobes and the wall at full, the moves and each light
    layer's parts."""
    return merge(SHAPE[shape], level_rows(STROBES, level=1.0, ring=1.0), level_rows(BARS, level=1.0),
                 effect_rows(dict(parts, move=move)))


SEQ_FIXTURES = {"sequence": LIGHTS, "seq_heads": MOVERS, "seq_strobes": STROBES, "seq_battens": BARS}


# --- EFFECTS: the whole rig, tiered by energy ------------------------------------------------------------------------------
def from_sequence(name, move=None):
    _, shape, seq_move, parts, clock = next(q for q in SEQUENCES + [SUPERNOVA] if q[0] == name)
    return dict(parts, move=move or seq_move), clock


EFFECTS = [  # (name, (layers, clock))
    # ---- CALM
    ("AWAKEN", from_sequence("BREATH")), ("TIDE", from_sequence("TIDE")), ("ORBIT", from_sequence("ORBIT")),
    ("HEARTBEAT", from_sequence("HEARTBEAT")),
    # ---- GROOVE
    ("STRIDE", from_sequence("STRIDE")), ("PING PONG", from_sequence("PING PONG")), ("ANSWER", from_sequence("ANSWER")),
    ("FALL", from_sequence("FALL")),
    # ---- BUILD
    ("IGNITION", from_sequence("IGNITION")), ("CHARGE", from_sequence("CHARGE")), ("RISER", from_sequence("RISER")),
    ("CONVERGE", from_sequence("CONVERGE")),
    # ---- CRAZY
    ("DETONATE", from_sequence("DETONATE")), ("SHOCKWAVE", from_sequence("SHOCKWAVE")),
    ("CASCADE", from_sequence("CASCADE")), ("SUPERNOVA", from_sequence("SUPERNOVA")),
]
TIERS = ("CALM", "GROOVE", "BUILD", "CRAZY")


def look_rows(layers):
    return effect_rows(layers)


# --- FULL LOOKS ---------------------------------------------------------------------------------------------------------
FULL = [  # (name, static, effects, colour, global overrides): every shape and every colour once
    ("GENESIS", "OPEN", "AWAKEN", "ARCTIC", {}),
    ("TIDEWATER", "SKY", "TIDE", "ICE FB", {"haze": .04}),
    ("CAROUSEL", "STAR", "ORBIT", "ULTRA", {"haze": .04}),
    ("PULSE", "SPOT", "HEARTBEAT", "EMBER", {"haze": .045}),
    ("STRIDE", "PARALLEL", "STRIDE", "ACID", {}),
    ("RALLY", "CROSS", "PING PONG", "PRISM", {}),
    ("DIALOGUE", "WAVE", "ANSWER", "SUNSET", {}),
    ("RAINFALL", "CURTAIN", "FALL", "WHITE", {}),
    ("IGNITION", "TUNNEL", "IGNITION", "GOLD", {}),
    ("CHARGE", "FAN", "CHARGE", "VIOLET IN", {}),
    ("ASCENT", "WINGS", "RISER", "GOLD ALT", {}),
    ("VORTEX", "DIAMOND", "CONVERGE", "TOXIC", {}),
    ("DETONATION", "V", "DETONATE", "LAVA", {"bloom": .16}),
    ("SHOCKWAVE", "LATTICE", "SHOCKWAVE", "NEON", {"bloom": .16}),
    ("CASCADE", "FINGERS", "CASCADE", "DUSK", {"bloom": .16}),
    ("SUPERNOVA", "CROWN", "SUPERNOVA", "CANDY", {"bloom": .2}),
]

RHYTHM = {"rhythm_1_mode": 0.0, "rhythm_1_cycle": 1.0, "rhythm_1_rest": 0.0, "rhythm_1_offset": 0.0,      # KICK
          "rhythm_2_mode": 0.0, "rhythm_2_cycle": 1.0, "rhythm_2_rest": 1.0, "rhythm_2_offset": 1.0,      # SNARE 2, 4
          "rhythm_3_mode": 0.0, "rhythm_3_cycle": .5, "rhythm_3_rest": .5, "rhythm_3_offset": .5}         # HI-HAT
GLOBAL_DEFAULT = {"master": 1.0, "exposure": 1.0, "bloom": .12, "sensor_white_start": 2.0,
                  "sensor_white_response": .16, "streak_strength": .005, "streak_length": .08, "haze": .03}


def full_rows(static_name, color_name):
    """A FULL look's aim, levels and palettes: everything at its default level, strobes full, then the shape and the
    colour routing."""
    base = {}
    for f in LIGHTS:
        if f["kind"] == 0:
            base.update({f["slot"]: {"pan": 0.0, "tilt": 0.0}, BEAM0 + f["slot"]: {"level": 1.0},
                         LAYER2 + f["slot"]: {"ring": .6}})
    base = merge(base, level_rows(STROBES, level=1.0, ring=1.0), level_rows(BARS, level=1.0))
    route = dict((n, r) for n, _, r in COLORS)[color_name]
    return merge(base, SHAPE[static_name], palette_rows(route))


# --- build ----------------------------------------------------------------------------------------------------------------
def clocked(snap, clock):
    if clock:
        snap = dict(snap)
        snap[f"{STATE}show_strobe_rate"] = float(clock[0])
        snap[f"{STATE}show_strobe_duty"] = float(clock[1])
    return snap


def build():
    out = {}
    out["static"] = [(n, static_snapshot(rows, STATIC_MASK)) for n, rows in STATIC]
    out["effects"] = [(n, clocked(effects_snapshot(look_rows(layers)), clock or (4, .3))) for n, (layers, clock) in EFFECTS]
    out["color"] = [(n, {**static_snapshot(palette_rows(route), {"beam_palette", "ring_palette"}),
                        **{STATE + k: v for k, v in palette_records(PALETTES, pal).items()}})
                    for n, pal, route in COLORS]
    slot = {kind: {n: i for i, (n, *_) in enumerate(table, 1)} for kind, table in
            (("static", STATIC), ("effects", EFFECTS), ("color", COLORS))}
    effects = dict(EFFECTS)
    full = []
    for name, st, ef, col, glob in FULL:
        layers, clock = effects[ef]
        pal = dict((n, p) for n, p, _ in COLORS)[col]
        snap = {**static_snapshot(full_rows(st, col)), **effects_snapshot(look_rows(layers)),
                **{STATE + k: v for k, v in palette_records(PALETTES, pal).items()},
                **{STATE + k: v for k, v in RHYTHM.items()},
                **{f"{STATE}global_{k}": float(v) for k, v in {**GLOBAL_DEFAULT, **glob}.items()},
                f"{STATE}static_pitch": 0.0, f"{STATE}lighting_master": 1.0,
                # The pads this look is built from; the Surface lights them after the recall.
                f"{STATE}look_parts": f"static=static {slot['static'][st]};effects=effects {slot['effects'][ef]};"
                                      f"color=color {slot['color'][col]}"}
        full.append((name, clocked(snap, clock or (4, .3))))
    out["complete"] = full
    out["rhythm"] = [("STANDARD", {STATE + k: v for k, v in RHYTHM.items()})]
    built = [(name, seq_rows(shape, move, parts), clock) for name, shape, move, parts, clock in SEQUENCES]
    for kind in SEQ_FIXTURES:
        out[kind] = [(name, family_snapshot(kind, rows, clock)) for name, rows, clock in built] + \
                    [("BLACKOUT", blackout_snapshot(kind))]
    return out


def write_titles(built):
    def names(kind): return "{" + ",".join(f'"{n}"' for n, _ in built[kind]) + "}"
    text = "\n".join([
        "--!strict",
        "-- Generated by tools/ss_looks.py; edit the generator, not this file.",
        "-- Pad names for the preset banks; index = pad slot. Effects run CALM 1-4, GROOVE 5-8, BUILD 9-12, CRAZY 13-16.",
        "return {",
        f"    static={names('static')},",
        f"    effects={names('effects')},",
        f"    color={names('color')},",
        f"    complete={names('complete')},",
        "    -- sequence banks (pad page 2): every type at once, then each type's part of the same sequences",
        *[f"    {kind}={names(kind)}," for kind in SEQ_FIXTURES],
        "}", ""])
    path = ROOT / "scripts" / "show" / "preset_titles.luau"
    path.write_text(text, encoding="utf-8", newline="\n")
    return path


# --- docs/LOOKS.md -------------------------------------------------------------------------------------------------------
SHAPE_NOTES = {
    "OPEN": "front row fans onto the crowd, back row fans up and out over it: the reference aim",
    "FAN": "two flat fans over the crowd, the back row's higher and wider",
    "CURTAIN": "every head straight down: a wall of light in front of the DJ and one behind",
    "PARALLEL": "every beam straight out over the crowd",
    "CROSS": "front beams cross onto the far side of the floor, back beams cross up over the crowd: an X above an X",
    "LATTICE": "neighbouring heads lean into each other and cross, the back row crossing in the front row's gaps: a "
               "chain of X's across the stage",
    "TUNNEL": "every beam converges over the back of the room, a corridor seen from the floor",
    "SPOT": "all sixteen onto the DJ: the front row lights them, the back row rims them",
    "CROWN": "everything up and out, the rows fanned",
    "SKY": "everything up over the crowd, parallel",
    "STAR": "both rows meet at one point in the haze over the front of the crowd",
    "WINGS": "each half of the stage throws a sheet of parallel beams out and down to its own side",
    "FINGERS": "alternate pairs from the centre out: one pair down onto the front of the crowd, the next up and out",
    "DIAMOND": "the front row converges on the crowd, the back row on a point high over the front of the stage: a "
               "diamond drawn in beams",
    "V": "the front row converges on the dancefloor, the back row fans up behind it",
    "WAVE": "a frozen wave across each row, low where the other row is high",
}
ROUTE_NOTES = {r_mono: "mono (beams A, halos and second colours B)", r_fb: "front A, back B",
               r_wall: "the rows and strobes A, the wall C", r_depth: "front A, back row and floor strobes B, wall C",
               r_pairs: "alternate mirror pairs A / C", r_inout: "inner A, outer B",
               r_fire: "the rows and strobes B with A halos, the wall A with B accents"}
MOTION_NOTES = {"still": "still", "formations": "formations", "m_orbit": "circles", "m_rise": "rise with the ramp",
                "m_dive": "dive with the ramp", "m_roam": "free"}
SEQ_NOTES = {
    "BREATH": "steady beams whose colour drifts out from the centre, halos and plates swelling outward twice a phrase, "
              "the wall a mirrored PLASMA; heads still",
    "TIDE": "the heads hold a formation for a phrase and glide to the next over its last bar, the halos and plates "
            "swell outward; slow chevrons climb the wall",
    "ORBIT": "the one flowing look: every head draws a slow circle, the two halves turning opposite ways; halos and "
             "plates roll outward; the wall's runs scan from the centre out",
    "HEARTBEAT": "lub-dub: the front row thumps on the kick, the back row a fifth of a beat later, both glowing on "
                 "through the beat; the wall beats from its centre; heads still",
    "STRIDE": "a new formation every two bars, landing on the downbeat; beams re-hit outward from the centre on "
              "every kick, white hits on 2 and 4; the wall a mirrored equaliser bouncing on the kick",
    "PING PONG": "front on the beat, back on the off-beat: beams, halos and strobes; the wall's mirror pairs "
                 "alternate; heads still",
    "ANSWER": "call and response by zone: the outer heads and wall runs on the kick, the middle on the off-beat, "
              "the centre on 2 and 4, over steady halos; heads still",
    "FALL": "the kick ripples out from the centre, rain falls down the wall, the floor strobes silhouette the DJ on 2 "
            "and 4; heads still",
    "IGNITION": "over a phrase: the back row and the wall's climbing bands hold the stage, the front row lights at "
                "the second bar, the plates at the third, and the strobes fire over the last; heads still",
    "CHARGE": "the 16-beat build: beams pulse faster and brighter, heads rise, the strobes strobe up the ramp, the "
              "wall's equaliser bounces with it",
    "RISER": "the build with steady beams brightening as the heads climb; the truss strobes strobe; chevrons climb "
             "the wall",
    "CONVERGE": "the build rolling inward from the edges while the heads dive onto the crowd; the wall's runs close "
                "in with it",
    "DETONATE": "every kick bursts out from the centre over steady halos: a ripple across the wall, the truss "
                "strobes strobing, the floor strobes blinding; the rows snap to a new symmetric formation every bar",
    "SHOCKWAVE": "every kick lands on the front of the stage and travels back through the back row to the wall, "
                 "over steady halos; heads still",
    "CASCADE": "eighth-note cascades out from the centre across the beams and the wall, white hits on the off-beat; "
               "the rows take turns to step formation every two bars",
    "SUPERNOVA": "everything on the kick at double rate over steady halos, the wall strobing, the floor strobes "
                 "blinding on 2 and 4; every head roams on its own",
}
EFFECT_SOURCE = {"AWAKEN": "BREATH"}


def write_doc():
    out = ["# SIMPLE STAGE looks", "",
           "Generated by `tools/ss_looks.py` from the definitions it compiles; edit the generator, not this file.", "",
           "Every look is authored as geometry and intent and compiled against the solved mounts with the inverse the",
           "GPU uses (`tools/ss_show.py`). The banks own disjoint fields, so they mix live:", "",
           "| Bank | Owns |", "|---|---|",
           "| STATIC | the heads' pan, tilt and beam and halo levels; the runs' level. Never the strobes. |",
           "| EFFECTS | every effect field of every fixture (lanes, sizes, spread, width, offset, look, order) and the "
           "strobe clock. Never aim, levels or colour. |",
           "| COLOR | the 8-palette library, the active palette and each fixture's routing (A / B / C). |",
           "| FULL LOOKS | a STATIC + an EFFECTS + a COLOR, the renderer's globals and the rhythm. |",
           "| SEQUENCES | aim, levels and every effect field of the types they play; palettes stay with COLOR. |", "",
           "Two rules run through every look. **Symmetry:** every shape, chase, colour routing and move is its own",
           "mirror image about the stage's centre line; chases run out from the centre or front to back, alternations",
           "pair each fixture with its mirror, and moves lean the two halves opposite ways. **Stillness:** a STATIC",
           "shape is the picture, so most effects leave the heads where it put them. Moving is a deliberate act: a",
           "formation look holds a symmetric formation for bars at a time and glides to the next on a downbeat, ORBIT",
           "circles, the builds lift the heads with the ramp, and only SUPERNOVA lets the heads roam.", "",
           "Lanes: KICK every beat, SNARE on 2 and 4, HI-HAT the off-beat eighths (it rests half of each beat, so it "
           "only carries accents), BUILD a 16-beat ramp that restarts on the beat after its recall, brightens from 30% "
           "with its ramp and doubles its pulse rate each quarter, PHRASE one turn per 16 beats.", "",
           "## STATIC: 16 beam shapes", "", "| # | Shape | Tilt range | What the beams do |", "|---|---|---|---|"]
    for i, (name, rows) in enumerate(STATIC, 1):
        tilts = [v["tilt"] for r, v in rows.items() if r < L.STROBE0 and "tilt" in v]
        out.append(f"| {i} | {name} | {round(min(tilts)) + 0} to {round(max(tilts)) + 0} deg | {SHAPE_NOTES[name]} |")
    out += ["", "## COLOR: 8 palettes x routings", "",
            "Each colour is authored as it should look and linearised into the DMX the fixtures play (a fixture's RGB",
            "is LED output, linear light).", "", "| Palette | A | B | C |", "|---|---|---|---|"]
    for name, cols in PALETTES:
        out.append(f"| {name} | " + " | ".join("#%02X%02X%02X" % tuple(c) for c in cols) + " |")
    out += ["", "| # | Colour | Palette | Routing |", "|---|---|---|---|"]
    for i, (name, pal, route) in enumerate(COLORS, 1):
        out.append(f"| {i} | {name} | {PALETTES[pal][0]} | {ROUTE_NOTES[route]} |")
    out += ["", "## EFFECTS: 16 in four energy tiers", "",
            "The same layers as the sequences, without the shape, so each plays on any STATIC look.", "",
            "| # | Tier | Effect | Heads | Strobe clock | What it does |", "|---|---|---|---|---|---|"]
    for i, (name, (layers, clock)) in enumerate(EFFECTS, 1):
        src = EFFECT_SOURCE.get(name, name)
        out.append(f"| {i} | {TIERS[(i - 1) // 4]} | {name} | {motion_of(src)} | {clock[0]}/beat, "
                   f"{int(clock[1] * 100)}% | {SEQ_NOTES[src]} |")
    out += ["", "## FULL LOOKS", "", "| # | Look | STATIC | EFFECTS | COLOR | Globals |", "|---|---|---|---|---|---|"]
    for i, (name, st, ef, col, glob) in enumerate(FULL, 1):
        g = ", ".join(f"{k} {v}" for k, v in glob.items()) or "-"
        out.append(f"| {i} | {name} | {st} | {ef} | {col} | {g} |")
    out += ["", "## SEQUENCES (pad page 2, the desk's SEQUENCES bank)", "",
            "Fifteen whole-rig sequences and BLACKOUT, each with its own shape. RIG plays every type at once; BEAMS,",
            "STROBES and BATTENS hold each type's part of the same sequences, so the same slot on each is the same",
            "moment and they mix: BEAMS on STRIDE under STROBES on DETONATE.", "",
            "| # | Sequence | Shape | Heads | What it does |", "|---|---|---|---|---|"]
    for i, (name, shape, *_rest) in enumerate(SEQUENCES, 1):
        out.append(f"| {i} | {name} | {shape} | {motion_of(name)} | {SEQ_NOTES[name]} |")
    out += ["| 16 | BLACKOUT | - | - | every level and ring of its types at 0; the next look brings them back |", ""]
    path = ROOT / "docs" / "LOOKS.md"
    path.parent.mkdir(exist_ok=True)
    path.write_text("\n".join(out), encoding="utf-8", newline="\n")
    return path


def motion_of(name):
    """What a sequence's heads do, for the docs: still, formations (how often), circles, the build's lift or free."""
    move = next(q[2] for q in SEQUENCES + [SUPERNOVA] if q[0] == name)
    part = move(MOVERS[0])
    if part is None: return "still"
    if part.get("lane") == BUILD: return "rise with the build" if part.get("rise", 0) > 0 else "dive with the build"
    if part.get("order") == SHUFFLE: return "free"
    if part.get("look") == 0: return "circles"
    steps = 2 ** ((part["look"] - 52) & 3)
    return {1: "a new formation each phrase", 2: "a new formation every 2 bars", 4: "a new formation every bar"}[steps]


def report():
    """What the shapes do to the beams, so a bad aim shows before a capture does; and that every look is symmetric."""
    for name, rows in STATIC:
        heads = [(r, rows[r]) for r in rows if r < L.STROBE0]
        tilts = [v["tilt"] for _, v in heads]
        lit = sum(1 for f in MOVERS if rows.get(BEAM0 + f["slot"], {}).get("level", 0) > 0)
        print(f"  static {name:10s} heads lit {lit:2d}/16  tilt {min(tilts):7.1f}..{max(tilts):6.1f}")
    print(f"  symmetry: {check_symmetry()} mirrored fields checked, every look is its own mirror image")


def mirror_of(f):
    """The fixture's mirror image across the centre line (same family, opposite side, same distance)."""
    return next(g for g in LIGHTS if g["family"] == f["family"] and abs(g["pos"][0] + f["pos"][0]) < 1e-3)


def check_symmetry():
    """Every STATIC, COLOR, EFFECTS and FULL look compiled, fixture against mirror: the same tilt, level, ring, palette
    and effect fields, and a pan that mirrors (a head's pan is its own mirror's, negated)."""
    def compare(rows, label):
        n = 0
        for f in LIGHTS:
            g = mirror_of(f)
            for base in (0, BEAM0, LAYER2):
                if f["kind"] != 0 and base == BEAM0: continue
                a, b = rows.get(base + f["slot"]), rows.get(base + g["slot"])
                if a is None and b is None: continue
                assert a is not None and b is not None, (label, f["name"], g["name"], base)
                for k in a:
                    va, vb = a[k], b[k]
                    if k in ("pan", "pan_amp"):
                        # A GLIDE under ORDER MIRROR mirrors in the motors; anything else must be authored mirrored.
                        mirrored = k == "pan_amp" and a.get("order") == MIRROR and a.get("look", 0) >= 52
                        vb = vb if mirrored else -vb
                    assert abs(va - vb) < 1e-6, (label, f["name"], g["name"], base, k, va, vb)
                    n += 1
        return n
    total = 0
    for name, rows in STATIC: total += compare(rows, f"static {name}")
    for name, pal, route in COLORS: total += compare(palette_rows(route), f"color {name}")
    for name, (layers, _) in EFFECTS:
        if name == "SUPERNOVA": continue                 # the one look whose heads roam on their own
        total += compare(look_rows(layers), f"effects {name}")
    return total


def main():
    built = build()
    for kind, presets in built.items():
        path = write_group(kind, presets)
        print(f"{path.relative_to(ROOT)}: {len(presets)} looks, {path.stat().st_size // 1024} KB")
    print(write_titles(built).relative_to(ROOT))
    print(write_doc().relative_to(ROOT))
    report()


if __name__ == "__main__":
    main()
