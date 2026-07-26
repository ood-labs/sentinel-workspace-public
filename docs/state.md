---
type: state
updated: 2026-07-26
---

# Workspace State

## Current focus

Phase 2 - Audio Analysis v2 (`pulse2`) is implemented and committed, awaiting approval. It built a
reusable GPU audio analysis system: adaptive-whitened SuperFlux onset detection, click-to-place
spectral region isolation, a multi-feature classifier for coincident hits, and comb-filter tempo
with a dual-loop beat PLL. Two measured criteria gates are open (see below).

CRYOGRAM is committed and working as a measured-crystal audio-reactive example, with two known
defects tracked separately (see Blockers).

## Active sub-phase

None. All ten sub-phases (2A1 through 2F) are closed. Phase 2 is at its approval boundary.

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
Settled during Phase 2, kept here as the record:

- `fft_size` is **2048**, not the 4096 the source research recommended. 4096
  truncates Spectrum coverage to 0-12 kHz while still publishing 1024 bins, and
  nothing in the port metadata reveals it. Every committed score table records
  the `fft_size` in force.
- Corpus WAVs **are committed**, hash-frozen by `corpus.sha256`; the scorer
  refuses to run if any file drifts.

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
   corpus-wide. Actual CMLc 0.00-0.78, AMLc 0.02-0.78.

The beat clock itself is sound - intervals regular, no dropped beats, zero
spacing rejections. What fails is beat PLACEMENT.

**Lead on the continuity failure, found by a post-audit test and left failing
rather than loosened:** the PLL's period settles 5.6% above the tempo it tracks
(93.09 vs 88.14 hops on `four_on_floor_128`) while locked and correcting every
cook. The update is an exponential tracker whose only fixed point is the
observation, so something else is acting on `period`. A clock running 5.6% slow
drifts a quarter beat every four or five beats, which is more than the
continuity tolerance allows. **Chase this before resuming the snapping work.**

The `beat_snap` onset-anchoring mechanism is implemented and shipped disabled;
enabling it measured strictly worse even after a gain-scaling bug was fixed.

## Decisions pending for Phase 2 approval

- Accept the two open gates and approve Phase 2, re-scope them, or authorize
  further work on the PLL period defect above.
- `mu_tempo` ships at 0.2 rather than the phase doc's 0.02, because normalising
  the loop gains to per-beat changed their units. Recorded in the manifest and
  the 2E2 devlog as a Tier 2 adoption; the doc's Tier 2 clause does not name
  `mu_tempo` explicitly, so it is authorization by analogy.

## Last devlog

`docs/devlogs/2026-07-26-pulse2-2f-project-portability.md` - complete, approval
pending. Preceded by `2026-07-26-pulse2-2e2-pll-beat-clock.md`, which carries the
audit record.
