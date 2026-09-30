--!strict
-- Show-owned per-Runtime factory; Phase 5 compatibility conversion.
return function(host: any,get: any,config: any)
local Windows=get("rig_windows")
local M=get("static_rig")
local UI=get("programmer_surface")
local Attributes=get("attribute_editor")
local SelectionView=get("selection_view")
local Desktop=get("pad_desktop")
local root=""
local page: any={name="RIG",records=table.clone(M.records),params=Attributes.encoders()}
table.insert(page.records,SelectionView.offset)
local fourth_delta=page.params[4].on_delta
local fourth_format=page.params[4].format
page.params[4].on_delta=function(delta: number)
    if Attributes.bank().id=="gobo" and not M.reset_held then SelectionView.browse(delta) else fourth_delta(delta) end
end
page.params[4].format=function(): string
    if Attributes.bank().id=="gobo" then
        page.params[4].label="BROWSE";page.params[4].no_acceleration=true;page.params[4].fine_step=1
        return "ROWS"
    end
    return fourth_format()
end
page.windows={
    UI.bank("programmer_groups",function() return root end,0,"static",7,4,4),
    UI.bank("static_bank",function() return root end,4,"effects",7,4,4),
    UI.bank("color_presets",function() return root end,0,"color",3,4,4),
    UI.bank("full_looks",function() return root end,4,"complete",3,4,4)}
page.top={
    {kind="menu",menu=Attributes.menu,is_lit=function() return true end},
    {kind="trigger",on_press=function() M.request("undo") end,is_lit=function() return M.status.undo_available==true end},
    {kind="momentary",on_press=M.begin_reset,on_release=M.end_reset,is_lit=function() return M.reset_held or (#M.status.selection>0 and next(M.status.edits)~=nil) end},
    {kind="trigger",on_press=function() M.arm("store") end,is_lit=function() return M.mode=="store" end},
    {kind="menu",menu=function() return get("rig_menus").presets() end},
    {kind="trigger",on_press=function() M.request("update") end,is_lit=function() return M.status.edit_id~=nil and M.status.edit_id~="" end},
    {kind="trigger",on_press=function() M.clear_effects() end},
    {kind="trigger",on_press=Attributes.toggle_mode,is_lit=function() return M.editor_absolute.value==1 end},
}
page.top_labels=function() return {Attributes.bank().label.." >","UNDO EDITS","RESET SEL","STORE",string.upper(M.preset_kind).." >","UPDATE","FX OFF",if M.editor_absolute.value==1 then "ABSOLUTE" else "RELATIVE"} end
page.on_bind=function(bound_root: string) root=bound_root;M.start(root) end
page.on_frame=function(_dt: number,t: number) M.tick(t) end
-- The root schedules bounded background work separately from display rendering.
page.on_leave=function() M.mode="";M.reset_held=false;M.reset_used=false end
page.render=function(ctx: any)
    Windows.render(ctx,page.windows,page.desktop_window,UI.lit,UI.label)
    UI.status(ctx)
end

return page

end
