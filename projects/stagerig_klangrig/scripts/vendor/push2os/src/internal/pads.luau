--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
-- Push 2 OS pad and button LED surface. Owns the layer stack, the compositor,
-- the frame diff, and the single MIDI batch. Nothing else in the panel writes
-- MIDI output.
--
-- Surfaces are one flat index space so the whole controller is one frame:
--
--   0  .. 63   the 8x8 pad grid, index = row * 8 + col
--   64 .. 71   the eight buttons above the display
--   72 .. 79   the eight buttons below the display
--   80         Select (white CC 48)
--   81         Shift / active window pin indicator (white CC 49)
--   82         Layout / overview indicator (white CC 31)
--
-- Layers composite in the order `global`, `page`, `shift`, `transient`. A
-- later layer wins the surface outright; there is no blending, because the
-- hardware takes one velocity per surface and an average of two palette
-- indices is a third unrelated colour.
--
-- No host-binding work at module top level. `bind` runs from the core, which
-- the root calls from `on_start`.

local C = get("conventions")

local M = {}

local TOP_BASE = 64
local BOTTOM_BASE = 72
local SURFACES = 83

-- Composite order. Index in this list is the layer's priority.
local LAYER_ORDER = { "global", "page", "shift", "transient", "windows" }

local root_prefix = ""
local layers: { [string]: { [number]: number } } = {}
local regions: { [string]: { any } } = {}
-- Transient entries expire on wall time rather than on an event, so a pulse
-- cannot be left lit by a dropped release.
local transient_until: { [number]: number } = {}
local last_sent: { [number]: number } = {}
local have_sent = false
local batch_count = 0
-- The clock from the last composed frame, so `pulse` can set a deadline
-- without the caller holding the panel's elapsed time.
local frame_now = 0.0
-- Set only during the boot registration pass. See `declare`.
local collecting = false
local registered: { [string]: boolean } = {}
local sessions: { [any]: any } = {}
local current_page: any = nil
local solo_index = -1

local function path(rel: string): string
    return root_prefix .. "/" .. rel
end

function M.pad_index(row: number, col: number): number
    return row * 8 + col
end

function M.top_index(slot: number): number
    return TOP_BASE + slot
end

function M.bottom_index(slot: number): number
    return BOTTOM_BASE + slot
end

-- Global regions may live anywhere, not only on the convention's row 0.
-- Dynamic page views use this before drawing/editing their cells.
function M.is_global(row: number, col: number): boolean
    for _, region in ipairs(regions.global or {}) do
        if region.row == row and table.find(region.cols, col) ~= nil then
            return true
        end
    end
    return false
end

function M.set_windows(frame: { [number]: number }, pinned: boolean?, overview: boolean?)
    frame[81] = if pinned then 127 else 16
    frame[82] = if overview then 127 else 16
    layers.windows = frame
end

function M.paint_page(row: number, col: number, velocity: number?)
    if row < 0 or row > 7 or col < 0 or col > 7 or M.is_global(row, col) then return end
    if layers.page ~= nil then
        if velocity == nil then layers.page[M.pad_index(row, col)] = nil
        else layers.page[M.pad_index(row, col)] = velocity end
    end
end

-- The wire message for one surface. Pads are notes on the pad channel; the
-- two button rows are CCs on their own base, which is why the index space has
-- to be translated rather than sent raw.
--
-- A region declares its own `on` and `off` velocities, so a page can hand in
-- anything. The host rejects a message whose `data2` is outside 0..127 and
-- counts it failed, which would silently drop that one pad out of an
-- otherwise good batch. Clamp here, at the one place every velocity passes
-- through, rather than trusting eight page authors.
local function message_for(index: number, velocity: number): any
    velocity = math.clamp(math.floor(velocity or 0), 0, 127)
    if index == 82 then
        return { kind = "cc", channel = 1, data1 = 31, data2 = velocity }
    elseif index == 81 then
        return { kind = "cc", channel = 1, data1 = 49, data2 = velocity }
    elseif index == 80 then
        return { kind = "cc", channel = 1, data1 = 48, data2 = velocity }
    elseif index >= BOTTOM_BASE then
        return {
            kind = "cc", channel = C.MIDI.button_channel,
            data1 = C.MIDI.bottom_cc_base + (index - BOTTOM_BASE),
            data2 = velocity,
        }
    elseif index >= TOP_BASE then
        return {
            kind = "cc", channel = C.MIDI.button_channel,
            data1 = C.MIDI.top_cc_base + (index - TOP_BASE),
            data2 = velocity,
        }
    end
    return {
        kind = "note_on", channel = C.MIDI.pad_channel,
        data1 = C.MIDI.pad_note_base + index,
        data2 = velocity,
    }
end

local function layer_of(name: string): { [number]: number }
    local l = layers[name]
    if l == nil then
        l = {}
        layers[name] = l
    end
    return l
end

-- Reset everything a panel session owns. Called from `bind`.
function M.bind(root: string)
    root_prefix = root
    layers = {}
    regions = {}
    registered = {}
    sessions, current_page, solo_index = {}, nil, -1
    transient_until = {}
    last_sent = {}
    have_sent = false
    batch_count = 0
    for _, name in ipairs(LAYER_ORDER) do
        layers[name] = {}
    end
    host.state.register("pad_batches", 0)
    host.state.register("pad_changes", 0)
end

-- Each page keeps its own regions and transient LEDs while another tab is up.
function M.activate(page: any)
    if current_page == page then return end
    if current_page then
        sessions[current_page] = {regions=regions.page, pixels=layers.page,
            transient=layers.transient, deadlines=transient_until}
    end
    current_page = page
    local saved = sessions[page]
    if not saved then
        saved = {regions={}, pixels={}, transient={}, deadlines={}}
        sessions[page] = saved
    end
    regions.page, layers.page = saved.regions, saved.pixels
    layers.transient, transient_until = saved.transient, saved.deadlines
end

function M.mount(page: any)
    M.activate(page)
    if typeof(page.on_pads) == "function" then page.on_pads(M) end
end

function M.solo(index: number)
    solo_index = index
end

-- Walk one page's region declarations at boot so their state paths exist from
-- the first read, without making the regions live. See `declare`.
function M.register_page(page: any)
    if typeof(page.on_pads) ~= "function" then
        return
    end
    collecting = true
    local ok, err = pcall(page.on_pads, M)
    collecting = false
    if not ok then
        host.log.error("[push2os] on_pads registration failed: " .. tostring(err))
    end
end

-- Drop every region and lit surface a page owns. Called on a tab switch, so
-- the outgoing page's pads do not stay lit under the incoming page.
function M.clear_page()
    regions.page = {}
    layers.page = {}
    -- The transient layer goes with it. A pulse belongs to the page that fired
    -- it, and it composites above every region, so one fired on the last frame
    -- before a tab press would go on burning on the page in front of the
    -- operator: a beat flash from TEMPO at a slow tempo lands on the FX grid
    -- as a pad at held velocity, which is exactly what a live blinder looks
    -- like. Both pages already refuse to pulse while they are not visible;
    -- this closes the one frame that guard cannot cover.
    layers.transient = {}
    transient_until = {}
end

local function set_led(region: any, col: number, active: boolean)
    region.active[col] = active
    layer_of(region.layer)[M.pad_index(region.row, col)] =
        active and (region.on or C.LED.active) or (region.off or C.LED.dim)
end

-- What a region's state path holds before anything is pressed. The kinds do
-- not agree on a type: a switch is a boolean, a radio is the chosen index,
-- and a recall is the preset's name.
local function initial_value(region: any): any
    if region.kind == "radio" then
        return -1
    elseif region.kind == "recall" then
        return ""
    end
    return false
end

-- Declare a region. `layer` defaults to "page", which is what a page file
-- wants; the show's row-0 pads declare on "global" and survive tab switches.
--
-- A region:
--   kind    "momentary" | "latch" | "radio" | "recall"
--   row     number
--   cols    { number }
--   names   { string }, `recall` only, parallel to `cols`
--   group   string, `recall` only: the preset group to drive
--   on,off  velocity, defaulting to the conventions palette
--   key     state path suffix under the panel root, optional
--   on_change (col, active) -> (), optional
function M.declare(region: any, layer: string?)
    -- In the boot registration pass a page declares its regions only so their
    -- state paths exist. Registering and returning keeps the region itself out
    -- of the layers, so an unselected page's pads are not lit and its events
    -- are not routed, while nothing appears under the panel root later than
    -- the first read.
    if collecting then
        if region.key ~= nil and not registered[region.key] then
            host.state.register(region.key, initial_value(region))
            registered[region.key] = true
        end
        return
    end

    local name = layer or "page"
    local list = regions[name]
    if list == nil then
        list = {}
        regions[name] = list
    end
    region.layer = name
    region.active = region.active or {}
    table.insert(list, region)

    if region.key ~= nil and not registered[region.key] then
        host.state.register(region.key, initial_value(region))
        registered[region.key] = true
    end
    for _, col in ipairs(region.cols) do
        set_led(region, col, region.active[col] == true)
    end
end

local function publish(region: any, col: number, active: boolean)
    set_led(region, col, active)
    if region.key ~= nil then
        host.state.set(path(region.key), active)
    end
    if typeof(region.on_change) == "function" then
        pcall(region.on_change, col, active)
    end
end

-- Exactly one cell of a radio region is lit. Every other cell in the region
-- goes dark in the same pass, so the frame the compositor sees is never a
-- moment with two cells on.
local function choose(region: any, col: number)
    for _, c in ipairs(region.cols) do
        set_led(region, c, c == col)
    end
    region.index = col
    if region.key ~= nil then
        host.state.set(path(region.key), col)
    end
    if typeof(region.on_change) == "function" then
        pcall(region.on_change, col, true)
    end
end

-- Recall the preset a column names. The LED is NOT set here: it follows the
-- group's own reported active preset on the next frame, so a recall fired
-- from a cue, a mapping, or another surface lights the same pad this one
-- would have.
local function fire_recall(region: any, col: number)
    local at = table.find(region.cols, col)
    local name = at and region.names[at] or nil
    if name == nil then
        return
    end
    host.preset.recall(region.group, name)
    if region.key ~= nil then
        host.state.set(path(region.key), name)
    end
    if typeof(region.on_change) == "function" then
        pcall(region.on_change, col, true)
    end
end

-- Move a radio region from something other than a pad press.
--
-- A page whose active selection can be reached two ways, a pad row and an
-- encoder, needs this: without it the encoder changes the value and the lit
-- pad goes on saying what it said before, so the grid and the readout
-- disagree about which palette is being edited. Routing both through `choose`
-- means one code path decides what is lit, whichever surface asked.
--
-- Returns false when no region on any layer carries that key, so a page that
-- renamed its region finds out rather than silently losing its LEDs.
function M.select(key: string, col: number): boolean
    for _, name in ipairs(LAYER_ORDER) do
        for _, region in ipairs(regions[name] or {}) do
            if region.key == key and region.kind == "radio"
               and table.find(region.cols, col) ~= nil then
                choose(region, col)
                return true
            end
        end
    end
    return false
end

-- Route a pad event to whichever region owns it. Returns true when a region
-- consumed the event, so the core knows not to hand it to the page as raw.
function M.on_pad(ev: any): boolean
    local row, col = ev.row, ev.col
    if typeof(row) ~= "number" or typeof(col) ~= "number" then
        return false
    end
    for _, name in ipairs(LAYER_ORDER) do
        for _, region in ipairs(regions[name] or {}) do
            if region.row == row and table.find(region.cols, col) ~= nil then
                local pressed = ev.pressed == true
                if region.kind == "momentary" then
                    publish(region, col, pressed)
                elseif region.kind == "latch" and pressed then
                    publish(region, col, not region.active[col])
                elseif region.kind == "radio" and pressed then
                    choose(region, col)
                elseif region.kind == "recall" and pressed then
                    fire_recall(region, col)
                end
                return true
            end
        end
    end
    return false
end

-- Pull the LED state of any region whose truth lives outside this module.
-- Only `recall` qualifies so far: the preset group, not the pad, decides
-- which look is current.
local function refresh_external()
    for _, name in ipairs(LAYER_ORDER) do
        for _, region in ipairs(regions[name] or {}) do
            if region.kind == "recall" then
                local ok, current = pcall(host.preset.active, region.group)
                for at, preset_name in ipairs(region.names) do
                    local col = region.cols[at]
                    if col ~= nil then
                        set_led(region, col, ok and preset_name == current)
                    end
                end
            end
        end
    end
end

-- Light one surface above every region for a fixed time. This is the layer a
-- beat flash or a cue confirmation writes to; it reverts on its own.
--
-- The deadline is measured from the last frame's clock rather than a caller
-- argument, so a page can pulse from a button handler without being handed
-- the panel's elapsed time.
function M.pulse(index: number, velocity: number, seconds: number)
    layer_of("transient")[index] = velocity
    transient_until[index] = frame_now + seconds
end

local function expire_transients(now: number)
    for index, deadline in pairs(transient_until) do
        if now >= deadline then
            transient_until[index] = nil
            layer_of("transient")[index] = nil
        end
    end
end

-- A sparse map: undeclared cells remain transparent, including off-tab pages.
function M.page_cells(page: any): { [number]: number }
    local previous = current_page
    M.activate(page)
    refresh_external()
    expire_transients(frame_now)
    local out = table.clone(layers.page or {})
    for index, value in pairs(layers.transient or {}) do
        if index < 64 then out[index] = value end
    end
    if previous then M.activate(previous) end
    return out
end

function M.page_event(page: any, ev: any)
    local previous = current_page
    M.activate(page)
    M.on_pad(ev)
    if previous then M.activate(previous) end
end

-- Build the frame: every surface off, then each layer in order. `top_lit` and
-- the tab index come from the core so the buttons agree with the glass.
local function compose(top_lit: { boolean }, page_index: number,
                       page_count: number): { [number]: number }
    local frame: { [number]: number } = {}
    for i = 0, SURFACES - 1 do
        frame[i] = C.LED.off
    end

    for _, name in ipairs(LAYER_ORDER) do
        for index, velocity in pairs(layers[name] or {}) do
            if index >= 0 and index < SURFACES then
                frame[index] = velocity
            end
        end
    end

    for i = 0, C.CELLS - 1 do
        frame[TOP_BASE + i] = top_lit[i + 1] and C.LED.active or C.LED.off
        if i == page_index then
            frame[BOTTOM_BASE + i] = C.LED.active
        elseif i < page_count then
            frame[BOTTOM_BASE + i] = C.LED.dim
        else
            frame[BOTTOM_BASE + i] = C.LED.off
        end
    end

    -- The band pass above is the steady-state indicator and has to win over a
    -- stale `page` or `global` entry, so it runs after the layer pass. That
    -- also swallowed every `transient` write to a band index, which made
    -- `M.pulse(M.top_index(n), ...)` silently do nothing even though
    -- `top_index` and `bottom_index` are public. A transient is a deliberate
    -- momentary override with an expiry, so it is re-applied here and the
    -- indicator comes back on its own when the pulse lapses.
    for index, velocity in pairs(layers.transient or {}) do
        if index >= TOP_BASE and index < SURFACES then
            frame[index] = velocity
        end
    end

    if solo_index >= 0 then
        frame[BOTTOM_BASE + solo_index] = if math.floor(frame_now*4)%2 == 0 then 122 else 16
    end
    frame[82] = (layers.windows and layers.windows[82]) or 16
    frame[81] = (layers.windows and layers.windows[81]) or 16
    frame[80] = 127 -- Select is a monochrome button: steady bright white.
    return frame
end

-- Diff against the last frame actually sent and send only what moved. Two
-- identical frames produce no batch at all, which is what keeps a static
-- panel off the MIDI bus entirely.
function M.flush(top_lit: { boolean }, page_index: number, page_count: number,
                 now: number): number
    frame_now = now
    expire_transients(now)
    refresh_external()
    local frame = compose(top_lit, page_index, page_count)

    local messages: { any } = {}
    for i = 0, SURFACES - 1 do
        local v = frame[i]
        if not have_sent or last_sent[i] ~= v then
            table.insert(messages, message_for(i, v))
        end
    end

    if #messages == 0 then
        return 0
    end

    -- `send_many` returns { sent_count, failed_count, errors }, and returns
    -- zero sent when the output port does not exist: the Push 2 not yet
    -- enumerated at boot, or unplugged mid-show. Recording those messages as
    -- sent is the trap. The next composed frame would equal `last_sent`, the
    -- diff would emit nothing, and the grid would stay dark for the rest of
    -- the show even after the device came back. So a batch that did not fully
    -- land leaves `last_sent` alone and clears `have_sent`, which forces the
    -- next frame to resend all 83 surfaces.
    local res = host.midi.send_many(C.MIDI.out_port, messages)
    if typeof(res) == "table" and (res.failed_count or 0) > 0 then
        have_sent = false
        return 0
    end
    for i = 0, SURFACES - 1 do
        last_sent[i] = frame[i]
    end
    have_sent = true
    batch_count += 1
    host.state.set(path("pad_batches"), batch_count)
    host.state.set(path("pad_changes"), #messages)
    return #messages
end

-- Exposed for the offline spec.
M.compose = compose
M.message_for = message_for
M.SURFACES = SURFACES
M.TOP_BASE = TOP_BASE
M.BOTTOM_BASE = BOTTOM_BASE

return M

end
