---
type: state
updated: 2026-07-27
---

# Workspace State

## Current focus

Phase 2 - Audio Analysis v2 (`pulse2`) is **in progress**, not planned. See the detailed Phase 2
section below for the live position; this header block was stale through 2D and has been corrected.

Phase 3 - Interaction Lab v2 is **in progress**. All six sub-phases 3A-3F are built and committed,
and the **3B taste checkpoint has passed**. The lab is four stations (Style Authority, Motion
Console, Spline Desk, Gizmo Desk) plus `Spline_Output`. 3F's own seven criteria are met. The phase
is held open by ONE thing: the operator hands-on gesture pass for 3B.3, 3D.1 and 3E.1, which the
phase doc's Autonomy section makes a hard blocker.

CRYOGRAM is committed and working as a measured-crystal audio-reactive example, with two known
defects tracked separately (see Blockers).

## Active sub-phase

Phase 2: 2D complete with criterion 1 short (see below). Next is 2E1.

Phase 3: 3A-3F complete and committed, taste checkpoint passed. **Awaiting the operator hands-on
gesture pass**, then `$end-session`. Two audit rounds have landed; every actionable finding is
fixed. Regression harness: `python tools/interaction-lab-guards.py` (37 passed, 0 failed, 4 skipped
-- the four skips ARE the hands-on gap). Gesture recorder: `python tools/interaction-lab-handson.py`.

Phase 2 was audited before implementation by four parallel agents. Ten sub-phases (2A1, 2A2, 2B,
2C1, 2C2, 2C3, 2D, 2E1, 2E2, 2F). Five judgement calls are recorded in the phase doc's Plan Audit
Findings section and are individually revertible.

Phase 3 has six sub-phases (3A, 3B, 3C, 3D, 3E, 3F) and has **not** been plan-audited.

## Blockers

**PHASE 3 HARD BLOCKER: the hands-on gesture pass.** 3D.1 (anchor drag, handle drag, marquee,
keyboard), 3E.1 (gizmo axis/ring/centre drag) and 3B.3 (hover, which must NOT change the accent).
No MCP route exists to click inside a module preview, so these need a hand on the mouse. Run
`tools/interaction-lab-handson.py` first; it records the pass as assertions about what actually
moved and voids the record if any automation door fires.

**3B taste checkpoint PASSED (2026-07-26).** Look approved; pad, rail, state and bank confirmed
responding by the operator. 3B.3 (hover specifically) stays open and is carried into the 3F
hands-on pass.

**Injection constraint REVISED.** 3A recorded pointer injection as dead. That was too pessimistic:
`sentinel_ui action=click method=mouse` works and was proven by flipping a bool and reading it
back. Caveats that produce a false pass: the widget path needs the window prefix
(`Properties/Specimen/##demo_toggle`), and both `action=set` and `click` WITHOUT `method: mouse`
report success while changing nothing - always confirm with a StateTree readback. There is still no
MCP route to click an arbitrary point inside a module preview. Because `viewport.controls` binds to
parameters, though, everything downstream of a value is automatable; only hit-region mapping needs
a human. 3A's other finding stands: the Sentinel window is unreachable from the agent session, so
full-window screenshots are unavailable for the phase; pipeline texture capture works.

Nothing blocking Phase 2.

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
- Whether Interaction Lab v2 is promoted to the public workspace after Phase 3. Deliberately out of
  Phase 3 scope: Phase 1 is still approval-pending with an open cold-load follow-up.

## Last devlog

`docs/devlogs/2026-07-27-phase3-close-out.md` - complete, approval pending. It is the phase
boundary record; the narrative lives in `docs/devlogs/2026-07-26-phase3f-consolidation.md`. Eight Phase 3
devlogs exist (3A, 3B, 3C burst-confirmed, 3C motion-console, 3D, 3E, 3F, close-out); 3D and 3E are
`in-progress` because their gesture criterion is open, per phase doc :551.

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

## Phase 3 - Interaction Lab v2 (in progress, 2026-07-26)

Plan doc: `docs/phases/phase-3-interaction-lab-v2.md`. Not plan-audited.

**3A complete** — `docs/devlogs/2026-07-26-phase3a-baseline.md`. Profile ceiling 14.88 ms pipeline
with `Motion_Console` alone at 14.66 ms (98% of all pipeline time). `burst` confirmed a **one-way
latch** that survives two `force_reload`s — worse than the documented constant-1.0 — so one press
destroys the Pulse lane for the session; `sentinel_state get` and `sentinel_pipeline info` disagreed
on it, and `info` is the one to trust. xypad Y confirmed down=more on the render side.
`follow_panel` proven to pin resolution, which forced Amendment 1: every v3 station declares a
canonical fixed-resolution renderer. **Amendment 1 was later reversed by Amendment 3** -- it was the
wrong diagnosis, and all four shipped stations are `follow_panel`.

**3B complete** — `docs/devlogs/2026-07-26-phase3b-sui3-kit.md`. Six of seven criteria pass with
measurements; 3B.3 (hover) is structurally proven but gesture-dependent and deliberately **not**
marked complete. Two defects were caught by measuring rather than looking, both of which read as
correct to the eye:

1. Every hairline was a **2px half-intensity straddle** — `P = tid + 0.5` puts pixel centres on
   half-integers while the layout supplies integer edges. Fixed kit-wide by snapping geometry to
   `floor(v) + 0.5`; cell-frame runs went from `{1: 627, 2: 581}` to `{1: 1162}`.
2. The METERS bank rendered no readable value while the kit's own header claimed every control
   does. Fixed on both sides.

`Style_Authority` measures **1.865 ms** mean — one seventh of `Motion_Console` while drawing a much
denser sheet, which is the payoff for the single-tap glyph.

The premise: AUTOPSIA deliberately does not use Interaction Lab's shared UI kit
(`modules/_shared/au_hud/au_text.hlsli:9`). The refinement lives in the `au_*`
renderers while every lab station is built on the older, generic `sui_*` layer, so
lifting the lab station-by-station would be fighting the kit. The kit is replaced
first, then the stations are rebuilt on it.

Measured differences driving the work: 2px strokes plus a gutter versus exact 1px
hairlines; `lerp` toward filled control greys versus additive ink on a near-black
field; a grey accent spent on hover versus amber reserved for meaning; normalized
960x540 layout versus pixel space; no per-control readouts versus a live value on
every control.

Two operator decisions, binding:
1. **Hybrid scope.** New kit; Spline Editor, Gizmo Lab and Motion Console rebuilt;
   UI_Kit + Font_Sampler + UI_Style_Tuner merged into one Style Authority station that
   publishes the live theme the other three consume. Seven stations become four.
2. **Amber accent reserved for meaning.** Overrides the lab's monochrome precedent.
   X/Y/Z gizmo handles stay red/green/blue - those carry directional meaning.

Three platform gotchas inherited from AUTOPSIA, to be re-confirmed on this build in
3A rather than assumed: `type: button` reads a constant 1.0 in HLSL (Motion_Console's
`burst` is declared that way and is suspected dead); host `xypad` stores Y increasing
downward; never `[unroll]` a glyph loop.

Known hazards: rebuilt modules will orphan the 4 group presets and 7 node presets in
`interaction_lab.sentinel` - 3F migrates or explicitly retires each; `sui_*` headers
must not be edited because every other project bundles a copy.
