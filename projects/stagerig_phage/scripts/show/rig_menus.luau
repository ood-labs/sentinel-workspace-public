--!strict
return function(host,get)
local M=get("static_rig")
local Menu={}
function Menu.presets()
    local items={}
    for _,kind in ipairs({"static","effects","color","complete"}) do table.insert(items,
        {label=if kind=="complete" then "FULL LOOKS" else string.upper(kind),is_selected=function() return M.preset_kind==kind end,on_select=function() M.preset_kind=kind;M.message=string.upper(kind).." PRESETS" end}) end
    local masks={}
    for _,mask in ipairs({"all","position","color","levels"}) do table.insert(masks,
        {label=string.upper(mask),on_select=function() M.mask=mask;M.message="Store mask: "..mask end}) end
    table.insert(items,{label="STORE MASK",menu={title="STATIC ATTRIBUTES",items=masks}})
    return {title="PRESET BANK",items=items}
end
-- The canvas groups (same membership as the Lighting buttons), then the eight custom groups.
function Menu.groups()
    local items={}
    for _,group in ipairs(M.group_names) do if group~="none" then
        table.insert(items,{label=string.upper(group),on_select=function() M.select({group},true) end})
    end end
    for slot=1,8 do
        table.insert(items,{label=M.custom[slot].name.value or "GROUP "..slot,menu={title="CUSTOM GROUP "..slot,items={
            {label="SELECT",on_select=function() M.select({"custom"..slot},true) end},
            {label="STORE SELECTED",on_select=function() M.store_group(slot,M.custom[slot].name.value or "Group "..slot) end}}}})
    end
    table.insert(items,{label="CLEAR",on_select=function() M.select({}) end})
    return {title="RIG / CUSTOM GROUPS",items=items}
end
return Menu
end
