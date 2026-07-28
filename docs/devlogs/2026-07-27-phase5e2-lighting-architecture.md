---
type: devlog
date: 2026-07-27
phase: 5
subphase: 5E.2
status: complete
approval: pending
summary: "Living Room Lighting and Architecture are responsive sui3 instruments; the complete project is healthy, preset-safe, portable, and validator-clean"
---

## Done

`LR_Lighting` and the control-free events Canvas `LR_Architecture` now use the
frozen sui3 kit. The Living Room bundle is the runtime authority and the
Showcase Gallery copies match by normalized hash. Both producer contracts,
output names, parameters, and graph links are unchanged.

### Control verdict

All four Lighting sliders stay on Canvas:

| Control | Verdict | Reason |
| --- | --- | --- |
| Window Daylight | keep | changes a spatially drawn window light against the live plan |
| Practical Lamps | keep | changes four spatial lamp records and their plan glyphs |
| Ambient Fill | keep | balances the live light field while the plan remains visible |
| Shadow Softness | keep | shapes the same six-record lighting system in spatial context |

Properties still provides exact numeric entry. The Canvas earns its place by
co-locating the gestures, six real light records, and the Architecture /
Furnishings plan—not by duplicating a generic parameter list.

`LR_Architecture` deliberately has zero controls. Its Canvas is an inspectable
13-record plan producer with middle-pan and wheel-zoom events; dimensions remain
in Properties.

## Offline gates

- Lighting: `compile_ok=true`, four parameters, two passes, zero lints;
  `module-ui.ps1 validate` reports four controls.
- Architecture: `compile_ok=true`, 16 parameters, three passes, zero lints;
  `module-ui.ps1 validate` reports zero controls.
- v1 include grep: zero across both authority and Gallery copies.
- Copy guards: Lighting 4/4 files and Architecture 6/6 files match.
- Deliberately broken authority-manifest variants were rejected:
  - Lighting `54c2fa55... != 1ed45d2a...`
  - Architecture `dcc46ebd... != 845641ba...`

The stale numbered variants were all unused orphans, not active alternative
implementations. The validator required their removal rather than regeneration.
The exact 22 reported variant directories and the absolute-path
`living_room_sdf_depth_art_test.sentinel` were removed; all 100 tracked files
remain recoverable from Git history.

## Live proof

Host: Sentinel DIST 0.5.49, interactive Windows SessionId 1.

5E.2 used **two project loads in two separate Sentinel processes**:

1. the current-HEAD baseline archive once;
2. the edited main Living Room project once.

Together with 5E.1, Living Room proof used five loads in five processes. No
project was loaded twice in one Sentinel session.

### Lighting gestures

At 1222x488, all four rails reached their expected parameter and drawn-head
targets:

| Control | target 0.25: parameter / head | target 0.75: parameter / head |
| --- | --- | --- |
| Daylight | 0.75 / 0.2540 | 2.250001 / 0.7524 |
| Practical | 1.0 / 0.2540 | 3.000001 / 0.7524 |
| Ambient | 0.375 / 0.2540 | 1.125 / 0.7524 |
| Softness | 0.265 / 0.2540 | 0.755 / 0.7524 |

At 366x429, Daylight again reached 0.75 / 2.25 with heads at 0.2688 /
0.7527. `content_size == render_size` at both extents and no rail clips.

### Architecture events

The live output published 13 PNode records. At the narrow extent, the first
desktop middle-drag correctly focused the viewport. Repeating the real gesture
while focused panned the actual plan, changing **12.6173%** of pixels with no
parameter or output-schema mutation.

### Pixel measurables and aesthetic verdict

Measured on the wide captures:

- Lighting rule-normal `(57,59,56)` run histogram: **4,327 one-pixel runs,
  zero two-pixel runs**.
- Architecture rule-normal `(61,62,60)` histogram: **1,248 one-pixel runs**;
  four two-pixel samples were classified at crossings, with no ordinary
  doubled frame.
- Both panels show the measured **7 / 14 / 21 px** body, live-number, and title
  ladder.
- Lighting accent: **376 pixels / 0.638% of lit pixels**.
- Architecture accent: **667 pixels / 2.435% of lit pixels**.

Tier 1 aesthetic verdict: Lighting reads as a live spatial instrument with a
quiet control column, while Architecture reads as a plan producer rather than
a parameter form. Wide and narrow layouts are legible, monochrome, and use
amber only for live light/category evidence. Approval remains pending.

## Group, presets, health, and cost

The `LIVING ROOM SDF` Scene Group exposes exactly six controls. Each was driven
from `/sentinel/groups/annotation_87/parameters/*`, observed at its target, and
restored:

- Render Detail 96 -> 98 -> 96
- Ambient Occlusion 2.2 -> 2.52 -> 2.2
- Daylight 2.25 -> 1.89 -> 2.25
- Practical Lights 3.000001 -> 2.52 -> 3.000001
- Exposure 1.02 -> 1.964 -> 1.02
- Bloom 0.16 -> 1.26 -> 0.16

Fidelity, Performance, Daylight, Warm Evening, Gallery, and Material Study all
recalled successfully with **193 applied values** (186 parameters plus seven
bypass flags). Performance stayed healthy at its documented 960x540 target;
the other captures were 1280x720. Same-extent adjacent preset changes were
96.356%, 91.839%, and 83.706%; the Performance transitions also changed extent.

Matched wide-panel profiles:

- Lighting v1 0.00665 ms -> sui3 0.0037 ms (**-44.4%**), 57-59 cooks/s.
- Architecture v1 0.0296 ms -> sui3 0.01025 ms (**-65.4%**), 58 cooks/s.

All six active modules remained compiled, healthy, and cooking. The refreshed
proof bundle contains graph, links, profile, pipeline health, expressions, and
Program output; Daylight/Warm Evening differ by **95.74%**. Full-window capture
still reports `No window found matching 'Sentinel'` and remains
operator-unproven.

## Project gates

- README control, preset, camera, and remix guidance matches the shipped
  surfaces.
- Curated proof refreshed without expanding the pre-existing file set.
- `validate-official-examples.ps1 -Projects living_room_sdf`: six active,
  zero orphan, zero errors.
- Public-promotion report-only run: `mode=dry-run`, 129 expected changes,
  `pushed=false`, no validation findings. Nothing was promoted.

## Pending

- Human taste approval and operator-only full-window screenshot proof.
- Phase 5F and 5G. No later phase started.
