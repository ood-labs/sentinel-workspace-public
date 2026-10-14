# Fixture Gates

Run these in order for each fixture. A gate passes on recorded evidence: captures you actually viewed,
GPU record readbacks, measured timings. Compilation, a non-empty texture or a pleasing oblique view is
not a pass. Write expected versus observed behaviour and the result for each gate in the project's
README or `docs/PROOF.md`, along with thresholds, capture conditions and exclusions.

These gates were proven over fifteen spec-sheet fixtures. The bugs named under each one are what it
caught.

## G1. Identity, geometry and mounting

- Build one fixture, stationary, at an inspectable scale, one semantic node at a time.
- Capture front, oblique and rear, and compare them to the drawing and photos named in the fact sheet.
- Assert:
  - the exact emitter or zone count and arrangement;
  - the distinctive silhouette;
  - lens depth;
  - attached pivots and yoke arms.
- Audit measured dimensions against the fact sheet (skill step 2).
- Exercise the mount separately from aim: bracket rotation, fold, removal and hanging inverted.

Caught: floating heads, a substitute bowed arm, clipped bounds, an unexplained extra row of emitters.

## G2. Dimming and optics

- Freeze motion. Take each independent region to 1, 0.1, 0.01 and 0 with gain, exposure and haze
  held fixed.
- Subtract a matching black baseline so lighting is measured apart from the housing.
- At 0, illumination disappears, though worklight reflections may remain.
- Then the optics from the fact sheet. Exercise every one and capture the extremes:
  - zoom extremes, in beam degrees;
  - every gobo slot, indexed rotation and continuous rotation;
  - prism on and off, and its rotation;
  - frost, iris and focus;
  - every colour slot and mix extreme.

  The projected pattern and the beam volume must read the same mask.

Caught: a permanently lit flat-colour lens, a black cover substituted for blackout, a beam that did not
follow the dimmer.

## G3. Addressing through the real inputs

Pixel and multi-zone fixtures. For a single-source fixture, mark G3 N/A and cover its control in G8.

- Document the zone contract first:
  - logical rows and columns per section;
  - first and last ids;
  - origin and order looking at the front;
  - the sampling rule (cell centres);
  - colour interpretation;
  - which helper owns the conversion.
- Disable fog and bloom, freeze motion, and capture straight on with a temporary, disclosed framing
  that you restore afterwards.
- Drive one address at a time through the actual upstream input (content texture or DMX decoder), not
  a renderer-only solo.
  - Check the target's GPU record and that every non-target stays dark.
  - Define the image regions from known geometry, never from guessed screenshot positions.
  - Cover first and last addresses, neighbours, row transitions, each primary and black.
- Run a slow one-cell chase and asymmetric content visibly, in the right direction.
- Check the programmer or map preview's masks against the renderer separately. A preview defect is
  fixed in the preview.

Never infer orientation from symmetric content. Caught: a reversed X origin (fixed in the topology
helper, not by flipping content), preview dividers chopping cells, an address bank sampled between
cell centres by a filtering sampler.

## G4. Motors

N/A for static fixtures; say why and prove the manual mount instead.

- **Endpoints.** Feed 0, 0.5 and 1 per channel, then asymmetric spatial ramps across an array.
  - Compare the settled GPU poses to expectation within 0.05°.
  - Motion textures are 32-bit float. An 8-bit texture quantised the midpoint by about 1°.
- **Speed.**
  - Make a large jump at slow and fast speed, and compare the angle travelled with elapsed time and
    the cap derived from the spec's travel time.
  - Zero speed holds.
  - Continuous rotation wraps and reverses without the housing and beam separating.
  - Accumulate elapsed time with compensation: naive float accumulation drifted 0.1°.
- **Fallback.** Manual targets take over when the motion input is disabled or missing.

## G5. Atmosphere

- Use narrow cones for beams and a few binned sources for broad pixel faces, averaged from the real
  pixel colours.
- Exercise:
  - regions separately and together;
  - primaries and RGB white;
  - a travelling chase (the fog moves with it);
  - zero haze (faces stay lit, no scatter);
  - blackout;
  - near and far reach;
  - grazing views.
- Inspect a close oblique view with lit haze in front of and behind thin brackets and rims.
- Compute fog against the full-resolution nearest-surface depth and apply extinction once.

Caught: black outlines on thin brackets from half-resolution fog; doubled extinction in a mixed scene;
a narrow beam clipped at a diffuse fixture's cache boundary.

## G6. Scale

Only when an array is requested. A one-fixture study skips it and says so.

- Build exactly the requested count; 100 in a 10 × 10 is the established test. Replaceable colour
  content spans the whole arrangement, independent of motion, and each head samples its own motion
  target.
- Measure at a fixed camera, resolution and preview state, at 1280 × 720, over a 10-second window.
  - The target is 30 Hz or better, with 60 Hz desirable.
  - Publish the conditions and keep CPU cook rate separate from GPU timestamps.
- If it is over budget, optimise traversal, bounds, LOD, source bins and volume resolution, then
  rerun G1-G5.
- Never silently reduce the count or turn off required atmosphere. A smaller passing array is
  evidence, not a pass.

Caught: three fixtures between 19 and 29 Hz, fixed by binning fog sources and trimming samples.

## G7. Save, reload and reuse

- Save the isolated study and the array as their own entry points, each with:
  - a project-local dependency closure;
  - useful default content;
  - a camera-only frame preset;
  - a quality ladder (Hero capture-only).
- Reload, then:
  - verify the module paths rebound to the project;
  - exercise the controls;
  - capture the restored look.
- Exercise canvas gestures with `sentinel_ui action=click_at` and `drag_at`, and confirm delivery with
  `/sentinel/pipelines/<id>/viewport/delivered_boundary_count` before reading back the state they
  changed. List anything left for a hand test.

## G8. DMX personality (when the fixture takes a console)

- Generate the decoder's channel table from the fact sheet.
- Patch the decoder at a non-trivial address (not 1), in a universe other than DMX In's first, so
  record lookup by metadata address is exercised.
- Loop DMX back inside Sentinel and script a sweep. Step every simulated channel through the boundary
  values of every range, setting prerequisite channels and latches before dependent ranges.
  Read back the decoded attribute each time, and confirm the fixture responds the way the G2 and G4
  captures showed.
  - Fine channels move the attribute between coarse steps.
  - Default values match the manual.
  - An array decodes fixture `i` at `start + i * footprint`.
- If the user has a console or QLC+, repeat a short sample from it.
- List the ranges that are approximated or ignored.
