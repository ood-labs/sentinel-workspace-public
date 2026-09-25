# Klangrig look bank

STATIC, COLOR and EFFECTS are full (16 each). FULL LOOKS is unchanged.
Names live in `scripts/show/preset_titles.luau`. Pads show the first five characters; the status line shows the full name.

### STATIC: pad columns are energy, minimal (left) to full-rig statement (right)

| Row | Minimal | Graphic | Dense | Full rig |
|---|---|---|---|---|
| 1 | 01 REFERENCE (original) | 02 FRONT (original) | 03 HELIX: spine twists 30 deg per head, upper wings aim in at it, lower dark | 04 SUNBURST: everything radiates out of the rig centre and lifts |
| 2 | 05 NEEDLES: every 6th spine head straight down, nothing else | 06 V-GATES: upper wings A-frame above each bay, lower wings cross under | 07 WEAVE: left wings down-right, right wings up-left, spine herringbone | 08 CAGE: upper up, lower down, spine flat L/R |
| 3 | 09 RINGS: no beams, ring glow only | 10 PINPOINT: half the wings + every 4th spine head on one floor point | 11 CATHEDRAL: upper vault to a high ridge, lower rake out in three layers, spine fans up | 12 BLINDERS: every head at the FOH audience |
| 4 | 13 HORIZON: lower wings, every other head, flat fan over the crowd | 14 PRISM: front bay converges, middle bay fans up, back bay flat out | 15 SHARDS: fixed-random aims, about 60% lit | 16 X-FIRE: sides cross to the far opposite corners |

STATIC stores pan, tilt, beam and ring for active movers. Looks that leave heads dark set them to level 0; recall a full-rig static to bring them back.

### COLOR

| Slot | COLOR | Slot | COLOR |
|---|---|---|---|
| 01 | WHITE: beams, rings and LEDs | 09 | UV |
| 02 | CYAN (original reference, LED red) | 10 | MAGENTA |
| 03 | RED | 11 | PINK |
| 04 | ORANGE | 12 | WARM |
| 05 | GOLD | 13 | SP/WG: spine A, wings B |
| 06 | GREEN | 14 | UP/LO: spine A, upper B, lower C |
| 07 | AQUA | 15 | BAYS: bay 1/2/3 = A/B/C |
| 08 | BLUE | 16 | ALT: odd/even fixtures swap A/B |

### EFFECTS: pad columns are energy, calm (left) to maximum (right)

| Row | Calm | Groove | Driving | Maximum |
|---|---|---|---|---|
| 1 (operator) | 01 CHASE | 02 FX OFF | 03 L-SCATTER | 04 COMBO |
| 2 | 05 IRIS (PINPOINT / RIPPLE) | 06 CRISSCROSS (WEAVE / TWIN SPIN) | 07 ROTOR (SUNBURST / COMET) | 08 RIOT (REFERENCE / SCATTER strobe) |
| 3 | 09 ARCH (CATHEDRAL / FILL) | 10 BAY HOP (PRISM / EDGE HOP) | 11 ZIPPER (HELIX / SCANNER) | 12 SHATTER (SHARDS / SPARKLE) |
| 4 | 13 CURTAIN (V-GATES / BARCODE) | 14 WARP (BLINDERS / CHEVRON) | 15 RAIN (CAGE / SPARKLE) | 16 STORM (X-FIRE / SCATTER strobe) |

Each effect is written for the STATIC in brackets and carries the named LED content. Groups run on different lanes and rates (kick / snare / 4-beat cycle, chase repeats x1-x8). Only part of the rig is lit at any moment. Calm and groove effects mostly hold still and STEP between points. The maximum column adds random jumps, random strobe rolls and fast LED strobe. Per-group details are commented in `tools/klang_effects_bank.py`.

COLOR solids set palette 0 A=B=C and route everything, including LEDs, to A. Splits route groups to A/B/C so each group recolours independently.
EFFECTS 05-16 store all mover slots and the LED system. Lane 3 (HI-HAT) is the continuous 4-beat REPEAT cycle; KICK/SNARE are per-hit. Changing lane settings in SEQUENCE changes their rates. Effects work over any static.

## Mover FX (movers' LED LOOK value 16-47, shown as "MOV ...")

Value = 16 + rate (0-3 = chase repeats x1/x2/x4/x8 per lane pulse) + 4 RND (each flash lights a random third, reshuffled per hit) + 8 JMP (each move-lane trigger sends the head to a random position within +-PAN/TILT SIZE) + 16 STEP (each trigger moves to the next of five fixed points, holding still between; OFFSET picks the start point in fifths, DIRECTION reverses). STEP wins over JMP. OFFSET and DIRECTION are shared with the chase. Values 0-15 on movers mean no mover FX. Implemented in `modules/_shared/show.hlsli`, `Klang_Lighting/optics.hlsl` and `motors.hlsl`.
Aims are offsets on the stagerig_klangrig_Show reference aim (wing_elevation 45).

## LED content (RIG > LED FX > LED LOOK)

0 SOLID, 1 OUTLINES, 2 CHASE, 3 PULSE, 4 SCATTER, then new in `modules/Klang_LED/led_patterns.hlsli`:
5 COMET (head + decaying tail laps each loop), 6 TWIN SPIN (counter-rotating heads, flash where they cross), 7 FILL (loops fill round and drain), 8 SCANNER (ping-pong bar with ghosts), 9 BARCODE (dashes scroll opposite ways per tier), 10 PLASMA (world-space interference flowing through the rig), 11 SPARKLE (random twinkle over dim glow), 12 HEARTBEAT (lub-dub blooming from edge midpoints), 13 EDGE HOP (one edge per beat), 14 CHEVRON (diagonal stripes leaning per tier), 15 RIPPLE (spherical rings from rig centre).
Knobs: lane (timing), WIDTH (tail/bar/density/duty), SPREAD (stagger along rig or spatial scale), OFFSET, DIRECTION. Base colour = LED beam palette, accent = LED ring palette. With no lane, content free-runs one cycle per 4 s. Left loops are mirrored so motion is symmetric. All programmed content draws as a thin centre line (about a quarter of the band width), set by `band` in `led_patterns.hlsli`.

Authoring: `tools/klang_color_bank.py`, `tools/klang_static_bank.py`, `tools/klang_effects_bank.py` push rows into the live programmer via the `rows` rig command and store through the normal STORE path. `tools/klang_looks.py` has review cameras (`review`, `bank_sheet`, `strip`, `motion`).
