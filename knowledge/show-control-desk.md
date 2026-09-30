# Show Control Desks

Build performance desks two ways, in the same look: a Script window drawn
with `ui.*` show calls, or a Module panel whose controls a Script drives over
Event cables. Use a Script window for operator desks that live beside the
graph; use a Module panel when the desk must be a video output (Spout, NDI,
a projector) or share a canvas with visuals.

## Script window desks

Draw in `render(node)` and act on edges in `control_process`:

```lua
function script.render(node)
    ui.section("holds", "Holds", "zap")
    ui.pad("blackout", "Blackout", "momentary", "loaded", "kill", "eye-off")
    ui.pad_grid("bank1", 8, 2, 92, 46, node.state.labels, node.state.states, nil, "radio")
    ui.readout("bpm", string.format("%.1f", node.state.bpm), 48, "warn")
end

function script.control_process(node)
    while true do
        local id, kind = ui.next_edge()
        if not id then break end
        if id == "blackout" then sentinel.set("/sentinel/pipelines/Program/parameters/blackout", kind == "press") end
    end
end
```

- Pads: `ui.pad(id, label, mode?, state?, role_or_color?, icon?, fade?, w?, h?)`
  returns pressed, held, released. Modes are momentary, toggle, radio and go;
  states are empty, loaded, active, selected and fading; roles are neutral,
  accent, go, kill, warn, freeze, link and expression.
- `ui.pad_grid` draws a whole bank as one command; cells report edges as
  `<grid>.<n>`.
- Layout: `ui.grid_begin/grid_cell/grid_end`, `ui.strip_begin/strip_end`,
  `ui.section`, `ui.row`, `ui.bank_header` (page tabs with live pips).
- Continuous: `ui.fader`, `ui.knob`, `ui.crossfader`, `ui.xy` return
  `(changed, value)`; ALT drags fine, double-click resets.
- Feedback: `ui.readout`, `ui.meter`, `ui.lamp`, `ui.value_tile`, and
  `ui.meter_bound`, `ui.readout_bound`, `ui.lamp_bound` that follow a
  StateTree path with no script work.
- Show tools: `ui.tap_tempo`, `ui.transport`, `ui.submaster`, `ui.guarded`
  (hold 0.65 s, or arm then fire inside 3 s).

Held pads release on page-out, window close, reload and focus loss, so a
blackout hold cannot stick.

## Module panel desks

```yaml
viewport:
  panel: true
  controls:
    - { id: look1, kind: pad, rect: [0.01, 0.30, 0.09, 0.36], label: "Intro 1" }
    - { id: blackout, kind: pad, rect: [0.01, 0.18, 0.11, 0.26], label: "Blackout" }
    - { id: level, kind: fader, rect: [0.82, 0.06, 0.87, 0.90], label: "Level" }
    - { id: bpm, kind: readout, rect: [0.10, 0.05, 0.33, 0.14], label: "120.0" }
```

- The Module gets an Event output `panel` (press 1, release 2, value 3;
  payload `[index, value, value2]`) and an Event input `panel_feedback`.
  Wire `panel` to a Script input and the Script's feedback output back to
  `panel_feedback`.
- Feedback records: lit 10 `[index, 0 or 1]`, value 11 `[index, value]`,
  color 12 `[index, r, g, b]`, state 13 `[index, state, fade]`.
- `panel.label("MyDesk", "bpm", "128.0")` renames a control.
- Draw from `_ViewportControlState[index]` with the shared kit
  `show_controls.hlsli` (Sentinel ships it in
  `shaders/projects/_shared/ui/`; copy it into your project's
  `modules/_shared/ui/` when you bundle the desk). It draws pads in every
  state, faders, knobs, meters, section headers and label text.
- Echo fader values back as value feedback so the fader draws the running
  level, and re-send decoration periodically: feedback sent before a cable
  exists is lost.

Verify a desk by pointer: `sentinel_ui drag_at` holds and `click_at` taps on
the Pipeline Window, `sentinel_viewport info` for per-control state, and a
window capture with a vision assertion on what must be lit.
