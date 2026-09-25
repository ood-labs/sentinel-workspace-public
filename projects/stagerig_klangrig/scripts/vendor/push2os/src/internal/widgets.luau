--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
local display = host.display
-- Push 2 OS widget kit. Five drawing primitives a page composes its content
-- from, built only on `display.rect`, `display.line` and `C.text`.
--
-- The kit is named `widgets` rather than `display` so a page reading
-- `W.header(...)` next to a raw `display.*` call can tell at a glance which side
-- of the boundary it is on. The host global keeps its own name.
--
-- Text is clipped by character count, because `measure_text` is deferred host
-- work. The face is monospace and its advance ratio is measured on the panel,
-- so one constant in `conventions.FONT` covers every size; every text call
-- here goes through `C.clip`, so no widget can put a glyph past the box it
-- was given.
--
-- Nothing here opens or publishes a frame. `display.clear` is the core's, and
-- a page that calls it steals the frame from the band renderers that have
-- already drawn into it.
--
-- No host-binding work at module top level.

local C = get("conventions")

local M = {}

-- The kit's palette. Separate from `C.LED`, which is Push 2 pad velocities;
-- these are 24-bit display colours.
M.INK = C.INK

-- A one-line title with a rule under it. Returns the y below the rule, so a
-- caller stacks content without recomputing the header's height.
function M.header(x: number, y: number, w: number, text: string): number
    C.text(x, y, C.clip(text, C.TEXT.large, w), C.TEXT.large, M.INK.bright)
    local rule_y = y + C.TEXT.large + 4
    display.line(x, rule_y, x + w, rule_y, M.INK.rule)
    return rule_y + 6
end

-- A label above a value, which is the shape every readout column uses. The
-- label is dim and small, the value bright and larger, so the eye lands on
-- the number.
function M.label_value(x: number, y: number, w: number,
                       label: string, value: string)
    C.text(x, y, C.clip(label, C.TEXT.label, w), C.TEXT.label, M.INK.dim)
    -- The gap is taken from the readout row offsets rather than from the text
    -- size, so a page's own label-over-value lines up with the param strip.
    C.text(x, y + (C.READOUT_VALUE_DY - C.READOUT_LABEL_DY),
           C.clip(value, C.TEXT.value, w), C.TEXT.value, M.INK.bright)
end

-- A horizontal bar: a full-width track with a proportional fill. `frac` is
-- clamped, so a caller may hand it a raw ratio from a range that has moved
-- without drawing outside the box.
function M.meter(x: number, y: number, w: number, h: number, frac: number,
                 colour: number?)
    display.rect(x, y, w, h, M.INK.track, true)
    local f = math.clamp(frac, 0.0, 1.0)
    local filled = math.floor(w * f)
    if filled > 0 then
        display.rect(x, y, filled, h, colour or M.INK.fill, true)
    end
end

-- A filled colour chip with a border, for showing a palette entry as itself
-- rather than as its index.
function M.swatch(x: number, y: number, w: number, h: number, colour: number)
    display.rect(x, y, w, h, colour, true)
    display.rect(x, y, w, h, M.INK.rule, false)
end

-- One cell of a strip: an optional meter, then a label and a value. This is
-- the readout column, exported so a page that wants its own strip in the
-- content band gets the same geometry the param engine draws.
--
-- `cells` is a list of `{ label, value, frac }`, one per column; `frac` may be
-- nil for a cell with no range to show. A nil entry draws an inert dash, so a
-- strip always has the same number of columns and the eye can count across it.
function M.strip(y: number, cells: { any })
    for i = 1, C.CELLS do
        local x = C.cell_x(i - 1) + 6
        local w = C.CELL_W - 16
        local cell = cells[i]
        if cell == nil then
            C.text(x, y + C.READOUT_LABEL_DY, "-", C.TEXT.label, M.INK.faint)
        else
            if cell.frac ~= nil then
                M.meter(x, y + C.READOUT_BAR_DY, w, 6, cell.frac)
            end
            M.label_value(x, y + C.READOUT_LABEL_DY, w,
                          cell.label or "-", cell.value or "")
        end
    end
end

return M

end
