# Breathing Room

A realistic SDF living room that trips. A pre-war parlour on an upper floor: 2.85 m ceilings, a
herringbone oak floor, plaster walls with crown and picture rail, two tall west windows with sheers,
a marble fireplace with a real fire in the grate, a Tabriz rug, a linen sofa, cognac leather, brass
lamps at 2700 K and late-afternoon sun. Then it starts to breathe. Islamic geometry blooms out of the
plaster and the ceiling, textures swim and drip in place, the rug's medallion turns, objects swell and
slump, and colours deepen. This is closer to a real acid or mushroom
"replication" trip than to a cartoon of one: no faces or entities, and nothing is added to the room.
Only the way you see it changes, in waves.

It replaces `living_room_sdf`, the room example that shipped through 0.6.3. Only that project's split of
jobs was kept; every module here is new.

Open `breathing_room.sentinel`. **BR Lens** is the picture, and its HDR input is routed to BR Render
(the BR_Render input tile shows "Mouse -> BR_Render"), so you fly the camera from the final picture.
Right-click that tile to clear or restore the routing; the project saves it. BR Render's own
`Preview` output is a neutral view for judging the renderer without the eye. The six editors are
full-bleed canvases built on the Interaction Lab UI kit (see *The editors' UI kit*).

---

## Component map

```
BR Shell ──Shell──┬──────────────► BR Render ──HDR + Scene──► BR Lens   (the picture)
                  ├─► BR Furnish ─Furnish─┬─► BR Render
                  │                       ├─► BR Light ──Light──► BR Render
                  │                       ├─► BR Trip ──Trip───► BR Render, BR Lens
                  │                       └─► BR Rug ───Rug────► BR Render
                  ├─► BR Light
                  └─► BR Trip
BR Finish ──Finish──► BR Render
```

| Node | Owns (and nothing else decides it) | Its canvas |
| --- | --- | --- |
| `BR_Shell` | Room box, wall thickness, trims, floor pattern, every opening (windows, door, archway, fireplace) | **Unfolded room**: plan in the middle, each wall's interior elevation folded out from its own edge on a shared along-wall axis, drafting conventions, dimension chains, red alarms for collisions and corners |
| `BR_Finish` | 24 material slots (sRGB authored, linear stored) | **Finish schedule**: every slot shaded with the renderer's own BRDF and pattern families |
| `BR_Furnish` | Every piece: kind, variant, pose, host, material | **Furnishing plan + hidden-line section** with live design rules: coffee gap, conversation circle, walkway route from door to windows, hearth keep-clear, door swing, overlaps, legs on rug |
| `BR_Light` | Sun (from time, date, latitude and the building's bearing), lamps, fire | **Sun-path chart** with the windows, trees and skyline mapped onto the sky, a **day strip** marking golden and blue hours, and a **plan** of window sun patches and lamp light pools drawn as iso-illuminance rings |
| `BR_Trip` | Where the hallucination concentrates and how each kind runs through time | **Room unfolded** (floor, walls folded out, ceiling hinged off the east wall) with anchors attached to real features |
| `BR_Rug` | What is woven into the rug (BR_Furnish keeps its size and place) | **The rug laid flat**, woven by the same function the renderer uses, plus a dye column |
| `BR_Render` | Internal camera, every surface, light transport, the frame | Program image; a View selector with 16 diagnostics plus **Scope**, which shows where BR_Finish's selected material is used in the room |
| `BR_Lens` | Everything between radiance and the picture: visual-field warp, bloom, grade | The final image |

Every editor is a **plan authority over persistent records**. Parameters generate a complete room,
canvas edits are stored as deltas on top, and the two keep composing: you can change the room size
after hand-placing a lamp and the lamp stays on its table. Regeneration is signature-driven and
versioned (each editor's `PLAN_VERSION`), so hand edits survive every cook.

## Data contract

Every authority publishes 64-byte records, `BRRec { head, dims, look, meta }`, discriminated by
`head.x` (the ROLE), with disjoint role ranges per authority: Shell 1-9, Finish 20-29, Furnish 30-39,
Light 40-49, Trip 50-59, Rug 60-69. The semantics live in one place,
`modules/_shared/br_records.hlsli`, and the manifest schemas stay generic on purpose.

| Buffer | Layout |
| --- | --- |
| Shell (32) | 0 ROOM, 1-4 WALL (S E N W), 5-12 OPEN, 15 editor, 16-31 deltas |
| Finish (32) | 0-23 one material record per semantic slot, 31 editor (the selected slot, read by BR_Render's Scope view) |
| Furnish (112) | 0-47 pieces, 48-95 deltas, 96 editor, 97 frozen signature, 98 diag, 99 rules, 100-111 walkway route |
| Light (32) | 0 SUN, 1-8 LAMP (one per lamp piece, matched by furniture slot), 9 FIRE, 12 rules, 14-31 private |
| Trip (32) | 0 HEADER (effective amplitudes, motif, trip clock, envelope, worst Lipschitz), 1-12 ANCHOR, 13 diag, 14-31 private |
| Rug (16) | 0 header (family, proportions, abrash, wear, knot), 1-7 dye colours, 8 editor, 9+ deltas |
| Render `Scene` (224) | room, openings, sun, frame, camera matrices, lamps, trip globals and anchors, rug, objects, per-object trip warps, materials (consumed by BR_Lens) |

World frame: metres, Y up, floor at 0, +X east, +Z north. Sentinel's camera is left-handed. Every
input to BR_Render can be unlinked; the renderer falls back to house defaults.

## The trip

Ordered by how a replication trip actually behaves. Each line pairs the experience with how it's built.

- **Breathing.** Surfaces and objects swell and recede on slow cycles. These are per-object SDF warps
  (breathe, slump, twist). prep computes each object's warp parameters once per frame, and the
  distance is divided by the warp's Lipschitz bound so the march never steps through a surface.
  The furniture's share has its own channel, BR_Trip **Furniture** (0..1, default 0: every piece
  holds its shape), separate from Breathing, which still breathes the field, the plants and the
  picture. Lamps never warp.
- **Drifting.** Plaster, paint and fabrics swim and drip in place but never slide away. The swim is
  bounded and applied in surface space before texturing. BR_Trip's **Swim Scale** sizes it: at 1, the
  original broad 60 cm eddies 3.5 cm deep; smaller is finer and shallower in proportion (default
  0.4). The visual field's drift follows the same scale. A SWIRL anchor turns concentric rings
  against each other at that scale, instead of twisting the whole area round.
- **Tailored surfaces.** Anything with an identity of its own gets a trip made for it instead of
  being dragged by the swim:
  - **parquet**: the herringbone crawls slowly along its V columns, rigidly, so every slat stays
    whole. Its grain streams along each slat, the two slat directions flowing opposite ways, and a
    wave of tone chases up the columns.
  - **the rug** (`br_rug.hlsli`): the ornament comes alive. Field flowers swell and turn in rings
    that leave the centre. The medallion breathes, its ring of palmettes orbits it, its heart's
    rosettes counter-rotate and its scallops ripple. The border vine travels round the rug, the
    guards run against it, the abrash bands drift, and the dyes trade places within the rug's own
    palette.
  - **wood**: the grain flows along each board, never twists.
  - **the library**: the book spines ripple along each shelf like keys under a hand.
  - **the pictures** paint themselves. On the print the branch sways, the leaves flutter, the fruit
    swells and ripens, the bud opens into petals, the leaves turn toward autumn gold, and with melt
    the washes run down the paper. On the canvas the ridges roll, the sun sinks and rises, and the
    brushwork drifts.

  Travel and turning read two clocks that BR_Trip integrates (drift x dose and geometry x dose per
  trip second, trip record 30), so moving a slider changes the speed and never jumps the floor or
  the border.
- **Geometry.** Fine symmetric lattices emerge from plain plaster and the ceiling, crawl and morph.
  They use Hankin's method (polygons in contact), so the star lattice stays continuous across tiles
  while its contact angle animates. Four motifs: Girih, Lattice, Mandala, Moire. The pattern
  brightness follows local light, so it lives in the room's light rather than glowing on top of it.
- **Colour.** Hues deepen and drift in broad, slow regions (BR_Lens grade).
- **The visual field.** The whole image breathes, drifts, twists and sags around the anchors,
  projected through the same camera. Drug visuals are distortions of seeing, so this runs in the
  eye (BR_Lens), not in the room.
- **Lamp rainbows.** The lamps never warp (their thin shades sliced under it). Their trip is in the
  eye instead: soft bands of spectrum flow outward from each lit lamp's own outline, the shade's
  projected rims (a globe's circle), red on each band's inner edge to violet on its outer. Near the
  lamp they hug the drum or dome; further out they round off. They are only as strong as the lamp
  is visible, and the trip's geometry turns a six-fold flower through them. BR_Lens **Lamp
  Rainbows** scales them (0-3).
- **Plants.** Each moves its own way with the dose. The geometry channel resolves each into a
  symmetric diagram of itself (see Walk-through fixes).

**Overdrive.** Dose runs to 3. Up to 1 is the calibrated trip, exactly as before. Past 1, the push
(dose - 1, times the envelope; trip header `look.z`) grows every channel:
- amplitudes up to 4.2x (`tripAmp`) and spatial frequencies up to 2.6x (`tripFreq`): the swim, the
  lattice coverage and its scale, the object warps, the plants, the visual field (plus a ring
  ripple of its own), the hue drift, saturation and edge fringing, and the rainbows;
- the trip clock runs up to 2.2x faster, integrated in BR_Trip so pushing never jumps a phase.

The object warps are capped (breathe 12%, slump 0.22, twist 1.6 rad) where the march would starve,
since every amplitude raises the warp's stretch bound. BR_Trip's canvas shows the total dose in its
header and a thin overdrive bar under the dose.

**Anchors attach to features the room already decided**: the rug medallion, the ceiling over the
pendant, the longest plain wall, the chimney breast, the mantel, a picture, the sofa and the coffee
table. They follow those features when the room changes. Kinds are BREATHE, MELT, SWIRL, BLOOM and
FLOW. One trip clock is integrated in BR_Trip, so tempo changes never jump a phase. A dose envelope
is either **Steady**, **Waves** (the default: it comes and goes) or **Come Up**. Re-roll redraws
relationships (which feature each kind lives on) with guarantees, not free coordinates.

## Light

- Physical Kelvin colours: a 2700 K lamp is deep orange in linear light. The **camera white balance
  (4300 K)** in BR_Lens makes the room read warm and inviting rather than orange.
- Filmic view: max-channel shoulder for the mid-tones and per-channel compression for highlights, so
  hot lamp shades burn through yellow to white instead of going pink.
- The sun is placed by real solar geometry. Windows pass sun through glass, sheers and a volumetric
  street-tree canopy. Diffuse GI comes from an irradiance-probe volume (multi-bounce), with traced
  glossy reflections, normalised SDF AO, volumetric sunbeams with dust, and temporal accumulation
  while the camera holds still.
- The fire is a light (a lamp record of kind `LAMP_KIND_FIRE`) with flicker, plus volumetric flames,
  char and sparse embers on the logs, and a coal bed.

## The rug

`BR_Rug` weaves a real Persian design procedurally with the same function the renderer samples
(`_shared/br_rug.hlsli`), so what you design is what is on the floor.

- **Families:** Tabriz medallion (default), Isfahan all-over (herati field), Heriz geometric.
- **Palettes:** Tabriz, Kashan, Isfahan, Heriz, built from a table of real dye colours.
- **Weave:** abrash, wear and knot pitch.
- **Direct manipulation:** drag the medallion's tip to size it, drag the border's inner edge to
  widen it, click a dye swatch to step it along a dyer's list. Each handle shows its measure on a
  card while you hover or hold it (medallion size in %, border depth in metres; the Tooltips
  parameter turns the cards off); the all-over
  Isfahan family has no medallion, so it has no medallion handle. Each dye row says which of its
  dyer's six it is, in ink once a hand has stepped it.

---

## Control surface (Scene Group "Breathing Room")

Eight controls. The first seven were each driven through the **open Scene Group Properties panel**
with real widget input, and confirmed with a member-parameter readback and a capture
(`proof/scene_group/`). Furniture was added last. Its group path was written and read back through
the member, but it was not driven through the panel. No camera rows are exposed.

| Control | Member | Verified effect |
| --- | --- | --- |
| Dose | `BR_Trip.dose` | 0 is the sober room; 1 is full replication (39% of pixels change by more than 8/255); 1-3 is overdrive |
| Furniture | `BR_Trip.furniture` | 0 (default): every piece holds its shape; up to 1 the furniture swells, slumps and twists |
| Envelope | `BR_Trip.arc` | Steady / Waves / Come Up (combo, through the panel) |
| Geometry | `BR_Trip.geometry` | 0 has no lattice; 1 shows the star lattice on the breast and ceiling |
| Geometry Motif | `BR_Trip.motif` | Girih → Mandala swaps the lattice family |
| Time Of Day (h) | `BR_Light.time_of_day` | 16:15 sunlit → 19:15 lamplit evening |
| Lamp Dimmer | `BR_Light.lamp_master` | 1.0 → 0.15 drops the room to firelight (mean luminance 67 → 49) |
| Exposure (EV) | `BR_Lens.exposure` | 0 → +2 EV (mean 24 → 44) |

## Presets (project scope, narrow on purpose)

**Frame contracts** on BR_Render are camera parameters only: **Frame - Hearth** (the composed hero,
the saved default), **Frame - Fireplace** and **Frame - Corner**. The camera is meant to be flown, so
recall Hearth before any capture. All three recall correctly (`proof/frame_*.png`).

**Quality ladder** on BR_Render covers the seven quality parameters only (render scale, march,
shadow and reflection steps, GI probes per frame, beam samples, accumulation floor):

| Rung | Scale / steps / shadow / refl / GI / beams / floor | Graph GPU vs Live |
| --- | --- | --- |
| **Laptop** (manifest default, saved) | 0.4 / 128 / 24 / 16 / 512 / 16 / 0.04 | 0.24× |
| Draft | 1.0 / 96 / 32 / 0 / 512 / 16 / 0.06 | 0.75× |
| Live | 1.0 / 128 / 48 / 48 / 1024 / 24 / 0.04 | 1.00× |
| Beauty | 1.0 / 200 / 96 / 96 / 2048 / 48 / 0.03 | 1.10× |
| Hero (capture only) | 1.0 / 320 / 160 / 160 / 4096 / 96 / 0.02 | not measured |

Measured back to back by `.release/laptop-0.6.8/laptop_pass.py` on an RTX 5060 Laptop GPU (8 GB,
Sentinel 0.6.8, heat-soaked at about 100 W, the saved panel layout, the trip running at the saved
dose, the editors idle). Live was 49.0 ms of GPU for the whole graph there, Laptop 11.6 ms. Absolute
cost drifts with the trip's phase and the framing; quote the ratios.

## Performance, and the laptop target

**60 fps on an 8 GB laptop: met on the Laptop rung**, which the project opens on. On the RTX 5060
laptop the graph is 11.6 ms of GPU as opened: BR_Render 10.5 (shade 5.5, gbuf 2.1, probes 1.0,
sunvol 0.9, fog 0.4, resolve 0.3), BR_Lens 0.7, BR_Trip 0.4, and nothing for the five idle editors.
At Live the same graph is 49 ms there (shade 33.8, gbuf 10.5): on a desktop GPU, recall Live or
Beauty from the ladder.

What got it there, in order of what it bought:

1. **Render scale (the temporal upscale).** gbuf and shade fill only the top-left `render_scale`
   part of their full-size buffers, every group past it leaving at once; the resolve
   (`resolve.hlsl`) brings that image up to the full-resolution history sample by jittered sample.
   Each output pixel knows where this frame's samples fell around it; its history takes the nearest
   one as it is, in proportion to how close it landed, and a Gaussian over the nine around it
   stands in only where there is no history. The Halton jitter, in render-region pixels, sweeps
   every sample across the full-resolution pixels it covers. At 0.4 (512 x 288 rendered), measured
   by gradient energy against the full-scale frame: 85% of its detail on a still frame with the trip
   off, 69% with the trip running (it moves surfaces under a still camera, so history stays short),
   68% in a camera pan, against 56% for a plain 512 x 288 bilinear upscale. At 1.0 every pass is
   unchanged. Two things it needed:
   - geometric precision stays at the output resolution (gbuf's hit tolerance and shade's
     material footprints use the output pixel's angle): at the region's coarser angle, rays through
     the window panes snagged in the frame and the street disappeared behind grey;
   - every reader of gbuf or hdr maps into the region (fog, present's diagnostic views).
2. **Probes.** Groups past `gi_budget` still marched their 28 sun-patch rays (their `active` came
   from the patch weight alone), so GI cost 5.8 ms at any budget; they now leave at once (1.7 ms at
   1024, 1.0 at 512), and the budget is a real lever.
3. **Editors on_dirty.** BR_Furnish, BR_Light, BR_Shell, BR_Finish and BR_Rug drew their full
   canvases every frame, tab hidden or not (4.2 ms together on the laptop). They now cook on an
   edit, a viewport event or an upstream change: every pass `time_dependent: false` and ordered by
   `pass:` inputs. Proven: all five drawn on a cold open, `cook_hz` 0 at rest, a BR_Finish click
   selecting F-01 in one cook, a BR_Light sun drag moving the day 16:15 to 13:56. BR_Trip stays
   every frame (its clock).
4. **The lamp shadow ray** steps by the detail field alone: the segment from a surface to a bulb
   lies inside the room box, so the slabs cannot block it, and it no longer creeps away from the
   wall or floor it leaves (about 3 ms of shade at Live).
5. **The furnishing solve.** Every furniture edit re-solves the plan on one GPU thread, and most
   of that solve was the walkway: a 40 x 40 clearance grid that worked out every piece's footprint
   axes again for every cell, then six fast-sweeping passes. The obstacles are now resolved once
   per solve, the sweep keeps the cell it just swept in a register, and it stops at the first pass
   that lowers no cell, since every later pass would repeat it exactly. The published records are
   identical (four layouts compared record by record), and the solve went from 3.9 to 1.7 ms.
   While furniture is being dragged the graph is about 16 ms on the laptop: BR_Render 10.5, then
   BR_Furnish 3.2 with its canvas and BR_Light 0.9 redrawing. It holds 60 fps, with little to
   spare.

Tried and dropped (each measured, each bought under 1 ms or nothing): a per-ray furniture candidate
list (the walk over ~30 object records is not the cost; the near-surface model evaluations are), a
tighter local box per piece, reach-limited AO and normal taps, skipping the lamp shadow where the
lamp is under 4% of the light, coarse geometry for blurry reflections, and a quarter-rate sun
volume. Compiling BR_Render at O3 instead of `fast_compile` took 647 s on the laptop and saved only
2 ms of gbuf; it stays `fast_compile`.

What is left, if the Laptop rung ever needs to be sharper: shade is still most of the cost, and most
of shade is the shadow and reflection marches through detailed furniture (the plants alone are
about 5 ms of it at Live). Cheaper per-model bounds inside the plant and seat models, or shading
the secondary rays at a lower rate than the primary image, are the next levers.

---

## Verified with real input (injected viewport events, each read back)

- **BR_Shell**
  - Drag an opening along a wall and onto another wall: the door slid to 1.38 m from the corner,
    and windows re-host across walls.
  - Drag a wall face: the east wall moved 6.40 → 7.00 m, the plan refit, and the fireplace stayed
    centred.
  - RESET ROOM chip, `0` reset all, click empty space to deselect.
  - After all of this the board was pixel-identical to the clean state.
- **BR_Finish:** click a sample to select it, and BR_Render's **Scope** view shows every surface
  made of it in place (Cognac Leather lit the two lounge chairs; Wall Plaster lit the walls;
  `proof/editors/scope_*.png`). Escape clears.
- **BR_Furnish**
  - Drag a hosted piece: books stay on the coffee table.
  - Drag a floor piece: the armchair moved and the conversation readout went 2.63 → 2.93 m.
  - Drag in the section: the pendant drops.
  - `0` resets everything and Escape deselects; the board was pixel-identical to the clean state.
- **BR_Light**
  - Drag the sun along its path: it snapped to 16:00:39, elevation 17.5°, azimuth 245.5°, which
    matches the solar maths.
  - Select a lamp row, the WARMER chip, and dragging a lamp's light-pool ring all work.
  - Rack on/off switches: the renderer's light count went 6 → 4. RESET ALL works.
- **BR_Trip:** drag an anchor across a fold (ceiling onto a wall); anchor chips, RESET, CLOSE.
- **BR_Rug:** dye swatch click, medallion-tip drag (42% → 51%), RESET.
- **Scene Group:** all seven controls (above).

**Again on the Interaction Lab kit** (Sentinel 0.6.8, injected input on a docked 844x814 panel, each
read back from the records or a capture):

- **BR_Rug:**
  - hovering the medallion tip shows its card;
  - the medallion-tip drag took it 42% → 62% and the border-edge drag 0.34 → 0.48 m;
  - a dye click stepped the field 2 → 3 of 6;
  - the Family chip switched to Isfahan, which dropped the medallion handle;
  - Reset restored every parameter value.
- **BR_Finish:** a click selected M-02 brass and then L-01 leaf, with the header naming it; Esc
  and a click on empty space both cleared it.
- **BR_Trip:**
  - clicking an anchor selected it: the inspector switched to ANCHOR, with its scope curve in
    accent;
  - a drag carried it across the fold from the south wall onto the west wall;
  - Stronger took its strength 0.70 → 0.87;
  - Close returned to the TRIP view, and Reset all put the anchor back.
- **BR_Light:** the sun drag moved the time from 16:15 to 13:40 at elevation 33.8°, and the sun
  patch swung across the plan. Selecting a lamp and the ring hover with its reach readout were
  checked by hand.
- **BR_Shell and BR_Furnish:** both compile healthy and were checked by eye on the kit. Their
  gestures have not been re-injected since the conversion. BR_Shell's reducer is unchanged;
  BR_Furnish's changed only in its knob and grip grab radii, which now scale with the panel.

**Not machine-verified: the fly camera.** Injected right-button drags do not reach the host's fly
camera (the viewport never takes focus from synthetic input), so **RMB look, WASD and wheel speed
need a check by hand** in BR Render's preview. The camera *contract* is verified: the renderer uses
the injected matrices only, `camera_ref` is empty, Fly is saved, and the three frame contracts recall
to visibly different, correctly registered views.

## Exploration axes (shipped enums, swept on this build)

- **Rug family × palette.** All four combinations render correctly (Tabriz/Tabriz, Tabriz/Kashan,
  Isfahan/Isfahan, Heriz/Heriz). Tabriz on its own palette stays the default because it reads
  instantly as a Persian medallion rug.
- **Trip motif.** All four render on the chimney breast. Girih stays the default because it echoes
  the rug; Lattice and Mandala are strong alternatives; Moire is the subtlest (an interference
  sheen).
- **Furniture arrangement.** In the default 6.40 × 5.00 m room only **Hearth** (the default) passes
  every design rule. The others were repaired this session:
  - the side tables now count in the group's footprint;
  - a hearth on a side wall is now a keep-clear zone;
  - the snake plant no longer sinks into the wall when the sofa backs onto it.

  All three now raise **0 alarms**. In a 6.40 × 6.00 m room **Reading passes every rule**, while
  Facing (walkway 0.74 m) and View (walkway 0.56 m, hearth 0.58 m) still miss the 0.9 m walkway
  target. The editor flags this live in red; they need a bigger room, hand edits, or a
  compact-variant pass in the generator. The Shell styles were not swept this session.

## Stability in motion

**Symptom:** standing still the room converged beautifully. Flying through it (WASD at 3 m/s, about
5 cm per frame) everything flickered: lighting shimmered and slid, edges looked like Z-fighting, the
sheers behind the fig flashed, and every lamp and window dragged a glowing smear.

**Cause (measured, Sentinel 0.6.3):** a Module pass that reads a buffer *another* pass writes is
handed it as it stood at the end of the **previous cook**, for scratch and persistent buffers alike.
Only the camera cbuffer, `_Time` and external inputs are current. Proof: gbuf stamped its clock,
camera and scene frame counter into a G-buffer texel. Shade read them back exactly one frame counter
and 1/60 s behind its own, live and in render_sequence. So every pass that mixed the live camera with
another pass's image was wrong by one frame of motion:

- **The TAA** took its "previous camera" from the scene buffer, itself a cook late, and reprojected
  a whole frame of motion off. History was clipped away and the raw jittered frame flickered through.
  This was the dominant cause.
- **Shade and the beams** rebuilt rays from the live camera and walked them through last cook's
  G-buffer, so lighting was computed a frame's motion away from the surface drawn.
- **BR_Lens** read the renderer's image in several passes and saw several frames. Its bloom came
  out of a seven-pass pyramid, seven frames late, and its tracer smeared static lamps. The lens was
  later rebuilt with no tracer and a one-hop glow (see *Walk-through fixes*).

**Fix: self-describing images** (`_shared/br_camtexels.hlsli`). Every image a pass hands on carries
the camera that rendered it in texels (0..19, 0): view-projection, inverse, eye and jitter, as exact
half-float plus remainder pairs (about 22 bits, even in RGBA16F). Every pass that combines images
reprojects each through *its own* camera, never the live one:

| Stage | Reads | Uses the camera of |
| --- | --- | --- |
| gbuf | live camera | writes it into the G-buffer header |
| shade, fog | the G-buffer (a cook old) | the G-buffer's header |
| fogtaa | beams and its own history | each image's header; alpha packs T with ray length (`fogPack`) |
| resolve | shaded image, beams (older still), history | each one's header, reprojected into the shaded image's |
| BR_Lens glow0-3 | the HDR input directly | glow0 copies the input's header |
| BR_Lens grade | the HDR input directly, and the four glow levels (one cook older) | the input's header, and glow0's for the glow |

**Measured on the same 5 cm/frame fly-through** (`proof/stability/`):

| Metric | Before | History camera fixed | Whole chain |
| --- | --- | --- | --- |
| Motion-compensated flicker | 2.17 | 1.79 | 1.64 |
| Low-frequency (haze/lighting) flicker | 0.78 | 0.60 | 0.43 |

The flow metric has a floor from its own resampling, so these numbers understate the change. The
side-by-side crops show it: before, fig leaves were saw-toothed, the sheers blocky and streaked, the
globe and lamp dome trailed stepped copies. After, the same frames in motion look like the converged
still.

**Diagnostics shipped with it:**

- BR_Render **TAA Probe** view: swatches top left. Green means the shaded image, the beams and the
  history each carried a readable camera.
- BR_Lens **Bloom Timing** view: green swatches if the image and the glow each carried a readable
  camera, then one white block per renderer frame the glow trails the image (it shows one).

Other fixes made along the way:

- **Beams accumulate at their own quarter resolution** (fogtaa). There a 3×3 neighbourhood sees the
  march's noise; the main TAA's full-res box could not, and clamped the haze to each frame's noise.
- **Sheers, the view outside and mirrors reproject at the depth their image sits at:** the sheer
  instead of the 500 m window stand-in, the canopy across the street, the mirror's virtual image.
  Shade puts that depth in alpha.
- **The street canopy is sampled on slices fixed to the facade,** not from wherever a ray noticed it
  was outside, so the trees no longer churn as you walk.

## Walk-through fixes

Found by flying the room. Each was isolated with a review view before anything changed.

- **"A weird reflection" low on the back door was the late sun.** At 16:15 it comes in through the
  south-west window 15.5° up, crosses the room, and lands on the bottom 45 cm of the door and
  skirting. The geometry was right; the sun's shadow rays were not:
  - Each ray spent about 20 of its 48 steps squeezing through the 30 cm window reveal past the sash
    bars. Rays from across the room ran out of steps, and running out counted as shadow.
  - So the edge of the patch was a ragged, pixel-noisy line: the jagged white shapes.
  - The window outline was a hard in/out test where the ray met the wall plane.

  The fix is `sunWindowExit` in shade.hlsl, the same test the beams already used:
  - Sun rays leave through a window analytically. They must clear the sashes and muntins at the
    frame plane and the reveal at the street face, and each edge's distance becomes penumbra.
  - A ray that runs out of steps finishes the same way, keeping the penumbra it had measured.
  - Rays from the door leaf's recess switch to the cheap march once they enter the room.
  - The street trees' shadow and the sheer's pleats blur with distance by the size of the sun's
    disk (`brCanopyTransmitPen`).

  It is now one soft-edged patch of low sun, as it should be.
- **The books looked chopped up.** Each 38 mm slot measured the distance to its own book only, so
  rays stepped into taller or leaning neighbours and sawed every spine into stairs.
  - Now each point takes the nearest of the slots that can reach it: two to the left, one to the
    right. A 39 mm cap covers anything further.
  - Outside the row's book slab, the slab distance is itself the bound, and the search is skipped.
  - A book leans only into an empty slot, just far enough to rest on the next book. The last book
    in a row stands upright.
- **The red cushions sat inside the sofa's back cushions.** Placed 0.33 m in from the back edge,
  every throw cushion was 10.5 cm deep in the back. Each now stands where it just rests against
  the back (`cushionRest` in furnish.hlsl), with about 3 mm of squash. The offsets were measured by
  sampling both SDF models: sofas 0.49 m, lumbar 0.47, lounge chair 0.485, wingback 0.45, and club
  chair 0.34 (it has no back cushion). BR_Furnish `PLAN_VERSION` is now 1.3; no hand edits existed
  to lose.
- **The glow and glare lagged the camera by several frames, tracers or not.** Each hop between
  passes is a cook late, and BR_Lens built its bloom through a copy, a bright pass and six pyramid
  steps. The halo of every lamp and window reached the screen seven frames after the lamp did.
  - BR_Lens now reads the renderer's image directly in the grade, with no copy.
  - Each of the four glow levels (1/2 to 1/16) is a tent summed straight from that image
    (`glow.hlsl`), so the glow is one cook old. The grade reprojects it through the camera the
    half-resolution level carries.
  - The **Bloom Timing** view measures it: one frame, down from seven. On a fast pan (about 20 px
    per frame) each lamp's halo stays centred on its shade.
  - The lens costs the same as before: 0.098 ms GPU against 0.10 ms, in 5 passes instead of 11.
- **Tracers removed.** They were too much. The trail effect, BR_Lens's Tracers control and
  BR_Trip's Tracers channel are gone. Slot `look.z` of the trip header now carries the overdrive
  push.
- **Streaks fanned across the wall behind the fig.** They were ambient occlusion, not GI. The
  Ambient Occlusion view showed them and the Beams view did not. The AO taps ask how far the
  nearest leaf is from 2 to 45 cm away. The old leaves were flat ellipsoids with an approximate
  distance, which answered "very near" all along the planes they lay in. The plants are rebuilt
  (`_shared/br_plants.hlsli`) from exact distances: capsules, round cones, and 2D outlines
  (uneven capsules, vesicas) extruded into thin slabs, each scaled by its bending margin.
- **The plants were rebuilt to the room's fidelity, and they are connected.** Pot, soil, trunk and
  branches, and a petiole from the stem to every blade:
  - fiddle-leaf fig: 30 leaves at the golden angle on a wandering trunk and two branches. Each is a
    true violin outline (a wedge into a small lower lobe, a waist, a broad upper lobe) with a waved
    margin. Older leaves hang lower and every blade is turned on its midrib, so from eye height the
    leaves show their faces, not their edges.
  - snake plant: 12 folded, tapering, twisting blades in three clumps;
  - olive standard: a clear stem, seven branches and 42 lance leaves;
  - the coffee-table vase: silver-dollar eucalyptus (six arching stems of different heights, coins
    in clasping pairs turned a quarter at each node), replacing the green balls on sticks.

  Each leaf is shaded in its own frame, rebuilt from its part id: the fig has a pale midrib, arching
  veins and a glossy top; the snake plant has zigzag bands and a gold margin; the olive is silver
  beneath; the eucalyptus is glaucous with a waxy bloom.
- **Each plant moves its own way as the dose rises:**
  - breathe and drift: the fig's leaves open and fold in a wave that climbs the trunk, and its
    crown sways; the snake plant's blades wind and unwind with a ripple running up each; the olive
    head breathes and its leaves flicker in a wave like a shoal; the eucalyptus stems sway and
    their coins turn.
  - geometry: each plant resolves into a diagram of itself. The fig's trunk straightens and its
    leaves level into tiers round the spiral, the snake plant opens into an even twelve-fold
    rosette, and the olive head becomes an even starburst.
- **A lamp shade vanished and its stand showed through.** Two faults, both fixed:
  - The table lamps' shade distance was not exact. It measured horizontally to the tapered drum,
    over-reading by 1/cos(taper), about 4%. Seen from above, a ray stepped clean through the 5 mm
    wall, and an arch of the shade showed the stem and bulb inside: captured at the user's own view.
    `shadeShell` is now the exact distance to the profile segment in the (radius, height)
    half-plane. The paper lantern uses a scaled-sphere bound instead of the approximate ellipsoid.
  - The trip's twist took a piece's stretch bound from its footprint box. The arc lamp's dome
    hangs 1.42 m from its foot, five times the box, so the bound was about 5x too small. Objects
    now carry their true radial reach (`fkRadialReach`, `SC_OWARP0.dims.z`).

  On top of that, lamps no longer warp at all. Their trip is the rainbows in BR_Lens, and an
  anchor dropped on a floor lamp in BR_Trip lands on the floor under it. The earlier flicker near
  the lamps while zooming was most likely the first fault, since its overshoot grows with
  distance.
- **The picture behind the sofa read as a frame inside a frame.** The print was sunk 2 cm into a
  3 cm black box, and the box's inner walls read as a second frame. It is now a framed print:
  - a moulding with a raised outer rim stepping down to an inner flat;
  - a cream mat just behind it, cut with a 45-degree bevel whose white core outlines the image;
  - the print 3 mm behind the mat, under glass (a faint, sharp clear-coat reflection).

  The old six-leaf doodle is replaced with a watercolour pomegranate study: a branch of 13 leaves,
  a hanging fruit with its shadow graded across it, a young fruit, a cut half with irregular
  chambers and glossy arils (straight spokes read as an orange), and a scarlet bud. The washes
  pool at their edges and granulate, over a broken sepia pen line. Its edges and paper grain widen
  with the pixel footprint, so it holds still from across the room. Its u axis runs to the
  viewer's right, which is the piece's local -x: the camera is left-handed, and the first version
  read mirrored.
- **A blocky dark smear between the rows of books.** The bookcase's back board shared the case's
  varnish, so it mirrored the room behind the camera, and the traced reflection broke into blocks.
  The back board is now its own part (`FP_BACK`), matte and a shade darker: there is nothing to
  mirror there.
- **Flicker near the lamps when moving in and out.** Scripted dollies toward a table lamp did not
  reproduce it:
  - fast, 3.0 m to 0.6 m in 60 frames;
  - slow, 1.6 m to 0.9 m.

  Those dollies looked at the shade from its own height. The hole found later (above) needs a view
  from above, where the over-reading ray meets the sloped wall head-on.

**Cost:** at the close bookshelf and back-door view, single-frame GPU samples put BR_Render at
12-16 ms, with shade between 7.6 and 12.5 ms from one frame to the next. The same view measured
12.0 ms before these fixes. Run-to-run noise is larger than any difference the fixes make: the book
search costs more where a ray grazes the shelf, and the analytic window exit saves about 20 steps
on every sunlit pixel. The slot search keeps no local arrays. Wrapped in a branch, the array
version read 11.1-12.5 ms in shade over four samples, against 7.6-12.0 ms without arrays. That is
within the noise, but in the wrong direction for code that does less work.

## The editors' UI kit

The six editor canvases are built on the Interaction Lab UI kit: `modules/_shared/ui/`, vendored
from `projects/interaction_lab`, with its IBM Plex type atlas in `modules/_shared/type/` (SIL Open
Font License, beside the atlas). Each editor is four passes:

- **the reducer** (`shell.hlsl`, `finish.hlsl`, `furnish.hlsl`, `light.hlsl`, `trip.hlsl`,
  `rug.hlsl`): one thread; it consumes viewport events once each, by sequence, and owns the
  persistent records;
- **`plate.hlsl`**: the per-pixel drawing (plan, elevations, section, sun chart, the woven rug, the
  shaded samples), with no text;
- **`layout.hlsl`**: every caption, rule, chip, handle, card and readout, recorded into a draw list
  (`buffer:dl`);
- **`ui.hlsl`**: the kit's shared rasterizer, which draws the list over the plate.

The reducer, the plate and the layout share one layout header per editor (`*_layout.hlsli`), so
every hit test and every drawn rect come from the same functions. Sizes follow the panel through
the kit's ui scale (1 at 1280x720), and drag targets keep a minimum size in pixels. Colour follows
the instrument palette: grey chrome, amber only for the selection and a live reading such as the
trip's NOW line, red only for a broken rule, and a record's own colour where it stores one.
The cards and tags that pop up beside the pointer (BR_Rug's handle cards, BR_Light's time cards
and lamp reach, BR_Trip's anchor names) sit behind each editor's Tooltips parameter, on by
default: turn it off to keep the canvas clear while you work.

Captions live in each editor's `labels.txt`. After editing one, regenerate that editor's table:
`python tools/il_type.py labels BR_Rug` (always name the Module: a bare run rebuilds every
Module's labels). `python tools/fxc_check.py BR_Rug layout --Od` compiles one pass offline with the
live optimisation level, in seconds instead of a reload round trip; Sentinel's `compile_check` stays
the final word.

## Traps hit on the way (read before editing)

- **A shadow ray that runs out of steps is not in shadow.** It was grazing something, and it has
  already measured that penumbra. Calling it black drew the late sun's edge as a torn, noisy line.
  Find such bugs with a three-colour view of the shadow job: escaped, blocked, ran out.
- **A per-slot distance is not a bound** once the contents vary in height or lean. Evaluate every
  slot that can reach the current one.

- **A pass reads other passes' buffers a cook late** (0.6.3; see *Stability in motion*). Never mix
  the live camera with another pass's image; read the image's own header (`br_camtexels.hlsli`).
  Read an external input once. Keep filter taps off header texels (`nearCamTexels`).
- **A review view must not blank the shaded colour.** `if (view != 0) col = diag;` in shade sent
  Raw Shade (11), the TAA Probe (13) and Scope (17) a black frame, so Scope showed only the haze.
  Only the views shade draws (1..10) replace it now.

- **FXC drops stores made before a mid-body `continue` in a `[loop]`.** It hit three times:
  - BR_Light's rack switch never toggled.
  - BR_Furnish's drag path published a half-resolved plan: dragging the book stack resized the
    rug to its catalogue size.
  - BR_Shell's loop had the same shape.

  Every editor's event loop is now single-exit, and BR_Furnish resolves once more after the loop
  whenever an event was handled. **Write event handlers with no `continue`.**
- **Signature-gated generators keep the records from their last real cook.** A bad edit-path
  result persisted indefinitely, and old-build records can survive a recompile. After touching
  generation code, bump `PLAN_VERSION` *and* exercise an edit; idle output proves nothing about
  the edit path.
- **An SDF early-out must return a lower bound** (`d - reach`), never `1e9`; the march stepped
  through the crown moulding and punched slots in it.
- **Reserved words:** `decl`, `half` and `pass` fail to compile as identifiers.
- **Kelvin light needs a white balance.** Without it the whole frame is orange. A per-channel
  highlight roll-off stops orange highlights turning pink.
- **The ceiling lattice vanished** while its footprint was divided by N·V. Use the isotropic `t·pa`
  footprint.
- **The watcher can miss manifest edits** (a new data pin did not appear): use `force_reload`.

## Proof

`proof/` is gitignored and regenerated on demand:

- `bundle/`: proof bundle on BR Lens (graph, links, health, profile with GPU timings, output, window
  screenshot), with a sober-vs-full-dose diff (81% of pixels change at all).
- `motion_defaults_12s.mp4`: 718 frames at 60 fps of the default trip (Waves, dose 0.5).
- `frame_hearth_final.png`, `frame_fireplace.png`, `frame_corner.png`: the three frame contracts.
- `scene_group/`: before/after pairs for every group control.
- `editors/`: editor states mid-edit, the two Scope captures, and `furnish_rug_bug_before_fix.png`,
  which shows the rug resizing when a book stack was dragged, before the loop fix.
- `stability/`: before/after crops of the 5 cm/frame fly-through (fig and floor lamp, globe,
  floor), and the TAA and lens camera-header swatches.
- `walkthrough/`: the back door as reported, the sun shadow job's three-colour outcome (green out,
  red blocked, blue ran out of steps), the late sun before and after, the books before and after,
  the sofa cushions after, the lamp dolly crops, the Bloom Timing view (one white block: the glow
  trails the image by one frame), and a fast pan across the lamps with the halos centred. Also:
  - the table lamp's shade hole before and after (same pose);
  - the fig and the table lamp's rainbow aura at the user's parked view;
  - the lamp rainbows at dose 0.6 and 2, the eucalyptus, and the arc lamp beside the print;
  - the print and the snake plant;
  - the bookcase back as a matte board at the user's view, without the reflection smear;
  - the overdrive at dose 3 on the walls and curtains;
  - the tailored trip at dose 1, two seconds apart: the rug and the parquet (with difference
    images: the border motifs and field flowers moved, the herringbone and its grain crawled), the
    print (the branch swaying, the fruit swelling), and the book spines and the oil canvas.

**Not verified:** the fly-camera gestures (above), the laptop frame rate, a long-run soak, and an AI
vision review (none was run). Trip motion was judged by eye from recordings, not by an automated
motion evaluation. Stability in motion was proven with render_sequence camera tracks, not with
hand-flown WASD; fly it to confirm.
