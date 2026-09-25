--!strict
-- Show-owned per-Runtime factory; Phase 5 compatibility conversion.
return function(host: any,get: any,config: any)
local display=host.display
local C = get("conventions")
local Model = get("sequence_model")
local Window = get("pad_window")
local M = {}
local COLORS = { 0xDC8658, 0x63B9D5, 0xB49ADC, 0xDAAF58, 0x75C595, 0xD98EBA, 0x89A9DD, 0xB8C485 }
-- Palette indices are colors, not brightness. Spencer's hardware read:
-- 1 is red, 18 is bright blue-purple, 73 is gray, 96 is dark blue.
-- Keep the sequencer independent of the old generic dim/armed/held labels.
local VELOCITIES = { 4, 13, 18, 7, 11, 27, 19, 9 }
local EMPTY = 124 -- documented default RGB dark gray (20,20,20)
local PLAYHEAD_EMPTY = 123 -- light gray; a hit is brighter white (122)

function M.pixels(view: any, model: any, running: boolean): { [number]: number }
    local pixels = {}
    for index, cell in pairs(view.cells) do
        local track = model.tracks[cell.track]
        local v = C.LED.off
        if cell.step < track.length then
            v = if Model.enabled(track, cell.step) then VELOCITIES[cell.track] else EMPTY
            if track.muted then v = if Model.enabled(track, cell.step) then PLAYHEAD_EMPTY else 0 end
            if running and cell.step == track.step then
                v = if Model.enabled(track, cell.step) then C.LED.active else PLAYHEAD_EMPTY
            end
            pixels[index] = v
        end
    end
    return pixels
end

function M.render(ctx: any, view: any, model: any, selected: number,
                  first_track: number, first_step: number, running: boolean, layout: any)
    local track = model.tracks[selected]
    C.text(12, ctx.cy, track.name, C.TEXT.large, COLORS[selected])
    C.text(192, ctx.cy + 3, if running then "PLAYING" else "STOPPED", C.TEXT.body,
        if running then 0x75C595 else 0x88909C)
    C.text(310, ctx.cy + 3, string.format("steps %d-%d | %d cols x %d rows",
        first_step + 1, math.min(track.length, first_step + view.span), view.width,
        view.rows_per_track), C.TEXT.body, 0xC6CDD6)
    C.text(750, ctx.cy + 3, string.format("ORIGIN %d,%d", view.origin_col, 7-view.origin_row),
        C.TEXT.band, 0x818995)
    C.text(310, ctx.cy + 17, Window.hint(layout, ctx.t), C.TEXT.band,
        if layout.held then 0xFFFFFF else 0x818995)
    -- Compact track overview: the exact visible step window, including inactive
    -- cells after a shorter loop. White outline is playback, fill is the note.
    local count = math.min(view.capacity, model.track_count - first_track + 1)
    local h = math.min(17, math.floor(56 / math.max(count, 1)))
    for lane = 0, count - 1 do
        local index = first_track + lane
        local tr = model.tracks[index]
        local y = ctx.cy + 27 + lane * h
        local label = (if index == selected then ">" else " ") .. tr.name .. (if tr.muted then " M" else "")
        C.text(8, y, label, math.min(12, h), COLORS[index])
        local w = 818 / view.span
        for at = 0, view.span - 1 do
            local step = first_step + at
            if step < 64 then
                local valid = step < tr.length
                local fill = if valid and Model.enabled(tr, step) then COLORS[index]
                    elseif valid then C.INK.grid else C.INK.grid_empty
                display.rect(128 + at * w, y + 1, w - 2, h - 3, fill, true)
                if running and step == tr.step then
                    display.rect(128 + at * w, y + 1, w - 2, h - 3, 0xFFFFFF, false)
                end
            end
        end
    end
end

return M

end
