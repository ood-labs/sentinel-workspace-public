--!strict
-- Show-owned per-Runtime factory; Phase 5 compatibility conversion.
return function(host: any,get: any,config: any)
local state=host.state
local display=host.display
-- Page COLOR. Eight palettes, three colours each, edited in HSV.
--
-- Where the colour actually lives, and why it is split:
--
--   * The editor keeps H, S and V as floats in this module. A hue knob has to
--     return to where it started when it is turned back, and a value that
--     round-trips through eight-bit RGB every frame does not: at low
--     saturation the hue quantises to a handful of steps and the knob stops
--     meaning anything.
--   * Each colour is ALSO mirrored to one packed 24-bit RGB path under the
--     panel root. That is what the rest of the show reads, what the `bank`
--     preset group snapshots, and what survives the host process exiting.
--
-- So precision is exact while a hand is on the knob, and the one lossy step is
-- a decode at cold start, which nobody is turning a knob through.
--
-- The editor's own records carry `persist = "bank"`. That is what marks the
-- group dirty when a colour changes, and the debounced save then snapshots
-- every path in the group, these twenty-four included. See
-- `ctrl/stagerig/presets/push2_banks.json`.
--
-- No host-binding work at the top level. `on_bind` is called by the core from
-- inside the root's `on_start`.

local C = get("conventions")
local W = get("widgets")
local Window = get("pad_window")
local Pe=get("persist")
local paletteRecords={}

local page = {}

page.name = "COLOR"

local PALETTES = 8
local SLOTS = { "a", "b", "c" }
local SLOT_LABELS = { "A", "B", "C" }

local root = ""
local window = Window.new("color", 6, 0)
page.window = window
page.records = window.records

-- Every colour, keyed `<palette><slot>`, each a table of h, s, v in 0..1.
local hsv: { [string]: { h: number, s: number, v: number } } = {}

-- Session state in one table, so the module stays inside the 30-local rule.
-- `pushed` is the last packed value written per colour, so the page publishes
-- on change rather than twenty-four times a frame.
local S = {
    slot = 0,
    seeded = false,
}

local pushed: { [string]: number } = {}

local PARAMS: { C.Param }

local function num_at(p: string, fallback: number): number
    local v = state.get(p)
    if typeof(v) == "number" then
        return v
    end
    return fallback
end

local function key_of(palette: number, slot: number): string
    return tostring(palette) .. SLOTS[slot + 1]
end

-- HSV to packed 24-bit RGB. The standard six-sector conversion, written out
-- rather than pulled in, because the library has no colour module and one
-- page does not justify creating one.
local function pack_hsv(h: number, s: number, v: number): number
    local hh = (h % 1.0) * 6.0
    local i = math.floor(hh)
    local f = hh - i
    local p = v * (1.0 - s)
    local q = v * (1.0 - s * f)
    local t = v * (1.0 - s * (1.0 - f))
    local r, g, b = v, t, p
    if i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    elseif i == 5 then r, g, b = v, p, q
    end
    local function byte(x: number): number
        return math.clamp(math.floor(x * 255.0 + 0.5), 0, 255)
    end
    return byte(r) * 65536 + byte(g) * 256 + byte(b)
end

-- The one lossy step, run once per colour at cold start to seed the editor
-- from whatever the bank restored.
local function unpack_hsv(rgb: number): (number, number, number)
    local r = math.floor(rgb / 65536) % 256 / 255.0
    local g = math.floor(rgb / 256) % 256 / 255.0
    local b = rgb % 256 / 255.0
    local hi = math.max(r, g, b)
    local lo = math.min(r, g, b)
    local d = hi - lo
    local h = 0.0
    if d > 0.0 then
        if hi == r then
            h = ((g - b) / d) % 6.0
        elseif hi == g then
            h = (b - r) / d + 2.0
        else
            h = (r - g) / d + 4.0
        end
        h = h / 6.0
    end
    return h % 1.0, if hi > 0.0 then d / hi else 0.0, hi
end

local function active_palette(): number
    local rec = PARAMS[1]
    return math.clamp(math.floor(((rec and rec.value) or 0) + 0.5),
                      0, PALETTES - 1)
end

local function active(): { h: number, s: number, v: number }
    return hsv[key_of(active_palette(), S.slot)]
end

-- Copy the three editor records onto the colour they are pointing at. Called
-- whenever an encoder moves or the target changes.
local function pull_editor()
    local c = active()
    if c == nil then
        return
    end
    c.h = (PARAMS[2] and PARAMS[2].value) or c.h
    c.s = (PARAMS[3] and PARAMS[3].value) or c.s
    c.v = (PARAMS[4] and PARAMS[4].value) or c.v
end

-- Point the three editor records at a different colour, without that looking
-- like an edit of the colour they were on.
local function push_editor()
    local c = active()
    if c == nil then
        return
    end
    if PARAMS[2] ~= nil then PARAMS[2].value = c.h end
    if PARAMS[3] ~= nil then PARAMS[3].value = c.s end
    if PARAMS[4] ~= nil then PARAMS[4].value = c.v end
end

page.top_labels = {
    "A", "B", "C", "COPY", "PASTE", "-", "-", "-",
}

-- The three slot buttons are `subtab` verbs, which is what that kind is for
-- and the first live use of it: they choose which of a palette's three colours
-- the encoders are pointing at, without being a page of their own.
local function slot_verb(index: number): C.Verb
    return {
        kind = "subtab",
        on_press = function()
            S.slot = index
            state.set(root .. "/color_slot", SLOT_LABELS[index + 1])
            push_editor()
        end,
        is_lit = function(): boolean
            return S.slot == index
        end,
    }
end

local TOP: { C.Verb } = {}

-- Eight encoder slots. `detent_palette` on the selector is what makes one
-- hardware click move one palette; a continuous record there would slide
-- through three of them on a flick.
PARAMS = {
    {
        key = "palette", label = "PALETTE",
        min = 0.0, max = 7.0, default = 0.0, fmt = "%.0f",
        threshold = C.ENCODER.detent_palette, step = 1,
        persist = "bank",
        sink = {
            kind = "script",
            fn = function(v: number)
                local i = math.clamp(math.floor(v + 0.5), 0, PALETTES - 1)
                state.set(root .. "/color_palette", i)
                -- The pad row and this encoder both choose the palette, so
                -- both go through the region. Without this the lit pad keeps
                -- saying what it said before while the encoder edits another.
                state.set(root .. "/color_palette_pad", i)
                push_editor()
            end,
        },
    },
    {
        key = "hue", label = "HUE",
        min = 0.0, max = 1.0, default = 0.0, fmt = "%.3f",
        persist = "bank",
    },
    {
        key = "sat", label = "SAT",
        min = 0.0, max = 1.0, default = 1.0, fmt = "%.3f",
        persist = "bank",
    },
    {
        key = "val", label = "VAL",
        min = 0.0, max = 1.0, default = 1.0, fmt = "%.3f",
        persist = "bank",
    },
    window.width,
    { key = "color_window", label = "FROM PAL", values = {"1"}, default = 0,
        threshold = C.ENCODER.detent_palette, step = 1, persist = "snapshot" },
    window.height,
    { stage = "parked" },
}

page.params = PARAMS

-- Eight hues around the wheel, so a cold start is eight distinguishable
-- palettes rather than eight identical ones. B and C are the same hue at
-- lower value, which is a usable starting shape for a three colour look.
local function seed()
    for pal = 0, PALETTES - 1 do
        for slot = 0, #SLOTS - 1 do
            hsv[key_of(pal, slot)] = {
                h = pal / PALETTES,
                s = 1.0 - slot * 0.25,
                v = 1.0 - slot * 0.3,
            }
        end
    end
end

for pal=0,PALETTES-1 do for slot=0,#SLOTS-1 do
    local key=key_of(pal,slot)
    local rec={key="pal"..key,default=pack_hsv(pal/PALETTES,1-slot*.25,1-slot*.3),min=0,max=16777215,persist="bank"}
    paletteRecords[key]=rec;table.insert(page.records,rec)
end end

function page.on_bind(bound_root: string)
    root = bound_root
    S.slot = 0
    S.seeded = false
    pushed = {}
    seed()

    state.register("color_palette_pad", 0)
    state.register("color_palette", 0)
    state.register("color_slot", "A")
    for pal = 0, PALETTES - 1 do
        for slot = 0, #SLOTS - 1 do
            local key=key_of(pal,slot)
            local packed=paletteRecords[key].value or paletteRecords[key].default
            local c=hsv[key];c.h,c.s,c.v=unpack_hsv(packed);pushed[key]=packed
        end
    end

    for i = 0, #SLOTS - 1 do
        TOP[i + 1] = slot_verb(i)
    end
    TOP[4] = {
        kind = "trigger",
        on_press = function()
            local c = active()
            if c ~= nil then
                state.set(root .. "/color_clipboard", pack_hsv(c.h, c.s, c.v))
            end
        end,
    }
    TOP[5] = {
        kind = "trigger",
        on_press = function()
            local packed = num_at(root .. "/color_clipboard", -1.0)
            if packed < 0.0 then
                return
            end
            local c = active()
            if c ~= nil then
                c.h, c.s, c.v = unpack_hsv(packed)
                push_editor()
            end
        end,
    }
    state.register("color_clipboard", -1.0)
end

page.top = TOP

-- Palette contents stay logical; the desktop handles placement and ownership.
function page.refresh_window(background_ready: boolean?)
    if background_ready then return end -- on_frame already prepared the same viewport
    Window.read(window, root)
    local rect = Window.rect(window, 8, 8)
    if window.height.value == 0 then rect.height = math.min(rect.height, math.ceil(PALETTES / rect.width)) end
    local from: any = PARAMS[6]
    from.values = {}
    for i = 0, PALETTES-1, rect.width do table.insert(from.values, tostring(i+1)) end
    from.value = math.clamp(math.floor(from.value or 0),0,#from.values-1)
    window.mapping, window.pixels = {}, {}
    local selected_palette = active_palette()
    for y=0,rect.height-1 do
        for x=0,rect.width-1 do
            local index = (rect.row-y)*8+rect.col+x
            local pal = from.value*rect.width + y*rect.width+x
            if pal < PALETTES then
                window.mapping[index] = pal
                window.pixels[index] = if pal == selected_palette then C.LED.active else C.LED.armed
            end
        end
    end
end

function page.on_window_pad(ev: any, palette: number?)
    if not ev.pressed or palette == nil then return end
    PARAMS[1].value = palette
    state.set(root .. "/color_palette", palette)
    state.set(root .. "/color_palette_pad", palette)
    push_editor()
end

-- The twenty-four packed paths are the truth and `hsv` is a cache over them.
--
-- That direction is forced by the bank. A restore lands whenever the group
-- file finishes loading, which can be seconds after boot, so a page that only
-- ever wrote to those paths would publish its own defaults over the restored
-- palette and never notice. Adopting anything this page did not write itself
-- also means a bank recalled mid-show, or a colour set from a cue or over MCP,
-- shows up here without a special case for each.
function page.on_frame(dt: number)
    local restoredPalette=tonumber(state.get(root.."/palette"))
    if restoredPalette and not PARAMS[1].dirty then PARAMS[1].value=restoredPalette end
    local akey = key_of(active_palette(), S.slot)
    local adopted_active = false

    for pal = 0, PALETTES - 1 do
        for slot = 0, #SLOTS - 1 do
            local k = key_of(pal, slot)
            local packed = math.floor(num_at(root .. "/pal" .. k, -1.0))
            -- `pushed[k]` nil means this page has not published that colour
            -- yet, so there is nothing to compare against and nothing to
            -- adopt. The publish loop below fills it on the first frame.
            if packed >= 0 and pushed[k] ~= nil and pushed[k] ~= packed then
                local c = hsv[k]
                c.h, c.s, c.v = unpack_hsv(packed)
                pushed[k] = packed
                paletteRecords[k].value=packed
                Pe.publish(paletteRecords[k],host.time.now())
                if k == akey then
                    adopted_active = true
                end
            end
        end
    end

    -- Whoever moved last owns the editor. An adopted colour pushes into the
    -- records; otherwise the records push into the colour, which is the
    -- operator turning a knob.
    if adopted_active or not S.seeded then
        S.seeded = true
        push_editor()
    elseif (PARAMS[2] :: any).dirty or (PARAMS[3] :: any).dirty or (PARAMS[4] :: any).dirty then
        pull_editor()
    end

    for pal = 0, PALETTES - 1 do
        for slot = 0, #SLOTS - 1 do
            local k = key_of(pal, slot)
            local c = hsv[k]
            local packed = pack_hsv(c.h, c.s, c.v)
            if pushed[k] ~= packed then
                pushed[k] = packed
                state.set(root .. "/pal" .. k, packed)
                paletteRecords[k].value=packed
                Pe.publish(paletteRecords[k],host.time.now())
            end
        end
    end
    page.refresh_window()
end

function page.render(ctx: any)
    local pal = active_palette()

    C.text(18, ctx.cy + 0,
           "PAL " .. (pal + 1) .. "  " .. SLOT_LABELS[S.slot + 1],
           C.TEXT.large, 0xFFFFFF)

    local c = active()
    C.text(190, ctx.cy + 6,
           string.format("h %.3f   s %.3f   v %.3f   #%06x",
                         c.h, c.s, c.v, pack_hsv(c.h, c.s, c.v)),
           C.TEXT.body, W.INK.body)

    C.text(190, ctx.cy + 20, Window.hint(window, ctx.t), C.TEXT.band, W.INK.body)

    -- Eight palettes across, three swatches each stacked, so every colour in
    -- the bank is on the glass at once and the active one is framed.
    for p = 0, PALETTES - 1 do
        local x = 18 + p * 118
        for slot = 0, #SLOTS - 1 do
            local col = hsv[key_of(p, slot)]
            W.swatch(x, ctx.cy + 34 + slot * 16, 104, 14,
                     pack_hsv(col.h, col.s, col.v))
        end
        if p == pal then
            -- The active palette gets a rule under it rather than a border,
            -- because a border on a swatch column reads as a fourth colour.
            display.rect(x, ctx.cy + 82, 104, 3, 0xFFFFFF, true)
        end
    end
end

return page

end
