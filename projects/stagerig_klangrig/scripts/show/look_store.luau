--!strict
return function(host,get)
local Codec=require("@show/rig_codec")
local Titles: any=require("@show/preset_titles")
local function title(kind,slot) local t=Titles[kind] and Titles[kind][slot];return if t then " / "..t else "" end
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
        if job.kind=="color" then job.masks={beam_palette=true,ring_palette=true}
        elseif job.kind~="complete" and job.mask=="position" then job.masks={pan=true,tilt=true}
        elseif job.kind~="complete" and job.mask=="color" then job.masks={beam_palette=true,ring_palette=true}
        elseif job.kind~="complete" and job.mask=="levels" then job.masks={level=true,ring=true}
        elseif job.kind=="static" then job.masks={pan=true,tilt=true,level=true,ring=true} end
        if job.kind=="rhythm" or job.kind=="complete" then
            for _,r in ipairs(records(get("page:sequence"))) do if r.persist=="bank" then table.insert(job.paths,root.."/"..r.key) end end
        end
        if job.kind=="complete" then
            for _,r in ipairs(records(get("page:global"))) do if r.persist=="bank" then table.insert(job.paths,root.."/"..r.key) end end
            table.insert(job.paths,root.."/static_pitch");table.insert(job.paths,root.."/lighting_master")
        end
        if job.kind=="complete" or (job.kind=="effects" and job.selection["288"]) then
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
            if job.kind==b.kind or job.kind=="complete" or (job.kind=="color" and b.kind=="static") then
                local path=root.."/saved_"..b.rec.key
                if job.store then
                    local text=Codec.pack(job.rows,C[b.kind],b.first,b.last,
                        if job.kind=="complete" then nil else job.selection,if job.kind=="static" or job.kind=="color" then job.masks else nil)
                    if job.update and rig.active_values[path] then text=Codec.merge(rig.active_values[path],text) end
                    host.state.set(path,text);job.values[path]=text
                end
                table.insert(job.paths,path)
            end
            job.bank_cursor+=1;return
        end
        job.rows=nil;job.stage=1;return
    end
    if job.stage==3 then
        local remaining=4
        while job.bank_cursor<=#rig.banks do
            local b=rig.banks[job.bank_cursor]
            local text=job.result.values[root.."/saved_"..b.rec.key]
            job.bank_cursor+=1
            if text then
                Codec.unpack(text,job.rows,C[b.kind],b.first,b.last,C.attributes)
                remaining-=1
                if remaining==0 and job.bank_cursor<=#rig.banks then return end
            end
        end
        rig.remember();rig.rows=job.rows;rig.base=Codec.clone(job.rows);rig.save_live()
        rig.active_values=job.result.values;rig.active_kind=job.kind;rig.active_slot=job.slot
        rig.active_names=rig.active_names or {};rig.active_names[job.kind]=job.kind.." "..job.slot
        rig.status.active_id=job.kind.." "..job.slot;rig.status.edit_id=rig.status.active_id
        rig.message="Recalled "..rig.status.active_id..title(job.kind,job.slot);rig.job=nil;return
    end
    local name=job.kind.." "..job.slot;local group="stagerig_klangrig_"..job.kind
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
            job.result=result;job.rows=Codec.clone(rig.rows);job.bank_cursor=1;job.stage=3;return
        end
        rig.active_values=job.values;rig.active_kind=job.kind;rig.active_slot=job.slot
        rig.status.edit_id=name
        rig.active_names=rig.active_names or {};rig.active_names[job.kind]=name
        rig.status.active_id=name;rig.message=(if job.store then "Stored " else "Recalled ")..name
    else rig.message=result.error or result.message or result.code or "Preset failed" end
    rig.job=nil
end
return M
end
