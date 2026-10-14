# PHAGE look bank

Four banks of 16, every slot filled. Pads show the names below. Pad titles
come from `tools/phage_looks.py`, which generates every preset bank, so edit
the looks there (see [PROGRAMMING.md](PROGRAMMING.md#regenerating)).

The banks layer:

| Bank | Owns |
|---|---|
| **STATIC** | Mover pan, tilt, level and ring glow, plus the pixel-bar level (slots 1-12, the beam shapes). Truss-axis pan and tilt (slots 13-16, the poses). A shape never moves the truss and a pose never moves a beam, so any shape combines with any pose; the one exception is the capsid's HEADING, below. Strobes are never touched by a static. |
| **EFFECTS** | Every effect attribute of every fixture (lanes, sizes, spread, width, offset, direction, look, order) and the show strobe clock. |
| **COLOR** | The 8-palette library, the active palette and the A/B/C routing of every fixture. |
| **FULL** | One shape, one pose, one effect and one colour, plus the GLOBAL render controls, rhythm lanes, pitch and master. It carries the parts it was built from, so the desk lights them. |

## STATIC 01-12: beam shapes

Bar level is the pixel-bar level the shape sets.

Every shape stays inside the Halo Beam's reach. Its GDTF tilts +-135 deg, so a head cannot throw its beam more than
45 deg below its mounting plane, toward its own base. A head a shape sends there is refit (`fit` in
`tools/phage_looks.py`):

- out of reach by up to 12 deg: clamped to the limit, landing within a few degrees (FIBERS' knees, X-FIRE's side
  capsid heads);
- in a look of vertical lines: the other vertical (CATHEDRAL's and NEEDLES' lower capsid heads point down);
- further out: its beam is dark in that look, as CROWN's plate beams always were (CROWN's collar and lower capsid,
  PINPOINT's lower capsid and two knees a side, two capsid heads in FRONT and four in X-FIRE).

| Slot | Shape | Bars |
|---|---|---|
| 01 | **ORIGIN**, the identity look. Plate beams rake down over the crowd, capsid and knee beams stand up, collar and booth fan out low, and foot beams point up. | 0.85 |
| 02 | **CATHEDRAL**. Vertical columns: capsid, knees and feet straight up, plate straight down, collar fanned up. The booth pools straight down at half level. | 0.45 |
| 03 | **SUNBURST**. Everything radiates from the rig centre: capsid along its face normals, plate and booth out and down, knees and collar flat out, feet out and up. | 1.0 |
| 04 | **CROWN**. Capsid, collar, knee and foot beams converge on one apex 36 m above the rig. Plate beams are off and the booth is left as it was. | 0.6 |
| 05 | **FIBERS**. Beams trace the legs: each knee sends one beam down to its foot and one back up to the body, feet aim at their knee, and plate beams run out along the floor under the nearest leg. | 1.0 |
| 06 | **HELIX**. A double helix: every ring twists both ways at once, neighbours crossing, mirrored left to right, so the beams weave a lattice tower, rising through the capsid, knees and feet and falling through the plates and booth. It has no turn to it, so the capsid may spin under it. | 0.8 |
| 07 | **CAGE**. Bars of light around the crowd. The capsid rakes to the floor 30 m out, knees lace across to the next leg's foot, feet close on the capsid, and the plate lands 19 m out. | 0.7 |
| 08 | **FRONT**. The whole rig fans onto the front of the crowd, 22 m out. | 0.9 |
| 09 | **NEEDLES**. Hard verticals with no ring glow: hanging heads straight down, upright heads and the capsid straight up. | 0.25 |
| 10 | **X-FIRE**. Left and right halves cross to the far side at every tier: plate to the floor 16 m across, knees and feet to high and low points, capsid up and across. | 0.8 |
| 11 | **HALO**. Rings of light at every tier with full ring glow: level beams running round each ring toward the front, mirrored left to right so the two sides meet and cross in front of the stage. | 0.7 |
| 12 | **PINPOINT**. Every beam on one spot on the crowd 11 m in front of the stage, while the capsid throws a dim column straight up. | 0.3 |

**The capsid's HEADING.** The capsid carries its heads round as it spins. A
shape that is the same at any spin (ORIGIN, SUNBURST, CROWN, HELIX...) lets it
spin. A shape aimed at the room or mirrored about the stage's centre line (FRONT,
X-FIRE, HALO) only reads with the capsid facing front, so it sets the capsid's
HEADING to FRONT: the capsid stops spinning and turns the short way back to the
heading the shape was aimed for, whatever the pose and effects say, and its
sheath still plays. The next shape that turns with the capsid frees it. The
look compiler decides which by turning each shape's capsid and comparing.

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

On the desk each pad carries its tier as a step mark of one to four bars.

Every effect is the whole rig in one movement, built from the fixture banks and
the SEQUENCES (pad page 5): the light sweeps or journeys through the rig, the
heads move with it (a group glides to a new formation as the light reaches it),
and the truss moves with it, eased and never spinning.

### CALM, pads 01-04 (one bar)

| Slot | Effect | Light | Heads | Truss | Clock |
|---|---|---|---|---|---|
| 01 | **AWAKEN** | Beams swell up the rig, colour washes up the rings, a few plates breathe, plasma on the battens swelling | Slow random drift, each head on its own time | Body eases to new headings, the sheath breathes, the legs lift slightly in a wave round the body | 2 / 0.3 |
| 02 | **TIDE** | A band of light rises through every fixture over the phrase, a white tube edge leading it | A tilt swell rising up the rig | The sheath and legs swell with the tide | 2 / 0.3 |
| 03 | **ORBIT** | A lit sector circles the whole rig every bar | A nod travelling round the rings and leg to leg | The capsid turns to new headings; the legs step in turn | 2 / 0.3 |
| 04 | **HEARTBEAT** | Only the capsid and collar beat on the kick; the battens' core pulses, the limbs hit on the snare | A tilt swell | The sheath contracts in slow beats | 2 / 0.3 |

### GROOVE, pads 05-08 (two bars)

| Slot | Effect | Light | Heads | Truss | Clock |
|---|---|---|---|---|---|
| 05 | **SCAN** | A plane of light crosses the stage left to right every 8 beats | Plate rows and booth fanning open and closed | The body turns with the plane | 2 / 0.3 |
| 06 | **WALK** | The legs light leg by leg on every fixture of the legs | Knees then feet trading formations leg by leg | The phage walks: each leg lifts and swings in turn, a lap a bar, the body bobbing | 2 / 0.3 |
| 07 | **ANSWER** | The core on the kick, the limbs answering on the snare | Plate rows crossing, knees and feet nodding against each other | The capsid turns, the legs lift in a slow wave | 2 / 0.3 |
| 08 | **FALL** | A band falls from the capsid to the floor every bar | The figure rippling up from the feet against it | The body steps to new heights each bar | 2 / 0.3 |

### BUILD, pads 09-12 (three bars)

The journeys run through the anatomy over a phrase; CHARGE and RISER ride the
BUILD lane from the recall.

| Slot | Effect | Light | Heads | Truss | Clock |
|---|---|---|---|---|---|
| 09 | **IGNITION** | The core lights ring by ring, the light runs out the legs, round the plate, up the collar and capsid rings and bursts in the capsid, strobe tubes hitting as it arrives | Each group glides to a new formation as the light reaches it | The legs lift as the light runs out them; the sheath snaps at the burst | 4 / 0.4 |
| 10 | **INJECT** | The capsid injects down the core and out the feet | Each group re-forms as the light reaches it, capsid first | The sheath contracts as the light goes down the core; the legs lift in turn | 4 / 0.4 |
| 11 | **CHARGE** | From the feet in, up the legs and core into the capsid, quickening with the build | Every head lifts with the build | The body rises 1.6 m, the legs lift 1.6 m, the sheath stretches | 4 / 0.4 |
| 12 | **RISER** | A band climbs the whole rig, quickening with the build; the capsid and collar strobe | Every head lifts with the build | The body rises 2 m, the sheath stretches, the legs lift | 4 / 0.4 |

### CRAZY, pads 13-16 (four bars)

| Slot | Effect | Light | Heads | Truss | Clock |
|---|---|---|---|---|---|
| 13 | **DETONATE** | On every kick an explosion out of the capsid, down the core and out the legs | Formations snapping group by group | Body, capsid and legs lurch to new positions | 4 / 0.4 |
| 14 | **SHOCKWAVE** | A ring bursts outward from the centre across every fixture on every kick | The capsid and collar swirling high over the plates | The body bounces each bar, the legs jump | 2 / 0.3 |
| 15 | **CASCADE** | A waterfall down the rig every bar, strobe hits leading it | The groups re-form down the rig every other bar | The legs step in a cascade | 4 / 0.4 |
| 16 | **SUPERNOVA** | Everything: beams and rings bursting outward on the kick, every tube strobing, the battens exploding out of the capsid | Every head somewhere new every 8 beats | Body, capsid and legs thrown to new positions | 4 / 0.4 |

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

Pads carry the same tier step marks as the effects. Each look is shape +
pose + effect + colour, plus GLOBAL render values. Every look uses the GLOBAL
defaults (master 1, exposure 1, bloom 0.12, haze 0.03) except where the last
column says otherwise.

| Slot | Look | Shape | Pose | Effect | Colour | Globals |
|---|---|---|---|---|---|---|
| 01 | **GENESIS** | ORIGIN | REST | AWAKEN | PHAGE | |
| 02 | **TIDEWATER** | CATHEDRAL | RISE | TIDE | ICE | haze 0.04 |
| 03 | **CAROUSEL** | SUNBURST | REST | ORBIT | UV | haze 0.04 |
| 04 | **PULSE** | CROWN | REST | HEARTBEAT | INFRARED | haze 0.045 |
| 05 | **RADAR** | FRONT | REST | SCAN | VIRAL | |
| 06 | **PROCESSION** | FIBERS | BLOOM | WALK | BIOLUME | |
| 07 | **DIALOGUE** | HELIX | RISE | ANSWER | CORAL | |
| 08 | **DESCENT** | NEEDLES | REST | FALL | WHITE | |
| 09 | **IGNITION** | SUNBURST | REST | IGNITION | SODIUM | |
| 10 | **INJECTION** | CATHEDRAL | INJECT | INJECT | TOXIC | |
| 11 | **CHARGE** | NEEDLES | RISE | CHARGE | GLACIER | |
| 12 | **ASCENT** | CAGE | RISE | RISER | MAGMA | |
| 13 | **DETONATION** | X-FIRE | BLOOM | DETONATE | INFRARED | bloom 0.16 |
| 14 | **SHOCKWAVE** | SUNBURST | REST | SHOCKWAVE | SPLIT | bloom 0.16 |
| 15 | **CASCADE** | HALO | REST | CASCADE | DUSK | bloom 0.16 |
| 16 | **SUPERNOVA** | SUNBURST | RISE | SUPERNOVA | UV SPLIT | bloom 0.2 |

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

## Fixture banks: pad pages 2-4

Octave Up / Down on the Push pages the RIG pads to a page per fixture type
(see [PROGRAMMING.md](PROGRAMMING.md#layers)). Each has a bank per layer and one
for the whole fixture. MOVE FX and BEAM FX are their own choreography: every pad
gives each group of heads (plate, capsid, knee, collar, booth, foot) its own
part and timing, so groups take turns, answer each other and ripple instead of
all doing one thing, and HALO BEAMS is built from them. The other banks are
seeded from the looks above, so a layer from one look plays under a layer from
another:

| Bank | Pads | What a pad holds |
|---|---|---|
| **MOVE FX** | 16 moves, below | the Halo Beams' movement, per group |
| **BEAM FX** | 16 chases, below | their beam chase, per group; a group a pad leaves out burns steady |
| **HALO FX** | 16 ring cues, below | the 24-cell rings per group; a group a pad leaves out stays dark |
| **HALO BEAMS** | 15 looks, below, and BLACKOUT | the whole Halo Beam: a beam shape, a MOVE FX pad, a BEAM FX pad and the rings, with the capsid's HEADING |
| **TUBE FX** | 16 white accents, below | the tubes' look and chase per group, with the strobe clock; a group a pad leaves out stays dark |
| **PLATES FX** | 16 colour parts, below | the plates' look, chase and colour per group; a group a pad leaves out stays dark |
| **STROBES** | 15 looks, below, and BLACKOUT | a TUBE FX pad over a PLATES FX pad, tubes and plates at full, with the tube pad's clock |
| **PIXEL FX** | 16 contents, below | what each batten group shows: content, speed, direction and colour lane |
| **CHASE FX** | 16 sequences and dips, below | when each group shows: a dip, or HOLD windows that hand the light from group to group |
| **BATTENS** | 15 looks, below, and BLACKOUT | a PIXEL FX content under a CHASE FX sequence, bars at full |

MOVE FX, calm to wild (every move eases; most peak under 150 deg/s, RIOT and SHATTER snap at about 200). A pad's
sizes are 1.5 x the shared ones the EFFECTS looks use:

| Pads | Moves |
|---|---|
| HOLD, DRIFT, BREATH, WAVE | still; slow random drift, each head on its own time; a tilt swell rising up the rig; a nod travelling round the rings and leg to leg |
| SCAN, SCISSOR, AROUND, CASCADE | plate rows and booth fanning open and closed over the crowd; the plate rows fanning against each other so their beams cross, while knees and feet nod against each other; the five-point figure walking round each ring; the figure rippling from the feet up to the capsid |
| LEGS, STAGES, FORMATIONS, RISE | knees then feet trading formations leg by leg; one group at a time takes a new formation, capsid to feet over a phrase; formations cascading down the groups every 8 beats; everything lifts with the build |
| SHIFT, STORM, RIOT, SHATTER | the whole rig to a new position once a phrase; capsid and collar swirling high, the plates under them, legs still; every head somewhere new every 8 beats, groups a quarter step apart; formations snapping group by group |

BEAM FX: **STEADY**; **BREATHE** (a slow swell rising); **TURNS** (one group
lit at a time, capsid to feet); **RISE** and **OUTWARD** (light climbing the rig,
spreading from the centre); **CROWN** (capsid and knees on the kick); **CALL**
(capsid and collar on the kick, plates and booth answering on the snare);
**AROUND** (a chase round each ring and leg to leg); **LEGS**; **COLLAR RUN**
(the snare running round the collar under a capsid swell); **ROLL** (each beat
rolling capsid, collar, plates, booth); **BUILD** (pulses doubling with the
build, rippling upward); **STAGGER** (capsid and plates on the beat, collar and
booth off it); **SPARK** and **STORM** (random heads per group, each on its own
lane); **SUPERNOVA** (every kick bursting outward).

HALO FX is the rings, choreographed per group like the beams; a group a pad
leaves out stays dark. Its sequences carry the battens' names and timing, so
IGNITION (or INJECT, CASCADE, CHARGE, DETONATE) on HALO FX and on BATTENS run
through the rig together.

| HALO FX | What the rings do |
|---|---|
| GLOW, BREATHE, CROWN, TIDE | every ring on; a slow swell up the rig; only the capsid and collar; colour washing up the rig |
| ANSWER, ORBIT, LEG WAVE, HEARTBEAT | every ring on the snare, answering beams on the kick; a lit ring travelling round each group; leg by leg; the capsid and collar beating on the kick |
| IGNITION, INJECT, CASCADE, CHARGE | the inner plate, out the knees and feet, the outer plate, round the collar and up the capsid (a phrase); the capsid down to the feet; a waterfall every bar; from the feet up into the capsid, quickening with the build |
| DETONATE, SPARKLE, STAGGER, BURST | from the capsid to the booth on every kick; random rings flickering; capsid and plates on the beat, collar and booth off it; a burst outward on every kick |

HALO BEAMS puts the pieces together: each pad is a beam shape (aim and levels),
a MOVE FX pad, a BEAM FX pad and what the rings do (GLOW steady, ECHO the beam's
chase, or ANSWER it half a step later). A pad on a shape that holds the capsid
facing front (FRONT, X-FIRE, HALO) holds it too; storing a HALO BEAMS pad keeps
the capsid's HEADING with it, and nothing else of the truss.

| Pads | Shape + MOVE FX + BEAM FX, rings |
|---|---|
| MIST, NAVE, RIPPLE, SPIRE | ORIGIN + DRIFT + BREATHE, glow; CATHEDRAL + BREATH + TURNS, glow; HALO + WAVE + BREATHE, echo; NEEDLES + HOLD + RISE, answer |
| SWEEP, CROSSFIRE, STRIDE, WEAVE | FRONT + SCAN + CALL, answer; X-FIRE + SCISSOR + AROUND, glow; FIBERS + LEGS + LEGS, echo; HELIX + CASCADE + RISE, glow |
| RELAY, TIERS, CORONA, LIFTOFF | SUNBURST + STAGES + TURNS, echo; CAGE + FORMATIONS + ROLL, answer; CROWN + AROUND + COLLAR RUN, glow; PINPOINT + RISE + BUILD, echo |
| SURGE, TEMPEST, NOVA | X-FIRE + SHIFT + STAGGER, answer; CAGE + STORM + STORM, echo; SUNBURST + SHATTER + SUPERNOVA, echo |

The Linear Strobes hang in six groups (capsid 5, collar 6, knees 6, plate ring
18, feet 6, booth 6). TUBE FX is the white accent and PLATES FX the colour, both
choreographed per group, and both held back: a group a pad does not name stays
dark, most pads name one or two groups, and inside a group the tubes take turns
(round the ring, leg by leg, up the rig, side to side or at random). Measured on
the rig, most pads light under a quarter of the strobes at their busiest; WASH,
SUPERNOVA and WHITEOUT are the ones that fill the rig. The strobe clock is per
beat: RATE 2 is 4-7 flashes a second at 124-200 BPM, 4 is 8-13; the pads stay
at 1-4.

| TUBE FX | What the tubes do |
|---|---|
| DARK, PING, HEARTBEAT, SUNRISE | breakdown: all dark; single random pings in the upper rig; the capsid alone on the kick; a warm hit on the booth at the phrase, the capsid answering half way |
| SWEEP, WALKER, STRIDE, HATS | groove: the legs left then right on every beat; one tube walking round the plate ring; leg by leg; one random foot on each hat |
| LADDER, ROLL, CONVERGE, RISER | build (the BUILD lane from the recall): a band climbing the rig, doubling; one group at a time from the capsid down; a band closing in from the feet; the capsid and collar strobing harder as it builds |
| DROP, CROSSFIRE, STORM, WHITEOUT | drop: the plate ring and booth strobing on the kick; the legs strobing left and right; sparkles in the lower rig; every tube strobing |

| PLATES FX | What the plates do |
|---|---|
| WASH, EMBERS, TIDE, ISOLATE | calm: everything glowing; a few random plates breathing; a band of colour rising through the rig; only the booth and a capsid swell |
| SEESAW, CALL, ORBIT, STRIDE | groove: the legs rocking left and right; capsid and collar on the kick, the booth on the snare; comets circling the plate ring and collar; leg by leg |
| TURNS, ROLL, RISE, BLOOM | build: one group at a time over the phrase; each beat rolling capsid, collar, plates, booth; a band climbing with the build; a ring bursting outward on each kick |
| STAGGER, SPARK, BLINDERS, SUPERNOVA | crazy: capsid and plates on the beat, collar and booth off it; random single sparks; blinders on the plate ring and capsid; every kick bursting outward |

STROBES: AMBIENT (DARK + EMBERS), TWINKLE (PING + TIDE), PULSAR (HEARTBEAT +
ISOLATE), DAWN (SUNRISE + WASH); SWEEPER (SWEEP + SEESAW), ORBITAL (WALKER +
ORBIT), STRIDER (STRIDE + STRIDE), SHIMMER (HATS + CALL); LADDER (+ RISE),
DRUMROLL (ROLL + ROLL), IMPLODE (CONVERGE + TURNS), RISER (+ SPARK); DROP (+
BLOOM), CROSSFIRE (+ STAGGER), WHITEOUT (+ SUPERNOVA); BLACKOUT.

## Sequences: pad page 5

Fifteen sequences the whole rig plays at once, phrase-locked, then BLACKOUT.
**RIG SEQUENCES** recalls a sequence on the Halo Beams (aim, moves, beams and
rings, with the capsid's HEADING), the strobes and the battens together;
**BEAMS SEQ**, **STROBES SEQ** and **BATTENS SEQ** hold each type's part of the
same fifteen, so the same slot on each is the same moment and they mix (battens
IGNITION under strobes DETONATE). They move through the rig two ways:

- **Journeys**, group by group through the anatomy, as the battens' and the
  rings' sequences: on the strobes the plates carry the colour through each
  group's window and the tube hits white as the light arrives.
- **Sweeps**, one HOLD window ranked on the whole rig at once, so a band, a
  plane, a sector or a shockwave crosses every fixture type together, a white
  tube edge leading it.

| Pads | Sequences |
|---|---|
| BREATH, TIDE, ORBIT, HEARTBEAT | the whole rig swelling up through itself; a band of light rising through every fixture over the phrase; a lit sector circling the rig every bar; the capsid and collar beating alone |
| SCAN, WALK, ANSWER, FALL | a plane of light crossing the stage left to right every 8 beats (capsid held front); the legs walking leg by leg on every fixture of the legs; the core on the kick, the limbs answering on the snare; a band falling from the capsid to the floor every bar |
| IGNITION, INJECT, CHARGE, RISER | the journeys: the core, out the legs, round the plate, up into the capsid and burst; the capsid injecting down the core and out the feet; from the feet up into the capsid, quickening with the build; a band climbing the whole rig with the build, the capsid strobing |
| DETONATE, SHOCKWAVE, CASCADE | an explosion out of the capsid on every kick; a shockwave from the centre outward across every fixture on every kick; a waterfall down the rig every bar |

**BLACKOUT**: the bottom-right pad of every fixture page (slot 16 of HALO BEAMS,
STROBES and BATTENS, red on the Push) blacks that type out, every level and ring
at 0, so the rest of the rig plays on its own. It leaves the type's aim, moves
and chases as they are; a whole-fixture pad, a STATIC shape or a FULL look of
that type brings it back (a layer pad does not touch levels).

A fixture pad that rides the BUILD lane (RISE, BUILD) restarts the build when
it is recalled, as an EFFECTS or FULL recall does.

The Pixel Battens follow the phage's anatomy in eight groups: the SHEATH (5
rings up the core), the COLLAR (2 rings), the CAPSID struts and its three LINK
rings, the PLATE edge, the legs' UPPER bars (hip out and up to the knee) and
LOWER bars (knee out and down to the ankle), and the BOOTH. A leg bar's pixels
run outward, so a forward CHASE runs out the legs and a reversed one runs in.
PIXEL FX is what each group shows (a content, run x1-x8 per lane cycle); CHASE
FX is when it shows, and its sequences hand the light through the anatomy with
HOLD windows: a group outside its window is dark.

| PIXEL FX | What each group shows |
|---|---|
| GLOW, PLASMA, EMBERS, TIDE | calm: steady colour; world-space waves; sparkling limbs round a breathing core; a band climbing the rig |
| VEINS, JOURNEY, SCANNER, HEART | groove: a pulse out the legs on every kick, the sheath and collar spinning against each other, comets round the plate and capsid; the content IGNITION and INJECT play (legs carrying a pulse outward every 2 beats, collar spinning, capsid bursting); ping-pong along the legs, segments stepping up the sheath; a heartbeat in the core, pulses pumping out leg by leg |
| CHARGE, SPIRAL, RISER, FILL | build: the legs carrying the charge inward, the capsid strobing; everything chasing round the axis, leg by leg; strobes climbing with the build; everything filling toward the body |
| RIPPLE, SHRAPNEL, BARCODE, OVERLOAD | crazy: rings bursting out of the capsid on every kick; comets fired out the legs twice a beat; barcodes; the explosion content DETONATE plays |

| CHASE FX | When each group shows |
|---|---|
| OPEN, SWELL, SPINE, LIMBS | the content as it is; a slow swell up the rig; only the spine (sheath, collar, capsid, booth); only the limbs (legs and plate) |
| KICK DIP, ANSWER, LEG WAVE, TIERS | a dip on the kick; limbs on the kick, the spine answering on the snare; one leg at a time round the rig; a staircase, booth to capsid, twice a phrase |
| IGNITION, INJECT, CASCADE, CHARGE | sequences: the core lights ring by ring, the light runs out the legs, round the plate, up through the collar and the capsid rings and bursts in the capsid (a phrase); the reverse, the capsid injecting down the sheath and out the legs; a waterfall from the capsid to the booth every bar; from the feet in up the legs, up the core into the capsid, quickening with the build |
| DETONATE, STROBE, FLICKER, HEARTBEAT | on every kick an explosion from the capsid down the core and out the legs; strobing on the kick; random flicker on the hats; the spine on the kick, the limbs hit on the snare |

BATTENS: AMBIENT (PLASMA + OPEN), EMBERS (+ SWELL), TIDE (+ OPEN), VIGIL (PLASMA +
SPINE); VEINS (+ OPEN), HEARTBEAT (HEART + HEARTBEAT), WALKER (VEINS + LEG WAVE),
SCANNER (+ ANSWER); IGNITION and INJECT (JOURNEY + the sequence), CHARGE (+
CHARGE), STAIRS (SPIRAL + TIERS); DETONATE (OVERLOAD + DETONATE), CASCADE
(JOURNEY + CASCADE), SHOCKWAVE (RIPPLE + KICK DIP); BLACKOUT. A pad stores the
strobe clock only when something in it runs on it.

Store over any of these, or into the empty slots up to 16: the pad takes a
name from the layer's look (`PULSE x2`, `CIRCLE+PULSE` for a whole fixture),
and the names are saved with the Surface.
