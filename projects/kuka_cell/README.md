# kuka_cell

A cell of six-axis industrial arms, transcribed from a KR QUANTEC-class reference photograph,
arrayed by a directly-editable floor plan, and driven by four independent pattern channels at
once.

## Component map

Four nodes, strictly one responsibility each:

```
KA_Cell ──▶ KA_Rally ──▶ KA_Pose ──▶ KA_Robot
   │            │           │            ▲▲
   └────────────┴───────────┴────────────┘│
                └───────────Rally─────────┘
```

| Node | Owns | Preview |
| --- | --- | --- |
| `KA_Cell` | **Placement.** Where every base stands, its heading, frame size, control channel, live state — and the Point At target. | Plan over elevation + inspector |
| `KA_Rally` | **The ball.** Physics, striker election, pass aiming, participation. | Court plan over flight profile |
| `KA_Pose` | **Choreography + FK.** Four pattern channels, joint limits, forward kinematics. | Teach-pendant joint matrix |
| `KA_Robot` | **Drawing.** SDF arms + ball, internal camera, Program + Scope. | The image |

## Idle execution

All four nodes retain the default `EveryFrame` policy. `KA_Cell` integrates the target orbit and
services viewport edits, `KA_Rally` advances ball physics, `KA_Pose` evaluates live choreography,
and `KA_Robot` renders the changing cell state. Retained-output scheduling would still wake these
nodes every frame because their authored outputs are time-dependent.

---

## The route

**The archetype is a lattice of articulated instances.** The subject's identity is *relational*
in two directions at once — a robot is a kinematic chain (each link attached to its parent at a
named axis), and a cell is a regular field (each machine standing on a lattice station). Neither
survives having coordinates drawn for it freely. That single observation decided the whole build.

### Why the scaffold is a plan over an elevation

A robot cell is laid out on the **floor**, but its reach, its clearance and its danger are in
**height**. One view cannot show both, so `KA_Cell` draws a draughtsman's plan strip over an
elevation strip, sharing the world X axis *and one metres-per-pixel scale*. The same handle edits
both: drag in the plan and you move the machine on the floor; drag the same handle in the
elevation and you set its pedestal height while X keeps tracking.

Two strips at different scales would be two drawings, not a plan and an elevation — a ring would
not be round and a machine would not be as tall as the plan says it is wide.

### The failure mode is in the diagram

Every point of floor that **two work envelopes can both reach** is shaded alarm red, and the pair
count is a live readout. That is the one thing about a cell layout that is genuinely broken, and
it is invisible in the render until two machines have already collided.

It is calibrated, not decorative: a Standard frame reaches 2.93 m, so any two bases closer than
5.86 m are in conflict. The shipped `pitch` default of 6.4 m clears it. Set `arrangement = Ring`
with 18 arms at radius 8.6 and the readout goes to **CLSH 20** — 3.0 m of arc spacing against a
5.86 m requirement — before you have rendered a single frame.

`KA_Pose` carries the other two failure modes, which are motion rather than layout: a joint
sitting on its limit turns that bar red in the matrix, and a tool that has gone through the floor
drops into a red band below the floor line on the tool-height strip.

---

## What a re-roll means

**An array's identity is its lattice.** Drawing a fresh coordinate per arm does not produce a
different array; it produces a scrapyard. So `variation` perturbs *lattice parameters* — pitch,
rows, stagger, radius, arc span, run skew, heading convergence — and then jitters each station
**inside its own cell**, capped at 0.28 × pitch so neighbouring stations can never swap places.

`variation = 0` is exactly the arrangement the enum names and can never be lost.

`arrangement` itself is deliberately **not** touched by `variation`: it is a design choice the
user made, not a randomization axis.

### Arrangements (exploration axis, six values)

`Line` · `Grid` · `Ring` · `Arc` · `Twin Rows` · `Spur`

The plan draws the **armature** — the lattice polyline and its station nodes — rebuilt from the
same `ka_station()` function the layout used, with **no seed of its own**, so the guides are
guaranteed to be the guides the records were placed on rather than a published copy that can
drift. Drawn heavier and brighter than the record hairlines on purpose.

---

## Channels: four patterns at once

Every arm carries a channel index (0–3) decided by `KA_Cell`'s `Channel Split`, which is
**derived from the placement the lattice already chose** — by depth row, by concentric ring, by
checker, by quadrant sector, alternating, or scattered. Change the arrangement and the channels
re-split coherently; there is no routing table to keep in agreement by hand.

`KA_Pose` then runs an independent pattern, rate, amount and spread per channel.

| Pattern | Phase field it reads | What it is |
| --- | --- | --- |
| Hold | — | home pose, the baseline |
| Wave | position along X | a swing travelling across the floor |
| Ripple | radius from cell centre | a fold spreading outward |
| Spiral | bearing around centre | base sweep + roll, phase-locked to angle |
| Canon | live ordinal | one phrase entered at staggered times |
| Breathe | — | unison fold and unfold |
| **Point At** | ordinal (as orbit lag) | **every arm aims its flange at the target** |
| Scan | position along X | base sweep with wrist roll |
| Sway | depth | a lean whose elbow counter-rotates so the tool stays level |
| Drift | per-arm seed | smooth uncorrelated noise on all six axes |
| Salute | live ordinal | fast snap up, slow return |
| Fold | position along X | a folding front travelling across the cell |

Per-arm phase is derived from **where the machine actually stands**, so dragging one arm across
the cell changes *when* it moves as well as *where* it is. Each arm's hand-editable `bias` rides
on top, which is what makes "re-roll this one arm" a musically useful edit.

### Point At, and why the target lives in the plan

`Point At` is a two-link analytic solve. The wrist and tool fold into one rigid extension
(`L2 = l3 + l4`) and `a5` is driven to zero, which is what makes the flange land *on* the target
rather than near it. `spread` lags each arm around the target's own orbit, so the fleet trails
the mark like a comet instead of snapping to it in unison.

The target is a **record in `KA_Cell`'s buffer**, not a parameter in `KA_Pose`, because it is a
*place in the cell* — and places in the cell belong to the plan authority. That is why you can
drag it on the floor plan (and set its height in the elevation) instead of typing three numbers.
Its orbit phase is integrated against `_DeltaTime` and carried across layout rebuilds: re-rolling
an arrangement must never jog a clock.

---

## The rally

A beach ball kept up by the crowd, each arm knocking it to another.

**It is not a thirteenth pattern, and that distinction is the whole design.** A pattern is a
per-arm function of phase. A ball is one shared object with its own state, and "who hits it
next" is a global decision over the whole floor. Those are different responsibilities, so
`KA_Rally` owns the ball and the election, and `KA_Pose` executes whatever assignment it is
handed — still owning joint limits and FK, so no rally shot can produce a broken machine.

**Participation is a channel mode, decided in one place.** Four Play toggles put whole control
channels on the court. An arm holding an assignment takes its pose from the rally; an arm on a
channel that is not playing keeps running its pattern. The shipped default has channels A and B
playing while C and D stay on Point At and Scan, because seeing both systems at once is the
more interesting demonstration than either alone.

**The election is predictive, not reactive.** Every cook the ball's future is integrated forward
until it next descends through strike height, and whichever arm can reach that point is elected.
That gives the arm about a second of warning, which is what pays for a three-part swing — drop
and load, wind back off the ball, then drive up *through* the contact with a quadratic ease so
the tool is fastest exactly where it meets it. A "hit it when it gets close" rule gives an arm no
warning at all and reads as twitching.

**Everyone watches the ball.** Non-striking players yaw their base toward it and hold a ready
stance. This is the cheapest thing in the whole feature and it is what makes a floor of machines
read as a *crowd* rather than as one machine doing a trick next to some scenery.

**The pass is deliberately imprecise**, but the scatter is clamped into the receiver's own reach
disc. The next election then finds whoever can actually cover where the ball is really going —
so a bad pass gets covered by somebody else without anything anywhere being told to cover for
bad passes.

Its preview is a **court plan over a flight profile**. The profile is forward-looking rather than
a history trace: what you want to know is whether *this* arc comes down through strike height
inside somebody's reach and when, not where the ball has been. Both strips are drawn from the
same trajectory records the election used, so the diagram cannot show a different arc from the
one the arms are playing. The arc is truncated at the contact when somebody is going to take it,
because everything past a strike is fiction. Drawn failure mode: a predicted contact no arm can
reach turns alarm red and the readout says DROP.

### Getting it to actually rally — four bugs, in the order they mattered

| Symptom | Cause | Fix |
| --- | --- | --- |
| 245 serves, **zero** completed hits | contact required an exact substep crossing of the strike plane; any long frame stepped past it, and once below the plane no future crossing can ever exist | test a 1.3 m **band** below the plane, not a crossing |
| rallies died at 1–2 touches | the election permanently excluded the previous striker, so a pass that landed short of everyone else was never covered | two passes — exclude them first, then allow them if nobody else can reach |
| arms swiping a metre short of the ball | `playReach` used the arm's headline reach as if it were horizontal; at 1.8 m above the shoulder most of that budget is already spent going up | true horizontal reach at the strike plane: `off1 + sqrt(R² − Δy²)` |
| **3.3 touches per rally even with aim error switched off** | the 16 m/s speed clamp was silently clipping every long pass, which then fell short into the gaps between reach circles | raise the clamp to 24 m/s and cut `pass_max` to 9.5 m so the ball travels between *neighbours* |

Measured after: **40 strikes with zero drops in ~52 s**, rally counter at 44 and still climbing;
78 consecutive touches with only 12 players on court. Before the last fix: 20 strikes across 6
rallies with perfect aim.

The lesson worth keeping is the last one. Aim error was the obvious suspect and setting it to
zero changed nothing — the measurement is what found the speed clamp. Rally length is dominated
by **pass distance**, not by aim.

### Physical contact, and what it costs

Everything above describes **Scheduled** contact: the elected arm connects when the ball reaches
the strike plane inside its reach, and the ball leaves on exactly the velocity the swing solved
for. It sustains 40+ touches and it is the reliable show mode.

**Physical** contact is the true one, and it is shipped alongside rather than instead. The tool,
wrist and elbow are real spheres, contact is a swept sphere-sphere solve, the ball leaves on
whatever impulse it actually received, and an arm that cannot get there misses. The joints are
rate-limited to the real machine's per-axis speeds (105/101/107/136/129/206 deg/s for A1..A6),
which is what removed the snapping — poses are now *travelled to*, not cut to — and what makes an
arm's failure honest.

**The striking head is the collider, drawn.** The rally sweeps a sphere of exactly `Tool Radius`
centred on the flange, and for a long time nothing rendered it — so the ball bounced off empty air
a hand's width off the machine and contact never quite looked like contact. The head is that
sphere: same radius, same centre, not a decoration sized to look about right.

It is sized by ONE number. `KA_Rally` publishes `Tool Radius` into the instrumentation record and
`KA_Robot` reads it back; the renderer deliberately has no head-size control of its own. An
earlier attempt gave each node its own multiplier, and they drifted by a factor of five inside a
single edit — the arms swung a visible puck around a collider the size of a walnut. A shared
sizing function over two independently stored inputs does not prevent drift, it only hides it.

**Assist is the dial between them, and it is not the dial it sounds like.** Contact stays fully
physical at every setting including 1.0: the arm must genuinely reach the ball and the sweep must
genuinely fire. Assist only decides how much of the *outgoing* velocity comes from the shot the
arm solved for versus the impulse the collision produced. Measured, 24 arms at 6.4 m pitch, real
motor speeds, long windows:

| assist | touches/rally | whiffed crossings | longest rally | sample |
| --- | --- | --- | --- | --- |
| 0.00 | 1.95 | 24% | 5 | 22 rallies |
| 0.55 | 2.32 | 22% | 10 | 59 rallies |
| **0.85** | **4.05** | **15%** | **22** | 39 rallies |

0.85 ships because it is the first setting that actually rallies. The whiff rate *falling* as
assist rises is the interesting part: it is not the dial hiding misses, it is receivers finally
getting balls that arrive at them instead of dying short. At 0 the arms play honestly and badly,
about two touches before somebody is beaten, which is worth watching once.

### What the tuning actually found, including the wrong turns

Four plausible theories died by measurement, and they are recorded because each one is the
obvious guess:

| Theory | Test | Result |
| --- | --- | --- |
| the arms cannot travel fast enough | motors at **4×** real speed | no meaningful change |
| the arms are missing narrowly | tool radius 0.22 → **0.6 m** | no meaningful change |
| the ball falls in gaps between reach circles | pitch 6.4 → **5.2 m** | no meaningful change |
| the ball is not hit hard enough | `hit_power` 12, `tool_bounce` 1.25 | **worse** — 32% whiffs |

The counter that settled it is `end_out`: **zero**, across every configuration ever run, including
a super-elastic tool at maximum hit power. The ball has never once left the floor. It is not
being over-hit; it is being under-delivered, which is exactly what assist corrects.

Two process failures are worth more than any of the above. First, `shots` was read as "strokes
attempted" and used to compute a 43% whiff rate that drove three rounds of election work — but it
only increments on a serve and inside the struck branch, so it is serves plus contacts and can
never express a miss. Second, the windows were 18–35 rallies against a distribution whose standard
error is ±0.2, so several confidently-reported findings were differences of 0.2–0.35 and were
noise. Both failures have the same root: **there was no instrument for the thing being reasoned
about.** The control outputs below exist so that neither can happen again.

### Live telemetry

Nine monotonic counters published as control outputs, readable in one call and visible in
Properties while the cell plays. Monotonic means any two reads give the interval average with no
reset — `(touches₂−touches₁)/(rallies₂−rallies₁)` is the rally length right now.

| Output | What it counts |
| --- | --- |
| `rallies` / `touches` / `best_rally` | completed rallies, total contacts, longest |
| `crossings` | balls that fell past strike height, descending — the playable chances |
| `whiffs` | ...of those, the ones nothing touched. `whiffs/crossings` is the real miss rate |
| `end_out` / `end_ground` | why rallies end: left the floor, or died on the deck |
| `miss_sum` / `miss_max` | tool-to-ball distance over whiffs — centimetres or metres wants different fixes |

`miss_sum` has a known bias: when the striker has already been cleared it measures from the arm
that hit *last*, which has followed through and moved away, so it reads high. `whiffs`,
`crossings`, `end_out` and `end_ground` are clean.

### Ball model

Quadratic drag, not linear. Linear drag gives a heavy ball that falls; quadratic gives one that
accelerates to a low terminal speed and then *floats*, and that hang time is both the entire
character of a beach ball and the reason an arm has time to get under it. The pass velocity is
solved by three damped shooting iterations against the real integrator, because the naive
displacement/flight-time estimate under-throws by roughly a third once drag is in play.

The ball is **in the distance field**, not composited over the render — its shadow on the floor
is the only cue that says how high it is. Six gores alternating white with red, yellow and blue,
rotating with accumulated spin.

---

## Data contract

`KaRec` (48 B, 50 elements) — owned by `KA_Cell`. Index 0 is the header, 1–48 the arms, 49 the
target. `KaPose` (64 B, 50 elements) — owned by `KA_Pose`. `KaBall` (80 B, 89 elements) — owned
by `KA_Rally`: header, 48 per-arm assignments, then 40 trajectory samples. The trajectory is
stored as records rather than recomputed by the canvas because a per-pixel forward integration is
not a thing you can do, and because the diagram must draw the same simulation the election used.

Each rally assignment carries its own `lead_time`/`follow_time` in its unused `spin` field, so
`KA_Pose` never needs a duplicate copy of parameters that live in `KA_Rally`. Two nodes owning
the same number is how they drift.

Link dimensions, joint limits, the home pose, forward kinematics and the arrangement functions
all live in **one file**, `modules/_shared/cell.hlsli`, because three nodes consume them: the
plan draws reach circles, the pose node solves FK, and the renderer builds geometry. Two of them
disagreeing is how a reach circle stops meaning anything.

---

## Traps found the hard way

**The phantom bound cylinder.** `ka_arm()` early-outs on a bounding cylinder whose radius is the
arm's full *reach*. Returning that distance at a small threshold hands every shadow and AO ray an
invisible three-metre drum around each machine — the first build drew concentric ripples across
the entire floor. The threshold is now 2.0 m, past the range where soft shadow (`k·h/t`) or a
0.12 m AO radius can produce anything, and the tight per-group capsule bounds do the work inside
it. **A conservative distance bound is correct for marching and wrong for shading.**

**Four clocks, not one.** A single wrapping master clock multiplied by a per-channel rate looks
right and is not: at rate 0.7 the product jumps from 0.7 to 0 when the master wraps and every arm
on that channel snaps. Each channel integrates its own accumulator, which also makes `phase`
0 → 1 exactly one loop for *every* channel regardless of rate.

**A shipped default that trips its own alarm.** The first build defaulted to 4.2 m pitch against
2.93 m reach and opened with `CLSH 23`. An alarm that is always on teaches the user to ignore the
alarm.

**Truncating a decimal in two halves.** `dec1At` originally truncated the integer part and the
fraction independently, so 2.6 rendered as `2.5`. Round to tenths once, then split.

**A mark with no client.** The Scope drew the Point At cross-hair unconditionally, so during a
rally it floated in mid-air belonging to a pattern no arm was running. A mark that describes
nothing is worse than no mark: it is read as meaning something, and then it does not. It now
draws only when some live arm is actually on a pattern rather than on the ball, or when it is
selected for editing.

**Velocity and orientation in one field.** The ball's spin did `spin += bv * dt * k`, accumulating
VELOCITY into what the renderer reads as axis-angle. The axis therefore lay along the direction of
travel — a ball thrown upward span about the vertical like a top instead of tumbling — and the
angle was accumulated path length, unbounded, into the hundreds of radians within minutes, where
`sin`/`cos` of a float32 loses the low bits that carry the rotation. Angular velocity and
orientation are two quantities and now live in two fields.

**A button read as a level.** `Serve` was tested per cook rather than on its rising edge, so
holding it served sixty balls a second, each resetting the rally under the one in flight. One
press turned the cell into a hailstorm. A button in a per-frame simulation is a *moment*, and a
moment has to be detected against the previous frame.

**Cable frame tearing.** The dress pack was anchored half in the base frame and half in the
carousel frame. Physically defensible, and it tears the conduit in two the moment A1 turns,
because the frames only coincide at `a1 = 0`. It is now entirely in the carousel frame.

**The dark shoulder.** Making the whole A2 bearing hub a machined-steel material read as a hole
punched through the machine. On the reference only the small cover plate is dark; the housing is
part of the painted casting.

---

## Making the machine read

A six-axis arm at forty pixels is legible or not depending almost entirely on whether its members
are **flat-ended segments between drawn joints**. A chain of round-capped capsules is a
caterpillar. Every axis is a visible cylinder on its own axis and no link ends in a round cap.

Each member also answers the three questions a form has to answer:

| | |
| --- | --- |
| **meet** | the thigh roots into a shoulder flange; the forearm into the elbow cover plate |
| **carry** | the thigh has a deep side flute with a raised spine dividing two flat values; the forearm has a segmented A4 roll collar |
| **end** | the flange is a flat cut face with a raised boss and a bolt ring |

Section rounding is kept low (0.30 of the minor half-extent) — the reference casting has broad
*flat* side faces meeting at a crisp ridge, and a heavily rounded section is a tube no matter how
deep the flute is cut into it.

Cable dressing is silhouette-critical and corrugated by radius displacement; the base ancillaries
(air bottles, bracket) are why the base does not read as a plain cylinder. Frame sizes get their
own proportions rather than one silhouette scaled three ways: a Compact arm is relatively
stubbier and thicker, a Heavy arm relatively longer-limbed.

---

## Performance

Forty-eight arms are affordable because of **per-tile arm culling**. Each 8×8 thread group covers
a narrow view cone; its 64 threads cooperatively test all 48 arms against that cone and compact
the survivors into a groupshared list. Typically one to four arms survive, so the marching loop
iterates over a handful of bounding cylinders rather than forty-eight. Inside each arm, three
group bounds (base / thigh / forearm) mean a ray near one group does not pay for the others.

The ground is intersected **analytically** rather than being a plane in the SDF — a ray skimming
a distance-field plane takes its step count from the plane, and a floor is exactly the surface
rays skim along.

**Measured in one sitting**, 1280×720, RTX-class GPU, all three node preview windows open, the
Sentinel UI running:

| Rung | steps / shadow / AO / dist | 24 arms | 48 arms |
| --- | --- | --- | --- |
| Draft | 40 / 0 / 0 / 45 | display rate | — |
| **Live** (default) | 88 / 16 / 4 / 75 | display rate | — |
| Beauty | 150 / 32 / 6 / 110 | display rate | — |
| Hero | 240 / 56 / 8 / 180 | display rate | **58.9 fps** |

Every rung held the 60 Hz display rate on this machine, including Hero at the full 48-arm cell —
so the ladder is a headroom ladder here rather than a cost cliff. **These are not absolute
numbers and they are conditional**: identical presets have been measured 3–5× apart in this
workspace depending only on how many node previews are open. Detailed GPU-timestamp profiling is
a Stats preference and was off; these are app frame rates. On a smaller GPU, or at a higher
output resolution, expect Hero to fall below display rate first — it is labelled capture-only for
that reason.

---

## Shipped presets (project scope, narrow by design)

A preset that saves everything is a snapshot; a preset that saves one concern is a tool.

**`KA_Robot` — frame contract:** `Frame - Cell 3Q`, camera parameters *alone*. The internal
camera is meant to be flown, so the composed pose is lost the first time anyone explores and is
recoverable from nothing else in the project. Recall it before any final capture. Camera values
are deliberately **not** baked into the manifest — that is what this preset is for.

**`KA_Robot` — quality ladder:** `Quality - Draft` / `Live` / `Beauty` /
`Hero (capture only)`, the four cost parameters *alone*. Recalling a rung does not disturb the
framing; recalling the frame does not disturb the quality. Verified: recall reported
`applied: [march_steps, shadow_steps, ao_samples, max_dist]`, `skipped: []`.

**`KA_Robot` — a second frame:** `Frame - Rally Low`, a lower wider pose that keeps the ball in
shot while it travels the cell.

**`KA_Pose` — choreography:** `Show - Traffic` (the four-different-things default) /
`Show - Converge` (whole fleet on one mark) / `Show - Cascade` / `Show - Idle Breath`, the four
pattern enums *alone*, so a show change never touches rates or amounts.

> Known wrinkle: `KA_Pose` declares a `state_buffers` block, so its presets also carry a
> `durable_state` payload and a recall restores the pose buffer snapshot alongside the enums.
> The solve pass overwrites every joint angle each cook, so it self-corrects within a few frames,
> but the channel clocks jump once on recall.

## Scene Group surface

`KUKA Cell` exposes eight controls, all verified through the group path:

Arrangement · Arms · Channel Split · Variation · Master Rate · Rally · Hit Power · Light Rig

No camera control is exposed there, per the camera contract.

> Two things to know if you rebuild a node. Destroying and recreating a pipeline **drops its
> Scene Group exposures** — the ones targeting it must be re-exposed by hand; node presets
> survive, because they are identity-based. And a node that has never been rendered on screen
> reports a garbage size from `get_node_geometry` (`KA_Rally` reported a height of 455,000 units
> and climbing), so Scene Group containment silently fails until you `focus` it once and force
> the layout.

---

## Direct manipulation — what needs exercising by hand

Injected input does not reach Module viewport events, so the gesture paths below **could not be
machine-proven** and need exercising by hand in the `KA_Cell` preview. Everything reachable was
verified: buffer persistence, signature-driven regeneration, pick maths against known record
coordinates, the derived selection/overlap/outside flags, and the inspector readouts.

| Gesture | Effect |
| --- | --- |
| Click | select an arm, or the target |
| Drag in the **plan** strip | move on the floor (X and depth) |
| Drag in the **elevation** strip | move in X and set pedestal height |
| `A` / `D` | turn the base heading ±15° |
| `G` | cycle control channel |
| `K` | cycle frame size (Compact / Standard / Heavy) |
| `Q` / `E` | smaller / larger frame |
| `X` | arm on / off |
| `N` | re-roll this arm's phase bias and heading |
| `R` | reseed the whole cell |
| `C` | clear selection |

Dragging the **target** grabs its live orbiting point but moves its *anchor*, so the orbit keeps
running under your hand.

`KA_Rally` and `KA_Pose` declare no viewport interaction at all, deliberately. Every control on
them is an exact numeric or enum choice, which Properties already does better than a
shader-drawn slider, and the one genuinely spatial control — the Point At target — is a place in
the cell, so it belongs to the plan authority and you drag it there.

---

## Instrument palette

Both authored canvases use the shared instrument palette (`_shared/plan_theme.hlsli`), mostly
monochrome. Hue is spent on exactly three things and each can be named:

1. **Accent (amber)** — the selection, and the live phase-wheel hands in `KA_Pose`.
2. **Alarm (red)** — envelope collision, out-of-cell base, joint on its limit, tool through the floor.
3. **Identity** — the four control channels, a closed unordered set of four the eye must separate.

Frame size is *ordinal*, so it is a value ramp, never a hue. Depth in the elevation strip is
carried as a value for the same reason — it is the axis that projection cannot show.
