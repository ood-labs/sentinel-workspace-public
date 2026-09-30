---
name: laser-arcade-authoring
description: Build playable Sentinel arcade looks with synchronized projector pixels and direct laser paths, including input, persistent game state, per-device routing and gameplay/projection proof.
---

# Laser arcade looks

Use this for a playable game rather than ordinary pixel tracing. When physical outputs are involved, follow `laser-content-authoring` and `laser-trace-tuning` for output and scanner discipline, and the workspace `module-authoring` and `module-ui-authoring` contracts for the look itself.

## Establish the game's contract

Name the controls, playfield coordinates, game phases and what each physical laser draws before authoring. Keep scores, prompts, court decoration and particles pixel-only unless they have an explicit laser role. A laser budget must include blank travel and emitted samples, not just object/record counts. Small shapes can scan too slowly; complex or distant shapes can demand too much travel.

Use one authoritative persistent game state for both visuals and paths. Separate pure gameplay rules from viewport event handling so deterministic GPU fixtures can call production logic. Use ordered key events with sequence deduplication for one-shot actions and held state for movement. Reset enters a well-defined ready state; pause freezes the intended simulation, not just ball motion. Bound time steps, collision tunneling and spawn counts. Test ordinary play plus reset, held keys, loss/win and resume.

## Preserve the rig while authoring the look

Read current arming immediately before watched shader edits. Prepare changes disconnected, then disarm/verify before deploying. Never infer rearm authorization from a request to continue. Preserve working calibration, flips, device levels, PPS and scanner limits while adding games. Native defaults are not an automatic upgrade for an operator-tuned rig. A shared-setting change needs comparison against every existing look and separate operator acceptance.

Keep calibration and output transport downstream of the look. Extend the existing Mux/Unpack routing in the owning project; do not copy rig/device parameters into each game. Carry the picture, Scan Signal and routing tags together as a Bundle cable (see Bundle groups in `module-authoring`) instead of packing metadata into pixels.

## Pixel/path agreement

Use a single documented normalized coordinate system. If an older look still packs metadata rows under a 720-row picture, draw geometry using the picture extent, then convert to clip space using the actual target extent. Cropping a picture drawn at 744 rows introduces a 12-pixel center offset. Keep metadata byte-exact through selection; never filter or crossfade it. Send unpacked picture pixels to the projector.

Check known game coordinates against actual final pixel centers as well as decoded scan endpoints. Do this before moving calibration handles to compensate for an apparent offset.

## Prove three distinct outcomes

- Gameplay: production-core cases and real focused viewport input, followed by user play.
- Transport/geometry: checksums, routing masks, finite bounds, blank transitions, closure and correct per-device colors. Reject unwanted geometry on each destination, not merely malformed records.
- Physical projection: operator acceptance after explicit arming authorization. Native offline sample simulation can isolate timing/blanking regressions; it does not prove hardware behavior. Compare the actual configured profile and report emitted samples separately from authored segments.

If only a short bright part of a line appears, inspect minimum-speed blanking and lit duration. Closed reciprocal traversals solved this for Pong's paddles without lowering the minimum-speed threshold. Do not prescribe a universal pass count; mapped size, dwell, velocity and output profile all matter. If multiple existing looks regress simultaneously, investigate shared mapping/output settings before patching individual games.

When a show project records a rig's accepted settings, treat its numbers as that rig's observed baseline, never as generic scanner specifications.
