--!strict
return function(host,get)
local Codec=require("@show/rig_codec")
local Titles: any=require("@show/preset_titles")
-- A pad's name: the operator's stored fixture pad name, else the generated title.
local function title(rig,kind,slot)
    local t=(rig.fx_names and rig.fx_names[kind.." "..slot]) or (Titles[kind] and Titles[kind][slot])
    return if t then " / "..t else ""
end
local C=get("attribute_catalog")
local M={}
local function records(page)
    local result={};for _,r in ipairs(page.records or {}) do table.insert(result,r) end
    for _,r in ipairs(page.params or {}) do table.insert(result,r) end
    return result
end
function M.service(rig)
    local job=rig.job;local root=rig.root
    if job.stage==0 then
        job.paths={};job.masks=nil;job.rows=Codec.clone(rig.rows);job.selection=table.clone(rig.selection);job.bank_cursor=1;job.values={}
        -- A sequence preset (pad page 2) holds its family's rows, whatever is selected: its layers' effect rows and
        -- their aim and levels (masked as STATIC is; palettes stay with COLOR).
        local family=rig.FX_FAMILIES[job.kind]
        job.family=family
        if family~=nil then
            job.selection={}
            for _,L in ipairs(rig.row_list) do if family[L.kind] then job.selection[L.id]=true end end
            job.masks={pan=true,tilt=true,level=true,ring=true}
        elseif job.kind=="color" then job.masks={beam_palette=true,ring_palette=true}
        elseif job.kind~="complete" and job.mask=="position" then job.masks={pan=true,tilt=true}
        elseif job.kind~="complete" and job.mask=="color" then job.masks={beam_palette=true,ring_palette=true}
        elseif job.kind~="complete" and job.mask=="levels" then job.masks={level=true,ring=true}
        elseif job.kind=="static" then job.masks={pan=true,tilt=true,level=true,ring=true} end
        if job.kind=="rhythm" or job.kind=="complete" then
            for _,r in ipairs(records(get("page:sequence"))) do if r.persist=="bank" then table.insert(job.paths,root.."/"..r.key) end end
        end
        if job.kind=="complete" then
            if job.store then job.parts=rig.parts_text();host.state.set(root.."/look_parts",job.parts) end
            table.insert(job.paths,root.."/look_parts")
            for _,r in ipairs(records(get("page:global"))) do if r.persist=="bank" then table.insert(job.paths,root.."/"..r.key) end end
            table.insert(job.paths,root.."/static_pitch");table.insert(job.paths,root.."/lighting_master")
        end
        -- The strobe clock is part of every effects look (strobes and bars both run on it), and of a fixture preset
        -- whose layers run on it.
        if job.kind=="complete" or job.kind=="effects" or rig.clocked(job.kind) then
            for _,r in pairs(rig.strobe) do table.insert(job.paths,root.."/"..r.key) end
        end
        if job.kind=="complete" or job.kind=="color" then
            for _,r in ipairs(records(get("page:color"))) do if r.persist=="bank" then table.insert(job.paths,root.."/"..r.key) end end
        end
        local unique={};local paths={}
        for _,p in ipairs(job.paths) do if not unique[p] then unique[p]=true;table.insert(paths,p) end end
        job.paths=paths;job.stage=.5;return
    end
    if job.stage==.5 then
        local b=rig.banks[job.bank_cursor]
        if b then
            -- A sequence preset keeps only the partitions holding its rows (a partition is 32 slots and their layers).
            local fixture=false
            if job.family and (b.kind=="effects" or (b.kind=="static" and rig.FX_STATIC[job.kind])) then
                for _,e in ipairs(b.part.list) do if job.family[rig.row_list[e.row].kind] then fixture=true;break end end
            end
            local own=job.kind==b.kind or job.kind=="complete" or (job.kind=="color" and b.kind=="static") or fixture
            if own then
                local path=root.."/saved_"..b.rec.key
                if job.store then
                    local text=Codec.pack(job.rows,C[b.kind],b.part,
                        if job.kind=="complete" then nil else job.selection,
                        if job.kind=="static" or job.kind=="color" or (job.family and b.kind=="static") then job.masks else nil,
                        rig.owned_of)
                    if job.update and rig.active_values[path] then text=Codec.merge(rig.active_values[path],text,C[b.kind],b.part,b.kind) end
                    host.state.set(path,text);job.values[path]=text
                end
                table.insert(job.paths,path)
            end
            job.bank_cursor+=1;return
        end
        job.rows=nil;job.stage=1;return
    end
    if job.stage==2.5 then
        job.rows=Codec.clone(rig.rows);job.stage=3;return
    end
    if job.stage==3 then
        -- One partition per tick, and the cursor moves only once a partition is fully decoded: a tick that runs past
        -- its budget is interrupted by the host, and decoding the same text again is harmless, while skipping on
        -- would leave that partition half the old look.
        while job.bank_cursor<=#rig.banks do
            if rig.busy() then return end
            local b=rig.banks[job.bank_cursor]
            local text=job.result.values[root.."/saved_"..b.rec.key]
            if text then Codec.unpack(text,job.rows,C[b.kind],b.part,C.attributes,b.kind);rig.worked=true end
            job.bank_cursor+=1
            if text and job.bank_cursor<=#rig.banks then return end
        end
        job.stage=4;return
    end
    if job.stage==4 then
        -- The swap gets a tick of its own: an undo snapshot and a clone of every row.
        if rig.busy() then return end
        rig.remember();rig.rows=job.rows;rig.base=Codec.clone(job.rows);rig.save_live()
        rig.active_values=job.result.values;rig.active_kind=job.kind;rig.active_slot=job.slot
        rig.set_active(job.kind,job.slot,job.result.values[root.."/look_parts"])
        rig.status.active_id=job.kind.." "..job.slot;rig.status.edit_id=rig.status.active_id
        rig.recall_serial=(rig.recall_serial or 0)+1;rig.recall_kind=job.kind
        -- A fixture pad whose rows ride the BUILD lane restarts the build, as an EFFECTS or FULL recall does.
        rig.recall_build=false
        local family=rig.FX_FAMILIES[job.kind]
        if family then for r,L in ipairs(rig.row_list) do
            if family[L.kind] and (rig.rows[r].move_lane==4 or rig.rows[r].int_lane==4) then rig.recall_build=true;break end
        end end
        rig.message="Recalled "..rig.status.active_id..title(rig,job.kind,job.slot);rig.job=nil;return
    end
    local name=job.kind.." "..job.slot;local group="simple_stage_"..job.kind
    if job.stage==1 then
        local catalog=host.preset.list(group)
        if catalog.outcome=="pending" then return end
        if not catalog.ok then rig.message=catalog.message or catalog.code;rig.job=nil;return end
        job.exists=false
        for _,p in ipairs(catalog.presets) do if p.name==name then job.exists=true end end
        job.stage=2;return
    end
    local result=if job.store then (if job.exists then host.preset.save(group,name,{paths=job.paths,merge_existing=true}) else host.preset.create(group,name,{paths=job.paths,merge_existing=true}))
        else host.preset.recall_confirmed(group,name)
    if typeof(result)=="boolean" then result={ok=result,code=if result then "BANK_SAVED" else "SAVE_PENDING",outcome=if result then "saved" else "pending"} end
    if result.outcome=="pending" then return end
    if result.ok then
        if not job.store then
            -- The recall's values arrive in this tick; the copy of every row waits for the next one.
            job.result=result;job.bank_cursor=1;job.stage=2.5;return
        end
        rig.active_values=job.values;rig.active_kind=job.kind;rig.active_slot=job.slot
        rig.status.edit_id=name
        if rig.FX_FAMILIES[job.kind]~=nil then rig.fx_names[name]=rig.fx_label(job.kind);rig.publish_fx_names() end
        rig.set_active(job.kind,job.slot,job.parts)
        rig.status.active_id=name;rig.message=(if job.store then "Stored " else "Recalled ")..name
    else rig.message=result.error or result.message or result.code or "Preset failed" end
    rig.job=nil
end
return M
end
