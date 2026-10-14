--!strict
-- Compact, bounded scalar rows: each partition is one native bank value (static_bank_k / effects_bank_k).
-- A partition is a list of program rows (static_rig's partitions): 32 fixture slots' base rows, then those
-- fixtures' layer rows, so a bank stored before the layers existed is exactly the first lines of one stored after:
--   0-3  32 MOVE, 32 BEAM, 32 HALO         5  16 TUBE + 16 PIXELS, then 16 PLATES + 16 CHASE
--   4    32 TUBE, 32 PLATES                 6  32 PIXELS, 32 CHASE
--                                           7  16 PIXELS + 8 AXES, then 16 CHASE
-- Values are written at the look tools' precision (tools/phage_looks.py fmt): degrees to 1e-3, the rest to 1e-4,
-- which keeps the longest partition under the 4096-character limit of a native scalar.
local M={}
local DEGREES={pan=true,tilt=true,pan_amp=true,tilt_amp=true}
function M.fmt(key: string,v: number): string
    local r=if DEGREES[key] then math.round(v*1000)/1000 else math.round(v*10000)/10000
    local s=string.format("%.7g",r)
    return if s=="-0" then "0" else s
end
-- The effects values a CHASE row holds when a look stored before the layers carries its bar (no lane: x1).
local CHASE_NEUTRAL={move_lane="0",int_lane="0",color_lane="0",pan_amp="0",tilt_amp="0",spread="0.45",width="0.5",
    offset="0",reverse="0",look="0",order="0"}
-- part: {list={{row=<1-based row>,slot=<fixture id>,layer=<name>,base=<line of its fixture's base row>},...},
--   base_count=<base rows>}. `owned(e)` names the keys row e owns (nil: all).
function M.pack(rows,keys,part,selection,mask,owned)
    local out={"1"}
    for _,e in ipairs(part.list) do
        local own=if owned then owned(e) else nil
        local row={}
        for _,key in ipairs(keys) do
            table.insert(row,if (not selection or selection[e.id or e.slot]) and (not mask or mask[key]) and (not own or own[key])
                then M.fmt(key,rows[e.row][key]) else "_")
        end
        table.insert(out,table.concat(row,","))
    end
    local result=table.concat(out,";")
    assert(#result<4096,"Fixture bank exceeds native scalar limit")
    return result
end
-- A bank stored before the layers (only its base rows) gains each layer row derived from the row that drove that
-- layer then, so an old look plays as it did: BEAM and HALO copy their mover's line, PLATES its strobe's; CHASE holds
-- no lane (x1) in an effects look that carries its bar, and nothing in a static look.
function M.upgrade(text: string,keys,part,kind: string): string
    local lines=string.split(text,";")
    if #lines-1~=part.base_count or #part.list==part.base_count then return text end
    for n=part.base_count+1,#part.list do
        local e=part.list[n]
        local cells=string.split(lines[e.base+1],",")
        local carried=false
        for _,c in ipairs(cells) do if c~="_" then carried=true end end
        if e.layer=="chase" then
            for k,key in ipairs(keys) do cells[k]=if kind=="effects" and carried then CHASE_NEUTRAL[key] or "_" else "_" end
        end
        table.insert(lines,table.concat(cells,","))
    end
    return table.concat(lines,";")
end
function M.unpack(text,rows,keys,part,attributes,kind)
    text=M.upgrade(text,keys,part,kind)
    local lines=string.split(text,";")
    assert(lines[1]=="1" and #lines==#part.list+1,"Invalid fixture bank shape")
    local staged={}
    for n,e in ipairs(part.list) do
        local cells=string.split(lines[n+1],",")
        assert(#cells==#keys,"Invalid fixture row")
        staged[e.row]={}
        for k,key in ipairs(keys) do if cells[k]~="_" then
            local value=tonumber(cells[k]);local attr=attributes[key]
            assert(value and value==value and value>=attr.min and value<=attr.max,"Invalid fixture attribute: "..key)
            staged[e.row][key]=value
        end end
    end
    for i,row in pairs(staged) do for key,value in pairs(row) do rows[i][key]=value end end
end
function M.merge(previous,patch,keys,part,kind)
    if keys then previous=M.upgrade(previous,keys,part,kind) end
    local a,b=string.split(previous,";"),string.split(patch,";")
    assert(#a==#b,"Preset merge shape mismatch")
    for i=2,#a do
        local old,new=string.split(a[i],","),string.split(b[i],",")
        assert(#old==#new,"Preset merge row mismatch")
        for k,v in ipairs(new) do if v~="_" then old[k]=v end end
        a[i]=table.concat(old,",")
    end
    return table.concat(a,";")
end
function M.clone(rows)
    local copy={};for i,row in ipairs(rows) do copy[i]=table.clone(row) end;return copy
end
return M
