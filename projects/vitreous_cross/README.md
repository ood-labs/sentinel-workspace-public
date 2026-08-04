# Vitreous Cross

An interlocking cross of clear and amber glass volumes with a mass of trapped organic
inclusions, rebuilt from a reference image. Opaque white, black and burnt-orange plates sit
*inside* the glass and are seen through it; the organic masses are **air cavities**, so every
one of them is a real lens.

Everything is ray-marched signed-distance geometry lit by one authored HDR studio. There is
no diffusion, no photographic source, and no bitmap asset in the project.

Reviewed output: **`VC_Post`** (output `Program`), 1536 x 1024.

**Study this one for transmissive rendering** — medium-stack ray transport, spectral
dispersion from real per-wavelength indices, Airy thin-film interference, and the rough-membrane
lobe that is the difference between "clear bubble" and "substance".

---

## Component map

```
VC_Plan ──Plan(data)────────────────────────┐
                                            ├─> VC_Render ──Beauty──> VC_Post ─> Program
VC_Env ──Studio(tex) + Irradiance(tex)──────┘
       └──key_dir_{x,y,z} (control outputs) ──expression──> VC_Render shadow direction
```

| Node | Single responsibility |
| --- | --- |
| `VC_Plan` | **Plan authority and editor.** Decides where every volume, inclusion and plate sits. Publishes one 48-record `Plan` buffer plus a schematic preview. Click-select, drag-move, keyboard edits. |
| `VC_Env` | The studio as a lat-long HDR panorama, plus a cosine-convolved irradiance map and the key vector as control outputs. |
| `VC_Render` | The transport engine. Internal camera. Publishes **RGBA16F with linear depth in alpha**. |
| `VC_Post` | Lens and film finish: bloom, aberration, vignette, max-channel tonemap, grade, grain, edge AA. |

---

## The data contract

One record type, one buffer, one `role` discriminator — `_shared/vitreous.hlsli`.

```
VcRec = pos float3 · dims float3 · role · mat · tint float3
      · seed · p0 · p1 · flags · active                        (64 bytes)
```

**Fixed slot ranges**, so the marcher never scans 48 records: `0–11` glass slabs ·
`12–35` inclusions · `36–45` plates · `46` stage · `47` editor header.

`mat` spans one table for both transmissive and opaque materials, and
`VC_MAT_TRANSMISSIVE()` is the single test that decides whether a ray refracts through an
interface or terminates on it.

**Selection is deliberately not a flag** — it lives only in the editor header, so it cannot be
stored twice and fall out of sync.

---

## The idea the whole renderer rests on

This scene is not surfaces with transparency painted on. It is a **stack of media**: air
contains glass; glass contains *air cavities* and denser fluid pockets; opaque plates sit
inside the glass. A ray is never "hit and shaded" — it crosses interfaces, and at each one the
only questions are which medium it was in, which it is entering, and what the Fresnel split is.

Two consequences that are not obvious until you build it:

**The marcher steps on `|sdf|`, not on a signed union.** A signed union can only find the
outside of the outermost object. The *unsigned* boundary field finds the next interface no
matter which side of which shape the ray is currently on — which is exactly what medium
tracking needs.

**The organic masses are cavities, not blobs.** Crossing into one takes the ray from 1.50 to
1.00, so it bends the *other* way. That sign change produces the reference's swollen, lensed
interiors, and no amount of surface shading imitates it.

Partial reflections resolve straight to the studio panorama (`cs_5_0` forbids recursion), but
**total internal reflections continue in the main loop and are fully traced** — those are the
rays that carry the other bars' images around inside the glass, and the reference is full of
them.

---

## Rendering notes

**Spectral dispersion is geometric.** Up to seven wavelengths are traced independently, each
with its own Cauchy index of refraction, and recombined through a CIE-ish response. The fringes
are produced by rays going different places, not by offsetting colour channels afterwards.
Real glass splits by ~0.008 across the visible band, which is invisible at this scale and which
the reference plainly does not obey — so `dispersion` scales the Cauchy coefficient, and
`dispersion = 1` is the true material.

**Thin film is the real Airy summation**, not a hue ramp: optical path difference
`2·n·d·cos θt` over wavelength, with the finesse rising as Fresnel does. The bands therefore
compress toward grazing incidence — which is exactly where a silhouette is — and march with
thickness. That behaviour is the whole tell of a soap membrane.

**Tonemapping runs on the max channel.** A filmic curve applied per channel compresses the
bright channel of a saturated colour harder than the dim ones, which desaturates precisely the
pixels carrying the image's only colour: the amber glass and the dispersion fringes chalk out
to pale pink. Curving the largest channel and scaling the triple by that ratio compresses
luminance and leaves every hue and saturation ratio intact.

---

## Traps this build hit

**Grazing planes are the pathological case for sphere tracing.** A floor seen from eye height
advances by the *perpendicular* distance each step, so a ray two degrees below the horizon
needs several hundred steps to land. At 96 the entire lower half of the frame failed to find
the floor and fell through to the environment — a hard black horizon that looked like a shading
bug and was a convergence one. The cyclorama is now intersected **analytically**, which also
removes a shape from every step of every march.

**A pass that writes to a named buffer has no render target, so it cannot be a module output.**
The irradiance convolution ran correctly into `buffer:irr` and the node published an
`Irradiance` slot with **no SRV** — every diffuse surface downstream read pure black, and the
symptom was "the whole image is too dark", not an error. A trivial upsample pass gives the map
a bindable texture.

**Clear glass in front of a dark seamless renders as dark chrome.** That is physically correct
and it is not the reference. The masses read as milky *substance* because a real soap or
frosted membrane scatters transmission into a wide lobe — and the wide-lobe answer is exactly
what the pre-convolved irradiance map already holds. `inclusion_frost` splits the transmitted
energy between that lobe and the coherent ray. It is the single control that decides whether
this image works.

**The room's brightness and the backdrop's brightness are different numbers.** The glass needs
a bright room to reflect; the reference needs a dark backdrop. Raising `backdrop_value` (the
ambient the glass sees) while dropping `cyc_albedo` (the seamless's own reflectance) is a real
studio setup — light the subject, flag the background — and separating them is what let both
be right at once.

**Iterated smooth-min compounds.** Fusing two dozen records one after another accumulates one
blend radius per step and inflates a phantom shell well outside every contributing ellipsoid —
spheres that are not there. Every fuse is bounded at `plainMin - k`.

**A displacement amplitude has to be a fraction of the record's own radius.** At an absolute
0.11 the wobble was 7% of the radius and every mass rendered as a machined sphere. It is now
`VC_WOBBLE_K` × the record's smallest radius, and `vcIncLipschitz()` is derived from that
constant — raise one without the other and the marcher overshoots into speckled holes.

**A placement preset that cannot resize is not a placement preset.** Colonnade stood the cast
up as eight columns using an extent *multiplier*, so a 2.4-long bar became a 0.55-wide column
at a 0.31 pitch and every instance fused into its neighbours: the preset rendered as one
continuous wall. Column width now comes from the rank's pitch. Cascade threw its long bars
clean off both edges for the same class of reason, and now caps its longest axis and scales
the other two by the same ratio so proportions survive.

**Clamping a centre is not a frame guard.** A long bar centred just inside the limit still
hangs half its length outside the picture. `frameGuard()` clamps the centre against the
element's own half-extent.

**`working_format` is not `output_format`.** The former governs intermediate pass buffers; the
texture handed to the next node is governed by the latter, which defaults to `RGBA8`. This
module carries linear depth in alpha.

---

## Editing the plan

`VC_Plan` is a direct-manipulation editor, not a read-only generator.

| Gesture | Effect |
| --- | --- |
| click | select the element under the pointer (smallest hit wins) |
| drag | move it in the image plane |
| `M` | cycle material — per-role list (glass: clear/amber/smoke · inclusion: cavity/fluid · plate: white/black/copper) |
| `G` / `H` | bigger / smaller |
| `A` / `Z` | pull nearer / push deeper |
| `X` | toggle on/off (off elements stay selectable) |
| `N` | re-roll that element |
| `R` | reseed the whole layout |
| `C` | clear selection |

Verbs were chosen for *this* subject: a glass volume is defined by its proportion, its depth in
the stack (which decides how much glass a ray travels through, and therefore what the picture
is made of) and its material — so those go on keys.

Regeneration is signature-driven and **only structural parameters are in the signature**;
appearance refreshes in place, so a tint tweak never costs the user their layout. The canvas
draws and the hit test picks through **one shared `vc_uvToStage()`**, so they cannot drift.

---

## Exploration axes

| Axis | Node | Winner | The losers |
| --- | --- | --- | --- |
| `arrangement` | `VC_Plan` | **Cross** | **Pinwheel** is a genuine alternative — rotational, still interlocking. **Colonnade** and **Cascade** both originally failed (fused wall / off-frame bars) and were **repaired**, not deleted: Colonnade now derives column width from the rank pitch and is one of the better looks in the set. |
| `inclusion_form` | `VC_Plan` | **Cluster** | **Spill** drains the mass to the bottom and reads as a poured pour; **Column** stacks it into a vertical core; **Scatter** gives one bubble per volume and is the most graphic of the four. All four are usable. |
| `light_rig` | `VC_Env` | **Softbox** | **Twin Strip** is moodier with sharper speculars and a darker backdrop; **Overhead Wash** is low-contrast and reads by silhouette; **Window** is the only rig whose *shape* survives refraction, so the bubbles carry little mullioned window panes. |

`variation = 0` is exactly the transcribed reference and can never be lost — verified by
reading records back and comparing against the tables. Proportion is never re-rolled flat, so
the size hierarchy survives every seed.

Sweep images are in `proof/`.

---

## The randomiser

**Push `Variation` to 1 and scrub `Seed`.** In `Q0 Draft` that is a real-time dice roll.

It randomises **relationships, not coordinates**, and that distinction is the whole thing. This
subject is not a scatter of objects on a plane — it is one interlocking cluster of glass with
mass and plates trapped inside it. Drawing fresh coordinates per record (which is the correct
approach for a scatter-based plan like Soft Vitrine's) destroys the three relationships that
make it this object, and every seed comes out as debris no matter how well stratified the draw
is. It was tried first, and that is exactly what happened.

So each family is randomised against what it actually depends on:

| Family | Randomised as |
| --- | --- |
| glass volumes | attach to a **parent volume** at an offset guaranteed to share solid volume |
| inclusions | hosted **inside** a volume, in groups of four, radius derived from that volume's own extent |
| plates | hosted **inside** a volume, extent derived from that volume's face |

The parent tree is transcribed from the reference, so `variation` lerps each child's attach
offset from *exactly where the reference put it* to a free draw, continuously and validly the
whole way.

Five guarantees make an arbitrary seed presentable, and each one was added because a seed
looked broken without it:

1. **Attach offsets are drawn below the touching distance**, so volumes always share solid.
2. **`enforceInterlock`** clamps out (things drift apart into pieces) *and* in (a small child
   sits concentric inside a big one and disappears).
3. **The parent draw is biased hard toward the root.** The transcribed tree is a chain, and
   following a chain with random directions grows a straggling procession that walks off frame.
   Biasing toward the root builds a bush.
4. **`fitCluster()`** measures the finished cluster and applies one uniform similarity
   transform to recentre and zoom it into frame. Growth produces a valid cluster but says
   nothing about where it ends up — this is what makes every seed framed by construction, and
   because it is uniform, no proportion changes. It runs *before* inclusions and plates so they
   inherit the framing for free.
5. **Aspect is tempered and mass is capped.** Extremes pull 30% toward the record's own mean
   (a random cluster has nothing packed across a 2.4-long sliver, so slivers read as wire), and
   an inclusion can never exceed 0.9 of its host's scale — above that the mass swallows the
   glass and the plates and it stops being glass-with-mass-inside.

---

## Quality and cost

Four node presets on `VC_Render`, project scope, touching **only** the eight quality
parameters — none of them changes anything about the look's intent, only how finely it is
resolved. All measured at 1536×1024 on this machine, whole-graph frame time:

| Preset | Spectral | Rays | Steps | Interfaces | Measured |
| --- | --- | --- | --- | --- | --- |
| **Q0 Draft** | 1 | 1 | 52 | 5 | **60 fps** (1.2 ms) — capped |
| **Q1 Live** | 3 | 1 | 72 | 8 | **60 fps** (9.6 ms) — capped, **manifest default** |
| **Q2 Beauty** | 5 | 1 | 88 | 10 | **26 fps** (35 ms) — best interactive |
| **Q3 Hero** | 5 | 2×2 | 96 | 12 | 4.6 fps (217 ms) — **capture only** |

All four re-measured in one sitting on the reference arrangement, whole-graph frame time.
**Treat them as ratios, not absolutes** — an earlier pass measured the same presets 3–5× slower
because several node previews were open and redrawing. If a number matters, measure it in the
state you care about.

The project **opens at Q1 Live**, which is capped at 60 fps and holds the whole look. **Q2
Beauty** is the one to actually work in: it buys two more wavelengths rather than four times the
rays, which for this image is the better trade — post edge-AA already covers edges, and
dispersion is what the picture is *about*. **Q3 Hero** is a capture setting, not a place to sit;
at 217 ms it makes the whole app sluggish. Recall it, capture, recall Q2.

**Where the cost is.** Linear in `spectral_samples`, **quadratic** in `aa_samples`. Q3 traces 20
full ray paths per pixel, Q2 traces 5, Q1 traces 3. Supersampling is the first thing to drop and
the last to add back. `Q0 Draft` loses dispersion entirely (one wavelength has nothing to split)
but keeps every other behaviour, which makes it the right mode for composing, for scrubbing
`Seed`, and for driving the plan editor.

## Node presets

| Preset | Scope | Use |
| --- | --- | --- |
| `Frame Contract` | camera only | the canonical pose — position `(0, 0.05, 7.5)`, yaw `π`, 17° FOV, Fly. Recall after flying the camera. |
| `Q0`–`Q3` | quality only | the ladder above. Each touches only the eight quality parameters. |

Both families are deliberately **narrow-scoped**: recalling the camera must not disturb the
look, and recalling a quality rung must not disturb the framing.

**A path that runs out of interfaces used to render black.** At `max_bounces = 5` every glass
volume was outlined in soot, which read as a shading bug and was a budget. The tracer now cashes
a path's remaining throughput out against the environment when it exhausts its budget — the
deep interior of a stack of boxes is mostly ambient anyway. That single change is what makes
the cheap rungs usable rather than merely fast.

---

## Scene Group surface

Six controls, **each verified through the group path** to its member parameter: Light Rig, Key,
Dispersion, Membrane Frost, Contact Shadow, Exposure. No camera parameter is exposed — the
camera belongs to `VC_Render`'s own Properties.

---

## What was not verified

- **The plan's click / drag / key gestures.** Injected input does not reach Module viewport
  events, so these cannot be machine-proven. Verified instead: the state buffer is declared,
  sized and persisting; bindings publish; signature behaviour (a `PLAN_VERSION` bump provably
  rebuilt the buffer); the pick maths shares one conversion with the canvas; record values were
  read back through `capture_data_port` and matched the transcription exactly. **The user needs
  to exercise select / drag / M / G / H / A / Z / X / N / R / C by hand.**
- **`VC_Plan` is not inside the Scene Group.** Its node reports a height of ~48,600 units that
  climbs with the generation counter — a host-side quirk of data-output nodes — so no annotation
  can enclose it. The group therefore covers `VC_Env`, `VC_Render` and `VC_Post` only, and the
  plan's own controls (Arrangement, Variation, Seed, Inclusion Form) have to be reached from its
  Properties panel.
- **Per-node GPU timing.** Detailed Profiling was off, so `profile` reports null `own_ms`.
  Measured instead: all four nodes healthy with frames advancing, and whole-graph frame time.
- **AI visual review.** No provider key is configured in `vision.json`, so `sentinel_vision`
  was unavailable; every judgement in this build was made by eye from captures.
