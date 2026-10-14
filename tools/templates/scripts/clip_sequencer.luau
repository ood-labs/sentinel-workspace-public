-- Clip Sequencer: plays a list of Video File sources in order through a
-- Wired-mode Mux, from one Event or the window's Go button.
--
-- `sources` lists the clips in order; clip i is on the Mux's input i - 1.
-- Go restarts clip 1 and selects it. Each next clip is prerolled (paused at
-- 0 with its reader filled) while the one before plays, then started and
-- selected `fade` seconds before the current clip ends, so the Mux
-- crossfades while both play and the outgoing clip reaches its last frame as
-- the fade ends. A clip's end comes from its `ended_count`, so `clip_ended`
-- follows the true end within a frame. After the last clip, `end_mode`
-- `hold` keeps its last frame on air and `black` fades the Mux to
-- `black_input`, an input with nothing connected. Next fades to the next clip
-- at once; Stop applies the end mode and pauses every clip.
--
-- Event payloads carry the clip's position in `sources` (1 for the first).
local script = {}

script.manifest = {
    name = "Clip Sequencer",
    inputs = {
        {name = "go", type = "event"},
        {name = "stop", type = "event"},
        {name = "next", type = "event"},
    },
    outputs = {
        {name = "clip_started", type = "event"},
        {name = "clip_ended", type = "event"},
        {name = "sequence_ended", type = "event"},
        {name = "clip", type = "signal"},
    },
    params = {
        {name = "sources", type = "string", default = "clip1,clip2,clip3"},
        {name = "mux", type = "string", default = "Program"},
        {name = "fade", type = "float", default = 1.5, min = 0, max = 10},
        {name = "end_mode", type = "enum", values = {"hold", "black"}, default = "hold"},
        {name = "black_input", type = "int", default = 7, min = 0, max = 7},
    },
}

local TRIGGER = 1

-- Scheduling arithmetic, free of host bindings, so a test can load this file
-- in a bare VM and check it.
local schedule = {}

function schedule.split(text)
    local out = {}
    for item in string.gmatch(text or "", "[^,]+") do
        local trimmed = item:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            out[#out + 1] = trimmed
        end
    end
    return out
end

-- Seconds of the current clip still to play.
function schedule.remaining(duration, current_time, rate)
    rate = (rate and rate > 0) and rate or 1
    return math.max(0, (duration or 0) - (current_time or 0)) / rate
end

-- Start the next clip once no more than `fade` seconds remain.
function schedule.should_start_next(duration, current_time, fade, rate)
    if not duration or duration <= 0 then
        return false
    end
    return schedule.remaining(duration, current_time, rate) <= fade
end

-- Indices whose ended_count rose since the last look.
function schedule.ended(previous, counts)
    local out = {}
    for i, count in ipairs(counts) do
        if count > (previous[i] or count) then
            out[#out + 1] = i
        end
    end
    return out
end

-- When each clip starts, from the sequence start, for clip durations and a
-- fade: every clip after the first starts `fade` before the previous ends.
function schedule.start_times(durations, fade)
    local starts = {}
    local t = 0
    for i, d in ipairs(durations) do
        starts[i] = t
        t = t + d - fade
    end
    return starts
end

script.schedule = schedule

local function srcPath(id, leaf)
    return "/sentinel/sources/" .. id .. "/" .. leaf
end

local function muxPath(node, leaf)
    return "/sentinel/pipelines/" .. node.params.mux .. "/parameters/" .. leaf
end

local function subscribeAll(node, sources)
    for _, id in ipairs(sources) do
        if not node.state.subscribed[id] then
            for _, leaf in ipairs({"currentTime", "duration", "playbackRate", "ended_count", "playing"}) do
                sentinel.subscribe(srcPath(id, leaf))
            end
            node.state.subscribed[id] = true
        end
    end
end

local function endedCounts(sources)
    local counts = {}
    for i, id in ipairs(sources) do
        counts[i] = sentinel.get(srcPath(id, "ended_count")) or 0
    end
    return counts
end

local function preroll(id)
    sentinel.invoke(srcPath(id, "actions/preroll"), {time = 0})
end

local function startClip(node, sources, i, restart)
    local id = sources[i]
    if restart then
        sentinel.invoke(srcPath(id, "actions/restart"), {})
    else
        sentinel.set(srcPath(id, "playing"), true)
    end
    sentinel.set(muxPath(node, "selected"), i - 1)
    node.state.current = i
    node.outputs.clip_started:emit({event_type = TRIGGER, payload = {i}})
    if sources[i + 1] then
        preroll(sources[i + 1])
    end
end

local function applyEnd(node)
    if node.params.end_mode == "black" then
        sentinel.set(muxPath(node, "selected"), node.params.black_input)
    end
end

function script.init(node)
    node.state.subscribed = {}
    node.state.running = false
    node.state.current = 0
    node.state.counts = {}
    node.state.pause_at = {}
end

function script.control_process(node, ctx)
    local sources = schedule.split(node.params.sources)
    subscribeAll(node, sources)
    local now = time.now()

    local go = #node.inputs.go:read_events() > 0 or ui.get("go_btn")
    local stop = #node.inputs.stop:read_events() > 0 or ui.get("stop_btn")
    local skip = #node.inputs.next:read_events() > 0 or ui.get("next_btn")

    local counts = endedCounts(sources)
    if stop then
        node.state.running = false
        applyEnd(node)
        for _, id in ipairs(sources) do
            sentinel.set(srcPath(id, "playing"), false)
        end
        node.state.pause_at = {}
        log.info("stopped")
    elseif go and #sources > 0 then
        for _, id in ipairs(sources) do
            sentinel.set(srcPath(id, "loop"), false)
        end
        sentinel.set(muxPath(node, "fade_time"), node.params.fade)
        node.state.running = true
        node.state.pause_at = {}
        startClip(node, sources, 1, true)
        log.info("go")
    elseif skip and node.state.running and node.state.current < #sources then
        -- The outgoing clip plays through the fade, then pauses.
        local outgoing = node.state.current
        node.state.pause_at[outgoing] = now + node.params.fade + 0.1
        startClip(node, sources, outgoing + 1, false)
    end

    if node.state.running then
        for _, i in ipairs(schedule.ended(node.state.counts, counts)) do
            node.outputs.clip_ended:emit({event_type = TRIGGER, payload = {i}})
            if i == #sources then
                node.state.running = false
                applyEnd(node)
                node.outputs.sequence_ended:emit({event_type = TRIGGER, payload = {i}})
                if #sources > 1 then
                    preroll(sources[1])
                end
                log.info("sequence ended")
            end
        end

        local i = node.state.current
        if node.state.running and i >= 1 and i < #sources then
            local id = sources[i]
            local duration = sentinel.get(srcPath(id, "duration"))
            local t = sentinel.get(srcPath(id, "currentTime"))
            local rate = sentinel.get(srcPath(id, "playbackRate"))
            if sentinel.get(srcPath(id, "playing")) == true and
                schedule.should_start_next(duration, t, node.params.fade, rate) then
                startClip(node, sources, i + 1, false)
            end
        end
    end

    for i, at in pairs(node.state.pause_at) do
        if now >= at then
            sentinel.set(srcPath(sources[i], "playing"), false)
            node.state.pause_at[i] = nil
        end
    end

    node.state.counts = counts
    node.outputs.clip:set(node.state.running and node.state.current or 0)
end

function script.render(node, ui)
    local status = node.state.running and ("playing clip " .. node.state.current) or "idle"
    ui.text("status", status)
    ui.button("go_btn", "Go")
    ui.same_line()
    ui.button("next_btn", "Next")
    ui.same_line()
    ui.button("stop_btn", "Stop")
end

return script
