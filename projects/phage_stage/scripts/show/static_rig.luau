--!strict
-- PHAGE programmer: 616 program rows behind the attribute editor, the preset banks and the desk. Each of the 248
-- slots has its base row (MOVE, TUBE, PIXELS or an axis); the movers add BEAM and HALO, the strobes PLATES and the
-- pixel bars CHASE (rows below, tools/phage_program.py). Rows persist as 8 packed banks per kind (static / effects),
-- each a partition of 32 slots with their layer rows (rig_codec.luau).
return function(host,get)
local C=get("attribute_catalog")
local Codec=require("@show/rig_codec")
local Fixtures=require("@show/fixture_catalog")
local Pe=get("persist")
local SLOTS=#Fixtures
-- Program rows: 1-248 the base layer of each slot, 249-376 the movers' BEAM (slot + 248), 377-616 the second layer
-- (HALO, PLATES, CHASE) of every fixture but the axes (slot + 376).
local BEAM0,LAYER2=248,376
local BASE_LAYER={[0]="move",[1]="tube",[2]="pixels",[3]="axis"}
local SECOND_LAYER={[0]="halo",[1]="plates",[2]="chase"}
-- Row kinds (attribute_catalog kinds): the base rows keep their fixture's kind (0 MOVE, 1 TUBE, 2 PIXELS, 3 axis);
-- 4 BEAM, 5 HALO, 6 PLATES, 7 CHASE.
local LAYER_KIND={move=0,tube=1,pixels=2,axis=3,beam=4,halo=5,plates=6,chase=7}
local Layers={}
for i,f in ipairs(Fixtures) do Layers[i]={slot=f.id,fixture=i,layer=BASE_LAYER[f.kind]} end
for i,f in ipairs(Fixtures) do
    if f.kind==0 then Layers[BEAM0+i]={slot=f.id,fixture=i,layer="beam"} end
    if SECOND_LAYER[f.kind] then Layers[LAYER2+i]={slot=f.id,fixture=i,layer=SECOND_LAYER[f.kind]} end
end
local ROWS=#Layers
assert(ROWS==616,"PHAGE program rows")
-- Each fixture's rows (1-based), base row first.
local FixtureRows={}
for r,L in ipairs(Layers) do
    L.id=tostring(r-1);L.kind=LAYER_KIND[L.layer]
    FixtureRows[L.fixture]=FixtureRows[L.fixture] or {};table.insert(FixtureRows[L.fixture],r)
end
local PLAN="/sentinel/pipelines/Phage_Plan/parameters/"
-- Plan count parameters that populate the rig, with the Plan's own defaults until the values arrive.
local COUNT_DEFAULTS={plate_outer_movers=4,plate_inner_movers=2,capsid_movers=1,knee_movers=2,collar_movers=6,
    booth_movers=16,foot_movers=1,collar_strobes=6,plate_strobes=2,knee_strobes=1,foot_strobes=1,capsid_strobes=1,booth_strobes=6}
local M={records={},groups={},fixtures=Fixtures,row_list=Layers,message="Restoring PHAGE programmer",mode="",root="",now=0,
    status={revision=0,selection={},output={},base={},edits={},touched={},assignments={},presets={}},
    rows={},base={},history={},selection={},revision=0,preset_kind="static",mask="all",job=nil,pending={},loaded=false}
local banks={}
local counts: {[string]: number}=table.clone(COUNT_DEFAULTS)
local last_count_poll=-1
-- The rig decides which slots carry a fixture: Phage_Lighting builds the show's fixture table from the Fixture Rig
-- and publishes it as 16 presence words (rig_word0-15, bit s%16 of word s/16), so a fixture added to or deleted from
-- the rig is added to or removed from the programmer. Until the first words arrive, the Plan's counts stand in.
local LIGHTING_OUT="/sentinel/pipelines/Phage_Lighting/control_outputs/"
local rig_words: {[number]: number}={}
local undoKeys={}
for key,a in pairs(C.attributes) do if not a.field then table.insert(undoKeys,key) end end
table.sort(undoKeys)
local undoGesture=nil
local undoTime=-1
local function record(key,default,lo,hi,kind)
    local r={key=key,default=default,min=lo,max=hi,persist="bank",value_type=kind}
    table.insert(M.records,r);return r
end
M.slot=record("static_slot",1,1,64)   -- the last pad pressed: look banks hold 16, fixture banks 64
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
M.POSE_FIRST=POSE_FIRST
-- The capsid's truss row: its level is its HEADING (FRONT holds it facing front), which a HALO BEAMS pad carries.
for _,L in ipairs(Layers) do local f=Fixtures[L.fixture]
    if L.layer=="axis" and f.family==31 then M.capsid_axis=L.id end
end
-- Fixture banks (pad pages 2-4): one per layer of each fixture type, plus one per type that holds all its layers. A
-- layer bank stores and recalls only that layer's effect rows (plus the strobe clock when the layer runs on it), so
-- layer pads stack; a whole-fixture bank (FX_STATIC) also holds the type's aim and levels, so a fixture look built
-- from its layer pads stores as one pad. Palettes stay with COLOR. Kinds are the row kinds (0 MOVE, 4 BEAM, 5 HALO,
-- 1 TUBE, 6 PLATES, 2 PIXELS, 7 CHASE):
--   page 2 Halo Beam:      MOVE, BEAM, HALO, HALO BEAMS ("heads")
--   page 3 Linear Strobe:  TUBE, PLATES, STROBES
--   page 4 Pixel Batten:   PIXELS, CHASE, BATTENS
--   page 5 SEQUENCES:      RIG (every type at once), BEAMS, STROBES, BATTENS: the same 15 sequences, each type's part
M.FX_FAMILIES={move={[0]=true},beam={[4]=true},halo={[5]=true},heads={[0]=true,[4]=true,[5]=true},
    tube={[1]=true},plates={[6]=true},strobes={[1]=true,[6]=true},
    pixels={[2]=true},chase={[7]=true},battens={[2]=true,[7]=true},
    sequence={[0]=true,[4]=true,[5]=true,[1]=true,[6]=true,[2]=true,[7]=true},
    seq_heads={[0]=true,[4]=true,[5]=true},seq_strobes={[1]=true,[6]=true},seq_battens={[2]=true,[7]=true}}
M.FX_STATIC={heads=true,strobes=true,battens=true,sequence=true,seq_heads=true,seq_strobes=true,seq_battens=true}
M.FX_ORDER={"move","beam","halo","heads","tube","plates","strobes","pixels","chase","battens",
    "sequence","seq_heads","seq_strobes","seq_battens"}
-- Whether a bank's rows run on the show's strobe clock (RATE, DUTY): its presets store the clock with them.
function M.clocked(kind)
    for k in pairs(M.FX_FAMILIES[kind] or {}) do if M.CLOCKED[k] then return true end end
    return false
end
-- Pad names for stored fixture presets ("beam 3" -> "PULSE x2"); they travel in the Surface entry's serialize table,
-- like the lit looks.
M.fx_names={}
function M.fx_names_text()
    local out={};for k,v in pairs(M.fx_names) do table.insert(out,k.."="..v) end
    table.sort(out);return table.concat(out,";")
end
function M.publish_fx_names() if M.root~="" then host.state.set(M.root.."/fx_names",M.fx_names_text()) end end   -- mirror for automation
function M.restore_fx_names(text)
    M.fx_names={}
    for _,pair in ipairs(string.split(text or "",";")) do
        local k,v=string.match(pair,"^([%a_]+ %d+)=(.+)$");if k then M.fx_names[k]=v end
    end
    M.publish_fx_names()
end
M.pad_page=1
-- A short pad name for a fixture preset from its layers' first live rows: the look as the layer's own LOOK knob names
-- it. A whole-fixture pad names each lit layer by its first word ("CIRCLE+PULSE"); one with every layer dark, "DARK".
local function look_name(r: number,kind: number): string
    local L=C.attributes[C.look_of[kind]];local row=M.rows[r];local v=math.floor(row.look+.5)
    if kind==0 and v<48 and row.move_lane<.5 then return "STILL" end
    if (kind==4 or kind==5) and row.int_lane<.5 then return "STEADY" end
    if kind==7 and row.int_lane<.5 then return "NONE" end
    return L and L.choices[v+1] or ("LOOK "..v)
end
local function dark(r: number,kind: number,name: string): boolean
    if name=="STILL" or name=="NONE" or name=="OFF" or (kind==1 and name=="GLOW") then return true end
    if kind==0 or kind==7 then return false end
    return M.rows[r][if kind==5 or kind==6 then "ring" else "level"]<.02
end
function M.fx_label(kind)
    local family=M.FX_FAMILIES[kind];local whole=M.FX_STATIC[kind]==true;local parts={}
    for _,k in ipairs({0,4,5,1,6,2,7}) do if family[k] then
        for r,L in ipairs(Layers) do if L.kind==k and M.active_fixture(Fixtures[L.fixture]) then
            local name=look_name(r,k)
            if not whole then return name end
            if not dark(r,k,name) then table.insert(parts,string.split(name," ")[1]) end
            break
        end end
    end end
    return if #parts>0 then table.concat(parts,"+") else "DARK"
end
local LAYERS={"static","pose","effects","color","complete"}
for _,k in ipairs(M.FX_ORDER) do table.insert(LAYERS,k) end
local function parse_looks(a,text,skip)
    for _,pair in ipairs(string.split(text or "",";")) do
        local k,v=string.match(pair,"^([%a_]+)=(.+)$");if k and k~=skip then a[k]=v end
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
    if kind=="complete" then
        a.static,a.pose,a.effects,a.color=nil,nil,nil,nil
        for k in pairs(M.FX_FAMILIES) do a[k]=nil end
        parse_looks(a,parts,"complete")
    elseif kind~="rhythm" then a.complete=nil end
    -- A fixture preset changes part of the effects (the EFFECTS pad no longer tells the truth), and a whole-fixture
    -- one part of the aim and levels (nor does the STATIC shape); an effects recall replaces every fixture's effects
    -- and a shape every head's aim and levels (no fixture pad they cover does).
    if M.FX_FAMILIES[kind] then
        a.effects=nil
        if M.FX_STATIC[kind] then a.static=nil end
        -- Nor does any other fixture pad sharing a layer with it (HALO BEAMS holds MOVE, BEAM and HALO).
        for other,fam in pairs(M.FX_FAMILIES) do if other~=kind then
            for k in pairs(fam) do if M.FX_FAMILIES[kind][k] then a[other]=nil;break end end
        end end
    end
    if kind=="effects" then for k in pairs(M.FX_FAMILIES) do a[k]=nil end end
    if kind=="static" and slot<POSE_FIRST then for k in pairs(M.FX_STATIC) do a[k]=nil end end
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
-- strobes on GLOW (TUBE dark, PLATES steady), everything else on its plain look. Takes a fixture or a row.
function M.rest_look(f) return if f.kind==1 or f.kind==6 then 4 else 0 end
-- A row's own keys: the program fields its layer's knobs drive (aliases resolved). A bank stores only these, so a
-- layer's look never writes another layer's values.
M.owned={}
for r=1,ROWS do
    local L=Layers[r];local f=Fixtures[L.fixture]
    M.rows[r]={};M.groups[r]={};M.owned[r]={}
    -- Every row can carry a fixture the rig adds (a guest takes a free slot of its role), so every row is editable.
    for key,a in pairs(C.attributes) do if not a.field then M.rows[r][key]=a.default end end
    M.rows[r].look=M.rest_look(L)
    for _,key in ipairs(C.kinds[L.kind]) do
        local a=C.attributes[key]
        M.groups[r][key]=a
        M.owned[r][a.field or key]=true
    end
end
-- A layer row's power-on values follow its fixture's base row (PLATES its strobe's, CHASE holds no lane).
local CHASE_REST={move_lane=0,int_lane=0,color_lane=0,pan_amp=0,tilt_amp=0,spread=.45,width=.5,offset=0,reverse=0,look=0,order=0}
for r=SLOTS+1,ROWS do
    local L=Layers[r]
    for key,v in pairs(M.rows[L.fixture]) do M.rows[r][key]=v end
    if L.layer=="chase" then for key,v in pairs(CHASE_REST) do M.rows[r][key]=v end end
end
local function ownedOf(e) return M.owned[e.row] end
M.layers=Layers
M.bank_count=math.ceil(SLOTS/32)
-- Partition k: slots 32k..32k+31's base rows, then their BEAM rows, then their second-layer rows.
M.partitions={}
for bank=0,M.bank_count-1 do
    local first,last=bank*32+1,math.min(SLOTS,bank*32+32)
    local list={}
    for i=first,last do table.insert(list,{row=i,slot=Fixtures[i].id,id=Layers[i].id,layer=Layers[i].layer,base=i-first+1}) end
    local base_count=#list
    for _,offset in ipairs({BEAM0,LAYER2}) do for i=first,last do
        local L=Layers[offset+i]
        if L and L.fixture==i then table.insert(list,{row=offset+i,slot=Fixtures[i].id,id=L.id,layer=L.layer,base=i-first+1}) end
    end end
    M.partitions[bank]={list=list,base_count=base_count}
end
for _,kind in ipairs({"static","effects"}) do for bank=0,M.bank_count-1 do
    local part=M.partitions[bank]
    local r=record(kind.."_bank_"..bank,Codec.pack(M.rows,C[kind],part,nil,nil,ownedOf),nil,nil,"string")
    table.insert(banks,{rec=r,kind=kind,part=part,bank=bank})
end end
M.owned_of=ownedOf
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
    s.fixtures={}
    local seen={}
    for i in ipairs(M.rows) do
        if M.selection[tostring(i-1)] then
            table.insert(s.selection,tostring(i-1))
            local slot=Layers[i].slot;if not seen[slot] then seen[slot]=true;table.insert(s.fixtures,slot) end
        end
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
-- The strobe clock belongs to the show; it is edited whenever a layer that runs on it is selected (TUBE, PIXELS,
-- CHASE). The plates never flash on it, so PLATES pads do not store it.
M.CLOCKED={[1]=true,[2]=true,[7]=true}
function M.strobe_selected(): boolean
    for _,id in ipairs(M.status.selection) do
        local L=Layers[tonumber(id)+1];if L and M.CLOCKED[L.kind] then return true end
    end
    return false
end
-- The attribute `key` addresses on row i and the program field it lives in. A program field named directly (the
-- command seam's "level", "ring", "look") reaches the row's knob onto that field.
local function attrOf(i: number,key: string): (any,string?)
    local a=M.groups[i][key]
    if a then return a,a.field or key end
    for _,b in pairs(M.groups[i]) do if b.field==key then return b,key end end
    return nil,nil
end
M.attr_of=attrOf
function M.range(key,offset)
    if M.strobe[key] then
        if not M.strobe_selected() then return nil,nil end
        local r=M.strobe[key];local v=tonumber(host.state.get(M.root.."/"..r.key)) or r.value or r.default
        return v,v
    end
    local lo,hi=nil,nil
    for _,id in ipairs(M.status.selection) do
        local i=tonumber(id)+1
        local a,f=attrOf(i,key)
        if a and f then
            local v=M.rows[i][f]-(if offset then M.base[i][f] else 0)
            lo=if lo then math.min(lo,v) else v;hi=if hi then math.max(hi,v) else v
        end
    end
    return lo,hi
end
function M.active_fixture(f)
    local w=rig_words[math.floor(f.slot/16)]
    if w~=nil then return bit32.band(math.floor(w+.5),bit32.lshift(1,f.slot%16))~=0 end
    if f.unused then return false end
    if not f.gate then return true end
    return (counts[f.gate[1]] or 0)>f.gate[2]
end
-- Same membership as the Lighting canvas buttons (Phage_Lighting/lighting.hlsli inGroup).
local ZONES={plate={[0]=true,[1]=true,[11]=true,[22]=true},capsid={[2]=true,[14]=true,[25]=true,[26]=true,[31]=true},
    collar={[4]=true,[10]=true,[23]=true,[24]=true},knees={[3]=true,[12]=true},feet={[6]=true,[13]=true},
    booth={[5]=true,[15]=true,[27]=true},legs={[3]=true,[6]=true,[12]=true,[13]=true,[20]=true,[21]=true,[32]=true}}
local KINDS={movers=0,strobes=1,bars=2,axes=3}
-- Layer groups select one layer of every fixture of its type; every other group selects whole fixtures.
local LAYER_GROUPS={move=0,beam=4,halo=5,tube=1,plates=6,pixels=2,chase=7}
M.group_names={"all","none","movers","strobes","bars","axes","left","right","plate","capsid","collar","knees","feet","booth","legs","odd",
    "move","beam","halo","tube","plates","pixels","chase"}
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
        for _,id in ipairs(string.split(M.custom[custom].members.value or "",",")) do
            local n=tonumber(id);local L=n and Layers[n+1]
            if L and M.active_fixture(Fixtures[L.fixture]) then table.insert(ids,id) end
        end
        return ids
    end
    local layer=LAYER_GROUPS[group]
    for i,f in ipairs(Fixtures) do
        if M.active_fixture(f) and (layer~=nil or M.in_group(group,f)) then
            for _,r in ipairs(FixtureRows[i]) do if layer==nil or Layers[r].kind==layer then table.insert(ids,Layers[r].id) end end
        end
    end
    return ids
end
-- A fixture id (a slot, 0-247) means all of that fixture's layers; a row id (248-615) one layer.
local function expand(id: string,out: {string})
    local n=tonumber(id)
    if n==nil then for _,v in ipairs(M.group_ids(id)) do table.insert(out,v) end
    elseif n>=0 and n<SLOTS then for _,r in ipairs(FixtureRows[n+1]) do table.insert(out,Layers[r].id) end
    elseif n>=SLOTS and n<ROWS then table.insert(out,id) end
end
function M.select(ids,toggle)
    undoGesture=nil
    local expanded={}
    for _,id in ipairs(ids) do expand(id,expanded) end
    if not toggle then M.selection={} end
    local all=#expanded>0
    for _,id in ipairs(expanded) do if not M.selection[id] then all=false end end
    for _,id in ipairs(expanded) do M.selection[id]=not(toggle and all) end
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
            -- Dropped only once fully restored: a tick interrupted for its budget leaves the snapshot for the next UNDO.
            local snapshot=M.history[#M.history]
            local offset=0
            for _,row in ipairs(M.rows) do for _,key in ipairs(undoKeys) do
                row[key]=buffer.readf64(snapshot.data,offset);offset+=8
            end end
            table.remove(M.history)
            for key,v in pairs(snapshot.strobe) do publish(M.strobe[key],v) end
            M.save_live()
        end;return
    end
    if action=="update" then
        if not M.active_values or M.active_kind~=M.preset_kind then M.message="Recall or store this bank before UPDATE";return end
        M.mode="store";local job=M.recall(M.active_slot);if job then job.update=true end;return
    end
    -- A layer's LOOK knob (MOVE FX, BEAM FX...) steps through that layer's own order (attribute_catalog sequence).
    if action=="encoder" and args.discrete and C.attributes[args.attribute] and C.attributes[args.attribute].sequence then
        local seq=C.attributes[args.attribute].sequence
        local cur=math.floor((M.range(args.attribute) or 0)+.5)
        local idx=table.find(seq,cur) or 1
        local nxt=seq[math.clamp(idx+math.sign(args.value or 0),1,#seq)]
        action="set";args={attribute=args.attribute,value=nxt,absolute=true,discrete=true}
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
        for attr,a in pairs(M.groups[i]) do
            -- A knob (BEAM, HALO, MOVE FX...) edits its program field; a field named directly edits the knob onto it.
            local f=a.field or attr
            if (not key or key==attr or (key==f and not M.groups[i][key])) and not M.strobe[attr] then
                if action=="reset_selected" or action=="release" then row[f]=M.base[i][f]
                elseif action=="encoder" or action=="set" or action=="offset" then
                    local v=if absolute then value else row[f]+value
                    row[f]=math.clamp(if a.step then math.floor(v+.5) else v,a.min,a.max)
                end
            end
        end
    end end
    M.save_live();M.message=string.upper(action)
end
function M.clear_effects()
    M.remember()
    for i,row in ipairs(M.rows) do if M.selection[tostring(i-1)] then
        row.move_lane=0;row.int_lane=0;row.color_lane=0
        row.pan_amp=0;row.tilt_amp=0;row.look=M.rest_look(Layers[i])
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
        for _,b in ipairs(banks) do b.rec.value=Codec.pack(M.rows,C[b.kind],b.part,nil,nil,ownedOf) end
    end
end
function M.start(root)
    M.root=root
    get("rig_commands").bind(root)
    for _,b in ipairs(banks) do host.state.register("saved_"..b.rec.key,b.rec.default) end
    host.state.register("look_parts","");host.state.register("active_looks","");host.state.register("fx_names","")
    M.active_names=M.active_names or {}
    for key in pairs(COUNT_DEFAULTS) do pcall(host.sentinel.subscribe,PLAN..key) end
    for w=0,15 do pcall(host.sentinel.subscribe,LIGHTING_OUT.."rig_word"..w) end
    M.base=Codec.clone(M.rows)
    for _,id in ipairs(string.split(M.selection_record.value or "",",")) do if tonumber(id) then M.selection[id]=true end end
end
function M.tick(t) M.now=t end
local function count_value(v: any): number?
    if v==true or v=="true" then return 1 elseif v==false or v=="false" then return 0 end
    return tonumber(v)
end
-- Each service tick spends at most about 0.8 ms of the host's 2 ms tick on the resumable steps (publishing banks,
-- decoding a recall, building and sending the upload); the rest picks up on the next tick. `worked` marks a tick that
-- already did a heavy step, so a later step yields once the budget is spent but always gets one step otherwise. Each
-- step is safe to cut anywhere: the host interrupts a tick that overruns.
M.tick_start=0;M.worked=false
function M.busy(): boolean return M.worked and host.time.now()-M.tick_start>0.0008 end
function M.service()
    M.tick_start=host.time.now();M.worked=false
    for _,r in pairs(M.strobe) do r.value=tonumber(host.state.get(M.root.."/"..r.key)) or r.value or r.default end
    if M.now-last_count_poll>.2 then
        for key in pairs(COUNT_DEFAULTS) do counts[key]=count_value(host.sentinel.get(PLAN..key)) or counts[key] end
        for w=0,15 do local v=tonumber(host.sentinel.get(LIGHTING_OUT.."rig_word"..w));if v then rig_words[w]=v end end
        last_count_poll=M.now
    end
    local changed=false
    local decoded=false
    local complete=true
    if M.persist_cursor then
        M.worked=true
        local b=banks[M.persist_cursor]
        local text=Codec.pack(M.rows,C[b.kind],b.part,nil,nil,ownedOf)
        publish(b.rec,text);b.last_text=text;b.echo=text;b.echo_at=host.time.now()
        M.persist_cursor+=1;if M.persist_cursor>#banks then M.persist_cursor=nil end
    else for _,b in ipairs(banks) do
        local text=host.state.get(M.root.."/"..b.rec.key) or b.rec.default
        -- State reads come from one snapshot per tick, so a bank this programmer just wrote reads back its previous
        -- text for a while. Wait for the echo, or 2 s, before taking a difference as an outside change: decoding the
        -- stale text would put the previous look back into that partition.
        if b.echo then
            if text==b.echo or host.time.now()-b.echo_at>2 then b.echo=nil else text=b.last_text end
        end
        if b.last_text~=text and not decoded then
            Codec.unpack(text,M.rows,C[b.kind],b.part,C.attributes,b.kind)
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
