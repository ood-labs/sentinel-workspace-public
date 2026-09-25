--!strict
-- Shared bounded selectors. Browsing changes navigation only; commit is explicit.
return function(host: any, get: any, config: any)
local C=get("conventions")
local Grid=get("column_grid")
local M={}

function M.new(spec: any): any
    assert(typeof(spec)=="table" and typeof(spec.id)=="string" and spec.id~="","Editor requires stable id")
    assert(spec.mode=="grid" or spec.mode=="list","Editor mode must be grid or list")
    assert(typeof(spec.items)=="table" and #spec.items>0,"Editor requires items")
    local bounds=spec.bounds
    assert(typeof(bounds)=="table","Editor requires bounds")
    bounds=table.clone(bounds)
    for _,field in ipairs({"x","y","w","h"}) do
        assert(typeof(bounds[field])=="number" and bounds[field]%1==0,"Integer bounds required")
    end
    assert(bounds.x>=0 and bounds.y>=0 and bounds.w>=30 and bounds.h>=16
        and bounds.x+bounds.w<=960 and bounds.y+bounds.h<=160,"Editor bounds outside display")
    local columns=if spec.mode=="list" then 1 else (spec.columns or 3)
    local rows=spec.rows or 3
    assert(columns>=1 and columns%1==0 and rows>=1 and rows%1==0,"Positive integer grid dimensions required")
    local cellW=math.floor(bounds.w/columns)
    local cellH=math.floor(bounds.h/rows)
    assert(cellW>=24 and cellH>=16,"Editor cells too small")
    local items,ids={},{}
    for index,item in ipairs(spec.items) do
        assert(typeof(item)=="table" and typeof(item.id)=="string" and item.id~="" and not ids[item.id],"Unique item ids required")
        assert(typeof(item.label)=="string","Item label required")
        ids[item.id]=index
        items[index]=table.clone(item)
    end
    local focus=if spec.selected_id then ids[spec.selected_id] else 1
    assert(focus~=nil,"Selected item id is unknown")
    local selected=spec.selected_id
    local offset=0
    local editor:any={id=spec.id,mode=spec.mode,bounds=table.clone(bounds)}
    local function window(): any
        local view=Grid.window(#items,columns,rows,offset,focus)
        offset=view.offset
        return view
    end
    function editor.move(delta: number): string
        assert(delta%1==0,"Navigation delta must be an integer")
        focus=math.clamp(focus+delta,1,#items)
        window()
        return items[focus].id
    end
    function editor.focus(id: string)
        assert(ids[id]~=nil,"Unknown focus id")
        focus=ids[id];window()
    end
    function editor.commit(): string
        local item=items[focus]
        if spec.on_select then spec.on_select(item.id,item.value) end
        selected=item.id
        return selected
    end
    function editor.selected(id: string)
        assert(ids[id]~=nil,"Unknown selected id")
        selected=id
    end
    function editor.status(): any
        local view=window()
        return {id=spec.id,focus_id=items[focus].id,selected_id=selected,offset=view.offset,
            first=view.first,last=view.last,count=#items,columns=columns,rows=rows}
    end
    function editor.render()
        local view=window()
        for index=view.first,view.last do
            local localIndex=index-view.first
            local x=bounds.x+(localIndex%columns)*cellW
            local y=bounds.y+math.floor(localIndex/columns)*cellH
            local chosen=items[index].id==selected
            local focused=index==focus
            host.display.rect(x,y,cellW-2,cellH-2,if chosen then C.INK.menu_selected else C.INK.menu_card,true)
            if focused then host.display.rect(x,y,cellW-2,2,C.INK.accent,true) end
            local size=math.min(12,cellH-6)
            C.text(x+3,y+math.floor((cellH-size)/2),C.clip(items[index].label,size,cellW-8),size,
                if chosen or focused then C.INK.bright else C.INK.dim)
        end
    end
    return editor
end

return M
end
