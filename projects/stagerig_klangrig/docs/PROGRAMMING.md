# Klangrig performance controls

The show is native to Sentinel. `stagerig_klangrig_Clock` owns tempo, `stagerig_klangrig_Surface` owns
the four-page Push 2 surface, and `stagerig_klangrig_Program` publishes per-fixture
programming to Lighting and LED. The Push 2 OS package in `scripts/vendor/push2os`
is a pinned, unmodified copy; its hashes are in `scripts/push2os-provenance.json`.

## Select in Lighting

Open **stagerig_klangrig_Lighting**. Its top-down view supports click, drag selection,
Shift-add, Ctrl-toggle, A for all movers, and Escape to clear. Named buttons
select ALL, SPINE, WINGS, UPPER, LOWER, LEFT, RIGHT, LED, NONE, and the three
bays. Four custom group buttons show their saved names (first 12 characters).
Selection feeds the Push 2 attribute editor and comes back to the viewport.
ALL includes the LED virtual fixture; A selects the visible moving-head system.
LED is one virtual fixture; every physical LED face keeps its own UV region.

Name and store custom groups in the `stagerig_klangrig_Surface` control window (ADVANCED view). Eight slots
are available there; the first four appear directly in Lighting. Custom
membership uses stable fixture IDs and ignores inactive slots when selected.

## DESK (no Push 2)

`stagerig_klangrig_Desk` is a Module panel with 85 controls. Clicks leave on its `panel`
Event cable as press (event type 1) and release (2) records carrying the control
index. `scripts/show/desk_panel.luau` runs each one as a `rig_command` and sends
state (13) and lit (10) feedback back on `panel_feedback`, plus text through
`panel.label` for the BPM, beat, PLAY/PAUSE and status readouts. The panel's
manifest, `modules/Klang_Desk/desk_layout.hlsli` and
`scripts/show/desk_layout.luau` are generated together from one control list
(StageRig `tools/build_klang_desk.py`), so the pad indices always match.

The `stagerig_klangrig_Surface` control window also opens on a DESK view: TAP, PLAY/PAUSE, STOP
and SYNC with a BPM slider, the four look banks (FULL LOOKS, STATIC, EFFECTS,
COLOR) with the live look marked, BLACKOUT and STROBE latches, and camera orbit
buttons. Every DESK button runs a `rig_command` (see the README), the same path
the Push uses, so both surfaces stay in step.

## Push 2 pages

| Page | Controls |
|---|---|
| SEQUENCE | Step editor with three rhythm lanes: KICK, SNARE, HI-HAT. Encoders: BPM, length, rate, track, REPEAT/STEPS, cycle beats, rest beats, offset beats. Top buttons: PLAY, STOP, TAP, SYNC. |
| GLOBAL | Master, exposure, bloom, sensor whitening start/response, streak strength/length, haze. Top 1 holds blackout; tops 2-7 control the orbit camera. |
| RIG | Edit selected fixtures with the POSITION, LIGHT/COLOR, MOVE FX, CHASE/COLOR FX and LED FX attribute banks. Encoders 7/8 are overall pitch and rig master. Relative editing preserves differences; absolute editing gives selected fixtures the same value. |
| COLOR | A/B/C HSV palette editor, eight palettes, copy/paste and a movable pad window. |

The RIG pads hold presets, not fixture groups:

- **STATIC:** upper-left 4x4, slots 1-16. Position and beam/ring intensity.
- **EFFECTS:** upper-right 4x4, slots 1-16. Movement, chase and colour modulation.
- **COLOR:** lower-left 4x4, slots 1-16. Fixture A/B/C assignments plus the resolved palette colours.
- **FULL LOOKS:** lower-right 4x4, slots 1-16. Every fixture's static, effects and colour settings, LED strobe knobs, sequence/rhythm settings, pitch/master and the GLOBAL rendering controls. Full stores ignore fixture selection and partial masks.

Tap a populated pad to recall it. STORE, then a pad, stores into that bank.
UPDATE merges the selected attributes into the most recently stored or recalled
look in that bank. UNDO EDITS reverses a programmer edit; RESET SEL restores the
recalled base for the selection. FX OFF releases movement, chase and colour
modulation on selected fixtures without changing their static settings. The
bank menu offers position-only and level-only static store masks. Every bank
is described in [LOOKS.md](LOOKS.md).

Movement offsets add to the mounted reference aim. Intensity chases multiply
static brightness. Colour modulation is independent of both. Each effect picks
OFF, KICK, SNARE or HI-HAT; changing a rhythm does not replace static positions.
REPEAT uses cycle/rest/offset in beats; STEPS restarts a cycle on the chosen
track's step hits. Everything follows the same Conductor tempo.

LED modes are SOLID, OUTLINES, CHASE, PULSE, SCATTER and eleven programmed
content patterns (COMET to RIPPLE). LED colour uses palette A/B/C, and its level
follows the same master and blackout as the moving heads. The Address sweep and
Sequential face test in stagerig_klangrig_LED override the performance pattern for
addressing checks while still respecting master and blackout.

## Global keys (every page)

| Button | Action |
|---|---|
| Play (bottom left) | Start / pause the clock; lit while running. Shift+Play stops and returns to beat 0. |
| Tap Tempo (top left) | Tap tempo; pulses on each beat. Shares tap history with SEQUENCE TAP. |
| Metronome | SYNC: resync to beat 0. |
| Arrows | Orbit camera (below). |
| Clip | Save the live camera as the current orbit point. |
| Right-side bottom button | Hold blackout. |
| Right-side second button | Hold all-rig white strobe (12 Hz, 35% duty). |

Blackout wins when both side holds are pressed; releasing either reveals the
underlying look. Held states never enter presets. The strobe includes mover
beams, rings and all wing LED loops.

## Orbit camera

The arrows jump `stagerig_klangrig_Camera` between 40 authored points (8 orbit positions x 5
heights), from the camera's point of view:

- Left / right step one of 8 positions round the room (F, FL, L, BL, B, BR, R, FR).
- Up / down step through 5 heights, wrapping: UNDER, LOW, MID, HIGH, TOP.
- Each position aims at a different part of the rig and fits its own lens, so
  the symmetric rig still gives 40 distinct pictures.
- GLOBAL top 2 sets the move: CUT, 0.5, 1, 2 or 4 s. Glides ease round the orbit
  and taps during a glide stack. After a hand-moved camera, the next tap starts
  from the nearest point.
- GLOBAL tops 3 / 4 zoom in / out; top 5 goes home (MID F).
- To adjust a point, arrow to it, move the camera by hand in the viewport, then
  press Clip (or GLOBAL top 6). GLOBAL top 7 restores the authored framing.
  Saved points live in the Surface Script state; save the project to keep them.
- While moving, a CAMERA panel covers the right quarter of the Push display.

Authored points are the `M.ROWS` and `M.COLS` tables in
`scripts/show/camera_orbit.luau`. The Push 2 controller profile has no arrow or
Clip controls, so the module listens to their raw CCs (arrows 44-47, Clip 113)
on the port it owns and drives their LEDs the same way.

## Persistence

The programmer, palettes, sequences and custom groups persist in
`presets/stagerig_klangrig_push2.json` plus the Surface Script's saved snapshot. Static,
effects and colour presets have separate native bank files; `stagerig_klangrig_complete`
backs FULL LOOKS. Full recall keeps BPM and transport while restoring fixture
attributes, pitch/master, rhythm, palettes, LED knobs and GLOBAL render controls.

## Implementation notes

Stable slots: 0-63 first spine fixtures, 64-255 twelve wings with sixteen
reserved slots each, 256-287 extra spine fixtures, and 288 the LED system.
Raising the spine to 96 does not renumber wing fixtures or their presets.

Sentinel's native programmer catalog is limited to 128 targets and 1,024 paths,
so this show packs its programming into bounded strings (nine each for static
and effect attributes), uploads one typed GPU buffer, and commits a revision
only after every fixture upload finishes. Recall decodes four populated
partitions per control tick; rapid recalls coalesce per bank. Command-to-GPU
response is roughly 130-150 ms with playback running; physical motor slew is
separate.

LED Snare Scatter (EFFECTS 03) stores the LED group only and layers over the
movers' kick chase. Select LED in Lighting, then choose LED STROBE from the RIG
attribute menu. Knobs 1-6: rate (flashes per beat), duty, burst length,
stagger, trigger lane and direction.

## Warehouse

`stagerig_klangrig_Warehouse` is independent of Push 2 programming. ROOM LIGHTING controls
room fill, truss fill, moving-head spill, LED spill and fill tint. MATERIALS
controls metal roughness/reflection, floor roughness/reflection/wear and concrete
texture. HALL GEOMETRY controls dimensions, walls/roof and floor level (saved
hall: 36 x 56 x 14 m, floor at world Y=0). Floor reflections are current-frame
screen-space approximations; off-screen objects cannot reflect.
