---
name: controller-surface-authoring
description: Drive Sentinel from hardware MIDI controllers and the Ableton Push 2 and Push 3 panels. Covers controller profiles (bundled and workspace JSON), enabling a controller, Script surface ownership (`surface.claim`), semantic `midi.on`/`midi.send` routing and LED feedback, raw MIDI and batches, the virtual surface for device-free testing, writing a profile for a new device, and rendering the Push 2 or Push 3 display from a Script through the Push Display node. Use when mapping a Midi Fighter Twister, Push 2, Push 3, APC mini mk2, X-Touch Compact or another MIDI controller, adding a controller profile, lighting pads or rings, or drawing on the Push 2 or Push 3 screen. Read `script-node-authoring` first for general Script rules.
---

# Controller Surface Authoring

A controller in Sentinel is three pieces:

1. A **profile**: a JSON file that names every control on the device
   (`mft.encoder.3`, `push2.pad.2.5`, `apc.fader.0`) and says how it maps to
   MIDI in and out.
2. The **controller service**: Sentinel opens the device ports, decodes input
   through the profile and sends feedback. It is configured per profile under
   `/sentinel/controllers/<profile>/`.
3. A **Script node** that claims the surface and handles controls by name
   with `midi.on`, sending feedback with `midi.send`.

There are no vendor controller nodes to place in the graph. Old projects that
contain `twister` or `push2` nodes open with a warning and without those
nodes; rebuild them as a Script surface.

MIDI In and MIDI Out nodes remain the right tool for generic MIDI streams
(learned CCs as Signals, notes as Events, timestamped note output). Use a
controller surface when you want named controls, LED feedback and exclusive
ownership of a device.

## Bundled profiles

| Profile | Prefix | Port match | Controls |
| --- | --- | --- | --- |
| `midi-fighter-twister` | `mft` | `Midi Fighter Twister*` | `encoder.0..15` (absolute, ring auto-echo), `encoder.press.0..15`, `side.0..5` |
| `push2-user-mode` | `push2` | `*Ableton Push 2*` | `pad.<row>.<col>` (8 by 8, rows from the bottom), `encoder.0..7` (relative), `encoder.touch.0..7`, `button.top.0..7`, `button.bottom.0..7`, `button.side.0..7`, `button.select`, `button.shift`, `button.layout`, `transport.play/record/stop` |
| `push3-user-mode` | `push3` | `*Ableton Push 3*` | Every Push 2 control under the `push3` prefix, plus `encoder.master` (relative), `encoder.master.touch`, `jog` (relative) and `jog.press`, `jog.left`, `jog.right`. Not yet verified on a Push 3 |
| `apc-mini-mk2` | `apc` | `APC mini mk2*` | `pad.<row>.<col>` (row 0 on top), `bottom.0..7`, `scene.0..7`, `shift`, `fader.0..7`, `fader.master` |
| `x-touch-compact` | `xtc` | `X-TOUCH COMPACT*` | `fader.0..8`, `encoder.0..15`, `encoder.press.0..15`, `button.0..23`, `select.0..8`, `transport.0..5`, `foot_switch`, `expression_pedal` |
| `sandbox` | `sandbox` | `sctrl-sandbox*` | Hardware-free test surface: `encoder.0..7`, `pad.<row>.<col>` (4 by 4), `btn.0..3` |

The full id is `<prefix>.<control>`. From a Script, `midi.semantic_ids()`
lists every id and `midi.controllers()` lists profiles with their matched
input and output ports.

Push 2 and Push 3 must be in User mode (press the User button); a standalone
Push 3 must also be in Control mode. Sentinel sends them no SysEx. Do not send Push 2 mode or init SysEx with `midi.send_sysex` either:
tested sequences put the device into a state where LED writes are ignored.
Recovering from that took a USB power cycle. The Twister profile expects the factory default absolute mode.

## Enable a controller

Each profile has these session settings. Set the ports first, then enable:

| Path | Value |
| --- | --- |
| `/sentinel/controllers/<profile>/device_in` | Exact MIDI input name, or `none` |
| `/sentinel/controllers/<profile>/device_out` | Exact MIDI output name, `record`, or `none` |
| `/sentinel/controllers/<profile>/record_path` | JSONL path; required when `device_out` is `record` |
| `/sentinel/controllers/<profile>/enabled` | `true` |

Read-only health: `status`, `dropped`, `egress_failures` under the same root,
plus `/sentinel/controllers/status`. These settings are session-scoped: they
reset to disabled when a project is replaced, so a show setup step (or a
startup script) must enable the controller after each load.

Port names must be the raw device names from `midi.ports()` and
`midi.output_ports()`, for example `Ableton Push 2`. Other tools often show a
decorated name with a ` 1` suffix; that name will not match.

To make a project self-starting, let the surface Script configure its own
profile. Set the ports in `init` with the profile disabled. Enable it only when
the surface is ready to handle input and repaint feedback:

```lua
local P = "/sentinel/controllers/push2-user-mode/"
function script.init(node)
    sentinel.set(P .. "enabled", false)
    sentinel.set(P .. "device_in", "Ableton Push 2")
    sentinel.set(P .. "device_out", "Ableton Push 2")
    -- claim, subscribe, start building ...
end
-- later, once startup has finished (see the restore barrier in script-node-authoring):
--     sentinel.set(P .. "enabled", true)
```

While the profile is disabled, `midi.send_many` batches report failures. That
is expected during startup, so repaint once after enabling.

Use `device_out=record` with a `record_path` to capture every outgoing
message with timestamps when you have no device or want proof of feedback.

## Claim the surface and handle controls

```lua
local script = {manifest = {name = "Twister surface"}}

function script.init(node)
    local claim = surface.claim()
    if not claim.ok then
        log.warn("surface refused: " .. claim.code)
        return
    end
    node.state.token = claim.token

    midi.on("mft.encoder.0", "encoder_absolute", function(e)
        sentinel.set("/sentinel/pipelines/Glow/parameters/intensity", e.value / 127)
    end)

    midi.on("mft.encoder.press.0", "momentary", function(e)
        if e.pressed then
            sentinel.set("/sentinel/pipelines/Glow/parameters/enabled", true)
        end
    end)
end

function script.stop(node)
    surface.stop(node.state.token or 0)
end

return script
```

Rules:

- **Claim before subscribing.** A surface has one owner. Input routes only to
  the owning Script and `midi.send` fails without a lease. A second claim is
  refused with a stable `code`; show it in the node (for example with
  `ui.text`) so a refusal is visible.
- **Always release in `stop`.** `surface.stop(token)` sends release edges for
  every held pad or button (your callbacks receive `pressed=false`) before the
  lease retires. A stale token cannot stop a newer owner.
- Callbacks run on the control clock inside the Script's tick budget. Keep
  them short: set a parameter, update `node.state`, send feedback.
- **Raw MIDI subscriptions also need the lease.** A second Script cannot listen
  to raw MIDI from any port while another Script holds the surface, including
  a different device such as a keyboard. Have the owning Script subscribe and
  forward what the other Script needs through typed Event and Signal cables.
  Pack each message into the four event payload floats.
- Held state is transient. Never persist a held pad, and clear held overrides
  on reload. Track each release against the control that was pressed.

### `midi.on(id, kind, callback)`

`kind` filters by control type: `encoder_absolute`, `encoder_relative`,
`encoder` (either), `momentary`, `pad` or `any`. The event table carries:

| Field | Meaning |
| --- | --- |
| `id`, `kind` | Semantic id and control type |
| `value` | Absolute value 0 to 127 (velocity or pressure for pads) |
| `delta` | Signed step for relative encoders |
| `pressed` | True while a pad or button is down |
| `row`, `col`, `index` | Position within the control family |
| `source` | `hardware`, `virtual` or `inject` |
| `time`, `timestamp_ns`, `sequence` | Input timing |
| `port`, `channel`, `data1`, `data2` | Raw MIDI detail |

Relative encoders (Push 2) report `delta`; integrate it yourself:

```lua
midi.on("push2.encoder.0", "encoder_relative", function(e)
    node.state.level = math.clamp((node.state.level or 0) + e.delta / 128, 0, 1)
    sentinel.set("/sentinel/pipelines/Blur/parameters/radius", node.state.level * 40)
end)
```

Push 2 encoders send bursts: two events can arrive microseconds apart. If you
add acceleration, base it on event density over a short window. The gap
between two events is not a reliable speed measure. For stepped choices (a
list, an enum), accumulate deltas and move one step per threshold, about 12
ticks. Never merge separate discrete steps into one jump.

Passing a port name instead of a semantic id subscribes to raw MIDI from that
input port, with a raw `kind` such as `note_on`, `cc`, `pitch_bend` or `any`.
A glob works as the port name. Raw events carry `channel`, `data1`, `data2` and
`pressed`.

This is how you reach controls a profile leaves out. The bundled Push 2
profile has no arrows or named buttons beyond the ones listed above. Listen to
their raw CCs on the same device while you hold the lease:

```lua
local ARROWS = {[44] = "left", [45] = "right", [46] = "up", [47] = "down"}
midi.on("*Ableton Push 2*", "cc", function(e)
    local dir = e.channel == 1 and ARROWS[e.data1]
    if dir and e.pressed then step_camera(dir) end
end)
```

Confirmed Push 2 CCs: arrows 44 to 47, Duplicate 88, Select 48, Shift 49,
Layout 31. Light them with raw `cc` messages in `send_many`. For any other
button, log its CC on the real device before relying on it.

### Feedback and sending

| Call | Use |
| --- | --- |
| `midi.send(id, value)` | Send the control's feedback message, value 0 to 127 |
| `midi.send(port, kind, channel, data1, data2)` | One raw message to a port |
| `midi.send_many(port, messages)` | A batch; returns `{sent_count, failed_count, errors}` |
| `midi.send_sysex(port, bytes)` | One SysEx message, `F0 ... F7` |
| `midi.clear_notes(port, channel, notes)` | Note-offs for a list of notes |
| `midi.ports()`, `midi.output_ports()` | Current device names |

Feedback meaning depends on the device:

- **Push 2 RGB pads and buttons:** value is a palette index (0 off, 1 dim
  white, 122 bright white, 127 red). Those four indices are hardware-verified;
  check any other index on the device.
- **Push 2 white-only buttons** (Shift, Layout, arrows, Duplicate): the value
  is brightness, for example 16 dim and 127 bright. They cannot show color.
- **APC mini mk2 pads:** value is a color velocity.
- **X-Touch Compact buttons:** 0 or 1 off, 2 solid, 3 blink.
- **Twister:** `mft.encoder.<n>` sets the ring position. The ring already
  follows physical turns (auto-echo). `mft.encoder.color.<n>` sets the hue and
  `mft.encoder.anim.<n>` the animation.

When the output is `record`, the raw port name is `record:<profile>`.
`send_many` counts messages accepted into the send queue. When
`failed_count` is nonzero, resend the whole state on a later tick instead of
assuming the device received it. A raw message in the batch is
`{kind = "cc", channel = 1, data1 = 44, data2 = 127}` (or `note_on`).

For a full grid, keep a model of what each LED should show. Once per tick,
diff it against what was last sent and send the changes in one `send_many`.
Update the last-sent cache only for messages that went out. If a cache blocks
resends, one lost message leaves a pad stale until something else changes it.
LEDs owned by another part of the surface (a side-button effect, for example)
should be kept out of the page compositor. Give them a slow periodic refresh.

Some Sentinel builds silently dropped LED messages that were more than 10 ms
late. That produced stale pads after page changes. Commit `246a21de` fixed
it. If pads stick on an older build, suspect that first.

A pad light-up pattern:

```lua
midi.on("push2.pad.0.0", "pad", function(e)
    midi.send(e.id, e.pressed and 122 or 0)
end)
```

On connect, repaint all your feedback state once (for example in `init`
after claiming, and when `midi.controllers()` shows the output port coming
back), since the device does not remember what you sent before it was
plugged in.

## Test without hardware: the virtual surface

Open the Script's control window and expand **Controller surface**. Pick a
profile to get clickable, draggable controls that dispatch exactly like the
device, with `source = "virtual"` in the event. This is the fastest loop for
authoring and the right proof when no device is attached. Enable the profile
with `device_in=none` and `device_out=record` to also capture the feedback
your script sends.

Label the evidence honestly: virtual and record proof shows the script logic
and feedback messages; it says nothing about a physical device's response.

## Write a profile for a new device

Put the file in `<workspace>/controllers/<name>.json`. A workspace profile
with the same `name` as a bundled one overrides it. Profiles load when
Sentinel starts, so restart after adding or editing one. An invalid profile
reports the failing field in the Script status.

```json
{
    "name": "my-pad-grid",
    "id_prefix": "grid",
    "port_name_glob": "My Pad Grid*",
    "controls": [
        {
            "id_template": "pad.{row}.{col}",
            "type": "pad",
            "input": {"kind": "note_on", "channel": 1},
            "output_primary": {"kind": "note_on", "channel": 1},
            "count": 64,
            "expansion_params": {"base": 36, "row_stride": 8, "col_stride": 1}
        },
        {
            "id_template": "knob.{n}",
            "type": "encoder_absolute",
            "input": {"kind": "cc", "channel": 1},
            "count": 8,
            "expansion_params": {"base": 70, "stride": 1}
        },
        {
            "id_template": "shift",
            "type": "momentary",
            "input": {"kind": "cc", "channel": 1, "cc_base": 49}
        }
    ]
}
```

Schema:

| Field | Meaning |
| --- | --- |
| `name` | Kebab-case profile name; also the `/sentinel/controllers/<name>` key |
| `id_prefix` | Prefix for every semantic id |
| `port_name_glob` | Port name pattern; make it specific to this device |
| `init_sysex` | Optional byte array `F0 ... F7` sent on connect |
| `controls[].id_template` | Uses `{n}`, or `{row}` and `{col}` for grids |
| `controls[].type` | `encoder_absolute`, `encoder_relative`, `momentary` or `pad` |
| `controls[].input` | `{kind, channel}` with kind `cc` or `note_on`; single controls give `cc_base` or `note_base`; relative encoders add `"encoding": "twos_complement_64"` |
| `output_primary/secondary/tertiary` | Optional feedback wiring; secondary and tertiary map to the `.color.` and `.anim.` id aliases |
| `count` | Number of controls the template expands to |
| `expansion_params` | `base` plus `stride`, or `row_stride` and `col_stride` for grids |
| `auto_echo` | Mirror input back to `output_primary`; requires it |

Grid columns are inferred from `count`: 8 for 64 or more, 4 for 16 to 63.
A negative `row_stride` flips rows (APC uses `base 56, row_stride -8` so row 0
is the top). Every expanded MIDI number must land in 0 to 127, and ids must be
unique.

Name controls by meaning (`transport.play`, `fader.3`), check the vendor's
MIDI chart, then confirm on the real device: charts are often wrong. Enable
the profile and log every event with a catch-all handler while pressing
controls:

```lua
for _, id in midi.semantic_ids() do
    if string.sub(id, 1, 5) == "grid." then
        midi.on(id, "any", function(e) log.info(e.id .. " " .. e.value) end)
    end
end
```

## Push 2 and Push 3 display

The Push 2 or Push 3 screen (960 by 160) is driven by a **Push Display** node
(`push2display`) fed from a Script's Display output:

```lua
local script = {manifest = {
    name = "Push 2 meters",
    inputs = {{name = "level", type = "signal"}},
    outputs = {{name = "display", type = "display"}},
}}

function script.render_display(node, d)
    d.clear(0x090D18)
    d.text(18, 8, "LEVEL", 1, 0xD8E3F0)
    local v = node.inputs.level:stale() and 0 or math.clamp(node.inputs.level:get(), 0, 1)
    d.meter(18, 32, 92, 104, v, 0x43AA8B, 0x1B263B, "vertical")
end

return script
```

Wire Script `display` to the Push Display `display` input. One Display
output feeds one Push Display.

Draw calls (colors are `0xRRGGBB`, coordinates in panel pixels):

| Call | Purpose |
| --- | --- |
| `d.clear(rgb)` | Background |
| `d.rect(x, y, w, h, rgb, fill?, thickness?)` | Rectangle |
| `d.line(x1, y1, x2, y2, rgb, thickness?)` | Line |
| `d.circle(x, y, r, rgb, fill?, thickness?)` | Circle |
| `d.polyline(points, rgb, thickness?)` | `{{x, y}, ...}` |
| `d.text(x, y, text, scale?, rgb?, font?, tracking?)` | Bitmap text |
| `d.text_vector(x, y, text, size_px?, rgb?)` | Smooth TrueType text |
| `d.meter(x, y, w, h, value, fg?, bg?, orientation?)` | Meter, `"vertical"` or horizontal |
| `d.skip()` | Keep the previous frame |

Use `d.text_vector` for anything an operator reads, and pick a monospace font
for live numbers so readouts don't jitter as digits change width. Bitmap
`d.text` scales only in whole steps and looks rough at panel size. The global
`display.text_vector` also takes an optional `font` argument. Only one Script
should paint a given panel.

A draw list holds up to 4,096 commands. `render_display` has its own
`display_budget_us`; a failure there stops only display rendering. Repeated
misses disable the display while the Script's control `health` stays 1, so a
dark panel with a healthy node usually means display-budget trouble. Move the
work to the control tick or into a startup barrier; don't raise the budget.
Before startup finishes, call `d.skip()` rather than drawing a partial UI. By default
a successful return publishes the frame. For multi-step drawing that may
fail midway, use `display.begin_frame(rgb)`, `display.complete_frame()` and
`display.abort_frame()` inside the callback so a partial frame never reaches
the panel.

Push Display parameters: `source` (`display`, `video`, `test_bars`,
`black`), `transport` (`record` or `winusb`), `device` (`auto`, `push2` or
`push3`: which model WinUSB opens), `brightness`,
`hold_last_frame`, `fit` for video, `record_name`, `record_png_every`, and
`refresh_devices`. The `video` source scales any video cable onto the panel
instead of a Script. Health outputs include `frames_rendered`, `frames_sent`,
`connected` and `dropped`; the `capture_display` action writes the current
panel image to PNG, which is the proof of what the glass shows.

Physical output uses WinUSB (`transport=winusb`). Only one application can
own the display interface, so quit Ableton Live and any other software that
drives the screen. Push 2 needs no driver. Push 3 needs the Ableton Push 3
Display driver, which Live installs the first time Push 3 is connected while
it runs; Device Manager then lists **Ableton Push 3 Display**. Without it the
status names the missing driver. If the interface has no WinUSB binding the
status stays `device not found` while rendering and the record transport keep
working. Push 3 support uses the Push 2 protocol and has not yet run on a
real Push 3; start with `source=test_bars` (eight vertical colour bars) to
check the panel.

## Proof checklist

- `sentinel_state get /sentinel/controllers/<profile>/status` reads healthy
  after enabling.
- The owning Script's node shows its lease; a second claimant shows its
  refusal code.
- Operate a control (physical, or the virtual surface) and read the target
  parameter change, then screenshot the output it drives.
- Feedback: check the record file or look at the device LEDs. Physical LED and
  screen behavior needs a person looking at the hardware.
- Push screen: `capture_display` PNG plus, on hardware, a look at the glass.
  Display health is separate from MIDI and Script health. Check `connected`,
  advancing `frames_sent`, and the change in display misses over a soak.
- LED delivery: compare messages admitted with messages completed (a
  `record` file or egress counters). A full repaint should come out equal.
- Reconnect: unplug and replug the device. Held controls should release and
  the whole LED state should repaint.
