--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
local display = host.display
-- Push 2 OS band renderers. The 16 px strip above the content area shows the
-- eight top-button verbs; the 16 px strip below it shows the eight page tabs.
--
-- This module holds no state. Everything it draws is passed in, which is what
-- lets both the display band and the LED compositor ask the same question
-- about the same slot and get the same answer.
--
-- Split out of `core.luau` when that module reached the 30 top-level local
-- rule and the pad compositor still had to be wired in.

local C = get("conventions")

local M = {}

-- A page's `top_labels` may be a table or a function returning one, so a page
-- can label a slot from live state without re-registering its verbs.
local function labels_of(page: any): { string }
    local t = page.top_labels
    if typeof(t) == "function" then
        local ok, res = pcall(t)
        if ok and typeof(res) == "table" then
            return res :: { string }
        end
        return {}
    end
    if typeof(t) == "table" then
        return t :: { string }
    end
    return {}
end

-- A verb cell is lit when the button is physically down, or when the verb
-- reports itself lit (a toggle that is on, a hold that has fired). The LED
-- compositor reads this too, so the glass and the button never disagree.
function M.verb_is_lit(page: any, top_state: any, slot: number): boolean
    if page and (page.desktop_window or page.window) and (page.desktop_window or page.window).held then
        return page.desktop_windows ~= nil and #page.desktop_windows > 1 and page.desktop_focus == slot+1
    end
    local st = top_state[slot]
    if st ~= nil and st.down then
        return true
    end
    local verbs = page and page.top or nil
    local verb = verbs and verbs[slot + 1] or nil
    if verb ~= nil and typeof(verb.is_lit) == "function" then
        local ok, res = pcall(verb.is_lit)
        return ok and res == true
    end
    return false
end

function M.draw_top(page: any, top_state: any,override: any?)
    local labels = page and labels_of(page) or {}
    for i = 0, C.CELLS - 1 do
        if override and override(i) then continue end
        local x = C.cell_x(i)
        local label = labels[i + 1]
        if page and (page.desktop_window or page.window) and (page.desktop_window or page.window).held then
            local w = page.desktop_windows and page.desktop_windows[i+1]
            label = if w and #page.desktop_windows > 1 then w.name else "-"
        end
        if label == nil or label == "" then
            label = "-"
        end
        local lit = M.verb_is_lit(page, top_state, i)
        display.rect(x, C.TOP_Y, C.CELL_W - 2, C.TOP_H,
                     lit and C.INK.tab_active or C.INK.tab, true)
        C.text(x + 6, C.TOP_Y + 3, C.clamp_label(label, C.BAND_CHARS),
               C.TEXT.band, lit and C.INK.bright or C.INK.dim)
    end
end

function M.draw_bottom(pages: { any }, page_index: number, solo_index: number?, overview: boolean?)
    for i = 0, C.CELLS - 1 do
        local x = C.cell_x(i)
        local page = pages[i + 1]
        local active = (i == page_index)
        display.rect(x, C.BOTTOM_Y, C.CELL_W - 2, C.BOTTOM_H,
                     active and C.INK.tab_active or C.INK.tab, true)
        local name = page and page.name or "-"
        if active and overview then name="LAYOUT "..name end
        if solo_index == i then name = "SOLO " .. name end
        C.text(x + 6, C.BOTTOM_Y + 3, C.clamp_label(name, C.BAND_CHARS),
               C.TEXT.band, active and C.INK.bright or C.INK.tab_dim)
    end
end

return M

end
