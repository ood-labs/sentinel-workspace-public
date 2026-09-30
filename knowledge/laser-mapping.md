# Laser Mapping

How to map a laser onto a surface in Sentinel, and how to preview it without one. The reference build is `projects/laser_mapping_lab`; read its README first.

## The chain

```text
look (Laser Look bundle) ─▶ Mux (Groups) ─Bundle─▶ Bundle Split ─laser.a.scan─▶ Adaptive_Mapping ─Mapped Scan─▶ Laser Out ─▶ DAC
                                    └─Out (projector video)                            ▲
                                                               Mapping_Editor ─Calibration
```

- **Content is a Scan Signal:** 80-byte records (`endpoints`, `color0`, `color1`, `timing`, `meta`).
  - Record 0 is the header: `(count, cycle_s, pps, phase)`.
  - Up to 1,023 active records.
  - Blank travel records have `timing.w = 1`.
  - Coordinates are ILDA scanner space: x right, **+y up**, ±1 is the scan field.
- **Author content as a look that publishes a bundle,** not as a loose scan plus a separate video. One Module draws the projector video and every laser's scan from the same records and publishes them together:

  ```yaml
  bundle_outputs:
    - name: Laser Look
      video: Projection
      channels:
        - {key: laser.a.scan, data: Scan Signal, header_records: 1, transition: {mode: handoff, at: mid}, neutral: empty}
  ```

  Each look sits in a Scene Group with one Group Output fed by the bundle. A Mux with `source_mode` Groups picks the look, and hands every laser channel over at the transition midpoint. A native **Bundle Split** (`keys: laser.a.scan[,laser.b.scan]`) gives each laser its scan, and the Mux's video feeds the projector. Author in the 16:9 projection frame: scale x by 9/16 so a circle is round. `projects/laser_mapping_lab` (the Shapes look) is the template, and the BLINK 2026 busk looks use the same contract.
- **Mapping_Editor** is the editing surface. It stores one working 5 × 5 handle lattice (named mappings are node presets) and compiles it into a 32 × float4 **Calibration**:
  - element 0: `(valid, extent, 1, 0)`
  - elements 1–3: the corner homography
  - elements 4–28: the per-handle residuals of a bicubic warp (`.xy`); element 4 `.zw` carries the scanner-correction centre
  - element 29: scanner correction `(bow x, bow y, spacing x, spacing y)`; elements 30–31: its value at the four mapped corners, precomputed

  Corner drags change the homography. Other handles bend the grid locally. The editor works in screen space (+y down); Adaptive_Mapping converts to and from ILDA space at its single warp.
- **Scanner Correction** removes the laser's own distortion, which a real scanner adds and a perfect simulation doesn't. It's modelled in the laser's field, centred on its straight-on point, and anchored at the mapped corners, so the corners never move. Map in this order:
  1. corners with the handles
  2. **Bow X/Y** until the edges run straight (lasers bow inward; positive bows back out)
  3. **Spacing X**, then **Centre X**, for the inner vertical lines
  4. **Spacing Y**, then **Centre Y**, for the horizontal lines
  5. handles and arrow-key nudges (one screen pixel at the current zoom, Shift ×10, Alt ×0.1)
- **Adaptive_Mapping** compiles the content through the Calibration. It subdivides a stroke only where the warp actually bends it, within its tolerance and record budget. It clips anything that leaves the ±1 scan field, or falls in a zoning mask, to blank, and reports `Compiler Stats`. Each chain of blank moves that contains hidden geometry becomes one direct jump, timed at Blank Jump Speed. Min Cycle pads a mostly-masked cycle.
- **Zoning masks** (rectangle, ellipse, polygon; Block or Only-In) are drawn in the Mapping Editor in scanner space and ride in the Calibration: 32 is the header, 33..64 the records, and 65..576 the polygon points. A Calibration without the mask block fails closed. Laser Out moves lit points about 0.003 units after mapping, so keep Mask Margin (0.01) above that. `scripts/mask_check.py` proves the zoning on the Sent Stream.
  - An identity or pure-perspective mapping keeps the record count.
- **Both mapping nodes run every frame.**
  - Adaptive_Mapping must: an idle compiler stops publishing, and Laser Out's deadman blanks a static scan after `deadman_ms`. A full compile of the grid is about 0.05 ms GPU. Its passes also need `time_dependent: true`, or they are skipped when inputs are unchanged.
  - Mapping_Editor must: an idle `on_dirty` editor misses about one in five real mouse drags (ood-labs/sentinel-bugs#152).
- **Laser Out** owns everything physical: protocol and device, scanner protection (step, step change, dwell, blanking, duty), flips, and arming. It publishes **Sent Stream**, the actually-sent cycle; `meta.w = 2` marks decimation.

## Rules that bite

- **Grid extent ≤ mapping extent.** Content that reaches past the mapping's Extent is extrapolated beyond the mapped lattice. After a warp it can cross ±1 and be blanked. Run the Alignment Grid at the mapping Extent (0.99).
- **Y convention.** Scan Signals are +y up. The Alignment Grid writes its scan that way, and its F reads upright with Flip Y off.
- **X orientation.** The lasers tested so far (a DS-3000 over ShowNET and a LaserCube) draw X mirrored with no flips, so they need Laser Out **Flip X** on (ood-labs/sentinel-bugs#147). The simulated fixture's **Device Mirrors X** models this.
- **Colour delay.** Keep Laser Out `color_delay` at 0 unless you've measured modulation lag. 6 samples cut about 20% off the start of every grid line and turned short strokes into dots.
- **Scanner field.** If the laser stands off-axis, its near-side field edge limits how far you can pull a corner. A handle dragged past the field edge sends that stroke to blank. Widen the scan angle, or move the laser.
- **Editor input.** In the Mapping Editor:
  - Drag handles, box-select on empty space, Shift to add, wheel to zoom, middle- or right-drag to pan, arrows to nudge.
  - `F` fits and `Ctrl+A` selects all. Reset Mapping is a Properties button with no hotkey, and it resets to a small centred square, never the full field (a reset must not sweep the room).
  - The Properties buttons for the same actions fire only once (ood-labs/sentinel-bugs#154). Use the keys.
- **Arming is manual.** It needs the node **Armed** switch and the global laser master arm. Arming never persists. Automation (scripts, agents, expressions) must never arm. **Shift+Esc** stops every Laser Out. Do not relink laser inputs while a real device is armed.

## Previewing without a laser

The laser simulation sits downstream and never replaces the real nodes:

```text
Mapped Scan ─▶ Laser_Fixture ─World Scan + Fixtures─▶ Laser_Previs
```

- **Laser_Fixture** is a raw scanner (Laser Lab LS_Projector): pose, scan angles, Hermite scan reconstruction. It publishes **World Scan** (112 B: `origin, direction0, direction1, color0, color1, timing, meta`), one aperture ray pair per sub-segment, and **Fixtures** (80 B housings). It must model an *uncalibrated* laser, so keep BLINK's "Calibrated to Wall" off. Drive its flips from Laser Out with `ref("Laser_Out/parameters/flip_x")` and `flip_y` so it receives what the DAC would, and leave **Device Mirrors X** on while #147 stands.
- **Laser_Previs** (Laser Lab LS_Air) renders the beams as analytic single scattering in haze, plus the scan landing on the first surface it meets, in one box-model world (`site.hlsli`). The same geometry is used for camera rays, beam occlusion and surface hits, so beams are shadowed by props. Air extinction is separate from haze scattering.
- **A video projector** in the same previs lights surfaces with its image, mapped to the target (BLINK's projector term: sample the image where the projector ray meets the wall, test occlusion). Feed it the look switcher's video, so it always shows the selected look's own projection. The laser can then be lined up against a projected reference, which is the usual on-site job.
- **Map in the previs exactly as on site.** Recall a square-to-the-wall camera frame and drag handles until the laser grid lies on the projected grid. Then match Laser_Fixture's pose and scan angles to your real room.

## Proving it

- Drag with `sentinel_ui drag_at` on the **open, frontmost** editor panel, taking coordinates from `sentinel_pipeline info` → `panel.view.content_rect`. A docked tab hidden behind another does not receive events. Re-read the output after the on-dirty recompile before judging.
- Judge the landing from a previs capture, not from the editor. The editor shows handle positions; only the previs shows the beam on the surface.
