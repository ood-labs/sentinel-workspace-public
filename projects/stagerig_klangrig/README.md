# Klangrig

A programmed concert lighting rig that runs entirely inside Sentinel: 216 moving
heads and 48 LED truss faces on a spine-and-wings structure in a warehouse, with
a full bank of looks and a native Ableton Push 2 performance surface. Everything
the show needs is in this folder. It needs no external control application.

Requires Sentinel 0.5.87 or later. A Push 2 is optional: the `stagerig_klangrig_Desk` panel
plays the whole show with the mouse.

## First run

1. Open `stagerig_klangrig.sentinel`. The rig renders in `stagerig_klangrig_Renderer`. If `stagerig_klangrig_Surface`
   and `stagerig_klangrig_Push2_Display` are disabled and `stagerig_klangrig_Clock` is stopped (a freshly
   generated starter show; see docs/starter/START-HERE.md), enable both nodes, run their Start
   action (node header, or `/actions/start`) and start the clock. The Surface
   Script then starts and the rig plays at the saved tempo.
2. Open the `stagerig_klangrig_Desk` panel (Window toggle in its node header). It is the
   show's desk:
   - **TAP** (tap along to set the tempo; it pulses on the beat), **PLAY/PAUSE**,
     **STOP** (pause and return to beat 0) and **SYNC** (restart the bar), with
     live BPM and bar/beat readouts.
   - Four banks of 16 looks: **FULL LOOKS** (the whole picture), and the layered
     **STATIC** (position), **EFFECTS** (movement and chases) and **COLOR** banks.
     The live look in each bank is lit.
   - **BLACKOUT** and **STROBE**, which act while held.
   - **CAMERA** arrows (UP over LEFT/DOWN/RIGHT, as on the Push 2), **IN**, **OUT**
     and **HOME**, which orbit the view.
   The `stagerig_klangrig_Surface` control window also opens on a simpler **DESK** view with
   the same controls.
3. In the `stagerig_klangrig_Surface` window, pick **ADVANCED** in the **View** combo for the programmer and Push 2 tools:
   **Push 2 page** switches between SEQUENCE, GLOBAL, RIG and COLOR, and
   **Encoder -1 / +1** turns the selected encoder. Expand **Controller surface**
   and pick `push2-user-mode` for clickable Push 2 pads, buttons and encoders.
4. To use a real Push 2, put it in User mode. Close any other application that
   drives its display. The Surface configures the `push2-user-mode` controller
   profile for the raw port name `Ableton Push 2` and enables it once startup
   completes. `stagerig_klangrig_Push2_Display` drives the screen over WinUSB. The Push and
   the desks drive the same looks and transport and can be used together.

Looks are listed in [LOOKS.md](docs/LOOKS.md). Performance controls are described in
[PROGRAMMING.md](docs/PROGRAMMING.md).

## Automation (agents, MCP, scripts)

Everything the DESK and the Push do is also reachable through state, so an agent
can operate the show without hardware:

- **Commands:** write a string to
  `/sentinel/pipelines/stagerig_klangrig_Surface/state/rig_command`. Start each command with a
  new id of your choice; the Surface answers in `rig_command_ack` as
  `<id>:accepted` or `<id>:<error>`. The DESK buttons run these same commands.

| Command | Effect |
|---|---|
| `<id>\|tempo\|<tap\|play\|stop\|sync\|start\|pause>` | Transport, as the DESK buttons (`play` toggles; `stop` returns to beat 0) |
| `<id>\|tempo\|bpm\|<30-300>` | Set the tempo |
| `<id>\|preset\|recall\|complete\|<1-16>` | Recall a FULL LOOK (also `static`, `effects`, `color`, `rhythm`) |
| `<id>\|preset\|store\|static\|<1-16>` | Store the current programmer into a slot |
| `<id>\|select\|<ids>` | Select fixtures by comma-separated stable slot ID |
| `<id>\|encoder\|<attribute>\|<value>\|absolute` | Set an attribute (for example `pan`) on the selection |
| `<id>\|momentary\|blackout\|1` / `...\|0` | Hold / release blackout (also `strobe`) |
| `<id>\|camera\|<left\|right\|up\|down\|in\|out\|home>` | Orbit camera, as the Push arrows |

- **Pages and window widgets:** the control window's widgets only exist while it
  is open (`sentinel_pipeline action=open_window pipeline_id=stagerig_klangrig_Surface`).
  Window DESK buttons are `Script: stagerig_klangrig_Surface/desk_<bank>_<slot>`, `desk_tap`,
  `desk_play` and so on. `stagerig_klangrig_Desk` panel pads are viewport controls named
  `<bank>_<slot>`, `tap`, `play`, `blackout`, `cam_up` and so on
  (`sentinel_ui action=viewport_control_drag pipeline=stagerig_klangrig_Desk control=static_5`
  with `phase` begin, then end; the panel window must be open). For Push pages, first set the `view` combo to ADVANCED
  (index 1), then set `page_tab` (zero-based 0-3 for SEQUENCE, GLOBAL, RIG,
  COLOR). Confirm with `/sentinel/pipelines/stagerig_klangrig_Surface/state/page`.

Send one command at a time and wait for its ack before the next; the Surface
handles the latest string only. Slots 1-16 are the pad numbers shown on the Push
and the DESK (STATIC 05 is slot 5). Moving heads slew physically: allow about 6
seconds after a position change before capturing.

For frame comparisons, stop time on a beat: send `tempo|pause`, then invoke
`/sentinel/pipelines/stagerig_klangrig_Clock/actions/resync` with `{"beat": 16}`. Intensity
follows the rhythm lanes, so a clock paused between beats can leave the rig dark.
Then recall EFFECTS 02 (no movement or chase), COLOR 01 (white) and any STATIC
look for a steady, repeatable picture. The program image is the output of
`stagerig_klangrig_Renderer`.

## Component map

| Component | Role |
|---|---|
| `stagerig_klangrig_Plan` | Construction authority: top, side and end views of the spine and twelve four-edge wings. Drag wing handles; parameters set dimensions, heights, tier spacing and fixture counts. Publishes fixture mounts and truss segments. |
| `stagerig_klangrig_Assembly` | Expands Plan segments into truss geometry for the renderer. |
| `stagerig_klangrig_Lighting` | Martin RUSH MH10 Beam FX moving heads: motors, optics and a top-down selection view (click, box, Shift/Ctrl, named groups). Publishes Pose, Optics and Selection. |
| `stagerig_klangrig_Program` | Per-fixture programming (position, level, colour, movement and chase FX, LED FX) written by the Surface Script and committed as one revision. |
| `stagerig_klangrig_Show` | Reference chase: one clock aligning LED loops and heads, plus the global strobe and the switch that hands lighting to the programmer. |
| `stagerig_klangrig_LED` | Content for the 48 inward LED faces: solid, outlines, chase, pulse, scatter, programmed patterns and address tests. |
| `stagerig_klangrig_Warehouse` | Procedural hall with room fill, spill and material controls. |
| `stagerig_klangrig_Renderer` | HDR stage render with atmosphere, floor reflections, bloom, highlight shoulder and lens streaks. This is the program view. |
| `stagerig_klangrig_Camera` | Shared camera for the renderer. The Push 2 arrows orbit it between 40 authored points. |
| `stagerig_klangrig_Clock` | Conductor: tempo and beat for every rhythm lane. |
| `stagerig_klangrig_Surface` | Script node that runs the show: the `stagerig_klangrig_Desk` panel's clicks and feedback, the window DESK view, the Push 2 surface (four pages, fixture programmer, preset banks, transport keys and orbit camera) and the `rig_command` automation seam. Source in `scripts/`. |
| `stagerig_klangrig_Desk` | The mouse desk: an 85-control panel (transport, readouts, blackout/strobe holds, four look banks, camera arrows). Clicks travel on its `panel` Event cable to `stagerig_klangrig_Surface`, which runs them and lights the pads through `panel_feedback`. Generated from one control list; see PROGRAMMING.md. |
| `stagerig_klangrig_Push2_Display` | Push 2 Display node fed by the Surface Script's display output. |

Scripts: `scripts/Klang_Surface.luau` is the entry. Show logic lives in
`scripts/show/` and page factories in `scripts/pages/`. The pinned Push 2 OS
package is in `scripts/vendor/push2os/` (MIT, see its LICENSE; hashes in
`scripts/push2os-provenance.json`). Require aliases are in `scripts/.luaurc`.

Preset banks in `presets/`: `stagerig_klangrig_static`, `stagerig_klangrig_effects`, `stagerig_klangrig_color` (layered
partial presets), `stagerig_klangrig_complete` (FULL LOOKS), `stagerig_klangrig_rhythm`, and `stagerig_klangrig_push2`
(surface state, palettes, sequences and custom groups).

## Geometry and fixtures

One 32 m spine and three longitudinal sets of four closed wing loops. The saved
rig has 72 spine heads plus 12 per wing (216 movers). The spine supports up to
96. Stable fixture slots are 0-63 and 256-287 for the spine, 64 + wing x 16 for
wings, and 288 for the LED system, so changing counts never retargets stored
programming. Dimensions are an interpretation of reference footage, not a
surveyed stage.

Fixture geometry, motor conventions and beam/ring optics derive from the Sentinel
workspace fixture batch (Martin RUSH MH10 Beam FX). Truss construction and UI
assets derive from the workspace DJ truck modules. The Scientifica bitmap font
licence is beside the font in `modules/_shared/fonts/`.

## Learn more

The Sentinel agent skills `script-node-authoring` (Script nodes, lifecycle,
persistence, performance), `controller-surface-authoring` (controller profiles,
surface ownership, Push 2 display), `module-authoring` and `lighting-busking`
explain the techniques used here.
