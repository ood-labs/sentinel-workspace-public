--!strict
-- Show-owned per-Runtime factory; Phase 5 compatibility conversion.
return function(host: any,get: any,config: any)
-- Placement is a viewport: clipping never changes the musical pattern.
local Grid = get("sequence_grid")
local M = {}
local cached: any = nil

function M.make(row: number, col: number, length: number, width_choice: number,
                selected: number, window: any, track_count: number, height: number?): any
    local requested = if width_choice == 0 then math.min(8, length) else width_choice
    local width = math.min(requested, 8 - col)
    local available = math.min(height or 8, row + 1)
    local rows_per_track = math.min(math.ceil(length / width), available)
    local count = math.ceil(length / width)
    window.value = math.clamp(math.floor(window.value or 0), 0, count - 1)
    -- Geometry alone is cached; pattern, playback and LED content remain live.
    -- Keep this per Runtime and include every input that can change a cell.
    if cached and cached.row == row and cached.col == col
        and cached.length == length and cached.width == width
        and cached.available == available and cached.selected == selected
        and cached.offset == window.value and cached.tracks == track_count then
        window.values = cached.values
        return cached.view
    end
    local rows, cols = {}, {}
    for r = row, row - available + 1, -1 do table.insert(rows, r) end
    for c = col, col + width - 1 do table.insert(cols, c) end
    local capacity = math.floor(#rows / rows_per_track)
    local first_track = math.floor((selected - 1) / capacity) * capacity + 1
    -- Scroll by one displayed row; even a one-column viewport reaches every step.
    window.values = {}
    for step = 0, length - 1, width do table.insert(window.values, tostring(step + 1)) end
    window.value = math.clamp(math.floor(window.value or 0), 0, #window.values - 1)
    local first_step = window.value * width
    local view = Grid.make(rows, cols, rows_per_track, first_track, first_step, track_count)
    view.width, view.rows_per_track = width, rows_per_track
    view.origin_row, view.origin_col = row, col
    view.first_track, view.first_step = first_track, first_step
    cached = { row = row, col = col, length = length, width = width,
        available = available, selected = selected, offset = window.value,
        tracks = track_count, values = window.values, view = view }
    return view
end

return M

end
