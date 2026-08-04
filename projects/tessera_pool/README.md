# tessera_pool

A glass tank of mosaic-tiled water, transcribed from a reference image: a displaced surface
refracting the lining, photon caustics on the floor and the submerged walls, Beer-Lambert depth
in the water body, and a bright glass rim. Dragging on the rendered water pushes real ripples
into the simulation.

The tank opens in manual mode: `TP_Sim / Sources / Auto Sources` is off, so the fixed plan
records do not fire periodic drops. Turn it on when you want the authored drop/emitter/swell
system back. In `TP_Render`, left-drag belongs exclusively to the water and right-drag belongs
exclusively to the camera.

Optical finishing stays narrow-scoped: `TP_Caustics / Caustics / Spectral Spread` separates
wavelengths only around irradiance gradients (`0` is the exact monochrome solve), while
`TP_Post / Lens / AA Crispness` controls how much center detail the diagonal-edge resolve keeps.
The defaults are subtle rather than a whole-frame chromatic-aberration look.

Open `tessera_pool.sentinel`. The Program output is `TP_Post`.

---

## Component map

| Node | Single responsibility |
| --- | --- |
| `TP_Plan` | Plan authority: tank, lining, palette, light, ripple sources. |
| `TP_Sim` | The water simulation with live pointer injection. |
| `TP_Caustics` | Photon caustics splatted onto the unfolded tank interior. |
| `TP_Render` | Optics and the internal camera. |
| `TP_Post` | Bloom, grade, edge antialias. |
| `TP_Flicker` | Delivered-pixel temporal probe; diagnostic only. |

## The graph

```
TP_Plan ──(Plan records)──┬─────────────────────────────┬────────────────┐
                          ↓                             ↓                ↓
                       TP_Sim ──(Field)──► TP_Caustics ─(Atlas)─► TP_Render ──► TP_Post
                          ▲                                          │
                          └────── ext_u / ext_v / ext_down ◄─────────┘
                                  (expressions, not a link)
```

| Node | Owns |
| --- | --- |
| `TP_Plan` | the tank, the lining, the palette, the light, and every ripple source. Nothing else decides any of them. |
| `TP_Sim` | the water surface: a damped wave equation over the tank footprint, plus live pointer injection. |
| `TP_Caustics` | where the sun goes after it enters the water, splatted onto an unfolded tank interior. |
| `TP_Render` | optics. Owns Sentinel's internal camera. Decides nothing about the composition. |
| `TP_Post` | bloom, grade, edge antialias. |
| `TP_Flicker` | an independent delivered-pixel temporal probe; diagnostic only, never part of the image path. |

The loop from `TP_Render` back to `TP_Sim` runs through **control outputs and expressions**, not
a data link, so there is no cycle in the graph — only a one-frame delay, which for water is
nothing. `TP_Sim`'s measured `wave_peak` returns to `TP_Plan` the same way.

---

## The scaffold: plan over section

`TP_Plan`'s canvas is a draughtsman's drawing, not a small copy of the render. Two strips share
one x axis and one scale:

- **Plan** — the footprint from above, the tile grid at its real pitch, and every ripple source
  drawn as the ring train it will actually produce (spaced at its own wavelength). Everything is
  clipped to the water, because a ripple cannot exist outside the tank.
- **Section** — the cut through the tank. This is the strip that earns its place: it carries the
  depth and the freeboard, which a plan cannot show at all; it draws the **measured** wave
  envelope fed back from the sim, not a predicted one; and it draws the **failure mode** — an
  envelope that clears the glass rim, or one that scrapes the floor — in alarm red where it
  happens. It also carries the refracted sun ray, which is the only place in the show that
  explains why a caustic does not sit directly under the ripple that made it.

Verbs: click select, drag move, `M` cycle kind (drop / emitter / swell), `G`/`H` stronger/weaker,
`A`/`Z` longer/shorter wavelength, `X` on/off, `N` re-roll one, `R` reseed, `P` re-roll palette,
`C` clear.

---

## What a re-roll means

Ripple sources are points on a plane — their identity is positional, not relational — so
`variation` draws coordinates, and that is the right answer here. What keeps every seed
presentable is the set of guarantees, all gated on `variation > 0` so the transcription is never
nudged off its own coordinates:

| Guarantee | Without it |
| --- | --- |
| stratified 4x4 draw, hash-permuted order | sources march along a row |
| three separation relaxation sweeps | two sources inside one wavelength read as one |
| descending amplitude ladder, imposed by construction | four equal puddles instead of a composition |
| margin clamp inside the footprint | a source outside the tank does nothing at all |
| one uniform centroid fit | the cluster lands wherever the draw happened to put it |
| **total energy normalised to the transcription's** | a seed comes out flat, or blown past the rim |

`variation = 0` is exactly the reference. That is verifiable rather than asserted: read the Plan
data port and source 0's amplitude comes back `1.00005` — the energy normalisation is a
measurable no-op there.

---

## Exploration axes (shipped as enums, not throwaway variants)

- `TP_Plan / arrangement` — Single Drop (the transcription) · Rain · Corner Swell · Lattice
- `TP_Plan / basin` — Square · Wide · Deep Well · Shallow Pan
- `TP_Plan / tiling` — Mosaic · Running Bond · Penny Round · Banded
- `TP_Caustics / method` — Photon (default) · Divergence

Diagnostic views ship too, because in a chain that is mostly invisible bookkeeping they are the
only way to tell a dark lane from a dead one: `TP_Render / view_mode` (Beauty, Surface, Normals,
Caustics, Steps, Depth) and `TP_Caustics / view_mode` (Irradiance, Raw Counts, Opposite Half).

---

## Node presets (project scope)

- **`TP_Render / Frame - Reference View`** — camera parameters ALONE. The internal camera is
  meant to be flown, so the composed pose is lost the first time anyone explores and is
  recoverable from nothing else. Recall it before any final capture.
- **`TP_Render / Q0 Draft · Q1 Live (default) · Q2 Beauty · Q3 Hero (capture only)`** — surface
  march steps and rays per axis ALONE.
- **`TP_Caustics / Q0 Draft · Q1 Live (default) · Q2 Beauty`** — photon step and reconstruction
  radius ALONE.

Recalling the camera does not disturb the look; recalling a quality rung does not disturb the
framing. That is the point of the narrow scope.

**Measured, in one sitting, with all five node previews open:** the whole graph held its 60 Hz
vsync cap at every rung including Q3 Hero (176 march steps, 3x3 = 9 rays per pixel). The renderer
is analytic — two slab tests and a bracketed height-field march — rather than a sphere tracer,
which is why it is roughly an order of magnitude cheaper than an SDF scene of this complexity
would be. Hero is still labelled capture-only because it buys nothing in motion; Q1 Live is the
manifest default and the near-left grazing region is visibly cleaner at Q2 and above.

---

## Traps found here, worth not rediscovering

**Passes are scheduled by buffer dependency, not by manifest order.** A clear-then-accumulate
pair has nothing linking it, so the clear is free to run *after* the splat — and it does. The
accumulator came out empty every cook and the splat pass looked like it had never run. The
repair-by-differencing (accumulate forever, snapshot, subtract) fails from the other direction:
making the resolve read the snapshot buffer *creates* the dependency that forces the snapshot to
run first, so the difference is exactly zero everywhere. `TP_Caustics` therefore splits its
accumulator in half and alternates by cook parity — one writer, no ordering assumptions, and the
two halves never touch the same memory in the same dispatch so there is no race.

**A producer must state what it did in the buffer it owns.** Having the resolve read the same
cook counter and derive the parity for itself does not work: the two passes observe the counter
one cook apart, so the resolve reads the half that was just wiped. The splat now writes its
chosen half into the accumulator's last element and the resolve reads that.

**A persistent buffer is not guaranteed to arrive zeroed.** `TP_Sim` came up with a non-finite
state texture, `keep` copied it back every cook, and it poisoned the surface for the lifetime of
the project — surviving reloads, because the buffer survives reloads. It presents as a perfectly
flat surface with an RMS of NaN. The solver now sanitizes on read, as a magnitude test rather
than `isnan()`, so it catches NaN and infinity together and cannot be optimised away.

**Do not build a feedback solver from separate texture-buffer scratch stages.** Named Module
texture buffers are ping-pong targets. The old `state -> w1 -> w2 -> w3 -> keep` chain exposed
opposite halves of that machinery on alternating cooks: one frame contained the real surface and
the next was flat, producing an exact ABAB flicker even though the wave equation itself was
stable. All three substeps now read and write the one persistent `state` buffer. The runtime flip
after each write gives the next pass the preceding result, and the third result is already the
state consumed by the next cook.

**A clamp is not a safety net.** The first bound on the wave field was `clamp(h, -8, 8)`. It
stops NaN and then holds the field at the ceiling forever, because a clamped value is perfectly
finite and the solver keeps it. Measured: peak and RMS both pinned at 8, the whole surface
saturated, the rim alarm stuck on permanently. The bound now **bleeds energy** above a height the
tank could never legitimately produce, so a transient settles back on its own in about a second.

**A substep that does not divide the timestep is not a substep.** The three wave passes each
received the FULL frame interval, so the solver advanced three frames per cook: waves travelled
at three times the authored speed, the emitted wavelength came out three times longer than the
plan drew it, and every continuous source deposited three times its intended energy. It also
threw away the entire benefit of substepping, which is CFL headroom.

**A displacement driver is an unbounded energy pump.** The continuous sources originally wrote
`h = lerp(h, target, k)` — they CLAMPED the surface to the driver's position inside the source
radius. That is a rigid piston, and a rigid piston in a low-loss tank has no upper bound: it
holds its own displacement regardless of what the surrounding water is doing, so every wave that
returns to the source is reflected and re-driven. The surface climbed until it thrashed, and no
amplitude setting could stop it because the piston's authority is total whatever amplitude you
ask for. They are springs now — `v += (target - h) * stiffness * mask * dt` — which do bounded
work per unit time and let water move through them.

**Linear damping does not bound a driven cavity; breaking does.** Damping only sets a steady
state proportional to drive over damping, and the damping had to stay low for ring trains to
cross the tank at all, so that steady state was enormous. Real water solves this by breaking past
a steepness around 0.9 — which is also why the sea does not accumulate every storm it has ever
had. The `break_slope` / `break_gain` pair costs exactly nothing below the threshold and makes
the surface self-limiting at any drive setting. Note the consequence: at a fixed steepness limit,
amplitude is proportional to wavelength, so the way to get a taller surface is a longer ripple —
not more gain. Drawn relief is exaggerated separately in the renderer's `slope_gain`, which keeps
"how steep the water is" (bounded, stable) apart from "how much relief we draw" (art direction).

**A line source is not a point source at the same amplitude.** A swell's band covers roughly
twenty times the area of an emitter's disc, so at equal stiffness it deposits twenty times the
energy and flattens the whole ring system into corduroy. The swell drive carries that area ratio
as a constant so a record's stored amplitude means the same thing whichever kind it is.

**Anything added AFTER the solver is deaf to every solver control.** The capillary chop is
analytic — added in `field.hlsl`, animated by its own clock — so ungated it ran forever and no
amount of damping, wave speed, wall reflectivity, wave gain or breaking could touch it. A tank
whose solver had settled to an RMS of 0.00003 still rippled visibly, which is indistinguishable
from a physics runaway and impossible to tune out, because none of the tuning reaches it. Its
amplitude now follows the local wave envelope (`Chop Follows Waves`), so still water is still.

**A boolean held in a persistent buffer cannot be cleared reliably.** The pointer's `down` flag
was only cleared by a drag-end event — and events stop arriving entirely the moment the preview
loses focus, so a drag ending off-focus stranded it at true and the sim pressed a finger into the
water forever, re-imposed every cook and immune to every damping control. It is a decaying HOLD
TIMER now, which cannot strand because it expires unless something keeps renewing it. Same class
of bug as the clamp above: state that can only be cleared by an event you might never receive.

**A persistent state buffer accumulates permanent damage.** After the latched-pointer period, one
texel of the wave field held a corrupted value that no amount of damping removed — it showed as a
fixed dimple with radial spokes at one spot, and it survived project reloads because the buffer
does. `TP_Sim / Reset (hold)` is the only thing that clears it. If the water ever behaves
impossibly in one small place, reset before debugging anything else.

**Publish the slope where it can be checked, not where it is cheapest.** The solver differenced
its own texels and divided by a cell size derived from `GetDimensions`, and what arrived
downstream was smaller than the true slope by more than an order of magnitude — the water
rendered as a mirror-flat sheet while its heights were plainly correct. The gradient is now
measured in `field.hlsl`, where the same `tex` sets both the sample offset and the world distance
it is divided by, so the two cancel whatever the texture's real extent turns out to be.

**Glass edges must not subtract light.** Shading the rim and the corner posts as pure reflection
made them *darker* than the backdrop they sit against, which outlined the tank in black bars and
read as plastic. Glass with nothing behind it transmits the backdrop and adds its reflection on
top.

**Detail below Nyquist is not detail.** The capillary chop bottomed out at five texels of the
published field. A gradient scales as amplitude times wavenumber and a *curvature* as amplitude
times wavenumber squared, so that aliased octave arrived with a curvature rivalling the ripples
it was decorating, and printed a fixed crosshatch across the caustic atlas that buried the ring
focus lines completely. Every octave now sits above ten texels, and `detail_amp` is calibrated
against the caustics rather than by eye on the surface.

**Measure temporal curvature, not merely motion.** A first frame difference lights up every
legitimate traveling ripple, so it cannot tell animation from flicker. `TP_Flicker` measures the
temporal second difference of delivered luminance, peak-holds the locator, and publishes mean,
peak, and affected area. The detector reads and writes its history through one structured-buffer
UAV; splitting history storage into another pass would let dependency scheduling store the
current frame first and make the detector report a perfect zero. An exact ABAB fault has another
useful fingerprint: frame `t` resembles `t-2` much more than `t-1`.

**Chromatic caustics belong in the irradiance field, not in full-frame post.** The photon solve
is deliberately scalar. `caustics_out.hlsl` estimates the local irradiance gradient, shifts red
and blue symmetrically along it, keeps green on the base sample, then corrects luminance so the
control adds hue rather than light. Flat irradiance therefore remains neutral, `Spectral Spread
= 0` is an exact monochrome path, and atlas-region bounds stop bookkeeping seams from becoming
false colour fringes. `TP_Render` consumes that RGB field without inventing another split.

**An antialias resolve must retain the pixel it is resolving.** The first edge filter averaged
four neighbours along the edge tangent and discarded the centre sample, which was stable but
unnecessarily soft. `TP_Post` now blends a near/far tangent neighbourhood back toward the centre
according to local luma range. `AA Crispness` changes that centre weight; it is not a disguised
global sharpen pass and does not amplify every tile edge equally.

**Reserved HLSL words** — `pass` and `line` are both reserved and fail with a bare syntax error;
`step` shadows the intrinsic.

---

## Honest gaps

- **The gesture paths cannot be machine-proven.** Injected input does not reach Module viewport
  events, so the click/drag/key paths in `TP_Plan` and the left-drag ripple on `TP_Render` were
  built and reasoned through but not exercised over MCP. What is verified: the pick maths against
  the still plane, the control outputs, the three registered expressions driving `TP_Sim`, and
  the buffer persistence. **Exercise by hand:** drag on the rendered water and confirm ripples
  follow the contact ring; click a source in the plan and confirm it turns amber; drag it and
  confirm it moves; press `M`, `G`/`H`, `A`/`Z`, `X`, `N`, `R`, `P`.
- **The caustics are art-directed, not physical.** `slope_gain` defaults to 0.5, well below 1.
  At this tank depth and this ripple steepness a physically exact caustic is a chaotic wash
  rather than the reference's organised concentric rings — the light focuses far above the floor
  and diverges again. The reference is a WebGL demo whose caustics are themselves an
  approximation. Raise `slope_gain` toward 1 for the physically honest deep-tank look.
- **The near-left grazing band** still shows scalloping at Q1 where the water surface is seen
  almost edge-on through the near wall; it clears at Q2 and above.
- **The four arrangement and basin presets were not swept and judged** against captures — they
  are built and reachable, but only Single Drop / Square / Mosaic has been looked at properly.
- **Do not run whole-graph auto-layout on this project.** Sentinel computes a node height that
  grows without bound for every node that has a video input — measured climbing past 40,000 units
  while the graph sat idle. Auto-layout consumes those heights and stacks the rows accordingly,
  which threw four of the five nodes to y = 647,894 and made every wire shoot off to a vanishing
  point. Nothing in the project causes it and nothing in the project can fix it; it is an
  application-side bug. Recovery is to reload the .sentinel, which restores the saved positions.
  Place nodes explicitly instead.
