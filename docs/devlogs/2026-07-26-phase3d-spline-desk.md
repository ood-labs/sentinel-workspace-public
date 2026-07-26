---
type: devlog
date: 2026-07-26
phase: 3
subphase: 3D
status: complete
approval: pending
summary: "Spline Desk v3 rebuilt on the sui3 kit; undo made real after finding the snapshot captured post-edit, contracts preserved byte-for-byte"
---

# Phase 3D - Spline Desk

## Done

`modules/spline_desk/` (live node `Spline_Desk`), the third v3 station. The data layer IS the
contract, so `types.hlsli`, `headers.hlsl`, `derive.hlsl`, `selection.hlsl` and the command
vocabulary in `update.hlsl` were preserved and only the interaction and render layers rebuilt. All
four data outputs are byte-identical to v1.

| # | Criterion | Result |
| --- | --- | --- |
| 1 | Hands-on editing pass | **DEFERRED to 3F** - gesture-dependent, see below |
| 2 | Downstream link still carries | `Spline_Output_V3` (`modules/spline_render`, unmodified) changes **7888 px / 0.380%** when knots move by an exact `(+0.06, -0.12)`, and returns **0 px different** after undo |
| 3 | Durable state survives save/close/reopen | SHA-256 over all 64 knot records identical across save -> new project -> reopen (`4fcbabfbb6bddff3`), with nudged anchors, tangent mode 2 and selection flags intact. `sentinel_viewport action=state`: **3072 bytes**, `element_count 64` |
| 4 | Selection / tangent / lane legible from the render | Selection = amber brackets on the anchor square; tangent mode = terminal SHAPE (free open ring, aligned ring-plus-bar, mirrored filled disc) plus a spelled-out readout; active lane at full ink with the others at rule weight, plus `LANE n` |
| 5 | Criterion 4 at both extents; validate clean | Legible at 640x360, 1600x900 and 1920x403. `module-ui.ps1 validate`: `OK Spline Desk (4 controls)` |

Cost: **0.737 ms** wall time.

## The real find: undo never worked, and not for the reason it looked like

`do_undo` emitted the right command every time -- proven with a `last_command` control output
added for exactly this -- and the desk did not move. Three attempts, each disproving the last:

1. **Capture on the command frame** (v1's rule, widened to all structural edits). Failed. The pass
   graph is a cycle: `snapshot` reads `spline_knots` and `update` writes it, while `update` reads
   `drag_snapshot` and `snapshot` writes it. The scheduler runs `update` first, so a snapshot taken
   on the command frame records the state AFTER the edit and undo restores the desk to exactly
   where it already is.
2. **Mirror continuously, freeze during the edit.** Also failed, and measurably: the first idle
   cook after the edit re-mirrors the post-edit state, so the undo window collapses to one cook.
3. **Arm-then-execute.** Works. An edit that undo must reverse is armed on one cook and executed on
   the next, and the snapshot captures on the arm cook -- which mutates nothing, so it is
   order-independent by construction rather than by luck.

v1 never exposed this because it only ever captured on drag-begin, where nothing has moved yet and
post-update happens to equal pre-drag. The accident does not survive discrete edits, and "undo the
delete" is a discrete edit.

Measured after the fix: tangent `1 -> 2 -> 0`, undo returns **0 -> 2**; delete `4 -> 0`, undo
returns **0 -> 4** with the tangent preserved.

## Other defects fixed

- **Hit testing was aspect-distorted.** v1 compared normalized distances against a flat `0.022`,
  which on the 1920x403 dock this station now has to survive is a 42x9 px ellipse. Distances are
  now measured in pixels against a `hit_radius` parameter.
- **The seed guard could not fire.** v1 guarded on `tool` being outside 0..1, but a zeroed buffer
  has `tool = 0`, which is valid, so the seed never ran: `tangent_mode` stayed 0 while the knots it
  described were created at mode 1, and the desk printed FREE next to handles drawn ALIGNED. Now a
  magic sentinel that cannot occur by accident.
- **Deleting every knot was unrecoverable.** `initialize()` runs once in the life of a persistent
  buffer, so an emptied desk had no way back - including for the next person to open the project.
  Added a reset command.
- **The renderer walked 512 sample records per pixel** to draw what is usually three cubic
  segments. It now walks the 64 knots and early-outs on the inactive ones. `Sampled Path` is still
  published unchanged; it is simply not what this renderer reads.

## Decisions

**Every action has two doors.** The three action plates stay `kind: button` and the shader reads
each control's `down` bit -- never the `type: button` parameter global that 3C measured as a
one-way latch. Alongside them, bool rising-edge parameters fire the same commands. This is not a
test hook: it is what lets OSC, a Conductor cue or an expression drive the desk, and it is the only
reason criteria 2 and 3 could be proven at all, since no MCP call can click inside a module
preview. Tool selection is an ordinary `int` parameter on a two-cell bank, so it undoes, presets
and saves like any other value.

Two selection commands and a nudge were added to `update.hlsl`. Both are purely additive and both
are genuine features - keyboard nudge is standard in any point editor - not scaffolding.

## Deferred to 3F

**Criterion 1 is gesture-dependent and is not marked complete.** Drag, marquee and the keyboard
bindings need a human at the mouse. What is proven structurally: the event reduction handles the
same phases as v1, the hit test is aspect-correct, and every command the gestures emit has been
fired through the automation doors and observed to produce its expected effect.

Also: the criterion asks for "`sentinel_viewport action=info` shows a non-zero delivered gesture
count". **That field does not exist.** The info surface returns bindings, controls,
`capture_owner`, `edit_transaction_active`, `focused` and selection - no gesture counter. The
hands-on pass should assert on `edit_transaction_active` and `capture_owner` changing during a real
drag instead; the criterion as written cannot be satisfied by this MCP surface.

## Next

3E, the Gizmo Lab - twelve selectable SDF objects with host-owned ray-query selection and durable
transforms.
