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

None started. Next is 2A - Scoring harness and synthetic corpus.

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
