--!strict
-- PHAGE programmer: 248 slot rows behind the attribute editor, the preset banks and the desk.
-- Rows persist as 8 packed banks per kind (static / effects), 32 slots each (the last holds 24).
return function(host,get)
local C=get("attribute_catalog")
local Codec=require("@show/rig_codec")
local Fixtures=require("@show/fixture_catalog")
local Pe=get("persist")
local SLOTS=#Fixtures
local PLAN="/sentinel/pipelines/Phage_Plan/parameters/"
-- Plan count parameters that populate the rig, with the Plan's own defaults until the values arrive.
local COUNT_DEFAULTS={plate_outer_movers=4,plate_inner_movers=2,capsid_movers=1,knee_movers=2,collar_movers=6,
    booth_movers=16,foot_movers=1,collar_strobes=6,plate_strobes=2,knee_strobes=1,foot_strobes=1,capsid_strobes=1,booth_strobes=6}
local M={records={},groups={},fixtures=Fixtures,message="Restoring PHAGE programmer",mode="",root="",now=0,
    status={revision=0,selection={},output={},base={},edits={},touched={},assignments={},presets={}},
    rows={},base={},history={},selection={},revision=0,preset_kind="static",mask="all",job=nil,pending={},loaded=false}
local banks={}
local counts: {[string]: number}=table.clone(COUNT_DEFAULTS)
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
M.strobe={strobe_rate=record("show_strobe_rate",C.attributes.strobe_rate.default,1,24),
    strobe_duty=record("show_strobe_duty",C.attributes.strobe_duty.default,.05,.95)}
M.colors={value=0};M.reset_held=false;M.reset_used=false
M.selection_record={key="selected_fixtures",default="",persist="snapshot",value_type="string"}
table.insert(M.records,M.selection_record)
-- What the pads light: the last recalled look of each bank. A beam shape (static 1-12) and a truss
-- pose (13-16) are separate STATIC layers. A FULL look lights the parts it was stored with (its
-- look_parts travel inside the FULL preset); any later partial recall unlights the FULL pad,
-- because the rig is no longer that look. The Surface entry carries the text in its own serialize
-- table (reloads and project saves) and state `active_looks` mirrors it for automation. It is not
-- a push2os record: a new durable record would make every older reload snapshot refuse to restore
-- (SNAPSHOT_RECORD_MISSING), and plain Surface state resets when it is re-registered.
local POSE_FIRST=13
local LAYERS={"static","pose","effects","color","complete"}
local function parse_looks(a,text,skip)
    for _,pair in ipairs(string.split(text or "",";")) do
        local k,v=string.match(pair,"^(%a+)=(.+)$");if k and k~=skip then a[k]=v end
    end
end
function M.parts_text()
    local a=M.active_names or {};local out={}
    for _,k in ipairs(LAYERS) do if k~="complete" and a[k] then table.insert(out,k.."="..a[k]) end end
    return table.concat(out,";")
end
local function publish_looks()
    local a=M.active_names or {};local out={}
    for _,k in ipairs(LAYERS) do if a[k] then table.insert(out,k.."="..a[k]) end end
    M.active_text=table.concat(out,";")
    host.state.set(M.root.."/active_looks",M.active_text)
end
function M.set_active(kind,slot,parts)
    local a=M.active_names or {};M.active_names=a
    local name=kind.." "..slot
    if kind=="static" and slot>=POSE_FIRST then a.pose=name else a[kind]=name end
    if kind=="complete" then a.static,a.pose,a.effects,a.color=nil,nil,nil,nil;parse_looks(a,parts,"complete")
    elseif kind~="rhythm" then a.complete=nil end
    publish_looks()
end
function M.restore_active(text)
    M.active_names={};parse_looks(M.active_names,text);publish_looks()
end
function M.is_lit(kind,slot)
    local a=M.active_names;if not a then return false end
    local name=kind.." "..slot
    return a[kind]==name or (kind=="static" and a.pose==name)
end
table.insert(M.records,M.editor_bank);table.insert(M.records,M.editor_absolute)
-- A strobe with no lane at LOOK 0 (PULSE) holds its tube at full: fresh rows and FX OFF rest
-- strobes on GLOW (colour plate only), everything else on its plain look.
function M.rest_look(f) return if f.kind==1 then 4 else 0 end
for i,f in ipairs(Fixtures) do
    M.rows[i]={};M.groups[i]={}
    for key,a in pairs(C.attributes) do M.rows[i][key]=a.default end
    M.rows[i].look=M.rest_look(f)
    if not f.unused then for _,key in ipairs(C.kinds[f.kind]) do M.groups[i][key]=C.attributes[key] end end
end
M.bank_count=math.ceil(SLOTS/32)
for _,kind in ipairs({"static","effects"}) do for bank=0,M.bank_count-1 do
    local first,last=bank*32+1,math.min(SLOTS,bank*32+32)
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
    for i in ipairs(M.rows) do
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
-- The strobe clock belongs to the show; it is edited whenever a strobe or a pixel bar is selected.
function M.strobe_selected(): boolean
    for _,id in ipairs(M.status.selection) do
        local f=Fixtures[tonumber(id)+1];if f and (f.kind==1 or f.kind==2) then return true end
    end
    return false
end
function M.range(key,offset)
    if M.strobe[key] then
        if not M.strobe_selected() then return nil,nil end
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
function M.active_fixture(f)
    if f.unused then return false end
    if not f.gate then return true end
    return (counts[f.gate[1]] or 0)>f.gate[2]
end
-- Same membership as the Lighting canvas buttons (Phage_Lighting/lighting.hlsli inGroup).
local ZONES={plate={[0]=true,[1]=true,[11]=true,[22]=true},capsid={[2]=true,[14]=true,[25]=true,[26]=true,[31]=true},
    collar={[4]=true,[10]=true,[23]=true,[24]=true},knees={[3]=true,[12]=true},feet={[6]=true,[13]=true},
    booth={[5]=true,[15]=true,[27]=true},legs={[3]=true,[6]=true,[12]=true,[13]=true,[20]=true,[21]=true,[32]=true}}
local KINDS={movers=0,strobes=1,bars=2,axes=3}
M.group_names={"all","none","movers","strobes","bars","axes","left","right","plate","capsid","collar","knees","feet","booth","legs","odd"}
function M.in_group(group,f)
    if group=="all" then return true end
    if KINDS[group] then return f.kind==KINDS[group] end
    if group=="left" then return f.x< -.05 end
    if group=="right" then return f.x>.05 end
    if group=="odd" then return f.index%2==1 end
    local zone=ZONES[group];return zone~=nil and zone[f.family]==true
end
function M.group_ids(group)
    local ids={}
    local custom=tonumber(string.match(group,"^custom(%d+)$"))
    if custom then
        for _,id in ipairs(string.split(M.custom[custom].members.value or "",",")) do local n=tonumber(id);if n and Fixtures[n+1] and M.active_fixture(Fixtures[n+1]) then table.insert(ids,id) end end
        return ids
    end
    for _,f in ipairs(Fixtures) do
        if M.active_fixture(f) and M.in_group(group,f) then table.insert(ids,f.id) end
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
    for _,id in ipairs(expanded) do local n=tonumber(id);if n>=0 and n<SLOTS then M.selection[id]=not(toggle and all) end end
    for id in pairs(M.selection) do if M.selection[id]==false then M.selection[id]=nil end end
    M.revision+=1;M.refresh()
    M.selection_record.value=table.concat(M.status.selection,",")
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
        if M.strobe_selected() then
            local r=M.strobe[key];local current=M.range(key)
            publish(r,math.clamp(if absolute then value else current+value,r.min,r.max))
            M.message="STROBE CLOCK";M.revision+=1;M.refresh()
        end
        return
    end
    for i,row in ipairs(M.rows) do if M.selection[tostring(i-1)] or action=="release" then
        for attr,a in pairs(M.groups[i]) do if (not key or key==attr) and not M.strobe[attr] then
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
        row.pan_amp=0;row.tilt_amp=0;row.look=M.rest_look(Fixtures[i])
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
    host.state.register("look_parts","");host.state.register("active_looks","")
    M.active_names=M.active_names or {}
    for key in pairs(COUNT_DEFAULTS) do pcall(host.sentinel.subscribe,PLAN..key) end
    M.base=Codec.clone(M.rows)
    for _,id in ipairs(string.split(M.selection_record.value or "",",")) do if tonumber(id) then M.selection[id]=true end end
end
function M.tick(t) M.now=t end
local function count_value(v: any): number?
    if v==true or v=="true" then return 1 elseif v==false or v=="false" then return 0 end
    return tonumber(v)
end
function M.service()
    for _,r in pairs(M.strobe) do r.value=tonumber(host.state.get(M.root.."/"..r.key)) or r.value or r.default end
    if M.now-last_count_poll>.2 then
        for key in pairs(COUNT_DEFAULTS) do counts[key]=count_value(host.sentinel.get(PLAN..key)) or counts[key] end
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
        if not M.loaded and complete then M.base=Codec.clone(M.rows);M.loaded=true;M.message="Select fixtures / recall a look" end
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
