---
type: devlog
date: 2026-07-26
phase: 3
subphase: 3A
status: complete
approval: pending
summary: "3A - baseline captured, profile ceiling set at 14.88ms pipeline; burst confirmed a permanent latch; xypad Y confirmed down=more; follow_panel proven to pin resolution, forcing an architecture change in 3B-3E"
---

## Outcome

Baseline established on **Sentinel 0.5.49** (dist build, RTX 3090 sm86, driver 581.80,
CUDA 13.0/12.8). Three of the four pass criteria met as written; the fourth is
unsatisfiable by construction and is substituted with a stronger executable mechanism
(see 3A.1 below).

Two inherited AUTOPSIA gotchas were re-confirmed on this build rather than assumed, and
both turned out to be *worse* or *different* than documented.

## 3A.1 - Baseline captures - PARTIAL, extent clause substituted

Seven captures written to `captures/phase3a_baseline/`, all non-blank, all showing real
current-build content. **The "640x360 and 1600x900" clause was not met and cannot be.**

`follow_panel` pins a module's render size to the dock content size. Proven three ways:

- `close_window` then write `resolution_width/height` -> ignored, size unchanged
- `force_reload` with the panel closed, then write -> ignored, size unchanged
- no dock-resize mechanism exists: `/sentinel/display` is empty, `sentinel_ui get_panels`
  does not list module dock tabs, and no state path or action resizes them

The Sentinel window is also unreachable from this agent session — `windows-control
list_windows` returns nothing for the process and `sentinel_screenshot` reports "No window
found". The app is a user-launched instance reachable only over IPC. **Full-window
screenshots are therefore unavailable for the whole phase**; pipeline texture capture works
and is what actually matters.

Native extents, which are wildly inconsistent because each station inherits whatever dock
it happens to occupy:

| Station | Extent | State |
| --- | --- | --- |
| `Spline_Editor` | **100x132** | unusable smear; title illegible, knots overlap |
| `Motion_Console` | 415x132 | unusable |
| `Gizmo_Lab` | 415x132 | unusable |
| `UI_Kit` | 703x132 | labels collide — "Enable Toggle" overlaps its own control |
| `UI_Style_Tuner` | 703x1321 | wrong aspect entirely |
| `Font_Sampler` | 1920x919 | legible; mostly empty space around four tiny samples |
| `Spline_Output` | 1920x1080 | fine (not a UI station) |

This is the strongest possible evidence for the phase premise: a normalized 960x540 design
space does not survive `follow_panel`, and five of seven stations are currently illegible
at their real extents.

**Substitution, recorded per the Tier 2 precedent for unavailable tooling.** The lab
violates `CLAUDE.md`'s Direct-Manipulation UI Architecture rule, which requires separating
a canonical Program renderer at an intentional fixed resolution from a flexible
`follow_panel` editor. Every current station is `follow_panel` with no canonical output.
The v3 stations must comply, and compliance makes the extent test executable: a
non-`follow_panel` canonical output honours `resolution_width`/`resolution_height`, so
captures at exactly 640x360 and 1600x900 become a direct parameter write.

The substitute is **not weaker** — it asserts the same legibility at the same two extents,
and additionally forces a `CLAUDE.md` compliance the current lab lacks. 3B-3E criteria
amended accordingly. The clause is dropped only for 3A, where the modules under test are
the unrebuilt originals.

## 3A.2 - Profile ceiling - MET

Five samples, 2s apart, after all compiles settled.

| Sample | total_ms | pipeline_ms | Motion_Console |
| --- | --- | --- | --- |
| 1 | 15.921 | 14.310 | 14.108 |
| 2 | 16.520 | 14.874 | 14.670 |
| 3 | 16.558 | 14.898 | 14.699 |
| 4 | 16.995 | 15.024 | 14.774 |
| 5 | 16.981 | 15.314 | 15.071 |

**Ceiling: pipeline mean 14.88 ms, total mean 16.59 ms.**

`Motion_Console` is the sole hotspot at **14.66 ms mean**, flagged
`node_wall_time_over_8ms`. It is **98% of all pipeline time** — every other node measures
0.004-0.035 ms. One station nearly consumes the entire 16.67 ms 60fps budget.

Likely cause: `sui_typography.hlsli:63` performs a **4-tap bilinear** glyph lookup, the
exact pattern `au_text.hlsli:28` records as having made compiles take minutes. Motion
Console draws 16 sliders plus labels plus four waveform lanes. Compile times across the lab
were correspondingly slow (~2 minutes for seven modules).

3F's "at or below the 3A ceiling" is therefore a very soft bar. The honest target for the
rebuilt console is **an order of magnitude below it**, and 3C should state a real number.

## 3A.3 - `burst` behaviour - MET, and worse than documented

AUTOPSIA records that `type: button` parameters "read as a constant 1.0 in HLSL". On 0.5.49
the truth is a **one-way latch**, which is worse:

| Step | `burst` param | `lfo4` | `energy` |
| --- | --- | --- | --- |
| initial | 0.0 | 0.0 / 0.5 cycling | 0.24 - 0.37 varying |
| after `set burst=1` | reads 1.0 via `info` | **1.0 pinned** | **1.0 pinned** |
| after `set burst=0` | still 1.0 — write ignored | 1.0 | 1.0 |
| +8s | 1.0 | 1.0 | 1.0 |
| mute on / off | 1.0 | 0.0 then 1.0 | 0.0 then 1.0 |
| after `force_reload` x2 | **1.0 — survives reload** | 1.0 | 1.0 |
| after project reload | 0.0 | cycling again | varying again |

So: it latches true on first trigger, **cannot be written back to false**, and **survives
`force_reload`**. Only a full project reload clears it.

`lfo_compute.hlsl:36` does `if (burst) d.lfo4 = 1.0;` and line 42 pins `energy` the same
way, so a single press permanently destroys the Pulse lane and the energy readout for the
rest of the session. This is not merely "the button does not fire" — it is a live
data-corruption bug in the shipped example.

**Second finding: two MCP surfaces disagree.** `sentinel_state get` on
`/parameters/burst` returned `0.000000` throughout, while `sentinel_pipeline info` reported
`1.000000` for the same parameter at the same time. Trust `info` for button-type params.

3C's event-hit-test rewrite stands, and is now justified by a stronger defect than planned.

## 3A.4 - `xypad` Y direction - MET on the render side

Measured by writing `pad_y` on `UI_Kit` (readback confirmed) and diffing captures to locate
the marker. Row index increases downward.

| `pad_y` | marker mean row |
| --- | --- |
| 0.05 | 69.0 |
| 0.95 | 94.4 |

Higher value places the marker **lower** on screen, so the renderer maps value with Y
increasing downward and the published control output means **"down = more"**. This is the
semantic AUTOPSIA corrects by publishing `1 - pad.y` exactly once at publish time.

The host-write half — whether a real drag upward decreases the stored value — needs pointer
input and is **deferred to the hands-on pass**. Inference: since the marker tracks the value
with Y down and no one has reported the reticle fighting the mouse, the host almost
certainly stores Y down too, making the pair visually consistent but semantically inverted.
Not asserted as measured.

## Incidental findings

- `scientific_ui.hlsli:17-20` defines `SUI_CYAN`, `SUI_BLUE`, `SUI_AMBER` and `SUI_RED` as
  **all grey**. The semantic colour names carry no semantics whatsoever.
- `sui_theme.hlsli:32` sets `accent` to grey `0.72` and `sui_controls.hlsli:45,55` spend it
  on hover and slider fill — the accent means "the pointer is here".
- The lab's four Scene Group annotations and 7 node presets / 4 group presets are intact and
  confirmed present in the loaded project.

## State restored

Project reloaded from disk; `burst` cleared to 0, `pad_y` back to its saved value, all seven
stations healthy with frames climbing. No file in `projects/interaction_lab/` was modified.

## Next

3B — author `sui3_*` and the Style Authority. Taste checkpoint follows, and it is a hard
stop.
