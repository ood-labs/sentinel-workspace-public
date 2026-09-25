--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
-- Adapt fixed page regions to the same movable, sparse desktop as new windows.
local W = get("pad_window")
local M = {}

function M.attach(page: any, pads: any, root: string): any
    local w = page.legacy_window or W.new("pads_" .. (page.legacy_window_id or page.id), 7, 0)
    page.legacy_window = w
    w.name = page.name
    w.legacy = true
    w.refresh = function()
        W.read(w, root)
        local rect = W.rect(w, if page.on_pads then 8 else 1, if page.on_pads then 8 else 1)
        local cells = pads.page_cells(page)
        w.pixels, w.mapping = {}, {}
        for index, velocity in pairs(cells) do
            local r, c = 7-math.floor(index/8), index%8
            if r < rect.height and c < rect.width then
                local dest = (rect.row-r)*8+rect.col+c
                w.pixels[dest] = velocity
                w.mapping[dest] = {row=7-r, col=c}
            end
        end
    end
    w.on_pad = function(ev: any, cell: any)
        if cell then pads.page_event(page, {row=cell.row, col=cell.col, pressed=ev.pressed}) end
    end
    return w
end

return M

end
