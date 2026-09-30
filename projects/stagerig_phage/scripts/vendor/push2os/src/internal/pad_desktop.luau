--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
local state = host.state
-- All tabs share one sparse ownership map. A tab owns any number of windows.
local W = get("pad_window")
local Pe = get("persist")
local Gesture = get("pad_window_gesture")
local Params = get("params")
local M = {}
local pages: { any } = {}
local entries: { any } = {}
local root = ""
local active: any = nil
local owners: { [number]: any } = {}
local presses: { [number]: any } = {}
local captured: { [number]: boolean } = {}
local clock = 0
local raise_at: number? = nil
local gesture: any = Gesture.new()
local shift_down = false
local select_down = false
local select_page: any = nil
local solo = -1
local overview = false
local layout_down = false

local function publish_focus()
    state.set(root .. "/pad_focused_window", if active then active.window.id else "")
    for _, page in ipairs(pages) do
        page.desktop_window = if active and active.page == page then active.window else nil
    end
end

function M.start(list: { any }, prefix: string, switch_page: any, pads: any?)
    pages, root, owners, presses, captured = list, prefix, {}, {}, {}
    entries, active, clock, raise_at = {}, nil, 0, nil
    gesture, shift_down, select_down, select_page = Gesture.new(), false, false, switch_page
    solo = -1
    overview, layout_down = false, false
    state.register("pad_layout_overview",false)
    state.register("pad_resize_armed", false)
    state.register("pad_solo_tab", -1)
    state.register("pad_focused_window", "")
    for _, page in ipairs(pages) do
        local windows = page.windows or (if page.window then {page.window} else {})
        -- Composition has already attached any explicitly requested legacy
        -- windows and registered their records in the restore inventory.
        page.desktop_windows, page.desktop_managed = windows, true
        page.desktop_focus = 1
        page.records = page.records or {}
        for _, w in ipairs(windows) do
            w.name = w.name or page.name
            w.held, w.pixels, w.mapping = false, {}, {}
            w.overview_expanded = false
            w.message, w.until_time = "", 0
            state.register(w.id .. "_placing", false)
            -- Register every dimension at boot; existing records keep their keys.
            for _, rec in ipairs({w.width,w.height,w.row,w.col,w.pin,w.z}) do
                if not table.find(page.records,rec) and not table.find(page.params or {},rec) then
                    table.insert(page.records,rec)
                end
            end
            table.insert(entries,{page=page,window=w})
        end
    end
end

function M.focus(page: any, now: number)
    if active then Params.service(now) end
    Gesture.cancel(gesture)
    if active then
        active.window.held = false
        state.set(root .. "/" .. active.window.id .. "_placing", false)
    end
    active = nil
    local w = page and page.desktop_windows[page.desktop_focus or 1]
    for _, entry in ipairs(entries) do
        if entry.page == page and entry.window == w then active = entry end
    end
    if active then
        active.window.held = select_down
        state.set(root .. "/" .. active.window.id .. "_placing", select_down)
    end
    raise_at = now
    publish_focus()
end

function M.solo_index(): number return solo end
function M.overview(): boolean return overview end

function M.tab(index: number, now: number)
    if not pages[index+1] then return end
    solo = if select_down then (if solo == index then -1 else index) else -1
    state.set(root .. "/pad_solo_tab",solo)
    select_page(index)
    raise_at = now
end

function M.layout(ev: any, now: number)
    local rising=ev.pressed==true and not layout_down
    layout_down=ev.pressed==true
    if not rising then return end
    Gesture.cancel(gesture)
    if select_down and overview and active then
        active.window.overview_expanded=not active.window.overview_expanded
    else
        overview=not overview
        for _,entry in ipairs(entries) do entry.window.overview_expanded=false end
    end
    state.set(root.."/pad_layout_overview",overview)
end

function M.select(ev: any, now: number?): boolean
    select_down = ev.pressed == true
    Gesture.tick(gesture,now or 0)
    if not ev.pressed and not gesture.armed then Gesture.cancel(gesture) end
    if active then
        active.window.held = select_down
        state.set(root .. "/" .. active.window.id .. "_placing",select_down)
    end
    return active ~= nil
end

function M.top(ev: any, now: number): boolean
    if not select_down and not gesture.armed and not overview then return false end
    if (select_down or overview) and ev.pressed and active then
        local page = active.page
        if #page.desktop_windows > 1 and page.desktop_windows[(ev.index or -1)+1] then
            page.desktop_focus = ev.index+1
            M.focus(page,now)
        end
    end
    return true
end

function M.shift(ev: any, now: number)
    local rising = ev.pressed == true and not shift_down
    shift_down = ev.pressed == true
    if not rising or not active or not select_down then return end
    local w = active.window
    W.read(w,root)
    w.pin.value = if w.pin.value == 1 then 0 else 1
    Pe.publish(w.pin,now)
    raise_at = now
    w.message = if w.pin.value == 1 then "ON TOP ENABLED" else "ON TOP DISABLED"
    w.until_time = now+2
end

function M.compose(pads: any, now: number?, background_ready: boolean?)
    local t = now or 0
    Gesture.tick(gesture,t)
    state.set(root .. "/pad_resize_armed",gesture.armed)
    for _, entry in ipairs(entries) do W.read(entry.window,root) end
    if raise_at ~= nil then
        for _, entry in ipairs(entries) do clock = math.max(clock,entry.window.z.value or 0) end
        -- Raise the whole tab, with its remembered focused window last.
        for _, entry in ipairs(entries) do
            if active and entry.page == active.page and entry ~= active then
                clock += 1; entry.window.z.value = clock; Pe.publish(entry.window.z,raise_at)
            end
        end
        if active then
            clock += 1; active.window.z.value = clock; Pe.publish(active.window.z,raise_at)
        end
        raise_at = nil
    end
    local frame, order = {}, {}
    owners = {}
    -- Suppress old page layers even in holes. Globals retain their own layer.
    for index=0,63 do
        if not pads.is_global(math.floor(index/8),index%8) then frame[index]=0 end
    end
    for _, entry in ipairs(entries) do
        if entry.window.refresh then entry.window.refresh()
        elseif entry.page.refresh_window then entry.page.refresh_window(background_ready==true) end
        if solo < 0 or entry.page == pages[solo+1] then table.insert(order,entry) end
    end
    table.sort(order,function(a: any,b: any): boolean
        local ap,bp = a.window.pin.value or 0,b.window.pin.value or 0
        if ap ~= bp then return ap < bp end
        local az,bz = a.window.z.value or 0,b.window.z.value or 0
        if az ~= bz then return az < bz end
        return a.window.id < b.window.id
    end)
    for _, entry in ipairs(order) do
        local w=entry.window
        if overview and not w.overview_expanded then
            local index=w.row.value*8+w.col.value
            if not pads.is_global(w.row.value,w.col.value) then
                frame[index],owners[index]=w.pixels[index] or (w.spec and w.spec.off or 2),entry
            end
        else
            local rect=w.rect
            if rect and (not w.legacy or w.width.value>0 or w.height.value>0) then
                for y=0,rect.height-1 do
                    for x=0,rect.width-1 do
                        local row,col=rect.row-y,rect.col+x
                        if not pads.is_global(row,col) then
                            frame[row*8+col],owners[row*8+col]=0,entry
                        end
                    end
                end
            end
            for index,velocity in pairs(w.pixels) do
                if not pads.is_global(math.floor(index/8),index%8) then
                    frame[index],owners[index] = velocity,entry
                end
            end
        end
    end
    if select_down or overview then
        -- Only the exposed origin is a focus target; never highlight a covered corner.
        local phase=(1-math.cos(t*math.pi*(if overview then 2.5 else 1)))/2
        local red=phase>0.5
        for _,entry in ipairs(order) do
            local w=entry.window
            local index=w.row.value*8+w.col.value
            if owners[index]==entry and red then frame[index]=5 end
        end
    end
    Gesture.paint(gesture,frame,t)
    pads.set_windows(frame,active ~= nil and active.window.pin.value == 1,overview)
    if pads.solo then pads.solo(solo) end
end

local function dispatch(entry: any, ev: any, cell: any)
    if entry.window.on_pad then entry.window.on_pad(ev,cell)
    elseif entry.page.on_window_pad then entry.page.on_window_pad(ev,cell) end
end

function M.pad(ev: any, pads: any, now: number): boolean
    if ev.row < 0 or ev.row > 7 or ev.col < 0 or ev.col > 7 then return true end
    M.compose(pads,now)
    local index = ev.row*8+ev.col
    if not ev.pressed then
        if captured[index] then
            Gesture.release(gesture,ev.row,ev.col); captured[index]=nil; return true
        end
        local press = presses[index]
        if press then
            presses[index]=nil; dispatch(press.entry,ev,press.cell); return true
        end
        return not pads.is_global(ev.row,ev.col)
    end
    if presses[index] or captured[index] then return true end
    if overview then
        captured[index]=true
        if pads.is_global(ev.row,ev.col) then captured[index]=nil;return false end
        local owner=owners[index]
        if owner then
            owner.page.desktop_focus=table.find(owner.page.desktop_windows,owner.window)
            local target=table.find(pages,owner.page)
            if target then select_page(target-1) end
        elseif active then
            active.window.row.value,active.window.col.value=ev.row,ev.col
            Pe.publish(active.window.row,now);Pe.publish(active.window.col,now)
        end
        return true
    end
    if gesture.armed then
        captured[index]=true
        if not pads.is_global(ev.row,ev.col) then Gesture.press(gesture,gesture.window,ev.row,ev.col,now) end
        return true
    end
    local owner = owners[index]
    if select_down and owner and owner.window.row.value == ev.row and owner.window.col.value == ev.col then
        captured[index]=true
        owner.page.desktop_focus = table.find(owner.page.desktop_windows,owner.window)
        local target = table.find(pages,owner.page)
        if target and select_page then select_page(target-1) end
        Gesture.press(gesture,owner.window,ev.row,ev.col,now)
        owner.window.message,owner.window.until_time = "WINDOW SELECTED | TAP TO MOVE | HOLD TO SIZE",now+2
        return true
    end
    if select_down then
        captured[index]=true
        if active and not pads.is_global(ev.row,ev.col) then
            Gesture.press(gesture,active.window,ev.row,ev.col,now)
        end
        return true
    end
    if owner then
        local cell = owner.window.mapping[index]
        if cell==nil then return true end
        presses[index]={entry=owner,cell=cell}
        dispatch(owner,ev,cell)
        return true
    end
    -- Empty desktop space cannot fall through to a covered legacy region.
    return not pads.is_global(ev.row,ev.col)
end

function M.stop()
    for index,press in pairs(presses) do
        dispatch(press.entry,{row=math.floor(index/8),col=index%8,pressed=false},press.cell)
    end
    presses={}
    Gesture.cancel(gesture)
end

return M

end
