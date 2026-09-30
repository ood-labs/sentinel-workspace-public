--!strict
local slot=1
local groupSlot=1
local name="Group 1"
return function(ui,rig)
    ui.text("programmer","RIG: "..rig.message)
    ui.text("selection","Selected: "..#rig.status.selection.." | Drag-select in Phage_Lighting")
    local bankLabels={};for i,bank in ipairs(rig.attribute_banks) do bankLabels[i]=bank.label end
    local bankChanged,bankIndex=ui.combo("attribute_bank","Knob controls",rig.editor_bank.value or 1,bankLabels)
    if bankChanged then rig.editor_bank.value=bankIndex end
    for i,group in ipairs(rig.group_names) do
        local _,pressed=ui.button("select_"..group,string.upper(group))
        if pressed then rig.select({group}) end
        if i%8~=0 then ui.same_line() end
    end
    local kinds={"static","effects","color","complete"}
    local changed,index=ui.combo("preset_kind","Preset bank",table.find(kinds,rig.preset_kind) or 1,kinds)
    if changed then rig.preset_kind=kinds[index] end
    local masks={"all","position","color","levels"}
    changed,index=ui.combo("attribute_mask","Store attributes",table.find(masks,rig.mask) or 1,masks)
    if changed then rig.mask=masks[index] end
    local slots={};for i=1,16 do slots[i]=tostring(i) end
    changed,index=ui.combo("preset_slot","Slot",slot,slots);if changed then slot=index end
    for _,action in ipairs({"store","recall","update","undo","reset_selected"}) do
        local _,pressed=ui.button("preset_"..action,string.upper(action))
        if pressed then
            if action=="store" then rig.arm("store");rig.recall(slot)
            elseif action=="recall" then rig.mode="";rig.recall(slot)
            else rig.request(action) end
        end
        ui.same_line()
    end
    ui.text("groups_label","CUSTOM GROUPS")
    changed,index=ui.combo("group_slot","Group slot",groupSlot,{"1","2","3","4","5","6","7","8"});if changed then groupSlot=index end
    local renamed,newName=ui.input_text("group_name","Group name",name)
    if renamed then name=newName end
    local _,save=ui.button("save_group","Store selection as Group "..groupSlot)
    if save then rig.store_group(groupSlot,name) end
    local _,recall=ui.button("recall_group","Select Group "..groupSlot)
    if recall then rig.select({"custom"..groupSlot}) end
    ui.text("aim_note","Pan and tilt are offsets from the mounted reference aim.")
end
