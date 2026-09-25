--!strict
-- Klang adapter behind the copied truck attribute editor and preset gestures.
return function(host,get)
local C=get("attribute_catalog")
local Codec=require("@show/rig_codec")
local Fixtures=require("@show/fixture_catalog")
local Pe=get("persist")
local M={records={},groups={},fixtures=Fixtures,message="Restoring Klangrig",mode="",root="",now=0,
    status={revision=0,selection={},output={},base={},edits={},touched={},assignments={},presets={}},
    rows={},base={},history={},selection={},revision=0,preset_kind="static",mask="all",job=nil,pending={},loaded=false}
local banks={}
local counts={}
local last_count_poll=-1
local undoKeys={}
for key in pairs(C.attributes) do table.insert(undoKeys,key) end
table.sort(undoKeys)
local undoGesture=nil
local undoTime=-1
local function record(key,default,lo,hi,kind)
    local r={key=key,default=default,min=lo,max=hi,persist="bank",value_type=kind}
    table.insert(M.records,r);return r
end
M.slot=record("static_slot",1,1,16)
M.editor_bank={key="attribute_bank",default=1,min=1,max=#C.banks,persist="snapshot"}
M.attribute_banks=C.banks
M.editor_absolute={key="attribute_absolute",default=0,min=0,max=1,persist="snapshot"}
M.pitch=record("static_pitch",0,-85,85);M.pitch.label="PITCH";M.pitch.fmt="%+.1f"
M.master=record("lighting_master",1,0,1);M.master.label="MASTER";M.master.fmt="%.2f"
table.remove(M.records);table.remove(M.records) -- Exposed directly as encoder records.
M.strobe={strobe_rate=record("led_strobe_rate",6,1,24),strobe_duty=record("led_strobe_duty",.35,.05,.95)}
M.colors={value=0};M.reset_held=false;M.reset_used=false
M.selection_record={key="selected_fixtures",default="",persist="snapshot",value_type="string"}
table.insert(M.records,M.selection_record)
table.insert(M.records,M.editor_bank);table.insert(M.records,M.editor_absolute)
for i,f in ipairs(Fixtures) do
    M.rows[i]={};M.groups[i]={}
    for key,a in pairs(C.attributes) do
        M.rows[i][key]=a.default
        if (M.strobe[key] and not f.mover) or (not M.strobe[key] and (f.mover or (key~="pan" and key~="tilt" and key~="ring" and key~="ring_palette" and key~="move_lane" and key~="pan_amp" and key~="tilt_amp"))) then M.groups[i][key]=a end
    end
    if not f.mover then M.rows[i].beam_palette=2 end
end
for _,kind in ipairs({"static","effects"}) do for bank=0,8 do
    local first,last=bank*32+1,if bank==8 then 289 else bank*32+32
    local r=record(kind.."_bank_"..bank,Codec.pack(M.rows,C[kind],first,last),nil,nil,"string")
    table.insert(banks,{rec=r,kind=kind,first=first,last=last})
end end
M.custom={}
for i=1,8 do M.custom[i]={name=record("group_name_"..i,"Group "..i,nil,nil,"string"),
    members=record("group_members_"..i,"",nil,nil,"string")} end
local function publish(r,v)
    r.value=v;Pe.publish(r,M.now)
end
function M.path(i,key) return tostring(i-1)..":"..key end
function M.is_selected(id) return M.selection[id]==true end
function M.refresh()
    local s=M.status;s.revision=M.revision;s.selection={};s.output={};s.base={};s.edits={};s.touched={}
    for i,row in ipairs(M.rows) do
        if M.selection[tostring(i-1)] then table.insert(s.selection,tostring(i-1)) end
    end
    s.undo_available=#M.history>0
    if s.undo_available then s.edits.changed=1;s.touched.changed=1 end
end
function M.save_live()
    M.persist_cursor=1
    M.revision+=1;M.refresh()
end
function M.remember(gesture)
    if gesture and gesture==undoGesture and M.now-undoTime<.3 then undoTime=M.now;return end
    undoGesture=gesture;undoTime=M.now
    -- A double buffer preserves exact values without thousands of table/hash copies.
    if #M.history>=32 then table.remove(M.history,1) end
    local snapshot={data=buffer.create(#M.rows*#undoKeys*8),strobe={}}
    local offset=0
    for _,row in ipairs(M.rows) do for _,key in ipairs(undoKeys) do
        buffer.writef64(snapshot.data,offset,row[key]);offset+=8
    end end
    for key,r in pairs(M.strobe) do snapshot.strobe[key]=tonumber(host.state.get(M.root.."/"..r.key)) or r.value or r.default end
    table.insert(M.history,snapshot)
end
function M.range(key,offset)
    if M.strobe[key] then
        if not M.selection["288"] then return nil,nil end
        local r=M.strobe[key];local v=tonumber(host.state.get(M.root.."/"..r.key)) or r.value or r.default
        return v,v
    end
    local lo,hi=nil,nil
    for _,id in ipairs(M.status.selection) do
        local i=tonumber(id)+1
        if M.groups[i][key] then
            local v=M.rows[i][key]-(if offset then M.base[i][key] else 0)
            lo=if lo then math.min(lo,v) else v;hi=if hi then math.max(hi,v) else v
        end
    end
    return lo,hi
end
function M.group_ids(group)
    local ids={}
    local custom=tonumber(string.match(group,"^custom(%d+)$"))
    if custom then
        for _,id in ipairs(string.split(M.custom[custom].members.value or "",",")) do local n=tonumber(id);if n and Fixtures[n+1] and M.active_fixture(Fixtures[n+1]) then table.insert(ids,id) end end
        return ids
    end
    local wing=tonumber(string.match(group,"^wing(%d+)$"));local bay=tonumber(string.match(group,"^bay(%d+)$"))
    for _,f in ipairs(Fixtures) do
        local hit=group=="all" or (group=="led" and not f.mover) or (f.mover and
            ((group=="spine" and f.wing==0) or (group=="wings" and f.wing>0) or
            (group=="upper" and f.upper) or (group=="lower" and f.wing>0 and not f.upper) or
            (group=="left" and f.left) or (group=="right" and f.wing>0 and not f.left) or
            (wing and f.wing==wing) or (bay and f.bay==bay)))
        if hit and M.active_fixture(f) then table.insert(ids,f.id) end
    end
    return ids
end
function M.select(ids,toggle)
    undoGesture=nil
    local expanded={}
    for _,id in ipairs(ids) do
        if tonumber(id) then table.insert(expanded,id) else for _,v in ipairs(M.group_ids(id)) do table.insert(expanded,v) end end
    end
    if not toggle then M.selection={} end
    local all=#expanded>0
    for _,id in ipairs(expanded) do if not M.selection[id] then all=false end end
    for _,id in ipairs(expanded) do if tonumber(id)>=0 and tonumber(id)<=288 then M.selection[id]=not(toggle and all) end end
    M.revision+=1;M.refresh()
    M.selection_record.value=table.concat(M.status.selection,",")
end
function M.active_fixture(f)
    if not f.mover then return true end
    return f.local_index<(counts[f.wing] or (if f.wing==0 then 72 else 12))
end
function M.selected(group)
    local ids=M.group_ids(tostring(group));if #ids==0 then return false end
    for _,id in ipairs(ids) do if not M.selection[id] then return false end end;return true
end
function M.store_group(slot,name)
    publish(M.custom[slot].name,string.sub(name,1,40))
    publish(M.custom[slot].members,table.concat(M.status.selection,","));M.message="Stored "..name;M.revision+=1;M.refresh()
end
function M.request(action,args)
    args=args or {}
    if action=="undo" then
        undoGesture=nil
        if #M.history>0 then
            local snapshot=table.remove(M.history)
            local offset=0
            for _,row in ipairs(M.rows) do for _,key in ipairs(undoKeys) do
                row[key]=buffer.readf64(snapshot.data,offset);offset+=8
            end end
            for key,v in pairs(snapshot.strobe) do publish(M.strobe[key],v) end
            M.save_live()
        end;return
    end
    if action=="update" then
        if not M.active_values or M.active_kind~=M.preset_kind then M.message="Recall or store this bank before UPDATE";return end
        M.mode="store";local job=M.recall(M.active_slot);if job then job.update=true end;return
    end
    M.remember(if action=="encoder" and not args.discrete then args.gesture else nil)
    local key=args.attribute
    local absolute=args.absolute==true or action=="set"
    local value=args.value or 0
    if action=="encoder" and absolute then
        local lo=M.range(key);value=(lo or 0)+value
    end
    if M.strobe[key] then
        if M.selection["288"] then
            local r=M.strobe[key];local current=M.range(key)
            publish(r,math.clamp(if absolute then value else current+value,r.min,r.max))
            M.message="LED STROBE";M.revision+=1;M.refresh()
        end
        return
    end
    for i,row in ipairs(M.rows) do if M.selection[tostring(i-1)] or action=="release" then
        for attr,a in pairs(M.groups[i]) do if not key or key==attr then
            if action=="reset_selected" or action=="release" then row[attr]=M.base[i][attr]
            elseif action=="encoder" or action=="set" or action=="offset" then
                local v=if absolute then value else row[attr]+value
                row[attr]=math.clamp(if a.step then math.floor(v+.5) else v,a.min,a.max)
            end
        end end
    end end
    M.save_live();M.message=string.upper(action)
end
function M.clear_effects()
    M.remember()
    for i,row in ipairs(M.rows) do if M.selection[tostring(i-1)] then
        row.move_lane=0;row.int_lane=0;row.color_lane=0
        row.pan_amp=0;row.tilt_amp=0;row.led_pattern=0
    end end
    M.save_live();M.message="FX OFF / selected fixtures"
end
function M.begin_reset() M.reset_held=true;M.reset_used=false end
function M.end_reset() if not M.reset_used then M.request("reset_selected") end;M.reset_held=false end
function M.set_colors() end
function M.arm(action) M.mode=if M.mode==action then "" else action;M.message=M.mode..": choose slot" end
function M.slot_name(slot) return M.preset_kind.." "..slot end
function M.active(slot) return M.status.active_id==M.preset_kind.." "..slot end
function M.recall(slot)
    local storing=M.mode=="store" or M.mode=="store_edits"
    local job={kind=M.preset_kind,slot=slot,store=storing,mode=M.mode,mask=M.mask,stage=if storing then 0 else 2}
    M.slot.value=slot;M.mode=""
    if M.job then
        if storing then M.message="Finish the current preset operation before storing";return end
        for i,pending in ipairs(M.pending) do if pending.kind==job.kind then
            M.pending[i]=job;return
        end end
        table.insert(M.pending,job);return
    end
    M.job=job;return job
end
function M.flush_snapshot()
    if M.persist_cursor then
        for _,b in ipairs(banks) do b.rec.value=Codec.pack(M.rows,C[b.kind],b.first,b.last) end
    end
end
function M.start(root)
    M.root=root
    get("rig_commands").bind(root)
    for _,b in ipairs(banks) do host.state.register("saved_"..b.rec.key,b.rec.default) end
    M.base=Codec.clone(M.rows)
    for _,id in ipairs(string.split(M.selection_record.value or "",",")) do if tonumber(id) then M.selection[id]=true end end
end
function M.tick(t) M.now=t end
function M.service()
    for _,r in pairs(M.strobe) do r.value=tonumber(host.state.get(M.root.."/"..r.key)) or r.value or r.default end
    if M.now-last_count_poll>.2 then
        for wing=0,12 do
            local path="/sentinel/pipelines/stagerig_klangrig_Plan/parameters/"..(if wing==0 then "spine_count" else string.format("wing_%02d_count",wing))
            host.sentinel.subscribe(path);counts[wing]=tonumber(host.sentinel.get(path)) or counts[wing]
        end
        M.active_names=M.active_names or {}
        for _,kind in ipairs({"static","effects","color"}) do
            if not M.active_names[kind] then
                local name=host.preset.active("stagerig_klangrig_"..kind)
                if name and name~="" then M.active_names[kind]=name end
            end
        end
        last_count_poll=M.now
    end
    local changed=false
    local decoded=false
    local complete=true
    if M.persist_cursor then
        local b=banks[M.persist_cursor]
        local text=Codec.pack(M.rows,C[b.kind],b.first,b.last)
        publish(b.rec,text);b.last_text=text
        M.persist_cursor+=1;if M.persist_cursor>#banks then M.persist_cursor=nil end
    else for _,b in ipairs(banks) do
        local text=host.state.get(M.root.."/"..b.rec.key) or b.rec.default
        if b.last_text~=text and not decoded then
            Codec.unpack(text,M.rows,C[b.kind],b.first,b.last,C.attributes)
            b.last_text=text;b.rec.value=text;changed=true;decoded=true
        end
        if b.last_text~=text then complete=false end
    end end
    if changed then
        if not M.loaded and complete then M.base=Codec.clone(M.rows);M.loaded=true;M.message="Select fixtures / create a static look" end
        M.revision+=1;M.refresh()
    end
    for _,g in ipairs(M.custom) do
        g.name.value=host.state.get(M.root.."/"..g.name.key) or g.name.default
        g.members.value=host.state.get(M.root.."/"..g.members.key) or g.members.default
    end
    if M.loaded then get("rig_commands").service(M) end
    if M.job then get("look_store").service(M) end
    if not M.job and #M.pending>0 then M.job=table.remove(M.pending,1) end
    get("rig_bridge").service(M)
end
M.banks=banks
return M
end
