---
type: state
updated: 2026-07-29
---

# Workspace State

## Current focus

**Cloth Lab shipped 2026-07-29 and is approved.** `modules/cloth_engine` is a
real-time XPBD cloth engine: one dispatch, 1024 threads, 2048 particles resident in
groupshared, every substep and graph-coloured constraint sweep barrier-separated
inside that single dispatch. Sign-aware curvature bending, long-range attachment,
collider projection with friction, tearing, viewport grab/cut, a Catmull-Rom
bicubic render surface, and kick-driven strike impulses from `audio_bands`.
0.56 ms GPU; 0.78% peak tensile strain on a sphere drape with zero penetration.
Packaged as `projects/cloth_lab/` with a README and a `Kick Strike Membrane`
preset.

Three reusable headers came out of it: `modules/_shared/xpbd/`,
`modules/_shared/surface/bicubic.hlsli`, `modules/_shared/viewport/pick3d.hlsli`.
Engineering notes in `knowledge/gpu-cloth-and-xpbd.md`.

**`modules/audio_bands` is now the documented source of truth for audio
reactivity.** Its `Threshold Mode` defaults to Fixed. The `pulse2_*` and
`cryo_pulse` modules are superseded and must not be built on; they are retained
only because saved projects reference them (`streamdiff_brush_canvas` needs
`pulse2_hits` and `bands_demo`). Stated at the head of
`knowledge/audio-reactivity.md` and summarised in all three entry manuals.
Next on cloth: snare behaviour as a distinct gesture from the kick's poke.


Strata maintenance completed on 2026-07-28: `blob_render` now uses the native
internal Fly camera and exposes Draft, Performance, Fidelity, and fully tunable
Custom SDF quality. The saved Draft 480 x 720 state measures 60 Hz with no graph
hotspots; higher tiers intentionally spend that budget on more parts, tighter
surface/normal precision, AO, shadows, and AA.

Phase 5 - Official Example UI Port is **technically complete; approval
pending**. After collection review, Topographic, Strata, and Desert were
deliberately reduced from authored Canvas panels to 480 x 270 passive control
bus previews with all exact editing in Properties. The standalone projects are
the shipping authorities. The combined Gallery remains review-only and is
excluded from promotion because its aggregate VRAM cost is unsuitable for
normal distribution.

Phase 2 - Audio Analysis v2 (`pulse2`) is implemented and committed, awaiting approval. It built a
reusable GPU audio analysis system: adaptive-whitened SuperFlux onset detection, click-to-place
spectral region isolation, a multi-feature classifier for coincident hits, and comb-filter tempo
with a dual-loop beat PLL. Two measured criteria gates are open (see below).

Phase 3 - Interaction Lab v2 is **in progress**. All six sub-phases 3A-3F are built and committed,
and the **3B taste checkpoint has passed**. The lab is four stations (Style Authority, Motion
Console, Spline Desk, Gizmo Desk) plus `Spline_Output`. 3F's own seven criteria are met. The phase
is held open by ONE thing: the operator hands-on gesture pass for 3B.3, 3D.1 and 3E.1, which the
phase doc's Autonomy section makes a hard blocker.

Phase 4 - Data Scope is **planned**. Lift the CHOP-style scrolling strip chart proved in
`modules/audio_bands` into a documented, reusable `sui3_trace` kit component with a worked example
station, so any module can plot any scalar stream over time.

CRYOGRAM is committed and working as a measured-crystal audio-reactive example, with two known
defects tracked separately (see Blockers).

## Active sub-phase

Phase 5: none. 5A-5G are closed. Human taste approval and the operator-owned
full Sentinel window screenshot remain pending under the phase contract's
allowed proof boundary; they do not require more implementation.

Phase 2: none. All ten sub-phases (2A1 through 2F) are closed. Phase 2 is at its approval boundary.

Phase 3: 3A-3F complete and committed, taste checkpoint passed. **Awaiting the operator hands-on
gesture pass**, then `$end-session`. Three audit rounds have landed; every actionable finding is
fixed. Regression harness: `python tools/interaction-lab-guards.py` (42 passed, 0 failed, 4 skipped
-- the four skips ARE the hands-on gap). Gesture recorder: `python tools/interaction-lab-handson.py`.

Round three caught a regression the round-one fix introduced: `spline_desk` re-captured the drag
snapshot on every cook of a live drag, so a drag accelerated away from the pointer and undo was
destroyed. It shipped green through the whole guard suite, because no automated call can drive a
pointer. **Five unguarded fixes now rest on the hands-on pass**, not three criteria.

Phase 4: decomposed into 4A (extract and document `sui3_trace.hlsli`), 4B (the Data Scope station),
4C (second consumer plus guards). Contract: `docs/phases/phase-4-data-scope.md`. Not started. It does
not depend on the Phase 3 hands-on blocker clearing, and must not be used as a reason to treat
Phase 3 as done.

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

While dragging, watch for two specific symptoms that no guard can see. A knot or object that
**accelerates away from the cursor** rather than tracking it means the snapshot is re-arming
mid-drag. **Undo immediately after a drag** must restore the pre-drag position; if it leaves things
where they are, the undo point was overwritten. Both were live defects during round three.

**3B taste checkpoint PASSED (2026-07-26).** Look approved; pad, rail, state and bank confirmed
responding by the operator. 3B.3 (hover specifically) stays open and is carried into the 3F
hands-on pass.

**PHASE 2: two measured criteria gates are open.** 2E1 criterion 3 (correct metrical level, 8/11
against a required 11/11) and 2E2 criterion 3 (CMLc/AMLc short of the bar). Neither is loosened and
both need a human call. Detail in the Phase 2 section below.

**HOST XY PAD DEFECT: CLOSED 2026-07-27, by the host.** Both host surfaces are now Y-up and agree.
Measured through `sentinel_ui action=viewport_control_drag` (new in this build): a pointer at the
top of the pad rect writes a HIGH value, so `value = 1 - pointer_y`. The kit had been drawing
Y-down to compensate, so on the updated host the compensation became the bug and the operator saw a
correct Properties row against an inverted pad. `sui3PadPoint` is now Y-up; that one function is
still the only value-to-pixel conversion for a pad. Full history in
`modules/_shared/ui/sui3_core.hlsli`.

**Injection constraint REVISED.** 3A recorded pointer injection as dead. That was too pessimistic:
`sentinel_ui action=click method=mouse` works and was proven by flipping a bool and reading it
back. Caveats that produce a false pass: the widget path needs the window prefix
(`Properties/Specimen/##demo_toggle`), and both `action=set` and `click` WITHOUT `method: mouse`
report success while changing nothing - always confirm with a StateTree readback. There is still no
MCP route to click an arbitrary point inside a module preview. Because `viewport.controls` binds to
parameters, though, everything downstream of a value is automatable; only hit-region mapping needs
a human. 3A's other finding stands: the Sentinel window is unreachable from the agent session, so
full-window screenshots are unavailable for the phase; pipeline texture capture works.

Tracked separately, out of Phase 2 scope:

- CRYOGRAM's snare volumetric noise burst does not render. Shock records are confirmed correct and
  the graph link resolves to the right pins, so the fault is in `cryo_relief`'s shade pass. One
  cause was fixed (radius scaled by strength plus a lifted sphere centre shrank the ground
  intersection to a ~0.1-unit speck on a 3.55-unit plate); still not visible.
- CRYOGRAM graph pin shift: adding `Shocks` ahead of `Probes` in the crucible's `data_outputs` moved
  `Probes` from pin 3 to pin 4, so the two older links into `cryo_console` and `cryo_program` now
  deliver `Shocks` into `Probes` inputs. Needs rewiring.

## Decisions pending

- Any public-repository promotion of Phase 5 requires a separate explicit
  request. The combined Showcase Gallery is explicitly review-only and cannot
  be promoted by the official-example promotion tool; ship the standalone
  project folders instead.

- Cold-load Scientific Organism from a clean checkout before public-workspace or official-gallery promotion.
- Keep raw intermediate effect captures in coordinate-contract proof; a correct later overlay is not sufficient.
- Whether Interaction Lab v2 is promoted to the public workspace after Phase 3. Deliberately out of
  Phase 3 scope: Phase 1 is still approval-pending with an open cold-load follow-up.

Settled during Phase 2, kept here as the record:

- `fft_size` is **2048**, not the 4096 the source research recommended. 4096
  truncates Spectrum coverage to 0-12 kHz while still publishing 1024 bins, and
  nothing in the port metadata reveals it. Every committed score table records
  the `fft_size` in force.
- Corpus WAVs **are committed**, hash-frozen by `corpus.sha256`; the scorer
  refuses to run if any file drifts.

## Decisions pending for Phase 2 approval

- Accept the two open gates and approve Phase 2, or re-scope them. The PLL
  period defect that was the standing lead is now fixed and is no longer a
  candidate explanation for the remaining continuity shortfall.
- The harness scored the WRONG DETECTOR for six consecutive full-corpus runs
  because `score_detector.py --lane-map` defaulted to `lane_map.json`
  (`pulse_baseline`, the Phase 1 module). The flag is now required, the map is
  recorded in every written table, and a baseline scored on a different detector
  is a hard error. No committed table was affected -- `scores/2E2.json`
  reproduces at +0.000 on every lane -- but any score table produced outside
  this workspace before that fix should be re-checked for which detector it
  actually measured.
- `mu_tempo` ships at 0.2 rather than the phase doc's 0.02, because normalising
  the loop gains to per-beat changed their units. Recorded in the manifest and
  the 2E2 devlog as a Tier 2 adoption; the doc's Tier 2 clause does not name
  `mu_tempo` explicitly, so it is authorization by analogy.

## Last devlog

`docs/devlogs/2026-07-29-cloth-lab-xpbd-engine.md` - complete, **approved**. The
Cloth Lab engine, its three extracted shared headers, the `audio_bands` source-of-
truth documentation, and the packaged example. User confirmed the look and verified
the viewport grab by hand (injected input cannot fire Module viewport events, so
that gate needed a human).

`docs/devlogs/2026-07-29-streamdiff-laser-etch-checkpoint.md` - in-progress,
approval pending. A mid-work checkpoint from the prior session, deliberately left
open.

`docs/devlogs/2026-07-28-strata-blob-render-refresh.md` - complete, approval
pending. Strata's blob renderer camera, SDF quality controls, and measured
60 Hz Draft path are closed as a maintenance pass.

`docs/devlogs/2026-07-27-phase5-close-out.md` - complete, approval pending.
The final implementation/audit narrative is
`docs/devlogs/2026-07-27-phase5g-showcase-gallery-resync.md`; 5A through 5G
each have their own committed wrap record.

`docs/devlogs/2026-07-26-phase3-audit-round-three.md` - complete, approval pending. The Phase 3
boundary record is `docs/devlogs/2026-07-27-phase3-close-out.md` and the 3F narrative is
`docs/devlogs/2026-07-26-phase3f-consolidation.md`. Nine Phase 3 devlogs exist (3A, 3B, 3C
burst-confirmed, 3C motion-console, 3D, 3E, 3F, close-out, audit round three); 3B, 3D and 3E are
`in-progress` because their gesture criterion is open, per the phase doc.

Upstream's most recent is `docs/devlogs/2026-07-26-pulse2-2f-project-portability.md` - complete,
approval pending, preceded by `2026-07-26-pulse2-2e2-pll-beat-clock.md`, which carries the Phase 2
audit record.

Note: the close-out devlog is dated `2026-07-27` in its filename and frontmatter but was written and
committed on 2026-07-26. Left as-is rather than renamed mid-phase; worth correcting at approval.

## Phase 2 - Audio Analysis v2 (complete, approval pending, 2026-07-26)

All ten sub-phases are implemented and committed. `projects/pulse2/` is bundled,
loads from a clean path with relative `project_dir` values, and reproduces its
committed score table from that load.

Onset detection is the solid part: kick 0.913, snare 0.782, hat 0.969 mean F1 on
the frozen corpus `50e89b594f08b41a` at +/-25 ms, raw. Tempo lands within 2 BPM
on every pattern that locks. The detector is honest under a -44 dBFS noise floor
and under digital silence, and held F1 to +0.000 across a 30-minute soak.

**TWO MEASURED CRITERIA GATES ARE OPEN AND NOT AUTHORIZED.** Both are recorded,
neither is loosened, and both need a human call:

1. **2E1 criterion 3** - correct metrical level on 11/11 patterns. Actual 8/11.
   `hats_only_150` was proven unachievable from magnitude-only data (100
   byte-identical hats at exactly 9600-sample spacing; no phase information
   exists in it). `sparse_90` and `halftime_shuffle_88` remain off.
2. **2E2 criterion 3** - CMLc >= 0.75 on steady patterns, AMLc >= 0.85
   corpus-wide. Actual after the outlier-rejection fix: CMLc 0.00-0.90,
   AMLc 0.03-0.90. Improved on seven of eleven patterns, still short.

The beat clock itself is sound - intervals regular, no dropped beats, zero
spacing rejections. What fails is beat PLACEMENT.

**The PLL period defect is RESOLVED and continuity improved, but not enough.**
It was never a PLL bug: an exponential tracker converges to the MEAN of its
input and every summary compared it against the MEDIAN. The comb intermittently
returns a metrical relative (131.8 hops against a true 88.2, a 3:2 dotted
quarter, about one cook in six) and those excursions dragged the mean 6% off.
The tempo loop now rejects outliers instead of averaging them, with a NET
disagreement counter so rejection cannot become a trap. Four of five patterns
now converge onto their observation exactly.

Continuity rose on seven of eleven patterns (breakbeat 0.02 -> 0.65, quiet_intro
0.09 -> 0.60, four_on_floor 0.19 -> 0.44, hats_under_loud_kick 0.78 -> 0.90,
tempo_ramp 0.71 -> 0.83) with onset F1 unchanged at +0.000 on every lane. It is
still short of the criterion: four_on_floor 0.44, dense_140 0.08,
syncopated_funk 0.00 against CMLc >= 0.75. Post-fix table: `scores/2E2fix.json`.

The `beat_snap` onset-anchoring mechanism is implemented and shipped disabled;
enabling it measured strictly worse even after a gain-scaling bug was fixed.

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

**The xypad gotcha above is wrong, and so was the first correction to it.** Cost five operator
reports of the same defect across four rounds. The host used to use OPPOSITE Y conventions on its
two surfaces for one `point2D` parameter - Properties row Y-up, canvas `kind: xypad` gesture
Y-down - so no module drawing satisfied both and flipping the Y term only chose which surface was
broken. **The host closed this on 2026-07-27**: both surfaces are Y-up and `sui3PadPoint` is now
Y-up to match, verified by drag measurement and by capture at both ends of the well. The
inverted-rect workaround was never viable and is closed by `module-ui.ps1`. Full history in
`modules/_shared/ui/sui3_core.hlsli`; read it before touching a pad.

Known hazards: rebuilt modules will orphan the 4 group presets and 7 node presets in
`interaction_lab.sentinel` - 3F migrates or explicitly retires each; `sui_*` headers
must not be edited because every other project bundles a copy.
