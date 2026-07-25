---
type: state
updated: 2026-07-25
---

# Workspace State

## Current focus

Phase 2 - Audio Analysis v2 (`pulse2`) is planned and awaiting implementation. It builds a reusable
GPU audio analysis system: adaptive-whitened SuperFlux onset detection, click-to-place spectral
region isolation, a multi-feature classifier for coincident hits, and comb-filter tempo with a
dual-loop beat PLL. The scoring harness is sub-phase 2A and is blocking.

CRYOGRAM is committed and working as a measured-crystal audio-reactive example, with two known
defects tracked separately (see Blockers).

## Active sub-phase

None started. Next is 2A1 - Frozen corpus and onset-export contract.

Phase 2 has been audited before implementation by four parallel agents. Ten sub-phases (2A1, 2A2,
2B, 2C1, 2C2, 2C3, 2D, 2E1, 2E2, 2F). Five judgement calls are recorded in the phase doc's Plan
Audit Findings section and are individually revertible.

## Blockers

None blocking Phase 2.

Tracked separately, out of Phase 2 scope:

- CRYOGRAM's snare volumetric noise burst does not render. Shock records are confirmed correct and
  the graph link resolves to the right pins, so the fault is in `cryo_relief`'s shade pass. One
  cause was fixed (radius scaled by strength plus a lifted sphere centre shrank the ground
  intersection to a ~0.1-unit speck on a 3.55-unit plate); still not visible.
- CRYOGRAM graph pin shift: adding `Shocks` ahead of `Probes` in the crucible's `data_outputs` moved
  `Probes` from pin 3 to pin 4, so the two older links into `cryo_console` and `cryo_program` now
  deliver `Shocks` into `Probes` inputs. Needs rewiring.

## Decisions pending

- Cold-load Scientific Organism from a clean checkout before public-workspace or official-gallery promotion.
- Keep raw intermediate effect captures in coordinate-contract proof; a correct later overlay is not sufficient.
- Phase 2 sub-phase 2A must settle `fft_size` 4096 versus 2048 by measurement. The source research
  recommends 4096 (11.7 Hz/bin, 0-12 kHz); the alternative is 2048 (23.4 Hz/bin, full 0-24 kHz).
  Adopt whichever scores higher and record the numbers.
- Whether the generated corpus WAV files are committed or regenerated on demand.

## Last devlog

`docs/devlogs/2026-07-23-axiom-choir-example.md` - complete, approved.

## Phase 2 - Audio Analysis v2 (in progress, 2026-07-25)

Complete and committed: 2A1 corpus + onset contract, 2A2 scorer/baseline, 2B core
detector (aggregate F1 0.774 vs 0.706 baseline), 2C1 region masks (kick 0.909,
aggregate 0.797).

**2C2 is BLOCKED at criterion 2 and is human checkpoint 1.**

Proven: criterion 1 (display audio-driven and legible) — see
`docs/devlogs/2026-07-25-pulse2-2c2-console-display.md`.

Blocker: no available automation command delivers viewport pointer events to a
Module. Tried `CLICK_AT`, `DRAG_AT` (both report ok, `method: imgui_injection`) and
`sentinel_viewport pick` (rejected — needs a `selection` interaction). A
position-independent event counter in the module (`dbg_events` control output) reads
exactly 0 throughout, and the shipped `cryo_console` events module behaves the same
way when probed, so the fault is the injection path and not the module.

Two ways forward, user's call:
1. Hand-verify the drag (open the `pulse2_console` tab, set Active Lane, drag
   vertically). If `dbg_events` goes non-zero, criteria 2-5 close quickly.
2. Redesign the interaction onto the host-owned selection path — declare regions as
   selectable objects with `viewport.interactions: [selection]` and drive them via
   `sentinel_viewport edit` four-phase transactions, which IS synthetically
   automatable. Larger change; abandons raw pointer events.

Not started: 2C3 lateral inhibition (the designed fix for the open 2C1 snare
precision deficit, 0.31-0.34 — kick click bleeding into 200-2400 Hz), 2D, 2E1,
2E2, 2F.

Trap defused: the console publishes region edges as control outputs and
`sentinel_expression` can bind them onto the analyzer's `rgn*_hz` parameters. Those
expressions are deliberately CLEARED — with them bound, a panel drag would silently
override the scorer's writes and change scoring configuration. Re-apply only for
interactive use; clear before any corpus run.

### 2C2 update - blocker RESOLVED by human verification

The user performed a real drag on the `pulse2_console` panel. `dbg_events` read
**1315**, and region placement visibly affected detection inside the drawn band. The
module was correct all along; `CLICK_AT` / `DRAG_AT` / `viewport pick` simply do not
feed the module viewport event ring on this build. Criterion 2's mechanism is
confirmed live. Do NOT re-litigate this — use real input, not injection, to test
Module viewport events.

Remaining for 2C2: criterion 3 (save/close/reopen byte-identity + undo of a drag),
4 (firing flash asserted in a capture during playback), 5 (mini-trace legibility),
6 (`module-ui.ps1 validate` + criterion 1 at 640x360 and 1600x900).

USER DECISION PENDING - palette. The user finds black->white hard to read and wants a
darker base through a colour spectrum to separate instruments. This OVERRIDES the
monochrome look specified in both CLAUDE.md and the phase doc (which explicitly says
not Magma/Inferno); CLAUDE.md permits it because the user asked. Awaiting their choice
of ordering: colour ramp first, or finish criteria 3-6 first.
