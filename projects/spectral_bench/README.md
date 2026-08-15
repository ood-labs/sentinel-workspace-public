# Spectral Bench

A 2D optical bench. Real spectral ray tracing — Cauchy dispersion, Fresnel, total internal
reflection — across prisms, mirrors, slabs, lenses, beam splitters, screens and blockers, drawn as
a studio photograph of light crossing a dark room.

Built from a reference photograph of a white beam through an equilateral prism. The transcription
is `variation = 0` and can never be lost.

```
LT_Bench  →  LT_Trace  →  LT_Field  →  LT_Lens
 records      physics      picture     the print
```

---

## Component map

| Node | Owns | Publishes |
| --- | --- | --- |
| `LT_Bench` | **bench space.** Every source and element: where it is, what it is, what glass. The only node that decides placement. | `Bench` — 77 records, `role`-discriminated |
| `LT_Trace` | the physics, and nothing else. One thread per (ray, wavelength, branch). | `Paths` — up to 32 256 segments |
| `LT_Field` | the program image. Tile-bins the paths, then draws the room, the glass and the light. | RGBA16F, genuinely above 1.0 |
| `LT_Lens` | the camera: halation, anamorphic streak, transverse aberration, ACES, grain, vignette. | the print |

---

## The scaffold — bench plan over a spectral rail

A plan view is the obvious first projection, and it is **not enough**. A plan can show where the
lines go; it cannot show *what happened at each interaction*, and it cannot show the axis this
subject is actually organised along — **wavelength**. So `LT_Bench`'s canvas is two strips:

- **Bench plan**, in millimetres on a 25/100 mm graticule. True element profiles, a chief fan per
  source as 32 grey hairlines with the two extreme wavelengths drawn in their own colour so the
  envelope is legible, the apex angle called out where a draughtsman would put it.
- **Spectral rail.** Left, an **event ladder**: wavelength (700 nm top) × interaction index, each
  cell coloured by what happened there, with the light still being carried drawn as a fill height
  inside the cell. Right, the **deviation profile**: total bend in degrees against wavelength. The
  width of that curve *is* the dispersion, and it is printed in the header as `SPREAD`.

### Every source draws, but only one can be on the rail

The chief buffer carries **one block per emitter** — 12 × 32 wavelengths × 14 segments — and the
plan strip draws them all. It did not at first: it held a single block, traced from `Rail Source`,
so a bench with three lights drew one beam bending and left the other two housings sitting in the
dark. That is the diagram quietly declining to describe most of its own subject, and multiple
sources is exactly the case where a plan earns its keep, because the program image alone will not
tell you which beam went where.

The rail is a different matter and is deliberately **not** generalised. An event ladder and a
deviation profile are readings of *one* beam; averaging them across sources would print a number
no beam on the bench actually produces. So `Rail Source` still picks exactly one block, the rail
captions it `SRC nn`, and that source's housing wears an amber ring in the plan above — one
reading, labelled in two places rather than two unrelated labels. The header `SPREAD` is that
source's too.

The rail's fan is drawn **last and at full weight** so it wins wherever fans cross; the others are
the same drawing at about half strength. An alarm is never dimmed — a beam that dies is worth the
same attention whichever source emitted it.

`Plan Fans` switches between **All Sources** (default) and **Rail Source**. It is also the cheap
rung: measured on the three-source bench below with all four previews open, the canvas pass runs
**2.5x** with three fans against one, and the cost tracks the number of fans *drawn*, not the
number of sources on the bench. The `chief` trace pass itself is unconditional and unmeasurable
next to it — 0.05 ms of a node total that stays under 0.7 ms, against ~9 ms for `LT_Field`.

### The failure modes are drawn

A bench is a chain, and the way a chain breaks is that something stops being lit.

| Condition | How it reads |
| --- | --- |
| An element no light reaches | red cross on the element, `ALARM n` in the header |
| A wavelength that TIRs on the exit face instead of dispersing | red cells in the ladder, red mark in the deviation profile, alarm on the prism |
| A ray that runs out of interaction budget | red terminal cell rather than a path that just stops |
| A beam that leaves the bench | dashed, not truncated |

The first capture of this build showed red ladder cells across the whole blue half of the
spectrum: at `dispersion 2.6` with a 60° flint prism, short wavelengths were exceeding the
critical angle at the exit face and never getting out. That is physically correct and creatively
useless, and it was visible in the diagram in about two seconds.

---

## What a re-roll means — relational, not positional

An optical layout's identity is **the chain**, not the coordinates. Draw free coordinates for the
elements and the beam misses all of them: not a different bench, just debris.

So `variation` re-draws the chain. Each element is placed **on the beam leaving the previous one**,
so it is lit by construction, and what gets drawn is the *relationship*: which kind, how far along
the beam, and how much deflection.

Guarantees, each one added because a seed looked broken without it:

| Guarantee | Without it |
| --- | --- |
| Element placed on the incoming ray | nothing is lit; every seed is debris |
| Stand-off clamped both ways (0.115 – 0.62) | elements interpenetrate, or the beam leaves the bench before arriving |
| Deflections snapped to an angle family | the bench reads as scatter however good each element is |
| Mirror deflection kept away from grazing | a mirror stops folding the path and starts skimming past it |
| Last link is always a screen | the fan fades out mid-air instead of landing on something |
| Uniform similarity **fit pass** | a chain grows in whatever direction its deflections take it and says nothing about where it ends up |
| Prism deflection taken from the physics, not drawn | see below |

Every correction is gated on `variation > 0`, so the transcription is never nudged.

### A prism's angle is not a free parameter

There is exactly one orientation where a ray passes a prism symmetrically, the deviation is
stationary and the spectrum comes out brightest and least smeared. It is the setting every prism
photograph is shot at, including the reference:

```
D_min = 2·asin(n·sin(A/2)) − A
```

and inside the glass the ray runs parallel to the base, so the apex→base axis is simply
perpendicular to the internal ray. So the orientation is **derived** from the arriving beam and
the glass, and it is **re-derived every cook** for any prism still on AUTO — drag the source and
every prism downstream re-aims itself. Rotate one by hand and it stops solving (`F_MANUAL`); press
**P** to hand it back and flip which way it bends.

**A PRISM AIMS ITSELF ONCE, THEN STOPS.** Three separate faults were found here, all reported as
"the prisms move when I move the source", and they had to be peeled apart one at a time:

1. **It rewrote position, not just angle.** The resolve re-centred an AUTO prism *onto* the beam.
   That is a pleasant trick with a single source and wrong in every other case, because **position
   is a record the user owns** — a resolve pass silently rewriting it means an element jumps when
   you move something else entirely. Placement is now decided once, at generation or when you drop
   the prism, and never re-decided.
2. **The resolve walks the scene once per source.** Two sources reaching one prism solved it twice
   a cook, so it took whichever emitter came last and lurched whenever either moved. A 64-bit claim
   mask now gives each prism to the first source that reaches it, in emitter index order.
3. **Continuous auto-aim was itself the bug.** Even with 1 and 2 fixed, every prism still *rotated*
   whenever its source moved — and a 60 mm triangle swinging its apex through an arc reads exactly
   like the prism is moving. Auto-aim is now a **one-shot** (`F_AIM`): a prism solves itself to
   minimum deviation on the cook after it is generated, dropped, or re-armed with **P**, then
   clears the bit and is inert forever. That is also what a real bench does.

The tell that unpicked the first two: the *generated* prism moved and the *hand-placed* one did not
— because the re-centring was gated on `F_EDITED`, which spawning sets. The third only fell out of
an isolated test node with no user input, changing the solve input and diffing the records:
`hdg 1.26396 → 1.37872` before, `1.37872 → 1.37872` after.

**Trap:** putting the prism's *centroid* on the beam is not the same as putting the prism on the
beam. At minimum deviation the internal ray runs parallel to the base, about H/6 nearer the apex
than the centroid — so a centroid-placed prism is entered within a hair of its base vertex and the
fan is thrown by a sliver of glass. It looks like a refraction bug and it is a placement bug.
`ltPrismCentreOnRay` positions a prism by its **entry point** instead.

---

## Building a bench by hand

The generated chain is a starting point, not the product. **Touch it and you own it**: the
generator allocates *around* anything you spawned or edited, so a bench you build by hand survives
every reseed, preset change and variation sweep. Set `Chain` to 0 for an empty bench.

| | |
| --- | --- |
| **A** | add an element at the cursor (inherits the selection's kind and glass) |
| **S** | add a source at the cursor, aimed at the selection |
| **D** | delete the selection |
| **0** *(zero)* | clear the WHOLE bench — every source and element. **R** re-rolls a generated one back |
| click / drag | select / move |
| right-drag *(or shift+left-drag)* | rotate — takes a prism off AUTO |
| wheel, **G**/**H** | resize |
| **K** / **M** | cycle element kind / glass (on a source: spectrum / beam profile) |
| **P** | back to minimum deviation, other side |
| **X** / **N** / **R** / **C** | on-off / re-roll this record / reseed / deselect |

**Two things about authored key bindings, both learned by breaking them.**

Delete is **D**, not Backspace: the host's input router gives text-editing keys priority over
authored bindings, so Backspace is consumed upstream and never reaches the module — a dead key with
nothing in any log to explain it.

And a key event arrives with its **modifiers**, but nothing checks them for you. Clear-all was on
`Z`, so pressing **Ctrl+Z to undo wiped the bench** — the module saw a bare Z. The same trap was
armed on Ctrl+S, Ctrl+A and Ctrl+D, which are add-source, add-element and delete here. Two fixes:
clear-all moved to the digit **0**, and the handler now drops any key carrying Ctrl / Alt / Cmd
before it looks at the code at all. Any authored binding on a bare letter has this problem, so the
guard belongs at the top of the handler rather than on each key.

Capacity is 12 sources and 64 elements. Events deliver only while the preview is **focused** —
clicking it focuses it, and a hot reload drops focus, so the first click after an edit just
refocuses. The full keymap is also published as a Controls strip beside the preview.

**Getting back.** `0` empties the bench completely — sources, elements, generated and hand-built
alike — and deliberately does *not* re-roll, so you are left with a blank bench to build on. `R`
re-rolls a generated one back into whatever slots are free.

**Nothing can be stranded.** Picking is gated on the plan rectangle and drawing is clipped to it,
so a record outside the bench is simultaneously invisible and unselectable — there is no gesture
that can reach it. The multi-source fan-out used to place source 1 at y = 0.655 on a bench only
0.5625 deep, producing exactly that: a light you could see the beam from and never delete. Two
fixes: the fan-out is clamped into the bench, and a reachability invariant in the resolve pulls any
live record back inside every cook. It is a bounds guard, not a placement decision — a no-op for
everything already on the bench.

**A dropped prism aims itself.** It spawns on AUTO, so the resolve walk solves it to minimum
deviation for whatever beam reaches it on the next cook. Rotate it and it stops solving; `P` hands
it back and flips which way it bends.

**One defect found and fixed while answering this:** the drag handler sampled the mouse buttons on
every *update* rather than latching at drag *begin*, so a move could be reclassified into a rotate
mid-gesture — which silently took a prism off AUTO and left the bench with an alarm and no obvious
cause. The mode is now decided once, at begin, and carried for the whole gesture.

---

## Dispersion is exaggerated, on purpose, in one place

At `Dispersion = 1.0` this is **real glass**, and real glass fans about 1.5° for crown and 6° for
heavy flint. That is the truth and it looks nothing like the reference photograph, which is a
long-throw studio shot of a demonstration prism.

Rather than faking the colours downstream, the exaggeration lives in exactly one labelled,
sweepable number: a gain on the Cauchy **B** term, i.e. on the Abbe number. Every material keeps
its true relationship to every other. The default is 2.0, which gives ~13° of spread with SF10 at
a 60° apex and leaves comfortable margin before the blue end starts total-internally-reflecting.

Fan colours are **not** a palette. They are the CIE 1931 observer evaluated at the wavelength that
segment was actually traced at, converted to linear sRGB. Changing the wavelength count cannot
tint the beam.

---

## The three families of light

The reference photograph contains three, and `Light Paths` selects how many are traced:

1. **The fan** — the transmitted route.
2. **The specular** — the reflection at the *first* dielectric face. Bright, white, undispersed;
   the beam heading away from the prism in the photograph.
3. **The secondary fan** — the reflection at the *second* face, the light that failed to leave the
   exit face, travelled back inside the glass and came out somewhere else. Weak and wide.

A branch lane that never finds its reflection has retraced the primary exactly, and is discarded
rather than doubling that beam's brightness.

---

## How wide is a ray?

A fixed width is wrong everywhere except at the source. Refraction into glass at steep incidence
spreads a bundle by 1/cos, a lens squeezes it, the internal-reflection branch leaves the exit face
strongly divergent. Drawn at one width, the bundle opens into visible stripes exactly where it
matters most — inside the prism.

So each segment asks the **neighbouring ray** where it is at the same interaction and draws itself
just wide enough to meet it. One extra buffer read, and beams narrow through a focus and fan
through a prism entirely on their own.

Growth is capped at 8× the base width, and the cap is set by the *worst* family, not the best.

---

## The acceleration layer

A beam is a sparse one-dimensional mark: it covers a few thousand pixels out of nine hundred
thousand. Per-pixel looping over every segment is the wrong cost model by two orders of magnitude.

`LT_Field/bins.hlsl` collects, per 32-pixel tile, the segments that could touch it — **by gather,
one thread per tile**, so no atomics, no clear pass, and a bit-identical result every cook. The
renderer tests only its own tile's list.

Three things this got wrong first, each visible only in a capture:

- **The binner must expand by exactly what the renderer draws.** Bin tighter than you draw and
  beams get chopped at tile seams — a 16-pixel staircase along every beam that reads as a
  rendering fault rather than a binning one.
- **The expansion must be per segment.** A single global worst case put every segment into a
  hundred tiles and overflowed the lists across half the frame.
- **The hot-spot highlight must be sized from the base width, not the widened one**, or its
  falloff reaches past what the binner expanded by.

The **Occupancy** view draws the tile lists and paints any tile that overflowed in red. It found
all three. Capacity (2046 per tile) was measured from it, not guessed — the worst tile is the one
containing the prism, because every lane in the graph passes through it.

---

## How thin can a beam get

The first beam model drew each ray as a **gaussian filament**. Gaussians do not tile: N of them
sum to a rippled profile, and the moment the beam is narrowed the gaps between rays open into
visible stripes. Thinness was therefore capped by ray count, which is the wrong currency.

A beam is a **sheet**, not N filaments. Each ray is now drawn as a **flat-top ribbon** exactly half
a ray-spacing to either side, so adjacent ribbons tile edge to edge and reconstruct the continuous
bundle. Three properties fall out of two lines:

- **`cov` is the exact overlap of that ribbon with a one-pixel box** — the analytic convolution,
  not an approximation — so a ribbon far thinner than a pixel resolves cleanly instead of aliasing
  into dashes.
- **Dividing by the ribbon's own width makes it flux conserving.** A ray carries fixed power, so
  squeezing it into a narrower ribbon raises the radiance: a beam brought to a focus brightens, a
  diverging one fades, and neither is tuned.
- **The reach shrank.** A ribbon has a hard edge rather than a 3-sigma tail, so the binner's
  footprint per segment fell even as the width cap tripled.

To make a beam thinner, reduce **Aperture** — that is the physical control, and the ribbons stay
tiled at any width. `Min Ray Width` is only a floor, for a single-ray source.

**Profile** picks the transverse intensity across the aperture. Real beams are not uniform; a
laser is very nearly gaussian (TEM00, falling as `exp(-2r²/w²)`), and a flat-topped bundle is most
of what makes a rendered beam look like a drawn rectangle instead of light. The constant restores
the total, so switching profile changes the beam's shape and not how much light is on the bench.

---

## Quality ladder

Renders at **1920x1080**; the framing is resolution-independent because pixels-per-bench-unit
scales with the frame, so raising the resolution is pure sampling and leaves the composition alone.

Measured in one sitting on a five-prism hand-built bench, all four node previews open, whole-graph
GPU time. Published as ratios, because identical presets measure 3-5x apart in this workspace
depending only on how many previews are open.

| Preset | λ / rays / bounces / paths | Relative cost |
| --- | --- | ---: |
| Draft | 10 / 5 / 5 / 1 | 1.0x |
| **Live (default)** | **20 / 12 / 7 / 3** | **5.9x** |
| Beauty | 28 / 14 / 10 / 3 | between |
| Hero — capture only | 32 / 28 / 14 / 3 | 16.6x, and the app drops to 30 fps |

Quality is bought along the **wavelength** axis first, because that is the axis the image is about:
two more wavelengths beat four times the rays at a fraction of the cost. Rays buy spatial detail
across the aperture, and with tiling ribbons a modest count is already smooth.

The ceiling is 40 rays x 32 wavelengths x 3 paths x 14 bounces. Bin capacity is 4094 per 32-pixel
tile, sized by the worst tile measured with the Occupancy view — which is **not** the one holding
the prism but anywhere along an UN-DISPERSED run, where every wavelength is still collinear and one
tile holds a segment per lane. Tile size cannot help with exactly-overlapping segments.

**`Frame — Reference`** on `LT_Field` saves the composed viewpoint and *nothing else* — recall it
before any final capture. It scopes `view_center` and `view_zoom` only, so it cannot disturb the
look; the quality ladder scopes the four trace counts only, so it cannot disturb the framing.

---

## Exploration axes

`Arrangement` ships four chain templates. Each is a permanent preset, not a throwaway variant.

| | |
| --- | --- |
| **Reference** *(default)* | one source, one prism at minimum deviation, one screen |
| Cascade | three prisms of three different glasses in series — the spectrum split and split again |
| Cavity | mirrors folding the path back on itself around a prism |
| Battery | a splitter feeding two prisms, then a wall |

`Cast` gives a continuous weight per category (prisms / mirrors / slabs+lenses / splitters),
implemented as **rejection and redraw** — the only way to honour "none of these" against a fixed
sequence. At 1.0 across the board a preset behaves exactly as authored; if every weight is zero an
element still falls back to a prism, because a bench with no prism is not this bench.

---

## Traps worth knowing

- **`output_format` defaults to RGBA8.** `LT_Field` publishes real HDR; without it explicit every
  beam core clips to flat white before `LT_Lens` sees a highlight, and the bloom has nothing to
  bloom from.
- **A long streak needs two chained passes.** A single 13-tap blur stretched over 300 px lands each
  tap as its own visible ghost — a ladder of copies marching away from every bright edge. Pass one
  covers ±6 steps, pass two steps by exactly 13.
- **A 1/16 halation buffer bands.** At 80×45, bilinear upsampling back to 1280×720 steps in visible
  16-pixel blocks wherever the source had an edge, which in an image made of hard-edged beams is
  everywhere. 1/8 plus a four-tap tent.
- **Include paths resolve from the *consuming module* directory**, not from the including file. A
  shared header including a sibling needs `../_shared/`.
- **SM 5.0 cannot pass a resource as a function argument.** The shared kernel reaches its buffers
  through `LT_BENCH` / `LT_PATHS` macros the consumer defines *after* declaring them, which is why
  `PathSeg` lives in `bench.hlsli` rather than beside the kernel.
- **Glass drawn before the light reads as a wireframe.** A glass edge is only bright where light is
  near it; accumulate the hardware separately and add it *after* the beams.

---

## Idle execution

The expensive physics and field stages retain their outputs between changes. `LT_Trace` and
`LT_Field` use `execution: on_dirty`, and every pass in both nodes declares
`time_dependent: false`. They wake for edited bench records, quality or look parameters,
resolution changes, and recompilation.

`LT_Bench` keeps the default scheduler policy because its authored canvas follows the panel
resolution. Its plan, chief-ray, and canvas passes are individually non-time-dependent, so GPU
dispatch is skipped until the panel, parameters, durable editor state, or viewport input changes.
`LT_Lens` remains continuous because it consumes the image texture and animates film grain.

---

## Verified, and not

**Verified from live state and captures:** all four nodes healthy with frames advancing; the
element/source record contract via the plan canvas and the trace scope; minimum-deviation solving
and prism re-centring; the TIR alarm, the unlit-element alarm (`ALARM 01`) and the deviation
readout; the tile-overflow diagnostic; all eight Scene Group controls writing through to their
members; the four quality rungs and the frame preset. Per-emitter chief blocks were proved by
moving `Rail Source` between two live sources on a three-source bench: the plan keeps all three
fans, the emphasis and the amber ring follow the target, and the ladder and deviation profile
change completely — which they cannot do if both are reading the same block.

**Not machine-verifiable:** injected input does not reach Module viewport events, so **every
pointer and keyboard gesture in `LT_Bench` needs exercising by hand** — click-select, drag-move,
right-drag-rotate, wheel-resize, and the A / S / Backspace / Z / K / M / P / X / N / R / C keys.
The pick maths is checked against known record coordinates and the persistence path is the standard
`state_buffers` one, but the gestures themselves are unproven.

Detailed profiling was toggled on for the ladder measurements and returned to off.
