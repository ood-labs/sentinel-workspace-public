# Flat Cartoon Look in 3D (and Recursive Zoom Loops)

Techniques proven building `projects/droste_heads/` — a seamlessly looping,
raymarched 3D SDF rebuild of a flat 2D cartoon reel. Read this before any job
whose reference is *drawn* rather than rendered, and before any droste /
infinite-zoom loop.

---

## 1. Draw the drawing. Do not model it.

The single biggest mistake on this build, and the one that cost the most
iterations: the face was authored as 3D geometry — spheres for eyes, capsules
for brows, a cone for the nose. It read as a puppet, and **no amount of
numeric tuning fixed it, because the medium was wrong.** A flat cartoon face is
ink art painted on a shape: the nose is a *line*, the eyes are flat discs,
nothing has volume.

The working architecture:

1. **Measure the reference numerically.** Connected-component analysis over the
   frame (`scipy.ndimage.label` on colour masks) gives exact centres, radii and
   stroke skeletons. Normalise everything to one unit — head half-width — with
   a fixed origin (the seam). Do this for *two* frames in different states; it
   is how we learned the pupils dilate 0.40 → 0.60 between calm and surprised,
   and that the closed mouth is a different shape from the open one.
2. **Author the drawing in those same units** in a project-local shared include
   so the constants in the code ARE the measurements. 2D SDF primitives only:
   tapered bezier strokes, discs, lens shapes.
3. **Verify it in 2D first.** Build a throwaway-looking but permanent sketch
   node (`DH_Face`) that renders the drawing flat over a head silhouette, and
   compare it against a crop of the reference taken through the *same* window.
   Then measure your own render the same way you measured the reference and
   diff the numbers. This loop is fast, and it catches errors that are
   invisible once a raymarcher is in the way.
4. **Only then project it onto the 3D surface** as a decal, in `classify()`,
   returning material ids. Delete the 3D face geometry entirely — the SDF gets
   simpler and compiles faster.

Judging a crop against a reference crop is only valid if both are cropped to
the same normalised window. An unequal crop makes features look bigger and
sends you chasing a scale error that is not there.

### Hand-drawn references are asymmetric on purpose

The artist drew a 3/4 view onto a frontal shape: all features live in one half
of the head with a big empty cheek on the other side, and the two eyes are
deliberately *different sizes*. Never centre or mirror them, and do not try to
recover the asymmetry by yawing the 3D head — draw it in.

---

## 2. Painting art onto a 3D surface

Two corrections are required, and both are invisible until you measure.

**Flatten the cross-section.** A circular revolve squashes decals toward the
silhouette. A shallow ellipse (depth ≈ 0.45 of width) keeps z nearly constant
across the face and cuts the compression. A rounded *slab* flattens even
better, but it turns rim and lid cuts into rectangles — if the design has
circular cut lines, the ellipse is the right trade.

**Make chart space equal screen space.** Screen x is `x/(D − z)`, so even on a
shallow section a decal read straight off local x still compresses toward the
cheek. Pre-compensate:

```
u_chart = u_surface / (1 − k·sqrt(1 − u_surface²)),  k = halfWidth·depth / cameraDist
```

Measured roundness of the far eye went 0.63 → 1.00. Use a nominal camera
distance, not the live one, or the art breathes when the camera moves.

**Wall thickness under a squashed section.** Shrinking a shallow ellipse's
radius by `wall` only thins it by `depth·wall` in Z. Offset the SDF by a true
distance instead (`dhCross(...) + wall`).

**Keep classify() byte-identical to the SDF.** When the shell distance and the
classifier compute the surface with different formulas, whole faces classify as
the wrong material — here the lid rendered as its own red interior across the
front. If the SDF changes, change the classifier in the same edit.

**Exclude painted ink from the outline pass**, or every black mark is dilated
back into a slab. Skip edges touching the ink material; solid-colour regions
like eye whites still outline against the head, which is the ring weight the
reference has anyway.

---

## 3. Model the parting surface, not added hardware

A latch/notch where two parts separate is **one jogged cut**, not a tab plus a
socket. Subtract a block from part A and let part B *keep* that same block
(box ∩ shell, evaluated in B's moving frame). Closed, the pieces reassemble
into an unbroken form; open, each carries its half of the jog. Three wrong
attempts preceded this: a through-window (you could see the child through it),
a blind pocket, and a radially protruding tab that read as a glued-on cube. The
tell in the reference is that every notch face is *cut* material and nothing
breaks the silhouette.

Related: a notch through a shell wall is a window. If you do not want to see
what is behind it, make it a **rebate** that leaves the inner skin standing.

---

## 4. Reveal materials progressively, never on a boolean

Gating a material on a single state test (`lidAngle > 0.12`) makes the whole
region flip on one frame — a visible pop. Gate on the **local** quantity
instead. For a hinged lid, the gap at a point is `distance-from-hinge-axis ×
sin(angle)`, so the cut lip is revealed where the lid has actually parted and
sweeps around toward the hinge. Same rule applies to any "is it open yet"
material decision.

---

## 5. Recursive-zoom (droste) loops

**Animate the world, not the camera.** The internal-camera contract forbids
shader-local camera animation, and it is also the better technique. Place
generation `g` at phase `p` by `σ = s^(g−p)` about the similarity's fixed point
`F = c/(1−s)`. The frame at p=1 equals p=0 with generations relabelled, so the
loop closes exactly and the camera stays genuinely flyable.

- **Cheat rule:** every per-generation cheat must be a pure function of the
  generation's age or relative scale, and identity at integer ages. That covers
  birth scale, rise, and feature fades.
- **Cull far enough out.** A hard cull that fires mid-cycle is a pop once per
  generation. Push it out until the departing shell's remaining pixels are flat
  colour already covered by the next ancestor, and add a generation to spare.
- **Ancestors are the set.** Previous lids and cavities supply the "background"
  for free; only the sky is a real backdrop.

### Deterministic capture of a loop

Module `_Time` counts *cooked frames*, not wall seconds — an idle cheap node
free-runs far above display rate, so an in-module clock drifts in wall terms.
Never record a loop off live playback. Instead:

1. Park the clock (`speed = 0`, snapping the accumulator to a cycle boundary).
2. Expose a `scrub` parameter on the FINAL node and drive the plan's phase from
   it with an expression, so `sweep_record` on the final node scrubs the whole
   graph deterministically.
3. For a palette that rotates per generation, **rotate the palette instead of
   advancing the clock** — rotating colours one slot is exactly equivalent to
   advancing one generation, so N colour-phases can be rendered back-to-back
   with no clock wrangling, then concatenated into the full-period loop.

**Trap:** `force_reload` silently drops expressions. Re-check
`sentinel_expression list` before any capture that depends on one — a dropped
bridge records a frozen frame that still looks plausible in a thumbnail. Always
verify a recorded loop numerically: joins should be no larger than the peak
within-segment frame difference.

---

## 6. Working method

- **Judge from the image, then from numbers.** Every visual claim here was
  settled by measuring pixels, not by reasoning. When a look is wrong, measure
  the reference and measure your render in the same units and diff them.
- **When several fixes in a row make something worse, the model is wrong, not
  the numbers.** Stop tuning and rebuild the abstraction (face-as-geometry →
  face-as-drawing; tab-and-socket → parting cut).
- **A separate design surface pays for itself.** The 2D face node made an
  intractable 3D problem tractable, and it stays in the project as an
  inspectable node.
