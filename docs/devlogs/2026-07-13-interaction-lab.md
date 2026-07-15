# Module Interaction Lab — 2026-07-13

## Progress saved

- Added `modules/_shared/ui/scientific_ui.hlsli`, a Scientifica-based shader UI foundation with a shared scientific palette and host-state-aware buttons, sliders, toggles, pads, glyphs, lines, rings, panels, and grids.
- Added `modules/ui_kit_gallery/`, a four-control authored viewport gallery demonstrating normalized host hit regions with HLSL-rendered feedback.
- Added `modules/spline_editor/`, a seven-pass cubic spline editor with local knot and handle selection, marquee selection, pen insertion, tangent modes, open/closed paths, deletion, cancellation, persistent knot state, drag snapshots, 512 sampled PNode-compatible records, and four typed data outputs.
- Expanded the existing `spline_render` consumer ceiling from 256 to 512 records and linked the editor's `Sampled Path` output to it in the example graph.
- Added `modules/transform_gizmo_lab/`, a six-pass selectable 3D scene with host ray-query picking, multiple selection, constant-screen custom handles, translate/rotate/scale modes, world/local axes, shared-pivot multi-object transforms, cancellation snapshots, durable scene state, and typed state/object outputs.
- Added the bundled `projects/interaction_lab/interaction_lab.sentinel` example with labeled graph regions and retained proof captures.

## Live verification

- All four Module directories passed the real offline Module compile path with no lints, and every live pipeline compiled healthy.
- Real injected viewport input moved a spline anchor and its two handles; the knot and selection data ports reflected the edit. `Ctrl+Z` restored the exact baseline and `Ctrl+Shift+Z` restored the edit.
- The pen toolbar hit was verified not to leak into the canvas, then a canvas click appended exactly one knot.
- Tool tabs use pressed-control state (and spline actions use an edge latch), so serialized momentary-button values cannot bias the active tool after project reload; select/pen and move/rotate were each switched back and forth with real pointer input.
- Real host picking selected scene objects. Two selected objects were translated, rotated, and uniformly scaled together; data-port readback showed the expected shared deltas and pivot behavior, and undo restored the baseline after each operation.
- Viewport diagnostics showed real boundary delivery with no event overflow. The saved project was bundled so all authored Module sources travel with it.

## Scope

This work is confined to the user-writable Module system and example project. It adds no Sentinel native features or application-source changes.

## Transform Lab interaction repair

- Replaced the broken pick-coordinate read with the viewport ABI's normalized pointer channels and added forgiving screen-space object hit regions.
- Made the picker recognize the active gizmo before scene objects so a handle press cannot silently select geometry behind it.
- Armed handles at the original mouse-down coordinate, retained that selection/pivot through the full transaction, and added combined begin/preview/commit commands for coalesced fast event batches.
- Kept drag ownership alive across ordinary event-free Module cooks, so pausing or moving quickly while held no longer drops the active handle.
- Replaced fake 2D axis directions with the real camera projection of world/local axes and mapped deltas onto the displayed axis.
- Added fixed pixel-to-world translation sensitivity to eliminate singular jumps when an axis points toward the camera.
- Made plane handles visible, restricted them to Move mode, and gave visible axis lines hit-test priority where projections overlap.
- Live proof covered correct picks across all visible rows, isolated world-axis movement, a rapid two-step fling after acquisition, and a held mouse-down that remained armed through a two-second pause.

## Monochrome type-system pass

- Replaced the blue/cyan UI palette across the UI kit, spline editor/output, transform scene, and graph annotations with black, white, and neutral gray.
- Kept only the transform gizmo's X/Y/Z handles chromatic because their red/green/blue colors communicate direction rather than theme.
- Removed the bold Scientifica face from the shared UI rendering path. Every label and title now starts from the regular glyph data; title emphasis is a controllable synthetic edge coverage instead of a different font face.
- Added `modules/font_style_sampler/` and bundled it as `Font_Sampler`. It compares Regular, Light Edge, Clean Edge, and Full Edge and exposes a live custom edge-weight slider. Clean Edge (`0.28`) is the current project default.
- Reversed only the blue Z-ring angle sign. A real clockwise blue-ring drag changed object 6 Z rotation from `0.78125` to `-96.3835`; undo restored the exact baseline. Red and green calculations were not changed.
- All five bundled modules compile cleanly and ran healthy at approximately 60 FPS with live preview textures and advancing frame counts. Retained monochrome captures live under `projects/interaction_lab/proof/`.

## UI control edge and rollover repair

- Added a constant 1.5-pixel inset frame to shared buttons, sliders, toggles, and XY pads so dark idle controls retain a clear silhouette against monochrome panels.
- Removed transient viewport hover flags from the visual fill and outline paths. Hover no longer changes unrelated edges or introduces a one-frame rollover flash; slider value, toggle value, and explicit selected modes still communicate meaningful state.
- Live automation hovered the pulse, slider, toggle, and XY pad independently. Each hovered capture was pixel-identical to the idle baseline (`0` changed pixels at 960 x 540).
- Recompiled and force-reloaded every live Module that consumes the shared UI include; all returned `state: ok` with no parameter changes.

## Pulse feedback and first-interaction repair

- Restored Pulse feedback from only the Pulse control's pressed bit (`_ViewportControlFlags[0].y & 2`), so the button face visibly lights only while the pointer is held and returns to idle on release even if the trigger parameter's last sampled value remains high.
- Kept the feedback local to the Pulse rectangle and ignored hover bits entirely, so the first press cannot brighten neighboring controls.
- Replaced subtractive outer-minus-inner borders with four explicit symmetric frame sides, removing the right-edge-specific boundary path.
- Both source and bundled UI Kit projects passed the real Module compiler with no lints, and the live bundled node reloaded healthy.
- Lossless 960 x 540 captures changed exactly 6,000 pixels while held, bounded to the Pulse interior at `522,130..671,169`; the released frame was pixel-identical to idle. A post-reload window capture confirmed the first click lights only Pulse and leaves the slider, toggle, pad, and all neighboring edges stable.
