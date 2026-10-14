---
name: equipment-from-specs
description: Recreate real stage equipment in Sentinel from its manufacturer documents - lighting fixtures (moving heads, beams, washes, strobes, blinders, pixel bars) with their real dimensions, optics, gobos, prisms, colour system, zoom, motors and DMX channel layout, plus truss and rigging hardware, speakers and line arrays, generators and vehicles - with every number sourced, correct mounting, and proof against the spec. Use when a user supplies a spec sheet, user manual, DMX chart, dimension drawing, product page or model name and asks to build, recreate or add that equipment, asks for a console-drivable fixture or a fixture library, or wants a previz rig built from real gear.
---

# Equipment From Specs

The user hands you the documents; you hand back a physical simulation whose every number traces to a
source. A recreation is only as good as its fact sheet, so the fact sheet comes first and the
geometry second.

Read `knowledge/stage-equipment.md` before building: it holds the conventions, record contracts and
rigging rules this skill relies on. Use `module-authoring` and `procedural-geometry-authoring` for the
Modules, `knowledge/internal-camera-template.md` for any 3D renderer, `knowledge/precise-construction.md`
for dimension audits, and `dmx-show-control` with `knowledge/lighting-and-show-control.md` for the DMX
nodes. When the equipment becomes a playable rig, `stage-rig-authoring` owns the show layer.

## 0. Ground rules

- **Documents stay out of the project.** Keep PDFs, drawings, photos, gobo images, CAD and GDTF files
  in a folder outside any project the user might share, such as `<workspace>/sources/<item-id>/`.
  The project carries facts with their sources, never the documents. Gobo images are traced into
  procedural masks. Use an image itself as a mask only in the user's private project, with their
  agreement, loaded from the sources folder, never copied into anything shared.
- **Claims stay inside what was built.** A recreation is visual and behavioural. It is not calibrated
  photometry, a structural calculation or a rigging approval. Never call anything safe, load-rated,
  certified, structurally sound or ready to rig. Weight and power are documentation only.
- **Name the model to identify the source, never to imply endorsement.**
- **Scope is what the user asked for.** One fixture is an isolated study, not permission to build a
  hundred-fixture scene: array and scale work (G6) runs only when an array is requested. Say which
  stages and gates below you will run.
- Follow the workspace manual: live discovery, one node at a time, preserve the user's projects and
  camera, never take over their mouse for convenience.

## 1. Build the fact sheet

Copy `assets/equipment-spec.yaml` (in this skill's folder) to `<project>/docs/specs/<item-id>.yaml`
and fill it before creating a node.

1. **Ask for the documents** the item needs:
   - every family: the product page, the user manual and the dimension drawing;
   - fixtures: also the DMX chart and the photometric sheet, plus the GDTF file if the user can get
     it. It is often behind a login, and it is the most structured source for modes, wheels and slot
     order;
   - speakers: also the rigging manual.

   Use the latest dated revision, and work to get it before giving up:
   - Manufacturer sites often build download lists in the browser, so a plain fetch shows none. Read
     the page's embedded data (for example a `__NEXT_DATA__` JSON block).
   - Search the manufacturer's domain for the document by name. Filenames can be case-sensitive.
   - Use the manual's changelog to learn which chart version is current.
   - A third-party mirror is acceptable only as a copy of the manufacturer's own file with the same
     title and revision. Record it as a mirror.
   - Otherwise ask the user to download and hand you the file.
   - Never fill a gap from memory.
2. **Look at the pages before transcribing.** Rasterise and view the dimension drawing, the DMX chart
   and any gobo or zone diagram, with PyMuPDF (`fitz`), poppler's `pdftoppm`, or your own PDF reader.
   If none is available, ask the user for page screenshots. Extracted text is not geometry, and
   dimension figures are often vector outlines with no text at all. Calibrate a drawing's scale from a
   dimension it states, and check it against a second one.
3. **Give every value a status and a source:**
   - `sourced`: stated in a document, with its page;
   - `derived`: computed, with the formula;
   - `inferred`: read off a drawing or photo by proportion, with the method;
   - `assumed`: a labelled guess the build needs. List every one in the README.
   - `not-stated`: no document gives it.
   - `absent`: the model does not have the feature.

   Add `weak: true` when the evidence is thin.
4. **Record every conflict and its decision.**
   - **Control facts** (channels, ranges, resolution, slot-to-value order): the GDTF file or the DMX
     chart wins. Product pages often claim 16-bit or features the chart does not have.
   - **Optical numbers:** the photometric report wins.
   - **Everything else:** a dated manual beats a data sheet, which beats product-page prose, which
     beats a hero image.
   - **Dates:** among documents of the same kind, the newer one wins unless only the older states the
     value.
   - **Within one document,** a specific table beats prose. Record both readings.
   - **Photos** settle counts of visible features, but not order. Tie a gobo or colour slot to its DMX
     value only from the chart or GDTF; otherwise mark the mapping `weak`.
   - Real cases:
     - "216 mm" was body height, not depth.
     - A manual gave both 10 and 12 emitters.
     - A hero image showed a 30° beam where the data sheet said 3.5-24°.
5. **Separate the quantities that look alike:**
   - emitter packages vs control zones;
   - beam (50%) vs field (10%) angle. Manufacturers often pair a beam angle at one zoom end with a
     field angle at the other; label each endpoint. Note whether the manufacturer's "field" is
     really 10%. Some optical modes (often set by a gobo or beam-shaper channel) switch the zoom
     range, so record each range;
   - body vs bracket-included envelope;
   - the pose a height applies to;
   - enclosure extents vs protruding hardware.

Then state a short plan:
- the silhouette and the parts that carry it;
- the origin and mounts;
- the control contract (zones, motors, channels);
- the optical approximations;
- the stages and gates you will run.

## 2. Isolate one item (all families)

Build one item, stationary, at an inspectable scale, with a camera-only frame preset and a Live
default quality.

- Match silhouette, proportions, hard and soft edges, emitter or driver layout and attachments
  before detail. Skip detail that does not survive normal viewing distance.
- Model the mount separately from aim: a bracket rotates about its real attachment and can fold or be
  removed; a cabinet seats on its anchor; a truss part mates by its ports.
- **Audit the dimensions** against the fact sheet with a measured readback from the live geometry,
  not by eye. Use the audit lane in `knowledge/precise-construction.md`, or a project-local audit pass.
  The audit must be able to fail: move something deliberately and watch it report.
- Capture front, side, top and oblique views and compare them to the drawing. Fix structure before
  materials.

**Gate:** the views read as the item, measured dimensions match the fact sheet within the tolerance you
state, and nothing floats, clips or escapes its bounds.

## 3. Behaviour by family

### Lighting fixtures

Run the gates in `references/fixture-gates.md` in order. In outline:

- **Emission.** Dim each zone through 1, 0.1, 0.01 and 0 to a true blackout. Surface, beam and haze
  follow one actual output. Keep radiance, dimmer, haze and exposure as separate controls.
- **Optics and effects from the spec.**
  - Zoom in beam degrees, with field interpolated, per optical mode. Infer missing endpoints from the
    photometric plots and label them `inferred`.
  - Gobo wheels slot by slot, with stable ids. Draw geometric gobos procedurally and approximate
    artwork gobos.
  - Indexed and continuous gobo rotation, plus shake.
  - The prism's facet count and rotation.
  - Frost, iris and focus.
  - The colour system the spec describes: CMY, colour wheel with split positions, CTO, or additive
    RGBW/RGBA.
  - Strobe ranges.
- **Motors.**
  - Ranges come from the spec, and speeds from its stated travel times. For example, 540° pan in
    2.6 s gives about 208°/s.
  - Many fixtures publish no travel time. Then use the fastest commanded move time from the DMX
    chart, or an `assumed` speed, and say that G4 proves the limiter against that labelled value,
    not against the real fixture.
  - Target and actual are separate; actual is limited by elapsed time.
  - Housing, lens, beam and haze all read the actual pose.
  - Time a large jump at slow and fast speed.
- **Addressing** (pixel and multi-zone fixtures; a single-source fixture is covered by G8). Document
  the zone origin and order, then drive one address at a time through the real input and check that
  every other address stays dark.
- **DMX personality** (when the fixture should take a console):
  - Write a small generator in the project's `scripts/`. It reads the fact sheet's `dmx` section and
    writes an HLSL include: the attribute index table, the range tables, dependencies and interlocks.
    Never hand-type the table.
  - Build a decoder Module that reads the DMX In port at a patch (universe and address as the console
    counts, plus mode) and publishes a per-fixture attribute state.
  - Prove every channel range by loopback.
  - The contract and proof are in `knowledge/stage-equipment.md`.
- **Scale** (only when an array is requested). Build it (100 is the established stress test) with
  independent content and motion per fixture. Measure the frame rate under stated conditions, and add a quality ladder only for real
  costs.

### Truss and rigging hardware

- **Build a parts catalogue from the profile facts:** straights at stock lengths, corners, junctions,
  base plates and hardware. Every part carries ports and chord mount intervals.
- **Assemble with a port solver** that connects and closes loops, as described in
  `knowledge/stage-equipment.md`.
- **Enforce its refusal rules:**
  - each port connects once;
  - end patterns must match, or there must be an explicit adapter;
  - clamps go on main chords only, sized to the chord, inside the usable interval, off brace junctions
    and never overlapping.
- **Prove it:**
  - unit tests for the solver;
  - live ports and mount frames read back from the GPU against the CPU solve;
  - a sampled clearance audit across hinge poses;
  - worklight inspection before haze.
- **Report it as geometrically checked, never structurally checked.**

### Speakers, power and vehicles

- **Speakers.**
  - Drive the envelope, taper, splay, drivers, grille, handles, runners and rigging points from the
    drawing.
  - Name the anchors (`ground`, `stack_top`, `front`).
  - Stack only what the manufacturer supports.
  - Give a line array a full per-cabinet pose, with joints inside the splay range and zero hinge gap.
- **Generators.** Model the enclosure, skid, louvers, panel and exhaust, and publish the skid frames as
  mounts.
- **Vehicles.** Encode dimensions as relations that refuse invalid sizes. Make door keepouts cover the
  full sweep. The deck publishes mount frames.
- **Audit contact:** a deliberate lift must read back as a gap.

## 4. Integrate into a stage

- **One placement authority** owns every mount. Equipment attaches through 64-byte mount frames.
  Nothing downstream re-derives a position, and a show layer never re-places a fixture.
- **Mount fixtures through their real hardware.** Hung heads hang inverted on a clamp that meets the
  actual tube. Floor equipment seats on a surface that publishes a frame.
- **Check the assembly:**
  - support gaps;
  - equipment against keepouts;
  - clamp rules on every mount;
  - bounds that cover protruding hardware.
- **Patch sheet.** When fixtures take DMX, publish universe and address per fixture from the placement
  authority, and point each decoder at its patch.
- **Hand off for show programming.** For looks, banks, a desk or a Push 2, continue with
  `stage-rig-authoring`.

## 5. Prove interaction and persistence

- **Exercise gestures** on editors and canvases with `sentinel_ui action=click_at` and `drag_at` at
  client coordinates. The panel must be open and in front; a docked tab hidden behind another
  receives nothing. Find a panel's rectangle at `/sentinel/pipelines/<id>/viewport/rect/*`.
- **Confirm delivery** with `/sentinel/pipelines/<id>/viewport/delivered_boundary_count`, which grows
  by 3 per click. Then read back the state the gesture should have changed.
- **Save and reload the project,** then compare stable ids, edited placements, mounts and patches.

## 6. Lock and report

Write the project README. It covers:
- the component map;
- the fact sheet's location;
- the conventions used;
- every record contract and stable id;
- the zone and channel order;
- the defaults and ranges;
- what is sourced, derived, inferred or assumed;
- each gate with its evidence;
- what is approximated, ignored or not yet proven.

Then:
- Save the camera-only frame preset and the quality ladder, with Hero marked capture-only.
- Once the real units are installed and a camera can see them, match the previz to it: published photometry
  can be off by an order of magnitude.
- Keep compilation, still inspection, motion review, measured performance, readback and hand testing
  as separate kinds of evidence. A missing review is not a pass.
- Leave the user's view in an intentional, recoverable state.
- Do not commit or publish without authorisation.
