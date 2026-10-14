# Interaction Lab

Interaction Lab is the reference set for Sentinel's interaction surface: fourteen stations, each a
complete small instrument, built on one shared UI foundation and proven with real input on
Sentinel 0.6.3. Agents learn what a Module can do from here, so every station shows a capability
end to end: the gesture, the durable state it writes, the data or events it publishes, and the
picture that changes because of it.

Load `interaction_lab.sentinel`. Each station is a numbered Scene Group in the graph; open a
node's window to use its canvas. A group's Properties hold that station's few honest controls.

## Component map

| # | Station | Nodes | Tier | What it teaches |
| --- | --- | --- | --- | --- |
| 00 | Kit | `Kit` | basic | the foundation's specimen: palette, type, every widget, and the host controls' round trip (an XY pad whose stored, published, read-out and drawn values agree) |
| 01 | Touch | `Touch` | basic | pointer and keys on a surface: strokes, a Space latch, undo, clear; durable through save, reload and preset recall |
| 02 | Handles | `Handles` | basic | drag to move, right-drag to turn: four fixtures whose transforms are ordinary parameters, each with a round grab ring |
| 03 | Still Life | `Still_Life` | basic | host-owned selection and picking in a marched 3D scene through the internal camera: click, Shift add, body slide, ring turn, Esc cancel |
| 04 | Pulse Bus | `Pulse`, `Pulse_Bus`, `Resonance` | basic | GPU physics appends an Impact event per strike, a Script picks the note, MIDI Out plays it, and the echo comes back to a renderer on the physics clock |
| 05 | Control Atoms + Scope | `Atoms`, `Scope` | basic | a Script as a control source (LFO, envelope, sample and hold, slew on the 240 Hz clock) with its own desk window; a scope that reads it through `ref()` |
| 06 | Desk | `Stage`, `Desk`, `Cue_Brain` | basic | a panel of pads, faders and readouts driving a Script that runs a cue stack: GO and BACK crossfades, a guarded blackout, live feedback to the pads |
| 07 | Curve Desk | `Curve_Desk` | instrument | a bezier key editor (a bouncing ball in three channels) with handles, box select, modes, auto handles and a spacing chart |
| 08 | Path Desk + Plotter | `Path_Desk`, `Plotter` | instrument | a pen tool and path editor read as curvature, feeding a plotter that plans its speed like CNC firmware and lays ink that pools at corners |
| 09 | Ramp Desk + Relief | `Ramp_Desk`, `Relief` | instrument | colour stops on an OKLCH plane, gamut-mapped into a published palette; a relief map that renders only when something changes |
| 10 | Patch Bay + Bloom | `Patch_Bay`, `Bloom` | instrument | cables, a matrix and bipolar depths patching five sources into six outputs that swing a guilloche rosette through expressions |
| 11 | Timeline + Sting | `Timeline`, `Sting` | sequence | a keyframe editor (stage, inspector, transport, dope sheet, graph) on four layers, drawn as a title sting with motion blur from the curves |
| 12 | Pattern + Pattern Bus | `Pattern`, `Pattern_Bus` | sequence | a polymetric step sequencer whose hits leave 100 ms ahead on a GPU event port and land on the grid within a millisecond |
| 13 | Score + Program | `Score`, `Program` | sequence | an act sequencer: a camera flown through a hall along marks, title cards between, hand-offs (cut, dip, glide), rendered by a Program whose internal camera the Score drives |
| - | Sound | `MIDI_Merge`, `Synth` | shared | one Script merging the Pulse Bus and the Pattern Bus into the one MIDI Out |

## Before you start

- **The lab makes sound.** `Synth` is a MIDI Out on the default Windows port (Microsoft GS
  Wavetable Synth). Pulse (04) strikes notes as balls fall and the Pattern (12) plays as soon as the
  project loads. To silence it: Space in the Pattern window, or `mute` in the 12 or 04 group. The
  Sound group's `channel` set to 10 turns every note into drums.
- **Everything running costs about 10 ms of GPU** on an RTX 5060 Laptop GPU (27 nodes). Disable
  the Scene Groups you are not using to give the rest the headroom.
- **Use the canvases with the mouse and keyboard.** Each station's gestures and keys are listed
  below; injected input proved all of them except what is marked *by hand*.

## The stations

**00 Kit.** The specimen sheet for `modules/_shared/ui`: the instrument palette (graphite ground, a
grey ladder, amber only for the selection and live readings, red only for broken), Plex Sans
Condensed and Plex Mono as SDF type, and every widget. Its host controls (toggle, fire, radio
pads, hold and latch, level, amount, an XY pad) are manifest controls, so the host owns them:
change one in Properties and the canvas follows, drag it on the canvas and Properties follows.
When the window has the height, a Widget States pane shows the widgets a module draws itself -
chip, slider, knob, toggle, segmented row, meter with a peak hold, keycaps, value row - in each
state they have (rest, hot, down, on), on the Kit's own amount, level and mode, so they move with
the host controls. The pad follows the XY authority contract: the stored parameter is never flipped, `ilPadPoint`
draws it and `ilPadValue` inverts a pointer, and the readout, the reticle and the published value
are checked against each other (the pad shows AGREE).

**01 Touch.** Click, drag, double-click, keys 1 - 4, a Space latch that holds either way, Backspace
undo, C clear. Strokes start at the press, lift where they leave the surface and restart when
they re-enter. Ink lives in a `state_buffer`, so it survives a reload, a save and a preset recall
without replaying old events. *By hand:* wheel.

**02 Handles.** A lamp and three blocks, each a position and a rotation parameter, each with a
round grab ring that has hover and held states. Sentinel 0.6.3 measures the grab radius in
normalized image coordinates, so on this 16:9 frame a handle also grabs up to 64 px left and right
of its centre, past its 36 px ring (Sentinel bug #174); the ring lights wherever a click would
grab. Move and rotate commit as ordinary parameter edits, so OSC,
expressions and undo all work. **On Sentinel 0.6.3 nothing moves until release.** Param gestures are documented to preview
live, but 0.6.3 writes the parameter only when the button comes up, and while the host holds the
drag the module receives no input at all (no events, no buttons, the pointer frozen at the press),
so nothing in the module can draw the drag either. That is Sentinel bug #173, and this station is
its test: drag a ring and the object should follow the pointer while the button is held; right-drag
and it should turn while held. *By hand:* that live preview, once the engine provides it.

**03 Still Life.** The internal camera and host selection together: click selects, Shift adds, a
miss clears; drag a body to slide the whole selection, arrows nudge, the ring turns, Esc cancels.
The selection outline is registered to the render from a flown viewpoint. Presets: the frame
contract `Frame · Table` (camera only) and a four-rung quality ladder (`Quality · Draft / Live /
Beauty / Hero (capture only)`). *By hand:* RMB look.

**04 Pulse Bus.** `Pulse` runs the physics on the GPU and appends one Impact record per strike to
an event port; the `Pulse Bus` Script turns each into a note on a scale and sends it to MIDI Out,
then echoes the played note to `Resonance` (video, data and event inputs at once) on Pulse's
clock: strike to echo is 25 ms, and every echo is drawn linked to its strike. The Script's window
has scale pads and a mute.

**05 Control Atoms + Scope.** The `Atoms` Script makes an LFO, an ADSR, a sample and hold and a slew
as Signal outputs on the 240 Hz clock (7 us a tick), with a desk in its own window: knobs, shape
pads, an LFO gate toggle and a held Gate pad over live previews. `Scope` plots all five through
`ref()` expressions: drag places and holds cursors A and B (1 and 2 choose), Space holds, Z and X
zoom, C clears. *By hand:* wheel zoom.

**06 Desk.** A panel module (readouts, eleven pads, two faders over a Stage preview) sends its
gestures to the `Cue Brain` Script, which runs the cue stack and writes the Stage: a cue pad makes
the next cue, GO crossfades (GO during a fade completes it), BACK fades back and reverses a fade
from where it is, the FADE and MASTER faders set the time and the level, and the blackout is
guarded - a tap is ignored, holding engages it (at 0.65 s), a tap restores. Lit, selected, fading, colour and value
feedback go back to the pads.

**07 Curve Desk.** Keys snap to frames, neighbours clamp, handles stay aligned until B breaks them,
box select, Backspace, double-click a curve to insert, 1 / 2 / 3 for step / linear / bezier, A
for auto handles (flat at extremes, Fritsch-Carlson limited), arrows, F frame, middle-drag pan,
ruler and chart scrub, Space play, R reset with Z bringing the edit back. Publishes `Curves` and
travel / height / squash / phase control outputs. Presets: `Curves · Bounce`, `Curves · Soft
contacts` (state only). *By hand:* wheel zoom, Shift-click.

**08 Path Desk + Plotter.** Up to six pen paths on a plotter's sheet: P is the pen (click a corner,
drag a smooth anchor, click an open end to continue, the first anchor to close, Enter to finish),
edit mode drags anchors and handles, double-click splits a curve exactly (de Casteljau) or
toggles an anchor's kind, O finds a short plot order. The curvature comb and a radius strip read
the geometry. `Path` (1024 arc-length samples) feeds the `Plotter`, which plans speed as CNC
firmware does - a curvature speed limit, forward and backward acceleration passes, minimum-jerk
pen-up moves - and lays ink by speed on a persistent sheet, with a pencil underdrawing that shows
an edit at once. The pen comes back to the Path Desk through `ref()`.

**09 Ramp Desk + Relief.** Up to twelve stops coloured on an OKLCH plane (lightness up, chroma
across, hatched where sRGB ends) and a hue strip, blended in OKLab, OKLCH or sRGB into 256
gamut-mapped entries published as `Palette`. Lanes show the ramp blended three ways, as lightness,
as each dichromat sees it, and as lightness, chroma and step curves. A stop asking for more chroma
than sRGB has keeps its ask and is shown brought in. `Relief` is `execution: on_dirty` with one
`time_dependent: false` pass: it renders once per change and costs nothing while idle. Presets:
`Palette · Hypsometric / Ink / Thermal / Diverging` (state only).

**10 Patch Bay + Bloom.** Five sources and an external `input` patched by cables into six outputs,
each resting on its base and swung bipolar by every cable into it (a negative depth inverts and
draws dashed). Click a cable to select it; drag its knob or the inspector's; drag jack to jack to
patch, a plug to re-patch or into the air to unplug; the matrix patches and unpatches; drag along
a meter to set a base; M mutes. Outputs are control outputs `out_1 .. out_6`; the `Bloom` rosette
rides them through expressions, and the bay's input rides the Curve Desk's ball. Presets:
`Default patch`, `S&H storm` (state only).

**11 Timeline + Sting.** Four layers (Ring, Sun, Block, Bar) by five channels, up to eight keys a
channel, each key hold, linear, ease, spring or back. One canvas holds the stage (motion paths,
onion skin), the inspector, the transport (speeds, loop in and out), the dope sheet and the graph
with ease handles; every one of their gestures was proven with injected input. The Sting draws the same
layers, motion-blurred across the shutter from the curves themselves. Presets: the Sting's
quality ladder `Quality 1 Draft .. 4 Hero (capture only)`, scoped to samples and resolution.
*By hand:* wheel zoom, Shift-click.

**12 Pattern + Pattern Bus.** Six lanes on one sixteenth clock, each its own length (the factory
16 12 7 5 9 11 realign every 55,440 steps); per step: on, velocity, chance, ratchet, nudge; swing.
Grid, rings, lane and step inspectors and a tape of every hit against the steps. Hits leave on a
GPU event port 100 ms before they are due with their "due in"; the `Pattern Bus` Script stamps
them and MIDI Out holds each until its time: NoteOn within +-0.6 ms of the swung grid. Presets:
`Pattern 1 Six lengths (factory, 96 bpm)`, `Pattern 2 Clave, bell, tresillo (108 bpm)`.

**13 Score + Program.** A show of acts on one clock. A rail act flies the camera through a
colonnaded hall along up to eight marks (eye, target and lens at a fraction of the act); a card
act is a title card (word, disc, bar). Every act has a light (day, dusk, night), a length and a
hand-off to the next: cut, dip through black, or glide (the camera and light blend between rails,
a card dissolves). The canvas holds the plan over the elevation (sharing the hall's long axis),
a schematic VIEW through the camera at the playhead, the inspectors, the act lane and a camera
track plotting eye height and lens over the whole show. The `Program` renders the hall - day sun,
dusk through the open end, night lamp pools under the moon, soft shadows, occlusion, a traced
reflection off the glossy works - and draws the cards from the same header the stage uses. The
Score's VIEW outline lies on the Program's render within a pixel. Presets: `Score 1 The hall by
day and night` (the default show), `Score 2 Nocturne` (state only); the Program's quality ladder
`Program Quality 1 Draft .. 4 Hero (capture only)` and its frame contract `Frame · The door (fly
from here)`. *By hand:* RMB look in the Program.

### Flying the Program's camera

The Score drives the Program's internal camera by six expressions:

```text
camera_pos_x  = ref("Score/control_outputs/cam_x")
camera_pos_y  = ref("Score/control_outputs/cam_y")
camera_pos_z  = ref("Score/control_outputs/cam_z")
camera_yaw    = ref("Score/control_outputs/cam_yaw")
camera_pitch  = ref("Score/control_outputs/cam_pitch")
camera_fov    = ref("Score/control_outputs/cam_fov")
```

Clear them to fly it yourself (WASD, RMB look, wheel for speed); recall `Frame · The door` to
start from the hall door. Set them again with `sentinel_expression set` to give the camera back to
the Score. While they are set, the frame preset changes nothing - the expressions win the next
frame. `camera_fov` is the vertical field of view.

## The foundation

`modules/_shared/ui/`:

| File | Role |
| --- | --- |
| `il_core.hlsli` | palette (on `plan_theme.hlsli`), rect and SDF helpers, coverage, the UI scale from the smaller axis |
| `il_draw.hlsli` | the GPU draw list: a layout pass records commands, text is expanded by 64 threads, record-heavy drawing goes into parallel batches |
| `il_ui.hlsli` | widgets on the draw list, including the XY pad authority (`ilPadPoint`, `ilPadValue`) |
| `il_raster.hlsli` | the generic tiled rasterizer every canvas shares |
| `il_events.hlsli` | ordered viewport events consumed once by sequence, latches, wheel notches |
| `il_pane.hlsli` | splitters and per-pane views |
| `il_text.hlsli` | per-pixel SDF text for program renderers that need a few labels |

A station is `reduce` (events to durable state, one thread) then `layout` (the draw list) then
`raster`. Labels are written in each module's `labels.txt` and generated with
`python tools/il_type.py labels <Module>`; `python tools/fxc_check.py <Module> <pass> [--Od]`
compiles one pass offline and times it. The other shared headers carry each data contract once
for both ends: `plot.hlsli` (Path Desk and Plotter), `palette.hlsli` (Ramp Desk and Relief),
`timeline.hlsli` (Timeline and Sting), `score.hlsli` (Score and Program).

## Ideas worth taking

Study these as ideas and rebuild them for your own problem; copy a station only to fork it.

- **Durable state with undo.** Canvas edits live in a `state_buffer`, not parameters; a snapshot
  swap gives Z, R restores the default, and state-only presets carry whole edits.
- **One authority per value.** Host controls stay in Properties; the canvas edits what Properties
  cannot (points, paths, cables, acts), and nothing is stored twice.
- **Typed routes.** Data ports (`Path`, `Palette`, `Motion`, `Score`), event ports (`Impacts`,
  `Hits`), Signal outputs (Atoms) and control outputs; expressions as back edges where a link
  would make a cycle (the Plotter's pen back to the Path Desk, the Score's camera to the Program).
- **Scripts as glue.** A Script turns events into notes (Pulse Bus, Pattern Bus), runs a cue stack
  (Cue Brain), makes control signals (Atoms) or merges streams (MIDI Merge), with its own window.
- **Musical time is sent ahead**, never placed on frames: stamp `timestamp + due in` and let MIDI
  Out schedule it.
- **Narrow presets.** Quality ladders scoped to quality, frame contracts scoped to the camera,
  shows and patches scoped to state; the defaults are always a rung you can work in.

## Measured

GPU time per frame, each measured with its own canvas open at 1579x1162 while the other stations
ran: Kit 0.35 ms, Touch 0.83,
Handles 0.49, Pulse 0.82, Resonance 0.45, Scope 1.10, Desk and Stage 0.17 each, Curve Desk 0.91,
Path Desk 1.46, Plotter 0.63, Ramp Desk 0.91, Relief 1.09 per render and nothing idle, Patch Bay
1.41, Timeline 1.05, Pattern 0.87, Score 1.21. The whole lab, all 27 nodes, about 10 ms.

Quality ladders, as ratios to the default rung (which is always the working one):

| Node | Draft | Live | Beauty | Hero (capture only) |
| --- | --- | --- | --- | --- |
| Still Life (march pass) | 0.41 | 1.00 | 1.11 | 3.9 |
| Sting (samples, resolution) | 0.49 | 1.00 | 3.4 | 15 |
| Program | 0.73 | 1.00 (1.04 ms) | 1.06 | 4.1 |

Identical presets measured several times apart depending on how many node previews were open, so
compare ratios, not absolutes. MIDI: 458 recorded notes left MIDI Out a median 0.98 ms after their
scheduled time (p95 3.9 ms).

## Building on 0.6.3

What this build taught, as it shapes every station:

- Module passes run in **reverse** manifest order. One-pass nodes and passes that read only their
  own buffer are robust to it; the Program marches and composites in one pass for this reason.
- FXC evaluates both sides of `?:`, compile time grows superlinearly with one inlined body (fold
  repeated calls into loops), and a runtime loop count is a constant bound with an early break.
- An event input takes one link; merge streams with a Script.
- Injected input must be issued one call at a time, readbacks and GPU timestamps lag by many
  frames, and an enum option labelled with a bare numeral catches numeric writes.
- Module outputs are displayed exactly as written: encode for display yourself.

## Licences

IBM Plex Sans Condensed and IBM Plex Mono are used under the SIL Open Font License 1.1
(`modules/_shared/type/IBM_PLEX_OFL.txt`; the source fonts and licence are in `tools/fonts/`).
