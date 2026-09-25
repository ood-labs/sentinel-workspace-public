--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
local state = host.state
-- Reusable window records and geometry. No host calls until the core binds it.
local C = get("conventions")
local M = {}
local read_batch = false
local read_seen: {[any]: boolean} = {}

-- Internal frame scope. Input dispatch outside the scope always reads fresh.
function M._begin_read_batch() table.clear(read_seen);read_batch=true end
function M._end_read_batch() read_batch=false end

function M.new(id: string, row: number, col: number): any
    local function rec(key: string, label: string, values: { string }?, default: number, lo: number, hi: number): any
        return { key = id .. "_" .. key, label = label, values = values,
            default = default, min = lo, max = hi, persist = "bank",
            threshold = C.ENCODER.detent_enum, step = 1 }
    end
    local w: any = { id = id, pixels = {}, mapping = {}, held = false,
        message = "", until_time = 0 }
    w.width = rec("window_width", "WIDTH", {"AUTO", "1", "2", "3", "4", "5", "6", "7", "8"}, 0, 0, 8)
    w.height = rec("height", "HEIGHT", {"AUTO", "1", "2", "3", "4", "5", "6", "7", "8"}, 0, 0, 8)
    w.row = rec("origin_row", "ROW", nil, row, 0, 7)
    w.col = rec("origin_col", "COL", nil, col, 0, 7)
    w.pin = rec("pin", "ON TOP", nil, 0, 0, 1)
    w.z = rec("z", "ORDER", nil, 0, 0, 1000000000)
    w.records = { w.row, w.col, w.pin, w.z }
    return w
end

function M.read(w: any, root: string)
    if read_batch and read_seen[w] then return end
    if read_batch then read_seen[w]=true end
    for _, rec in ipairs({w.width, w.height, w.row, w.col, w.pin, w.z}) do
        if not rec.dirty then
            rec.value = math.clamp(math.floor(tonumber(state.get(root .. "/" .. rec.key))
                or rec.default), rec.min, rec.max)
        end
    end
end

function M.rect(w: any, auto_width: number, auto_height: number): any
    local row, col = w.row.value or w.row.default, w.col.value or w.col.default
    local width_choice = w.width.value or 0
    local width = math.min(if width_choice == 0 then auto_width else width_choice, 8-col)
    local height = math.min(if (w.height.value or 0) == 0 then auto_height else w.height.value, row+1)
    w.rect = { row = row, col = col, width = width, height = height }
    return w.rect
end

function M.hint(w: any, now: number): string
    if w.resizing then return "CORNER ARMED - TAP OPPOSITE CORNER" end
    if now < w.until_time then return w.message end
    if w.held then return "TAP: MOVE | HOLD PAD: SIZE | SHIFT: PIN" end
    return if (w.pin.value or 0) == 1 then "ON TOP | SELECT + SHIFT: UNPIN"
        else "SELECT + PAD: MOVE | SELECT + SHIFT: PIN"
end

return M

end
