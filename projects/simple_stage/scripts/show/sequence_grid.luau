--!strict
-- Show-owned per-Runtime factory; Phase 5 compatibility conversion.
return function(host: any,get: any,config: any)
-- A view over tracks, never the pattern itself. Physical rows descend from
-- the top of the Push (row 7). Explicit geometry also supports narrower blocks.
local M = {}

function M.make(rows: { number }, cols: { number }, rows_per_track: number,
                first_track: number, first_step: number, track_count: number): any
    local cells = {}
    local capacity = math.floor(#rows / rows_per_track)
    for r, row in ipairs(rows) do
        local lane = math.floor((r - 1) / rows_per_track)
        if lane >= capacity then break end
        local track = first_track + lane
        if track > track_count then break end
        for c, col in ipairs(cols) do
            local step = first_step + ((r - 1) % rows_per_track) * #cols + c - 1
            if step < 64 then
                cells[row * 8 + col] = { track = track, step = step, row = row, col = col }
            end
        end
    end
    return { cells = cells, capacity = capacity, span = rows_per_track * #cols }
end

function M.at(view: any, row: number, col: number): any
    return view.cells[row * 8 + col]
end

return M

end
