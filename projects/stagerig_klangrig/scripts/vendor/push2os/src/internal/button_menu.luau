--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
local display = host.display
local log = host.log
local state = host.state
-- Shared top-button expansion. Only occupied option cells replace normal controls.
local C=get("conventions")
local M: any={}
local stack: {any}={}
local captured: {[number]:boolean}={}
local root=""
local function value(v: any,default: boolean): boolean
    if v==nil then return default end
    if typeof(v)=="function" then local ok,result=pcall(v);return ok and result==true end
    return v==true
end
local function publish()
    state.set(root.."/button_menu_open",#stack>0)
    state.set(root.."/button_menu_title",if #stack>0 then stack[#stack].spec.title or "CHOOSE" else "")
end
function M.start(bound_root: string)
    root=bound_root;stack={};captured={}
    state.register("button_menu_open",false);state.register("button_menu_title","")
    publish()
end
function M.active(): boolean return #stack>0 end
function M.close() stack={};publish() end
function M.open(spec: any)
    if typeof(spec)=="function" then spec=spec() end
    assert(typeof(spec)=="table" and typeof(spec.items)=="table","menu requires items")
    table.insert(stack,{spec=spec,offset=0});publish()
end
function M.item(slot: number): any
    local current=stack[#stack]
    if not current then return nil end
    if slot==7 then return if #stack>1 then {label="< BACK"} else nil end
    if slot==6 then
        if #current.spec.items>6 then return {label="MORE >",description="Next six options"} end
        return nil
    end
    return current.spec.items[current.offset+slot+1]
end
function M.lit(slot: number): boolean
    local item=M.item(slot)
    return item~=nil and value(item.enabled,true)
end
function M.route(ev: any): boolean
    local slot=ev.index
    if typeof(slot)~="number" or slot<0 or slot>7 then return M.active() end
    if not ev.pressed then
        if captured[slot] then captured[slot]=nil;return true end
        return M.active()
    end
    if not M.active() then return false end
    if not M.item(slot) then M.close();return false end
    captured[slot]=true
    local current=stack[#stack]
    if slot==7 then table.remove(stack);publish();return true end
    if slot==6 then
        if #current.spec.items>6 then current.offset=(current.offset+6)%(math.ceil(#current.spec.items/6)*6) end
        return true
    end
    local item=M.item(slot)
    if not item or not value(item.enabled,true) then return true end
    if item.menu then M.open(item.menu)
    else
        M.close()
        if item.on_select then
            local ok,err=pcall(item.on_select)
            if not ok then log.warn("[button_menu] selection failed: "..tostring(err)) end
        end
    end
    return true
end
function M.render_cell(slot: number): boolean
    local item=M.item(slot)
    if not item then return false end
    local x=C.cell_x(slot)
    local enabled=value(item.enabled,true);local selected=value(item.is_selected,false)
    local ink=if enabled then C.INK.accent else C.INK.menu_dim
    display.rect(x,0,C.CELL_W-2,C.TOP_H,if selected then C.INK.menu_selected else C.INK.menu_card,true)
    display.rect(x,C.TOP_H-2,C.CELL_W-2,2,ink,true)
    C.text(x+6,2,C.clip((if selected then "* " else "")..item.label,C.TEXT.band,C.CELL_W-12),C.TEXT.band,ink)
    return true
end
return M

end
