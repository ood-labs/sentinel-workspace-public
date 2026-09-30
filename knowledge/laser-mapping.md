# Laser Mapping

How to map a laser onto a surface in Sentinel, and how to preview it without one. The reference build is `projects/laser_mapping_lab`; read its README first. Requires Sentinel 0.5.99 or newer.

## The chain

```text
look (Laser Look bundle) ─▶ Mux (Groups) ─Bundle─▶ Bundle Split ─laser.a.scan─▶ Adaptive_Mapping ─Mapped Scan─▶ Laser Out ─▶ DAC
                                    └─Out (projector video)                            ▲                     └─Sent Stream─▶ previs
                                                               Mapping_Editor ─Calibration
```

- **Content is a Scan Signal:** 80-byte records (`endpoints`, `color0`, `color1`, `timing`, `meta`).
  - Record 0 is the header: `endpoints = (count, cycle_s, pps, phase)`.
  - Up to 1,023 active records.
  - Blank travel records have `timing.w = 1`.
  - Coordinates are ILDA scanner space: x right, **+y up**, ±1 is the scan field.
  - **Joint flags** live in `timing.z`. On a lit record it flags the joint at the record's start: 1 smooth (Laser Out gives it no Corner Dwell), 2 corner, 0 let Laser Out judge the turn. On the header, 1 marks the whole cycle as one closed lit loop, so its seam flows. Flag curve chords smooth and leave straight strokes at 0; a mapper that subdivides a stroke marks its new joints smooth and clears the closed flag when it clips. Never use `timing.z` for anything else (a stroke index there reads as flags).
- **Author content as a look that publishes a bundle,** not as a loose scan plus a separate video. One Module draws the projector video and every laser's scan from the same records and publishes them together:

  ```yaml
  bundle_outputs:
    - name: Laser Look
      video: Projection
      channels:
        - {key: laser.a.scan, data: Scan Signal, header_records: 1, transition: {mode: handoff, at: mid}, neutral: empty}
  ```

  Traced content packs the same bundle with a **Bundle Pack** node (Laser Trace's Scan Signal plus the image it traced). Each look sits in a Scene Group with one Group Output fed by the bundle. A Mux with `source_mode` Groups picks the look (by group name or id) and hands every laser channel over at the transition midpoint. A native **Bundle Split** (`keys: laser.a.scan[,laser.b.scan]`) gives each laser its scan, and the Mux's video feeds the projector. Author in the 16:9 projection frame: scale x by 9/16 so a circle is round.
- **Mapping_Editor** is the editing surface. It stores one working 5 × 5 handle lattice (named mappings are node presets) and compiles it into a 577 × float4 **Calibration**:
  - element 0: `(valid, extent, 1, 0)`
  - elements 1–3: the corner homography
  - elements 4–28: the per-handle residuals of a bicubic warp (`.xy`); element 4 `.zw` carries the scanner-correction centre
  - element 29: scanner correction `(bow x, bow y, spacing x, spacing y)`; elements 30–31: its value at the four mapped corners, precomputed
  - element 32: the zoning header `(count, 5151, margin, only-in count)`; 33–64 the zone records; 65–576 the polygon points

  Corner drags change the homography. Other handles bend the grid locally. The editor works in screen space (+y down); Adaptive_Mapping converts to and from ILDA space at its single warp.
- **Scanner Correction** removes the laser's own distortion. It's modelled in the laser's field, centred on its straight-on point, and anchored at the mapped corners, so the corners never move. Map in this order:
  1. the four corners, with the handles;
  2. **Bow X/Y** until the edges run straight (lasers bow inward; positive bows back out);
  3. **Spacing X** until every inner vertical line is off from its target by the same amount, then **Centre X** to slide them all onto it;
  4. **Spacing Y**, then **Centre Y**, the same way for the horizontal lines;
  5. select the handles still off and nudge them: arrows move one screen pixel at the current zoom, Shift ×10, Alt ×0.1, and Alt while dragging moves 10× finer.
- **Adaptive_Mapping** compiles the content through the Calibration. It subdivides a stroke only where the warp actually bends it, within its tolerance and record budget. It clips anything that leaves the ±1 scan field, or falls in a zoning mask, to blank, and reports `Compiler Stats`. Each chain of blank moves that contains hidden geometry becomes one direct jump, timed at Blank Jump Speed. Min Cycle pads a mostly-masked cycle. A Calibration without the zoning block fails closed. It runs every frame: an idle compiler stops publishing, and Laser Out's deadman blanks a static scan after `deadman_ms`.
- **Zoning masks** (rectangle, ellipse, polygon; Block or Only-In) are drawn in the Mapping Editor in scanner space and ride in the Calibration. Laser Out moves lit points about 0.003 units after mapping, so keep Mask Margin (0.01) above that. The lab's `scripts/mask_check.py` proves the zoning on the Sent Stream.
- **Laser Out** owns everything physical: protocol and device, scanner protection (step, step change, dwell, blanking, duty), retiming, flips, and arming. It publishes the **Sent Stream**, the cycle actually sent. The **simulate** protocol runs all of it against a virtual DAC, with no device and no file.

## Rules that bite

- **Grid extent ≤ mapping extent.** Content that reaches past the mapping's Extent is extrapolated beyond the mapped lattice. After a warp it can cross ±1 and be blanked. Run the Alignment Grid at the mapping Extent (0.99).
- **Orientation.** Scan Signals are +y up, and Laser Out's Flip X off is ILDA front projection: content +X lands on the audience's right for a laser projecting from the audience side. Flip X on is for a rear screen or a laser aimed back at the audience. An upright F in the top-left cell of the grid is the check.
- **Colour delay.** Keep Laser Out `color_delay` at 0 unless you've measured modulation lag. 6 samples cut about 20% off the start of every grid line and turned short strokes into dots.
- **Dwells and joints.** End Dwell 8, Corner Dwell 8 and Blank Delay 25 draw lines ending where they should and corners crisp. A curve that trips Corner Dwell hitches at every sharp-ish point, so flag curve joints smooth (see joint flags) rather than lowering Corner Dwell.
- **Strokes cost time.** Every separate stroke costs a blank jump plus the blank guard on both sides, about 3.5 ms at 20 kpps with Blank Delay 25. Dots are strokes. Prefer few, long strokes.
- **Scanner field.** If the laser stands off-axis, its near-side field edge limits how far you can pull a corner. A handle dragged past the field edge sends that stroke to blank. Widen the scan angle, or move the laser.
- **Laser against projector timing.** Use the lab's Alignment_Grid **Sync Sweep** to read the laser's offset from the projector in milliseconds and set Laser Out's Output Delay. A laser that creeps behind and then jumps ahead about once a second has a DAC clock that doesn't match the content rate.
- **Editor input.** In the Mapping Editor:
  - Drag handles, box-select on empty space, Shift to add, wheel to zoom, middle- or right-drag to pan, arrows to nudge, Alt for fine.
  - `F` fits and `Ctrl+A` selects all. Reset Mapping is a Properties button with no hotkey, and it resets to a small centred square, never the full field (a reset must not sweep the room).
- **Arming is manual.** It needs the node **Armed** switch and, for any protocol that emits light, the global laser master arm. A node's arm is saved with the project; the master's never is. Automation (scripts, agents, expressions) must never arm. **Shift+Esc** stops every Laser Out. Do not relink laser inputs while a real device is armed.

## Previewing without a laser

The laser simulation sits downstream of Laser Out and never replaces it:

```text
Laser Out (simulate or a real DAC) ─Sent Stream─▶ Laser_Fixture ─World Scan + Fixtures─▶ Laser_Previs
```

- **Laser_Fixture** is a raw scanner (Laser Lab LS_Projector): pose, scan angles, and a galvo model (angle-linear mirrors, X mirror ahead of Y, off-centre zero, gain and squareness error, amplifier nonlinearity, head pincushion) plus galvo lag. Reading the Sent Stream, it shows what the DAC was actually told, not the idealised mapped scan. It publishes **World Scan** (112 B: `origin, direction0, direction1, color0, color1, timing, meta`) and **Fixtures** (80 B housings). It must model an *uncalibrated* laser, so keep "Calibrated to Wall" off. **Device Mirrors X** models how a real scanner draws from the audience side; leave it on.
- **Laser_Previs** (Laser Lab LS_Air) renders the beams as analytic single scattering in haze, plus the scan landing on the first surface it meets, in one box-model world (`site.hlsli`). The same geometry is used for camera rays, beam occlusion, surface hits and room lighting, so beams are shadowed by props and the laser housing is lit like everything else. Air extinction is separate from haze scattering.
- **A video projector** in the same previs lights surfaces with its image, mapped to the target (sample the image where the projector ray meets the wall, test occlusion). Feed it the look switcher's video, so it always shows the selected look's own projection. The laser can then be lined up against a projected reference, which is the usual on-site job.
- **Map in the previs exactly as on site.** Recall a square-to-the-wall camera frame and work through the mapping order until the laser grid lies on the projected grid. Then match Laser_Fixture's pose and scan angles to your real room.

## Proving it

- Drag with `sentinel_ui drag_at` on the **open, frontmost** editor panel, taking coordinates from `sentinel_pipeline info` → `panel.view.content_rect`. A docked tab hidden behind another does not receive events. Re-read the output after the recompile before judging.
- Judge the landing from a previs capture, not from the editor. The editor shows handle positions; only the previs shows the beam on the surface.
- Judge what a laser draws from Laser Out's own preview over many cycles (the lab's `scripts/laser_frames.py`), not one still: a glitch that shows in one cycle in four is invisible in a single capture.
