# Laser Mapping Lab

Map a laser onto a surface. The same graph drives a real laser, and when you don't have one it drives a simulated laser in a hazy warehouse.

The simulated laser is a raw scanner on a tripod, standing 1.4 m left of a drywall mock-up, 5 m back. A video projector on a stand projects the selected content onto a 3 × 1.8 m frame on the drywall, already mapped, as a MadMapper-mapped projector would be.

Because the laser stands off-axis, the standard Alignment Grid lands keystoned and bowed. You map it exactly as you would on site: match the corners, straighten the lines with Scanner Correction, then finish with the handles until the laser grid lies on the projected grid.

It is also a **template for laser content**. Each piece of content is a look: one Module that publishes its projector video and its laser scan together as a **Laser Look** bundle, inside its own Scene Group. A switcher picks the look, so the projector and the laser always show the same thing. Copy the Shapes look to make your own.

Requires Sentinel 0.5.99 or newer (Laser Out Simulate, joint flags, Laser Trace dots, Module canvas panels). Background: `knowledge/laser-mapping.md`.

## First run

1. Open `laser_mapping_lab.sentinel`. Both Laser Outs open on `simulate`: **Laser_Sim** runs armed against a virtual DAC so the previs is live, and **Laser Out #0** (`laserout_0`, the real output) is disarmed with no device. The example has no screen output, so opening it never covers a display. Nothing is sent to hardware.
2. Open **Laser_Previs**. Recall a frame preset on it:
   - **Frame - Operator**: from behind the laser.
   - **Frame - Audience**: from the room.
   - **Frame - Wall**: square to the drywall. Map from this one.
3. Select the **Mapper** look on **Look_Select** (it opens on it). Open **Mapping_Editor** and click into it. Map in this order:
   1. **Corners.** Drag each corner handle onto its target. A corner drag is a perspective change of the whole grid.
   2. **Bow X / Bow Y** (Scanner Correction) until the edges run straight. A laser bows lines inward (pincushion); positive bows them back out.
   3. **Spacing X**, then **Centre X**, until the inner vertical lines sit on theirs. Spacing evens out lines that drift progressively across the grid; Centre slides them all together.
   4. **Spacing Y**, then **Centre Y**, for the horizontal lines.
   5. **Handles and arrow keys** for what's left. Select handles and press the arrows to nudge one screen pixel at the current zoom (Shift: 10, Alt: a tenth). Zoom in or hold Alt for finer steps.

   Scanner Correction never moves the four corners. It is measured from the laser's own centre, so an off-centre laser gets more correction on its far side, as a real one needs.
4. Other editor controls: drag on empty space to box-select (Shift adds), wheel zooms, middle- or right-drag pans. `F` fits the view and `Ctrl+A` selects all.
5. **Reset Mapping** (Properties only, with no hotkey on purpose, because it moves the beam) returns the mapping to a small square at the centre of the field, about 15% of the scanner's reach. It never resets to the full field, so a reset can't sweep the beam across the room. Zoom in and drag it out to the surface.
6. Watch Laser_Previs. You're done when every laser line lies on its projected line, and the laser F sits on the projected F, top-left and upright.

The Properties buttons **Reset Mapping**, **Fit View** and **Select All** fire only once on builds before 0.5.88 (ood-labs/sentinel-bugs#154).

## Laser and projector sync

The laser and the projector reach the wall with different delays. To match them, select the **Mapper** look and set Alignment_Grid's **Pattern** to **Sync Sweep**. A vertical line sweeps left and right on both, from the same clock. The projector also draws a ruler that rides with its line:
- **Top band:** ticks where the line *was* 10, 20, 30… ms ago, longer every 50 ms. A laser line sitting on a top tick is that many milliseconds **late**.
- **Bottom band:** ticks where the line *will be*. A laser line sitting on a bottom tick is **early**.

Read it, then add the lateness to the projector path or take it off Laser Out's **Output Delay**. If the laser is early, add the earliness to Output Delay. Repeat until the laser sits on the projected line. **Sweep Rate** spreads the ticks: faster makes a small offset easier to read. Set Pattern back to Grid for mapping.

## Saving mappings

Mapping_Editor holds one working mapping: a 5 × 5 handle grid and an **Extent**, saved with the project. Scanner Correction belongs to the laser, not the surface, so it lives beside the mapping rather than inside it.

Keep named mappings as node presets on Mapping_Editor:

- **A surface mapping** saves the handles (the `points` state) plus Extent. Recalling it swaps what the laser is mapped to.
- **A scanner correction** saves only Bow, Spacing and Centre. Recalling it leaves the handles alone.

Save these with `params` such as `["state:points", "extent_a"]` for a mapping and the six correction parameters for a correction. The project ships **Wall Mapping** and **DS-3000 Correction** as examples.

Earlier builds had three slots (Mapping A/B/C). The first cook of this build copies whichever slot was selected into the working mapping, once. The old slot and extent parameters stay hidden so older projects still load.

Keep **Alignment_Grid Extent** equal to the mapping's Extent (0.99). A grid larger than the mapped lattice gets extrapolated past the scan field, and those lines go dark.

## Zoning masks

Switch the Mapping Editor to **MASKS** to zone the laser. Masks are drawn on the laser's own field, so re-mapping the surface or changing the scanner correction never moves a zone off its object.

- **Draw:** pick **RECT**, **ELLIPSE** or **POLYGON**, then drag on empty space (Shift makes a square or circle). A polygon takes one click per point. Close it with a double-click, Enter, Esc, a right-click, or by clicking its first point.
- **Edit:** click any mask to select it, whatever tool is picked. Drag inside to move it. Corners resize it and the knob rotates it (Shift snaps to 15°). On a polygon, drag a point, or click an edge to add one.
- **BLOCK / ONLY IN:** Block means no beam inside. Only In means beam only inside Only-In shapes, which is the invert. Several of each combine, and order never matters. Each row also has **ON** and delete. No mask action has a hotkey.
- **Mask Margin** (0.01 by default) grows Block zones and shrinks Only-In zones. The dashed line is where the beam is actually cut. Laser Out moves lit points about 0.003 field units after mapping (measured on the DS-3000), and the margin absorbs that.

Adaptive_Mapping cuts every warped line at the field edge and at every mask edge, then blanks the hidden pieces. Hidden geometry costs no drawing time: each chain of hidden moves becomes one direct jump, timed at **Blank Jump Speed** (1.2 units/ms, just under the scanner's Max Step × point rate). **Min Cycle** (8 ms) pads a mostly-masked shape so it can't run hot. Masks travel inside the Calibration. A Calibration without them, or a line that crosses more edges than the mapper can track, blanks rather than drawing unmasked.

Masks are the editor's `zones` state. Save a venue's zones as a node preset with `params: ["state:zones", "mask_margin"]`.

`scripts/mask_check.py` is the proof. With the laser armed and a look playing, it counts lit samples inside Block zones, and outside Only-In zones, in both the Mapped Scan and Laser Out's Sent Stream. It says how much of the margin Laser Out used, and fails only if light reaches a zone as drawn.

## Content looks

```text
 Scene Group "Mapper":  Alignment_Grid    ─Laser Look─▶ Mapper_Out ┐
 Scene Group "Shapes":  Laser_Test_Shapes ─Laser Look─▶ Shapes_Out ┤
 Scene Group "Trace":   Trace_Canvas ─▶ Trace ─▶ Trace_Look ─Bundle─▶ Trace_Out ┤  collected wirelessly by
                                                                  Look_Select (Mux, Groups mode)
                          ─Bundle─▶ Laser_Split ─laser.a.scan─▶ Adaptive_Mapping
                          ─Out────▶ Laser_Previs Projection
```

- A look is one Module that publishes a **Laser Look** bundle: its projector video plus one channel per laser, keyed `laser.a.scan`. Declare it in the manifest:

  ```yaml
  bundle_outputs:
    - name: Laser Look
      video: Projection
      channels:
        - {key: laser.a.scan, data: Scan Signal, header_records: 1, transition: {mode: handoff, at: mid}, neutral: empty}
  ```

  Draw the video and the scan from the same records, in the same coordinates, so the projector and the laser show the same picture. Author in the 16:9 projection frame: scan (x, y) in ±1 covers the whole frame, so scale x by 9/16 for round shapes (see `Laser_Test_Shapes/shapes.hlsl`). Scans are ILDA scanner space, +y up.
- Each look sits in its own Scene Group with exactly one Group Output fed by the bundle.
- **Look_Select** is a Mux in Groups mode. It collects every look, freezes the ones not playing, and on a switch hands the laser over at the transition midpoint (`fade_time` sets a projector crossfade). Select a look with its button, or write the group id to `selected_group` from OSC or an expression.
- **Laser_Split** (Bundle Split, `keys: laser.a.scan`) takes the laser channel out of the bundle for the mapper. For a second laser, add `laser.b.scan` to every look and to Laser_Split's keys, then build a second mapping chain.
- **Traced looks** start from pixels, not records. In the Trace group, **Trace_Canvas** draws line art (a rotating star, a breathing circle, a travelling wave and a few twinkling single-pixel dots). Laser Trace (**Trace**: Dots on, Y Axis Up, Fit Stretch) turns it into a Scan Signal. **Trace_Look** (Bundle Pack: `laser.a.scan`, Data, neutral Empty, handoff at mid) pairs that scan with the canvas as the projector video, and **Trace_Out** publishes the look. Any white-on-black line image works in place of the canvas.
  - Laser Trace flags each joint it traces as smooth or a corner. Circles and the wave flow, and the star keeps its corner dwells, on one scanner profile (see Joint flags).
  - Every separate stroke costs a blank jump plus the scanner's blank guard on both sides, about 3.5 ms each on the studio profile. A dot is its own stroke, so keep dots to a handful. This look sends a cycle of about 40 ms.
- **Joint flags.** A Scan Signal can say which joints are corners. On a lit record, `timing.z` flags the joint at its start: 1 smooth (no Corner Dwell), 2 corner, 0 let Laser Out judge. On the header, `timing.z` 1 marks the cycle as one closed lit loop, so its seam flows too. Laser_Test_Shapes flags its curve chords smooth and its Lissajous and rose as closed, and leaves straight strokes to Laser Out. That way a spinning Lissajous draws with no holds while SENTINEL keeps its letter corners, on the same End Dwell 8 / Corner Dwell 8 profile. Adaptive_Mapping keeps the flags, marks the joints it makes when it subdivides a stroke as smooth, and clears the closed flag when it hides, clips or pads anything. Don't put anything else in `timing.z`.
- **To add content:** duplicate the Shapes group, point its Module at your own project folder, and keep the `Laser Look` bundle.

## How it works

```text
                                           Mapping_Editor ─Calibration─┐
Look_Select ─Bundle─▶ Laser_Split ─laser.a.scan─┬─▶ Adaptive_Mapping ─Mapped Scan─▶ Laser_Sim ─Sent Stream─▶ Laser_Fixture ─World Scan + Fixtures─▶ Laser_Previs
     │                                          │                                        (simulate)                                    ▲
     │                                          └─▶ Adaptive_Mapping_1 ─Mapped Scan─▶ laserout_0 (real laser)                           │
     │                                   Mapping_Editor_1 ─Calibration─┘                                                               │
     └─ Out ───────────────────────────────────────────────────────────────────────────────────────────────── Projection ──────────────┘
```

The simulated room and the real wall each have their own mapping chain, so mapping the real wall never disturbs the simulation's mapping, and the reverse.

- **Mapping is two nodes, from Laser Stage.**
  - **Mapping_Editor** is where you edit. It compiles the working mapping plus the Scanner Correction into a 32-element Calibration buffer.
  - **Adaptive_Mapping** compiles your content through that calibration. It subdivides a stroke only where the warp actually bends it, within a 0.001 tolerance and a record budget.
  - Both run every frame. Adaptive_Mapping must, or Laser Out's deadman blanks a static scan. Mapping_Editor must, because an idle editor misses real mouse drags (ood-labs/sentinel-bugs#152). Together they cost about 0.3 ms GPU.
  - A corner drag is a pure perspective change, so straight lines stay straight: 26 records in, 26 out. Scanner Correction and edge handles add records only where lines bend: the grid runs about 26 in, 47 out.
- **Laser Out #0** (`laserout_0`) is the real output, fed by **Mapping_Editor 2** and **Adaptive_Mapping 2** (`Mapping_Editor_1`, `Adaptive_Mapping_1`). Its protections (step size, dwell, blanking, duty) apply to what is sent.
- **Laser_Sim** is a Laser Out on `simulate`. It runs the same protections against a virtual DAC and feeds its Sent Stream to the simulated laser, so the previs shows what a real laser would draw.
- **Laser_Fixture** is the simulated laser. It's the scanner optics from Laser Lab's LS_Projector: Hermite scan reconstruction, a 40° × 30° field, and pose and aim. It is **not** a mapping: it stands where your laser stands and does what a raw, uncalibrated scanner does.
  - Its own **Flip X / Flip Y** mirror what it receives; keep them matched to your Laser Out.
  - **Device Mirrors X** models a laser that draws X mirrored with no flips (ood-labs/sentinel-bugs#147). The project ships with Laser Out Flip X off (front projection) and Laser_Fixture's Device Mirrors X and Flip X on. Check the orientation on your own laser (see Real laser).
- **Laser_Previs** is the room. It's Laser Lab's LS_Air renderer, from the BLINK show's previs:
  - analytic single scattering in drifting haze, with separate air extinction
  - the RAW-10 housing and aperture glow
  - the scan landing on the first surface it meets, with shadows from the pallet and road case
  - bloom and lens streaks
  
  The room is a box model in `modules/Laser_Previs/site.hlsli`: drywall mock-up, warehouse walls, steel columns, pallet, road case, tripod, and the video projector on its stand.
- **The video projector** (BLINK_Previs's projector term) lights every surface with the image pixel where its ray meets the wall. The image is mapped onto the 3 × 1.8 m frame. Anything in front of the wall catches the image and casts a shadow, as on site.
  - Its image is Look_Select's video: the selected look's projection, drawn in the same coordinates as its laser scan. That's why a mapped laser lands exactly on it.
  - Controls are in the **Video Projector** group on Laser_Previs: **Projector Brightness**, the position (**Projector X/Y/Z**), and **Projector Frustum Lines**.
  - Alignment_Grid's **Pixel Line Width** (5 here) sets the projected line weight only. It doesn't touch the laser.

## Match your own room

To preview your own space, set **Laser_Fixture** Pose to where your laser really stands: Position X/Y/Z in metres from the centre of the wall's base, plus Aim Yaw and Aim Pitch. Set its Horizontal and Vertical Scan Degrees to your scanner's field. To move the wall, frame or props, edit `site.hlsli`: the projection frame is `FRAME_C` and `FRAME_HALF`, and the boxes are `BMIN`/`BMAX`.

## Real laser

1. Check your local laser-safety rules first. Keep the scan above the audience.
2. On **Laser Out #0**, set **protocol** (`etherdream`, `lasercube` or `shownet`) and enter your own device address. The example ships with none. Changing the protocol disarms the output.
3. Set **Test Pattern** to Orientation F and set **Flip X / Flip Y** so the F reads upright and unmirrored from the audience side. Flip X off is front projection. Return Test Pattern to Input.
4. Arming is manual: the node's **ARM** plus **ARM LASERS** in the menu bar. The node arm saves with the project; the master never does, so a saved show reopens held off. Scripts and agents must not arm the master.
5. **Shift+Esc** stops all Laser Out nodes. Laser Out's scanner protections stay active at all times.
6. Do not relink laser inputs while a real device is armed.
7. Map against your real wall with **Mapping_Editor 2**, exactly as above. Keep Laser_Fixture's pose roughly matched to your room so the preview stays useful.
8. To show the looks on your projector, drag from **Look_Select**'s Out pin to empty canvas, add a **Display** output, and pick the projector's monitor in Properties. Every saved output starts when the project opens, so save this only on the machine the projector belongs to.

The Laser Out profile was dialled in on a Laserworld DS-3000 RGB (ShowNET, 20 kpps) against the grid and the Shapes look:
- Desired FPS 60 (0 skips the speed limits, ood-labs/sentinel-bugs#148)
- max step 0.074, max step change 0.143 (keep change at about 2 × step)
- min visible speed 0.001, speed window 64
- end dwell 8, corner dwell 8, blank delay 25, insert cap 64
- colour delay 0: any delay cuts the start off every line and erases short strokes
- amplitude 1.0

Scanner limits are per output sample; with **Scale Limits With Rate** on, Laser Out rescales them when you apply a new point rate. Tune your own scanner with Laser Out's **ILDA Test (file)** pattern and the official ILDA test file.

In a trial, Ether Dream, LaserCube and ShowNET run as record and open no link; Simulate is unaffected.

## Performance

Measured with every node's preview open:
- **Whole graph:** under 2 ms GPU. Laser_Previs is about 0.6 ms at 1920 × 1080, Mapping_Editor about 0.2 ms, Adaptive_Mapping about 0.05 ms.
- Looks that aren't selected are frozen by Look_Select and cost nothing.

The previs ships at 1920 × 1080. Cost grows with the number of scan records. Busy content costs more than the grid.

## Scripts

- `scripts/map_to_tape.py` is a proof harness, not part of the graph. It inverts Laser_Fixture's optics to find where each corner handle must go to land on the projected grid's corners, then drags those handles in the open Mapping Editor with real drag gestures. This is how the shipped mapping was solved and checked.
- `scripts/mask_check.py` proves the zoning on the live output (see Zoning masks).
- `scripts/laser_frames.py` shows what a Laser Out actually draws, cycle after cycle. It grabs about 50 stills a second of Laser Out's own preview and writes a montage, a flicker map and per-grab lit-pixel counts to `captures/laser_frames/`. Static content that draws clean is pixel-identical every grab. `--freeze Trace` adds an A/B with that node frozen, which separates problems caused by moving content from ones that are always there.
- `scripts/clock_check.py` checks whether a Laser Out draws every content frame exactly once. It compares the rate the DAC reports actually playing with the requested one, and the laser's cycles per second with the content's frames per second, then reports how often a frame is skipped or repeated. A skip or repeat shows as a once-a-second jump against the projector on moving content.
- `scripts/lm_mcp.py` is a small stdio client for `sentinel-mcp`. Set `SENTINEL_MCP` if it's not installed in the default location.

## Component map

| Component | Role |
|---|---|
| `Alignment_Grid` | The Mapper look: the standard alignment grid, 4 × 4 cells with an orientation F in the top-left cell. Publishes the **Laser Look** bundle: the **Projection Grid** image and the same grid as `laser.a.scan`. |
| `Trace_Canvas` | The Trace look's line art, drawn in the 16:9 frame for Laser Trace and the projector. |
| `Laser_Test_Shapes` | The Shapes look and the template for new content: eight laser-show shapes (spiral, rose, Lissajous, starburst, tunnel, wave, the word SENTINEL in a single-stroke font, morphing polygon) in the 16:9 frame, with detail, spin and colour, all within a Record Budget (250). Publishes a **Laser Look** bundle. |
| `Trace`, `Trace_Look` | The Trace look: Laser Trace turns the canvas into a Scan Signal, and Bundle Pack pairs it with the canvas as a Laser Look. |
| `Mapper_Out`, `Shapes_Out`, `Trace_Out` | Each look's Group Output. |
| `Look_Select` | The look switcher: a Mux in Groups mode. |
| `Laser_Split` | Bundle Split: `laser.a.scan` for the mapper. |
| `Mapping_Editor` | The mapping you edit: one 5 × 5 handle lattice plus Scanner Correction (Bow, Spacing and Centre, corner-anchored), and the zoning masks, with a pan/zoom canvas, box select and arrow-key nudge. Publishes the Calibration (mapping, masks and polygon points). |
| `Adaptive_Mapping` | Compiles the Scan Signal through the Calibration with adaptive subdivision, tolerance and record budget, cuts it at the zoning masks, and turns hidden geometry into single jumps. Publishes the Mapped Scan and Compiler Stats. Scans are ILDA space (+y up); the editor is screen space, converted at the warp. |
| `Mapping_Editor_1`, `Adaptive_Mapping_1` | The same pair for the real laser on the real wall, shown as Mapping_Editor 2 and Adaptive_Mapping 2. |
| `laserout_0` | Laser Out #0, the real laser output: `simulate`, disarmed and with no device as shipped, with node-enforced scanner protection and Sent Stream. |
| `Laser_Sim` | A Laser Out on `simulate` that drives the simulated laser through its Sent Stream. |
| `Laser_Fixture` | The simulated physical laser: pose, scan field and optics. Turns the mapped path into world-space scan records and publishes the housing. Follows Laser Out's flips. |
| `Laser_Previs` | The warehouse, drywall, video projector and simulated laser in haze, with frame presets Operator, Audience and Wall. This is the program view. |

## Provenance

- `Mapping_Editor` and `Adaptive_Mapping` come from the Laser Stage show's mapping Modules, adapted to one laser with one working mapping (named mappings are node presets). The venue calibration was replaced by an identity grid, and the second and third lanes were removed. Source hashes: `docs/laser_stage_mapping_source.sha256`.
- `Alignment_Grid` comes from the laser room calibration project's Alignment Grid (hashes: `docs/alignment_grid_source.sha256`). Since then its scan is written in ILDA space (+y up), and it publishes a Laser Look bundle.
- `Laser_Fixture` and `Laser_Previs` come from the BLINK show (`BLINK_LaserFixture` and `BLINK_Previs`, commit `3013ad2`), which were in turn built from Laser Lab (branch feature/anatomy-laser-etch, commit 1563058e).
  - Changes to the fixture: room-scale defaults, raw optics (Calibrated to Wall off), Laser Out flip following, and Device Mirrors X.
  - Changes to the renderer: one laser, the projector mapped to the 3 × 1.8 m frame and fed by Look_Select's video, and the site model replaced by the warehouse.
  - Hashes: `docs/blink_laser_source.sha256`.
- The scientifica font tables in `modules/_shared/fonts/` keep their licence file.
