--!strict
-- Show-owned per-Runtime factory; Phase 5 compatibility conversion.
return function(host: any,get: any,config: any)
local state=host.state
local tempo=host.tempo
-- SEQUENCE is a view/controller over a layout-independent pattern engine.
-- The inherited tempo/phase producer remains the sole phase authority.
-- Outputs seq_<track>_{gate,env,hits,step} are control signals. Hit counts
-- are monotonic within this instance; the bank stores patterns, not playback.
local C = get("conventions")
local Model = get("sequence_model")
local Window = get("pad_window")
local Layout = get("sequence_layout")
local Store = get("sequence_store")
local View = get("sequence_view")
local Pe = get("persist")
local Rhythm=get("rhythm")
local page: any = { name = "SEQUENCE", records = Store.records() }
local root = ""
local model: any = Model.new()
local now = 0.0
local view: any = nil
local window: any = Window.new("seq", 7, 0)
page.window = window
for _, rec in ipairs(window.records) do table.insert(page.records, rec) end
local RATES = { 1, 2, 4, 8 }
local LENGTHS = { 4, 8, 16, 32 }
local selected = 1
local first_track = 1
local first_step = 0
local published: { [string]: any } = {}

local function publish(key: string, value: any)
    if published[key] ~= value then
        state.set(root .. "/" .. key, value)
        published[key] = value
    end
end

local function value(slot: number): number
    local rec = (page.step_params or page.params)[slot]
    return rec.value or rec.default or 0
end

local function set_record(slot: number, v: number)
    local rec = (page.step_params or page.params)[slot]
    rec.value = v
    if rec.persist == "bank" then Pe.publish(rec, now) end
end

local function refresh_view()
    model.track_count = 3
    local length = LENGTHS[math.clamp(math.floor(value(2)) + 1, 1, #LENGTHS)]
    for i = 1, model.track_count do
        model.tracks[i].length = length
        Store.write(page.records, model, i, now)
    end
    publish("seq_length_steps", length)
    selected = math.clamp(math.floor(value(4)) + 1, 1, model.track_count)
    page.params[4].value = selected - 1
    Window.read(window, root)
    local rect = Window.rect(window, math.min(8, length), 8)
    view = Layout.make(rect.row, rect.col, length, math.floor(value(5)), selected, page.step_params[6], model.track_count, rect.height)
    first_track, first_step = view.first_track, view.first_step
    publish("seq_width_columns", view.width)
    publish("seq_selected_track", selected)
    publish("seq_first_step", first_step + 1)
    publish("seq_rows_per_track", view.rows_per_track)
end

local function edit_selected(fn: (any) -> ())
    Store.read(page.records, root, model)
    refresh_view()
    fn(model.tracks[selected])
    Store.write(page.records, model, selected, now)
end

local PARAMS: { C.Param } = {
    { key = "seq_bpm", label = "BPM", min = 30, max = 240, default = 124,
        fmt = "%.1f", persist = "none", sink = { kind = "script", fn = function(v: number)
            tempo.set_bpm(v)
        end } },
    { key = "seq_length_choice", label = "LENGTH", values = { "4", "8", "16", "32" },
        default = 2, threshold = C.ENCODER.detent_enum, step = 1, persist = "bank",
        sink = { kind = "script", fn = function(_v: number) refresh_view() end } },
    { key = "seq_rate", label = "RATE", values = { "1/4", "1/8", "1/16", "1/32" },
        default = 2, threshold = C.ENCODER.detent_enum, step = 1, persist = "bank" },
    { key = "seq_track", label = "TRACK", values = { "KICK", "SNARE", "HI-HAT" },
        default = 0, threshold = C.ENCODER.detent_palette, step = 1, persist = "snapshot" },
    window.width,
    { key = "seq_window", label = "FROM STEP", values = { "1", "9", "17", "25" },
        default = 0, threshold = C.ENCODER.detent_palette, step = 1, persist = "snapshot" },
    window.height,
    { key = "seq_decay", label = "DECAY", min = 0.03, max = 2, default = 0.2,
        fmt = "%.2fs", persist = "bank" },
}
page.step_params=PARAMS
page.params=table.clone(PARAMS)
for _,r in ipairs(Rhythm.records) do table.insert(page.records,r) end
for i=5,8 do table.insert(page.records,PARAMS[i]) end
for i,key in ipairs({"mode","cycle","rest","offset"}) do
    page.params[i+4]=Rhythm.encoder(key,string.upper(key),function() return selected end)
end

page.top_labels = { "PLAY", "STOP", "TAP", "SYNC", "TRACK -", "TRACK +", "MUTE", "CLEAR HOLD" }
local TOP: { C.Verb } = {
    { kind = "toggle", on_press = function()
        if tempo.status().running then tempo.pause() else tempo.start() end
    end, is_lit = function() return tempo.status().running end },
    { kind = "trigger", on_press = function()
        tempo.stop()
        model.last_trigger_tick = nil
    end },
    { kind = "trigger", on_press = function() tempo.tap() end },
    { kind = "trigger", on_press = function() tempo.resync(0) end },
    { kind = "stepper", on_press = function() set_record(4, math.max(0, selected - 2)) end },
    { kind = "stepper", on_press = function() set_record(4, math.min(model.track_count - 1, selected)) end },
    { kind = "toggle", on_press = function()
        edit_selected(function(tr: any) tr.muted = not tr.muted end)
    end, is_lit = function() return model.tracks[selected].muted end },
    { kind = "hold", hold_s = 0.8, on_fire = function()
        edit_selected(function(tr: any) tr.masks = { 0, 0, 0, 0 } end)
    end },
}
page.top = TOP

function page.on_bind(bound_root: string)
    root = bound_root
    Rhythm.bind(root)
    model = Model.new()
    now = 0
    selected = 1
    published = {}
    state.register("seq_width_columns", 8)
    state.register("seq_selected_track", 1)
    state.register("seq_tracks", 3)
    state.register("seq_length_steps", 16)
    state.register("seq_first_step", 1)
    state.register("seq_rows_per_track", 2)
    state.register("seq_running", false)
    state.register("seq_skipped_steps", 0)
    for _, key in ipairs(Model.TRACK_KEYS) do
        for _, suffix in ipairs({ "step", "gate", "env", "hits" }) do
            state.register("seq_" .. key .. "_" .. suffix, 0.0)
        end
    end
end

function page.on_window_pad(ev: any, cell: any)
    if ev.pressed ~= true or cell == nil then return end
    Store.read(page.records, root, model)
    refresh_view()
    if Model.toggle(model.tracks[cell.track], cell.step) then
        Store.write(page.records, model, cell.track, now)
        set_record(4, cell.track - 1)
    end
end

function page.refresh_window(background_ready: boolean?)
    -- on_frame already rebuilt this content during the same publication pass.
    -- Direct pad dispatch passes false and still reads current state immediately.
    if background_ready then return end
    Store.read(page.records, root, model)
    refresh_view()
    window.mapping = view.cells
    window.pixels = View.pixels(view, model, tempo.status().running)
end

function page.on_frame(dt: number, t: number, visible: boolean)
    now = t
    Store.read(page.records, root, model)
    -- Bank recall and external edits are authoritative when no encoder write
    -- is pending. This also works while a different tab owns the param engine.
    for _, slot in ipairs({ 2, 3, 5, 8 }) do
        local rec = (page.step_params or page.params)[slot]
        local v = tonumber(state.get(root .. "/" .. rec.key))
        if not rec.dirty and v ~= nil then
            local hi = if rec.values then #rec.values - 1 else rec.max
            rec.value = math.clamp(v, rec.min or 0, hi)
        end
    end
    local st = tempo.status()
    if not page.params[1].dirty then page.params[1].value = st.bpm end
    refresh_view()
    model.seconds_per_beat = 60 / math.max(1, st.bpm)
    Model.advance(model, st.beat, st.running, RATES[math.floor(value(3)) + 1], dt, value(8))
    for i, key in ipairs(Model.TRACK_KEYS) do
        local track = model.tracks[i]
        publish("seq_" .. key .. "_step", track.step + 1)
        publish("seq_" .. key .. "_gate", track.gate)
        publish("seq_" .. key .. "_env", track.env)
        publish("seq_" .. key .. "_hits", track.hits)
    end
    Rhythm.step(st.beat,st.running,model.tracks,t)
    publish("seq_running", st.running)
    publish("seq_skipped_steps", model.skipped)
    window.mapping = view.cells
    window.pixels = View.pixels(view, model, st.running)
end

function page.render(ctx: any)
    if view == nil then refresh_view() end
    View.render(ctx, view, model, selected, first_track, first_step, tempo.status().running, window)
end

function page.on_stop()
    for _, key in ipairs(Model.TRACK_KEYS) do
        state.set(root .. "/seq_" .. key .. "_gate", 0.0)
        state.set(root .. "/seq_" .. key .. "_env", 0.0)
    end
end

return page

end
