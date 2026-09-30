# PHAGE look bank

Four banks of 16, every slot filled. Pads show the names below. Pad titles
come from `tools/phage_looks.py`, which generates every preset bank, so edit
the looks there (see [PROGRAMMING.md](PROGRAMMING.md#regenerating)).

The banks layer:

| Bank | Owns |
|---|---|
| **STATIC** | Mover pan, tilt, level and ring glow, plus the pixel-bar level (slots 1-12, the beam shapes). Truss-axis pan and tilt (slots 13-16, the poses). A shape never moves the truss and a pose never moves a beam, so any shape combines with any pose. Strobes are never touched by a static. |
| **EFFECTS** | Every effect attribute of every fixture (lanes, sizes, spread, width, offset, direction, look, order) and the show strobe clock. |
| **COLOR** | The 8-palette library, the active palette and the A/B/C routing of every fixture. |
| **FULL** | One shape, one pose, one effect and one colour, plus the GLOBAL render controls, rhythm lanes, pitch and master. It carries the parts it was built from, so the desk lights them. |

## STATIC 01-12: beam shapes

Bar level is the pixel-bar level the shape sets.

| Slot | Shape | Bars |
|---|---|---|
| 01 | **ORIGIN**, the identity look. Plate beams rake down over the crowd, capsid and knee beams stand up, collar and booth fan out low, and foot beams point up. | 0.85 |
| 02 | **CATHEDRAL**. Vertical columns: capsid, knees and feet straight up, plate straight down, collar fanned up. The booth pools straight down at half level. | 0.45 |
| 03 | **SUNBURST**. Everything radiates from the rig centre: capsid along its face normals, plate and booth out and down, knees and collar flat out, feet out and up. | 1.0 |
| 04 | **CROWN**. Capsid, collar, knee and foot beams converge on one apex 36 m above the rig. Plate beams are off and the booth is left as it was. | 0.6 |
| 05 | **FIBERS**. Beams trace the legs: each knee sends one beam down to its foot and one back up to the body, feet aim at their knee, and plate beams run out along the floor under the nearest leg. | 1.0 |
| 06 | **HELIX**. Every beam turned 62 deg around the rig with a rise per tier: a twisted spiral. | 0.8 |
| 07 | **CAGE**. Bars of light around the crowd. The capsid rakes to the floor 30 m out, knees lace across to the next leg's foot, feet close on the capsid, and the plate lands 19 m out. | 0.7 |
| 08 | **FRONT**. The whole rig fans onto the front of the crowd, 22 m out. | 0.9 |
| 09 | **NEEDLES**. Hard verticals with no ring glow: hanging heads straight down, upright heads and the capsid straight up. | 0.25 |
| 10 | **X-FIRE**. Left and right halves cross to the far side at every tier: plate to the floor 16 m across, knees and feet to high and low points, capsid up and across. | 0.8 |
| 11 | **HALO**. Every beam tangential and level, with full ring glow: a ring of light at every tier. | 0.7 |
| 12 | **PINPOINT**. Every beam on one spot on the crowd 11 m in front of the stage, while the capsid throws a dim column straight up. | 0.3 |

## STATIC 13-16: truss poses

Programmer pan and tilt on the eight axes map to motion as follows:

- **Body:** tilt x 2.4/90 m of height (-2.4 to +2.0 m); pan is yaw in degrees (+-30).
- **Capsid:** pan is spin in degrees; tilt x 2.4/90 m of sheath contraction (-1.2 to +2.4 m).
- **Legs:** pan x 2.5/90 m of swing; tilt x 4/90 m of foot lift (0 to 4.5 m).

| Slot | Pose | Body | Capsid | Legs |
|---|---|---|---|---|
| 13 | **REST** | home | home | home |
| 14 | **RISE** | +2.0 m | sheath stretched 1.2 m | lifted 1 m |
| 15 | **INJECT** | -2.4 m (crouched) | sheath contracted 2.4 m | planted |
| 16 | **BLOOM** | +1.0 m, yaw 8 deg | spun 36 deg, contracted 0.5 m | alternate legs swing +-1.25 m; every other leg lifts 1.8 m |

## EFFECTS: four energy tiers

Rhythm lanes:

| Lane | Timing |
|---|---|
| KICK | Every beat |
| SNARE | Beats 2 and 4 |
| HI-HAT | The off-beat "and" |
| PHRASE | Once per 16 beats |
| BUILD | Ramps for 16 beats from the next beat after a recall, doubling its pulses each quarter (1, 2, 4, 8 per beat), then holds at the top |

"Strobe clock" is the flash rate per beat and duty the effect sets for STROBE,
SPARKLE and the held strobe.

### CALM, pads 01-04 (blue)

| Slot | Effect | Movers | Strobes | Bars | Truss | Clock |
|---|---|---|---|---|---|---|
| 01 | **DRIFT** | Slow phrase-long circle (pan 14, rise 6) rolling around the rig; steady intensity | GLOW plates breathing on PHRASE | PLASMA, colour on PHRASE | Body sways (yaw 8 deg, +-0.5 m), capsid a quarter turn per phrase, legs swing around the ring | 2 / 0.5 |
| 02 | **TIDE** | Rise and fall with the phrase; intensity rolls up the rig as a phrase-long decay | OFF | CLIMB up the rig on PHRASE | Body and capsid swell, legs lift in turn around the ring | 2 / 0.5 |
| 03 | **BREATHE** | Intensity breathes outward from the centre on PHRASE | GLOW breathing outward | PULSE outward on PHRASE | Body rises +-0.8 m; capsid contracts half a phrase later | 2 / 0.5 |
| 04 | **EMBER** | Sparse embers: double-time flashes on the kick, a random third at a time, stepping to a new point each phrase | GLOW plates on the kick, shuffled | SPARKLE, colour on PHRASE | Capsid a quarter turn per phrase | 2 / 0.5 |

### GROOVE, pads 05-08 (green)

| Slot | Effect | Movers | Strobes | Bars | Truss | Clock |
|---|---|---|---|---|---|---|
| 05 | **PULSE** | The whole rig pulses on the kick | GLOW plates on the kick | SEGMENTS on the kick, leg by leg | Body bounces on the kick; capsid half a turn per phrase | 4 / 0.3 |
| 06 | **WALK** | Circle on the kick, leg by leg (pan 18) | GLOW on the hat | CHASE leg by leg on the kick | Legs swing around the ring on the kick, so the truss walks; capsid half a turn per phrase | 4 / 0.3 |
| 07 | **SWAY** | Mirrored sway on the kick (pan 10, rise 10) | BLINDER hits on the snare | SCANNER on the hat | Body yaws on the phrase; capsid contracts and legs lift on the snare | 4 / 0.3 |
| 08 | **ORBIT** | Orbit around the rig on the kick (pan 25, rise 12) with a double-time chase | GLOW plates chasing around on the kick | COMET around on the kick | Body yaws 20 deg on the phrase; capsid one turn per phrase | 4 / 0.3 |

### BUILD, pads 09-12 (amber)

A 16-beat ramp from the recall.

| Slot | Effect | Movers | Strobes | Bars | Truss | Clock |
|---|---|---|---|---|---|---|
| 09 | **ASCEND** | Sweep widening to pan 30 and rising 40; accelerating pulses climb the rig | STROBE on BUILD, bottom to top | CLIMB on BUILD | The truss stands up: body +2 m, capsid contracts, legs lift 2.7 m | 4 / 0.3 |
| 10 | **TENSION** | Four-times shuffled chase on BUILD, twitching pan 15 | SPARKLE on BUILD | SEGMENTS on BUILD | The body crouches 1.6 m while the legs STEP between points on the build pulses | 8 / 0.3 |
| 11 | **LAUNCH** | STEP between points on BUILD, all heads flashing together | White PULSE accelerating with BUILD | FILL on BUILD | Full launch: body +2 m, capsid fully contracted, legs lifted 4 m | 8 / 0.3 |
| 12 | **COUNTDOWN** | Rise 30 as pulses climb the rig on BUILD | STROBE on BUILD, bottom to top | STROBE on BUILD, bottom to top | The rig compresses for the drop: body to -2.4 m, capsid fully contracted | 8 / 0.3 |

### CRAZY, pads 13-16 (red)

| Slot | Effect | Movers | Strobes | Bars | Truss | Clock |
|---|---|---|---|---|---|---|
| 13 | **RIOT** | JUMP to random positions on every kick (pan 50, rise 30), slamming on and decaying across the beat | STROBE bursts on the kick | STROBE on the hat | Body bounces, capsid spins, legs jump to random swing and lift on every kick | 8 / 0.3 |
| 14 | **STORM** | Random lightning: eight random-gated flashes per beat, sweeping on PHRASE (pan 40, rise 25) | SPARKLE tubes, colour plates flashing on the kick | SPARKLE on the kick | Body yaws 25 deg on PHRASE, capsid two turns per phrase, legs lift around the ring on the kick | 12 / 0.2 |
| 15 | **SHATTER** | STEP on the snare (pan 45, rise 30), flashing on the kick | Warm BLINDER hits on 2 and 4 | BARCODE on the hat | Body jumps on the snare, capsid spins on the kick, legs STEP on the snare | 6 / 0.35 |
| 16 | **SUPERNOVA** | Orbit around the rig on the kick (pan 35, rise 20) with a four-times chase | STROBE through the beat, plates on the kick | STROBE free-running | Body bounces, capsid spins twice per beat cycle, legs jump on every kick | 12 / 0.25 |

Effects run over any static and any colour. Movement offsets add to the static
aim. Intensity chases multiply the static level. Colour lanes are independent
of both.

## COLOR

| Slot | Colour | Palette | Routing (beam / ring) |
|---|---|---|---|
| 01 | **WHITE** | WHITE | mono: beams A, rings B |
| 02 | **ICE** | ICE | mono |
| 03 | **PHAGE** | PHAGE | zones: capsid C/A, legs B/A, body A/B |
| 04 | **INFRARED** | INFRARED | mono |
| 05 | **SODIUM** | SODIUM | mono |
| 06 | **VIRAL** | VIRAL | mono |
| 07 | **UV** | UV | mono |
| 08 | **ROSE** | SUNSET | mono |
| 09 | **GLACIER** | ICE | above 9 m B/A, below C/A |
| 10 | **BIOLUME** | PHAGE | mono (teal) |
| 11 | **MAGMA** | INFRARED | low/up: above 9 m B/A, below A/B |
| 12 | **DUSK** | SUNSET | low/up |
| 13 | **TOXIC** | VIRAL | zones |
| 14 | **UV SPLIT** | UV | sides: house left A/B, right B/A, centre line C |
| 15 | **CORAL** | SUNSET | alternate fixtures A/C and C/A |
| 16 | **SPLIT** | PHAGE | sides |

Palettes (A / B / C). The COLOR page edits them live, and a colour or FULL
recall restores the library below.

| Palette | A | B | C |
|---|---|---|---|
| ICE | `#46B4FF` | `#E4F4FF` | `#1432FF` |
| PHAGE | `#00FFB9` | `#FF1E96` | `#7828FF` |
| INFRARED | `#FF1908` | `#FF7300` | `#960028` |
| SODIUM | `#FF8C1E` | `#FFD696` | `#FF3C00` |
| VIRAL | `#96FF0A` | `#00FF50` | `#009687` |
| UV | `#7314FF` | `#FF00BE` | `#1900AA` |
| SUNSET | `#FF2476` | `#FF9614` | `#8C1EFF` |
| WHITE | `#FFFFFF` | `#FFE8C8` | `#C8E0FF` |

## FULL LOOKS

Pads are coloured by tier. Each look is shape + pose + effect + colour, plus
GLOBAL render values. Every look uses the GLOBAL defaults (master 1, exposure
1, bloom 0.12, haze 0.03) except where the last column says otherwise.

| Slot | Look | Shape | Pose | Effect | Colour | Globals |
|---|---|---|---|---|---|---|
| 01 | **GENESIS** | ORIGIN | REST | DRIFT | PHAGE | |
| 02 | **LULL** | CATHEDRAL | RISE | TIDE | ICE | haze 0.04 |
| 03 | **DEEP** | HALO | REST | BREATHE | UV | haze 0.045 |
| 04 | **EMBERS** | FRONT | RISE | EMBER | SODIUM | |
| 05 | **HEARTBEAT** | SUNBURST | REST | PULSE | INFRARED | |
| 06 | **PROCESSION** | FIBERS | BLOOM | WALK | VIRAL | |
| 07 | **SWELL** | CROWN | RISE | SWAY | ROSE | |
| 08 | **CAROUSEL** | HELIX | REST | ORBIT | BIOLUME | |
| 09 | **ASCENT** | CATHEDRAL | REST | ASCEND | GLACIER | |
| 10 | **PRESSURE** | CAGE | INJECT | TENSION | MAGMA | |
| 11 | **IGNITION** | X-FIRE | REST | LAUNCH | DUSK | |
| 12 | **ZERO** | NEEDLES | REST | COUNTDOWN | WHITE | |
| 13 | **RIOT** | X-FIRE | BLOOM | RIOT | INFRARED | bloom 0.16 |
| 14 | **STORM** | PINPOINT | INJECT | STORM | ICE | bloom 0.16 |
| 15 | **SHATTER** | CAGE | REST | SHATTER | TOXIC | bloom 0.16 |
| 16 | **SUPERNOVA** | SUNBURST | RISE | SUPERNOVA | SPLIT | bloom 0.2 |

Every FULL look also restores the rhythm lanes:

- KICK: cycle 1, rest 0.
- SNARE: cycle 1, rest 1, offset 1.
- HI-HAT: cycle 0.5, rest 0.5, offset 0.5.
- Pitch 0, lighting master 1.

A FULL recall keeps BPM and transport.

**How the stills were judged.** Every look was recalled on the live rig and
captured. Animated looks were judged from timed filmstrips, not single frames,
because a still can land between kicks. BUILD looks were judged partway up
their ramp. Tuning done this way:

- The CRAZY strobes' colour plates ride the kick instead of staying fully on.
  Without a lane they washed the haze grey.
- Renderer strobe haze is 0.5.
- STORM became cold lightning on PINPOINT.
- SUPERNOVA became a SUNBURST split in teal and magenta.
- EMBERS moved to FRONT.
- LAUNCH's strobes became accelerating white pulses instead of a warm blinder
  wash.
