--!strict
return function(host,get)
local M=get("static_rig")
local Windows=get("rig_windows")
local C=get("conventions")
local Titles: any=require("@show/preset_titles")
local UI={}
function UI.lit(cell) return M.active_names and M.active_names[cell.kind]==cell.kind.." "..cell.slot end
function UI.label(cell)
    local title=Titles[cell.kind] and Titles[cell.kind][cell.slot]
    return if title then string.format("%02d %s",cell.slot,string.sub(title,1,5)) else string.format("%02d",cell.slot)
end
function UI.bank(id,root,col,kind,row,width,height)
    local cells={};for slot=1,16 do table.insert(cells,{slot=slot,kind=kind}) end
    local colors={static=0x67D4C0,effects=0xB889EF,color=0xF1AE60,complete=0x77B9FF}
    local velocities={static={13,14},effects={24,25},color={9,10},complete={41,45}}
    return Windows.make({id=id,name=if kind=="complete" then "FULL LOOKS" else string.upper(kind),color=colors[kind],off=velocities[kind][1],on=velocities[kind][2],row=row,col=col,width=width,height=height,cells=cells},
        root,UI.lit,function(cell,pressed) if pressed then M.preset_kind=cell.kind;M.recall(cell.slot) end end)
end
function UI.status(ctx) C.text(12,ctx.cy+72,#M.status.selection.." selected in LIGHTING / "..M.message,10,0xE3EAF1) end
return UI
end
