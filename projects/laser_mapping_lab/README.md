# Laser Mapping Lab

Map a laser onto a surface. The same graph drives a real laser, and when you don't have one it drives a simulated laser in a hazy warehouse.

The simulated laser is a raw scanner on a stand, beside and slightly in front of a video projector, about 6 m from a drywall mock-up. The projector throws the selected content onto a 3 × 1.8 m frame on the drywall, already mapped, as a MadMapper-mapped projector would be.

Because the laser stands off-axis and its scanner distorts like a real one, the standard Alignment Grid lands keystoned, bowed and unevenly spaced. You map it exactly as you would on site: match the corners, straighten and even out the lines with Scanner Correction, then finish with the handles until the laser grid lies on the projected grid.

It is also a **template for laser content**. Each piece of content is a look: its projector video and its laser scan travel together as a **Laser Look** bundle, inside its own Scene Group. A switcher picks the look, so the projector and the laser always show the same thing. Copy the Shapes or Trace look to make your own.

Requires Sentinel 0.5.99 or newer (Laser Out Simulate, cycle-boundary handover and Scan Signal joint flags). Background: `knowledge/laser-mapping.md`.

## First run

1. Open `laser_mapping_lab.sentinel`. The laser output, **Laser_Sim**, is a Laser Out on the **simulate** protocol and opens disarmed. Simulate runs everything Laser Out does (scanner protection, retiming, the Sent Stream) against a virtual DAC. Nothing is sent to hardware and nothing is written to disk.
2. Arm **Laser_Sim** with its node **Armed** switch. Simulate emits no light, so it needs only the node arm, not the laser master.
3. Open **Laser_Previs** and recall a frame preset on it:
   - **Frame - Operator**: from behind the laser.
   - **Frame - Audience**: from the room.
   - **Frame - Wall**: square to the drywall. Map from this one.
4. Select the **Mapper** look on **Look_Select** (it opens on it), open **Mapping_Editor**, and map (next section).

## Mapping workflow

Map in this order. Each step fixes one kind of error, and doing them out of order makes the later ones fight the earlier ones. Watch Laser_Previs, or the wall, the whole time.

1. **Corners.** Drag each of the four corner handles in Mapping_Editor onto the corners of the projected grid. A corner drag is a perspective change of the whole grid, so straight lines stay straight.
2. **Bow X and Bow Y** (Scanner Correction, in Properties) until the grid's edges run straight. A laser bows lines inward (pincushion); positive Bow bows them back out.
3. **Spacing X** until every inner vertical line is off from its projected line by the **same amount**. Spacing evens out lines that drift progressively across the grid (a real scanner spaces lines wider towards the edges). Don't try to land them yet, only to make the offsets equal.
4. **Centre X** to slide all the vertical lines together onto their projected lines.
5. **Spacing Y**, then **Centre Y**, the same way for the horizontal lines.
6. **Handles for what's left.** Click a handle in Mapping_Editor to select it (drag on empty space to box-select, Shift adds), then:
   - drag it, or nudge it with the **arrow keys**: one screen pixel at the current zoom, **Shift** ×10, **Alt** a tenth of a pixel;
   - hold **Alt while dragging** for 10× finer movement;
   - zoom in with the wheel for finer steps still. Middle- or right-drag pans, `F` fits the view and `Ctrl+A` selects all.

You're done when every laser line lies on its projected line and the laser F sits on the projected F, top-left and upright.

- Scanner Correction never moves the four corners. It is measured from the laser's own centre, so an off-centre laser gets more correction on its far side, as a real one needs.
- **Reset Mapping** (Properties only, with no hotkey on purpose, because it moves the beam) returns the mapping to a small square at the centre of the field, about 15% of the scanner's reach. It never resets to the full field, so a reset can't sweep the beam across the room. Zoom in and drag it out to the surface.
- Keep **Alignment_Grid Extent** equal to the mapping's Extent (0.99). A grid larger than the mapped lattice gets extrapolated past the scan field, and those lines go dark.

## Laser and projector sync

The laser and the projector reach the wall with different delays. To match them, select the **Mapper** look and set Alignment_Grid's **Pattern** to **Sync Sweep**. A vertical line sweeps left and right on both, from the same clock. The projector also draws a ruler that rides with its line:
- **Top band:** ticks where the line *was* 10, 20, 30… ms ago, longer every 50 ms. A laser line sitting on a top tick is that many milliseconds **late**.
- **Bottom band:** ticks where the line *will be*. A laser line sitting on a bottom tick is **early**.

If the laser is early, add the earliness to Laser Out's **Output Delay**. If it's late, take it off Output Delay or delay the projector path. Repeat until the laser sits on the projected line. **Sweep Rate** spreads the ticks: faster makes a small offset easier to read. Set Pattern back to Grid for mapping.

If the laser keeps creeping behind and then jumping ahead about once a second, the DAC's clock is running at a different rate from the content. `scripts/clock_check.py` measures it.

## Saving mappings

Mapping_Editor holds one working mapping: a 5 × 5 handle grid and an **Extent**, saved with the project. Scanner Correction belongs to the laser, not the surface, so it lives beside the mapping rather than inside it.

Keep named mappings as node presets on Mapping_Editor, saved with an explicit `params` list:

- **A surface mapping** saves the handles and Extent: `["state:points", "extent_a"]`. Recalling it swaps what the laser is mapped to.
- **A scanner correction** saves only the six correction parameters (Bow, Spacing and Centre, X and Y). Recalling it leaves the handles alone.
- **A venue's zones** save `["state:zones", "mask_margin"]` (see Zoning masks).

## Zoning masks

Switch the Mapping Editor to **MASKS** to zone the laser. Masks are drawn on the laser's own field, so re-mapping the surface or changing the scanner correction never moves a zone off its object.

- **Draw:** pick **RECT**, **ELLIPSE** or **POLYGON**, then drag on empty space (Shift makes a square or circle). A polygon takes one click per point. Close it with a double-click, Enter, Esc, a right-click, or by clicking its first point.
- **Edit:** click any mask to select it, whatever tool is picked. Drag inside to move it. Corners resize it and the knob rotates it (Shift snaps to 15°). On a polygon, drag a point, or click an edge to add one.
- **BLOCK / ONLY IN:** Block means no beam inside. Only In means beam only inside Only-In shapes, which is the invert. Several of each combine, and order never matters. Each row also has **ON** and delete. No mask action has a hotkey.
- **Mask Margin** (0.01 by default) grows Block zones and shrinks Only-In zones. The dashed line is where the beam is actually cut. Laser Out moves lit points about 0.003 field units after mapping (measured on a DS-3000), and the margin absorbs that.

Adaptive_Mapping cuts every warped line at the field edge and at every mask edge, then blanks the hidden pieces. Hidden geometry costs no drawing time: each chain of hidden moves becomes one direct jump, timed at **Blank Jump Speed**. **Min Cycle** (8 ms) pads a mostly-masked shape so it can't run hot. Masks travel inside the Calibration. A Calibration without them, or a line that crosses more edges than the mapper can track, blanks rather than drawing unmasked.

`scripts/mask_check.py` is the proof. With the laser armed and a look playing, it counts lit samples inside Block zones, and outside Only-In zones, in both the Mapped Scan and Laser Out's Sent Stream. It says how much of the margin Laser Out used, and fails only if light reaches a zone as drawn.

## Content looks

```text
 Scene Group "Mapper":  Alignment_Grid    ─Laser Look─▶ Mapper_Out ┐
 Scene Group "Shapes":  Laser_Test_Shapes ─Laser Look─▶ Shapes_Out ┤
 Scene Group "Trace":   Trace_Canvas ─▶ Trace ─▶ Trace_Look ─Bundle─▶ Trace_Out ┤  collected wirelessly by
                                                                  Look_Select (Mux, Groups mode)
                          ─Bundle─▶ Laser_Split ─laser.a.scan─▶ Adaptive_Mapping
                          ─Out────▶ Laser_Previs Projection (and your projector)
```

- **Mapper** is the alignment grid, or the Sync Sweep.
- **Shapes** is eight laser-show shapes (spiral, rose, Lissajous, starburst, tunnel, wave, the word SENTINEL in a single-stroke font, a morphing polygon) with detail, spin and colour, all within a Record Budget.
- **Trace** starts from pixels, not records. **Trace_Canvas** draws line art (a rotating star, a breathing circle, a travelling wave and a few twinkling single-pixel dots). Laser Trace (**Trace**: Dots on, Y Axis Up, Fit Stretch) turns it into a Scan Signal. **Trace_Look** (Bundle Pack: `laser.a.scan`, Data, neutral Empty, handoff at mid) pairs that scan with the canvas as the projector video. Any white-on-black line image works in place of the canvas. Every separate stroke costs a blank jump plus the scanner's blank guard on both sides (about 3.5 ms each on the profile below), and a dot is its own stroke, so keep dots to a handful.

How a look is built:
- A look publishes a **Laser Look** bundle: its projector video plus one channel per laser, keyed `laser.a.scan`. A Module declares it in its manifest:

  ```yaml
  bundle_outputs:
    - name: Laser Look
      video: Projection
      channels:
        - {key: laser.a.scan, data: Scan Signal, header_records: 1, transition: {mode: handoff, at: mid}, neutral: empty}
  ```

  Draw the video and the scan from the same records, in the same coordinates, so the projector and the laser show the same picture. Author in the 16:9 projection frame: scan (x, y) in ±1 covers the whole frame, so scale x by 9/16 for round shapes (see `Laser_Test_Shapes/shapes.hlsl`). Scans are ILDA scanner space, +y up. A traced look packs the same bundle with a Bundle Pack node instead.
- Each look sits in its own Scene Group with exactly one Group Output fed by the bundle.
- **Look_Select** is a Mux in Groups mode. It collects every look, freezes the ones not playing, and on a switch hands the laser over at the transition midpoint (`fade_time` sets a projector crossfade). Select a look with its button, or write the group's name or id to `selected_group` from OSC or an expression (`/look Shapes`).
- **Laser_Split** (Bundle Split, `keys: laser.a.scan`) takes the laser channel out of the bundle for the mapper. For a second laser, add `laser.b.scan` to every look and to Laser_Split's keys, then build a second mapping chain.
- **Joint flags.** A Scan Signal can say which joints are corners, so one scanner profile suits every look. On a lit record, `timing.z` flags the joint at its start: 1 smooth (no Corner Dwell), 2 corner, 0 let Laser Out judge. On the header, `timing.z` 1 marks the cycle as one closed lit loop, so its seam flows too. Laser_Test_Shapes flags its curve chords smooth and its Lissajous and rose as closed, and leaves straight strokes to Laser Out. Laser Trace flags every joint it traces. Adaptive_Mapping keeps the flags, marks the joints it makes when it subdivides a stroke as smooth, and clears the closed flag when it hides, clips or pads anything. The result: a spinning Lissajous draws with no holds and no seam, while SENTINEL keeps its letter corners, on the same End Dwell 8 / Corner Dwell 8 profile. Don't put anything else in `timing.z`.
- **To add content:** duplicate the Shapes group, point its Module at your own project folder, and keep the `Laser Look` bundle. Or duplicate the Trace group and replace Trace_Canvas with your own line art.

## How it works

```text
Look_Select ─Bundle─▶ Laser_Split ─laser.a.scan─▶ Adaptive_Mapping ─Mapped Scan─▶ Laser_Sim ─Sent Stream─▶ Laser_Fixture ─World Scan + Fixtures─▶ Laser_Previs
     │                                                ▲                           (Laser Out)                                                            ▲
     │ Out                           Mapping_Editor ─Calibration                                                                                         │
     └──────────────────────────────────────────────────────────────────────────────────────────────────────────── Projection ──────────────────────────┘
```

- **Mapping is two nodes, from Laser Stage.**
  - **Mapping_Editor** is where you edit. It compiles the working mapping, the Scanner Correction and the zoning masks into the Calibration buffer.
  - **Adaptive_Mapping** compiles your content through that calibration. It subdivides a stroke only where the warp actually bends it, within its tolerance and a record budget.
  - A corner drag is a pure perspective change, so straight lines stay straight and keep their record count. Scanner Correction and edge handles add records only where lines bend.
- **Laser_Sim** is the laser output: a Laser Out on the **simulate** protocol. Its protections (step size, dwell, blanking, duty) apply to what is sent, and it publishes the **Sent Stream**, exactly what went to the DAC after retiming, dwells and blank guards.
- **Laser_Fixture** is the simulated laser. It reads Laser_Sim's Sent Stream, so the previs shows what a real laser would draw, not the idealised mapped scan. It adds what a real scanner does:
  - **galvo distortion** (Scanner Model: Galvo): angle-linear mirrors, the X mirror ahead of the Y mirror, an off-centre galvo zero, gain and squareness errors, amplifier nonlinearity and head pincushion. This is what Bow, Spacing and Centre correct, so the mapping steps above work on the simulation exactly as on a real laser;
  - **galvo lag** (0.2 ms), modelled as the colour leading the path;
  - **Device Mirrors X**, which models how a real scanner draws from the audience side. Laser Out's Flip X off compensates, as on real lasers.

  It is **not** a mapping: it stands where your laser stands and does what a raw, uncalibrated scanner does. The stand under it follows the laser's pose.
- **Laser_Previs** is the room. It's Laser Lab's LS_Air renderer, from the BLINK show's previs:
  - analytic single scattering in drifting haze, with separate air extinction;
  - the RAW-10 housing, lit by the room, and its aperture glow;
  - the scan landing on the first surface it meets, with shadows from the pallet and road case;
  - the projector's own beam in the haze;
  - bloom and lens streaks.

  The room is a box model in `modules/Laser_Previs/site.hlsli`: drywall mock-up, warehouse walls, steel columns, pallet, road case, the laser's stand, and the video projector on its stand. The room is lit by a cool skylight and one warm work lamp (Room group: Environment Light, Skylight, Work Lamp).
- **The video projector** (BLINK_Previs's projector term) lights every surface with the image pixel where its ray meets the wall. The image is mapped onto the 3 × 1.8 m frame. Anything in front of the wall catches the image and casts a shadow, as on site.
  - Its image is Look_Select's video: the selected look's projection, drawn in the same coordinates as its laser scan. That's why a mapped laser lands exactly on it.
  - Controls are in the **Video Projector** group on Laser_Previs: **Projector Brightness**, the position (**Projector X/Y/Z**), **Projector Beam in Haze** and **Projector Frustum Lines**.
  - To send the look to a real projector, add a screen or Spout/NDI output to Look_Select. The example ships with none.

## Match your own room

To preview your own space, set **Laser_Fixture** Pose to where your laser really stands: Position X/Y/Z in metres from the centre of the wall's base, plus Aim Yaw and Aim Pitch. Set its Horizontal and Vertical Scan Degrees to your scanner's field. To move the wall, frame or props, edit `site.hlsli`: the projection frame is `FRAME_C` and `FRAME_HALF`, and the boxes are `BMIN`/`BMAX`.

## Real laser

1. Check your local laser-safety rules first. Keep the scan above the audience.
2. On **Laser_Sim**, set **protocol** (`etherdream`, `lasercube` or `shownet`) and enter your own device address, or add a second Laser Out fed by Adaptive_Mapping's Mapped Scan. The example ships with no device. Changing the protocol disarms the output.
3. Leave **Flip X** off for a laser projecting from the audience side (ILDA front projection); turn it on for a rear screen or a laser aimed back at the audience. The F should read upright, top-left.
4. Arming is manual: the node **Armed** switch plus the global laser master arm. A node's arm is saved with the project, but the master never is, so a reopened show stays dark until you arm it. Scripts and agents must not arm.
5. **Shift+Esc** stops all Laser Out nodes. Laser Out's scanner protections stay active at all times.
6. Do not relink laser inputs while a real device is armed.
7. Map against your real wall exactly as above. Keep Laser_Fixture's pose roughly matched to your room so the preview stays useful.

The Laser Out profile was dialled in on a Laserworld DS-3000 RGB (ShowNET, 20 kpps):
- Desired FPS 60 (0 skips the speed limits)
- Max Step 0.074, Max Step Change 0.143 (keep change at about 2 × step)
- Min Visible Speed 0.001, Speed Window 64
- End Dwell 8, Corner Dwell 8, Blank Delay 25, Insert Cap 64
- Color Delay 0: any delay cuts the start off every line and erases short strokes
- Amplitude 1.0

Scanner limits are per output sample, so they mean something different at another point rate. Tune your own scanner first with Laser Out's **ILDA Test (file)** pattern and the official ILDA test file.

## Performance

- Laser_Previs ships at 1280 × 720. Node presets **Draft 960x540**, **Live 1280x720** and **Beauty 1920x1080 (captures)** trade quality for cost. Beauty is for captures, not for working in.
- Laser_Fixture draws the Sent Stream as a path, merging straight runs of samples into one beam (Beam Merge Tolerance), so the previs cost follows the content's shape, not its sample count.
- Looks that aren't selected are frozen by Look_Select and cost nothing.

## Scripts

These talk to Sentinel over `sentinel-mcp` and are proof tools, not part of the graph.

- `scripts/mask_check.py` proves the zoning on the live output (see Zoning masks).
- `scripts/laser_frames.py` shows what a Laser Out actually draws, cycle after cycle. It grabs about 50 stills a second of Laser Out's own preview and writes a montage, a flicker map and per-grab lit-pixel counts to `captures/laser_frames/`. Static content that draws clean is pixel-identical every grab. `--freeze Trace` adds an A/B with that node frozen, which separates problems caused by moving content from ones that are always there.
- `scripts/clock_check.py` checks whether a Laser Out draws every content frame exactly once. It compares the rate the DAC reports actually playing with the requested one, and the laser's cycles per second with the content's frames per second, then reports how often a frame is skipped or repeated.
- `scripts/galvo_model.py` is the offline model of Laser_Fixture's galvo distortion.
- `scripts/lm_mcp.py` is a small stdio client for `sentinel-mcp`. Set `SENTINEL_MCP` if it's not installed in the default location.

## Component map

| Component | Role |
|---|---|
| `Alignment_Grid` | The Mapper look: the standard alignment grid, 4 × 4 cells with an orientation F in the top-left cell, or the Sync Sweep. Publishes the **Laser Look** bundle: the **Projection Grid** image and the same drawing as `laser.a.scan`. |
| `Laser_Test_Shapes` | The Shapes look and the template for new content: eight laser-show shapes in the 16:9 frame, flagged for smooth joints, within a Record Budget (250). Publishes a **Laser Look** bundle. |
| `Trace_Canvas`, `Trace`, `Trace_Look` | The Trace look: line art, Laser Trace, and the Bundle Pack that pairs the traced scan with the canvas. |
| `Mapper_Out`, `Shapes_Out`, `Trace_Out` | Each look's Group Output. |
| `Look_Select` | The look switcher: a Mux in Groups mode. |
| `Laser_Split` | Bundle Split: `laser.a.scan` for the mapper. |
| `Mapping_Editor` | The mapping you edit: one 5 × 5 handle lattice plus Scanner Correction (Bow, Spacing and Centre, corner-anchored), and the zoning masks, with a pan/zoom canvas, box select and arrow-key nudge. Publishes the Calibration (mapping, masks and polygon points). |
| `Adaptive_Mapping` | Compiles the Scan Signal through the Calibration with adaptive subdivision, tolerance and record budget, cuts it at the zoning masks, turns hidden geometry into single jumps, and keeps the joint flags. Publishes the Mapped Scan and Compiler Stats. Scans are ILDA space (+y up); the editor is screen space, converted at the warp. |
| `Laser_Sim` | The laser output: a Laser Out on `simulate`, disarmed, with node-enforced scanner protection and the Sent Stream. Switch its protocol to drive a real laser. |
| `Laser_Fixture` | The simulated physical laser: pose, scan field, galvo distortion and lag. Turns the Sent Stream into world-space beams and publishes the housing. |
| `Laser_Previs` | The warehouse, drywall, video projector and simulated laser in haze, with frame presets Operator, Audience and Wall and quality presets Draft, Live and Beauty. This is the program view. |

## Provenance

- `Mapping_Editor` and `Adaptive_Mapping` come from the Laser Stage project's mapping modules, adapted to one laser with one working mapping (named mappings are node presets). The venue calibration was replaced by an identity grid, and the second and third lanes were removed. Zoning masks and joint flags were added here. Source hashes: `docs/laser_stage_mapping_source.sha256`.
- `Alignment_Grid` comes from the Laser Room Calibration project (hashes: `docs/alignment_grid_source.sha256`). Since then its scan is written in ILDA space (+y up), it publishes a Laser Look bundle, and it gained the Sync Sweep.
- `Laser_Fixture` and `Laser_Previs` come from the BLINK show (`BLINK_LaserFixture` and `BLINK_Previs`), which were in turn built from Laser Lab.
  - Changes to the fixture: room-scale defaults, raw optics, galvo distortion and lag, and reading Laser Out's Sent Stream.
  - Changes to the renderer: one laser, the projector mapped to the 3 × 1.8 m frame and fed by Look_Select's video, its beam in haze, and the site model replaced by the warehouse.
  - Hashes: `docs/blink_laser_source.sha256`.
- The scientifica font tables in `modules/_shared/fonts/` keep their licence file.
