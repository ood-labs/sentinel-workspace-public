--!strict
-- Compact, bounded scalar rows: each 32-fixture partition is a native bank value.
local M={}
function M.pack(rows,keys,first,last,selection,mask)
    local out={"1"}
    for i=first,last do
        local row={}
        for _,key in ipairs(keys) do
            table.insert(row,if (not selection or selection[tostring(i-1)]) and (not mask or mask[key])
                then string.format("%.7g",rows[i][key]) else "_")
        end
        table.insert(out,table.concat(row,","))
    end
    local result=table.concat(out,";")
    assert(#result<4096,"Fixture bank exceeds native scalar limit")
    return result
end
function M.unpack(text,rows,keys,first,last,attributes)
    local lines=string.split(text,";")
    assert(lines[1]=="1" and #lines==last-first+2,"Invalid fixture bank shape")
    local staged={}
    for i=first,last do
        local cells=string.split(lines[i-first+2],",")
        assert(#cells==#keys,"Invalid fixture row")
        staged[i]={}
        for k,key in ipairs(keys) do if cells[k]~="_" then
            local value=tonumber(cells[k]);local attr=attributes[key]
            assert(value and value==value and value>=attr.min and value<=attr.max,"Invalid fixture attribute: "..key)
            staged[i][key]=value
        end end
    end
    for i,row in pairs(staged) do for key,value in pairs(row) do rows[i][key]=value end end
end
function M.merge(previous,patch)
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
