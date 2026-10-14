--!strict
-- SS_Desk Module panel: the looks and the programmer without a Push 2. Clicks and fader moves arrive as `panel` Event
-- records and run through the rig_commands seam or the programmer (static_rig); state, value and colour feedback goes
-- back on `desk_feedback`, text through panel.label.
-- Panel records: event_type 1 press, 2 release, 3 value; payload {control_index, value, value2}.
-- Feedback records: 10 lit, 11 value, 12 colour {i, r, g, b}, 13 state {i, state}.
--
-- Programming: click fixtures on the map (each click toggles one) or a group (it replaces the selection), narrow it to
-- one layer if needed (MOVE, BEAM, HALO...), pick an attribute bank and drag the faders. A continuous fader moves every
-- selected fixture by the same amount (a fan stays a fan); a stepped one (lanes, palettes, looks) sets them all to the
-- step under the cap. STORE arms, and the next look pad stores the programmer into that pad: STATIC, EFFECTS and COLOR
-- keep the selected fixtures' part (the whole rig when nothing is selected), FULL everything, a sequence its types'.
return function(host,get)
local Layout=require("@show/desk_layout")
local Titles: any=require("@show/preset_titles")
local RigLayout=require("@show/rig_layout")
local C=get("attribute_catalog")
local PRESS,RELEASE,VALUE=1,2,3
local LIT,FVALUE,COLOUR,STATE=10,11,12,13
local EMPTY,LOADED,ACTIVE,SELECTED=0,1,2,3
local M={desk="",sent={},labels={},refresh=0,held={},labels_ok=true,seq_kind="sequence",armed=false,highlight=false,drag={},shown={},
    error=nil,cache_key="",cache={}}
local index={}
for i,c in pairs(Layout) do index[c.id]=i end
M.index=index
local SEQ_KINDS={rig="sequence",beams="seq_heads",strobes="seq_strobes",battens="seq_battens"}
local SEQ_NAMES={sequence="RIG",seq_heads="BEAMS",seq_strobes="STROBES",seq_battens="BATTENS"}
local LAYER_KIND={move=0,beam=4,halo=5,tube=1,plates=6,pixels=2,chase=7}
local LAYER_NAME={[0]="MOVE",[4]="BEAM",[5]="HALO",[1]="TUBE",[6]="PLATES",[2]="PIXELS",[7]="CHASE"}
-- Strobe-clock bank captions: the clock's own names for the shared fields (attribute_editor's).
local CLOCK_CAPTION={width="BURST",spread="STAGGER"}
-- HIGHLIGHT is SS_Lighting's own: the selected fixtures at full open white while it is on, whatever the look.
local LIGHTING="/sentinel/pipelines/SS_Lighting/parameters/"
local function run(...: string): (boolean,any)
    return get("rig_commands").execute(get("static_rig"),{"desk",...})
end
-- The desk pipeline sits beside the Surface: <show>_Surface -> <show>_Desk.
function M.bind(root: string)
    local surface=string.match(root,"/sentinel/pipelines/([^/]+)/state") or "SS_Surface"
    M.desk=string.gsub(surface,"_Surface$","_Desk")
end

-- Each fixture slot's program rows (row ids), and its short name on the map.
local ROWS_OF: {[string]: {string}}={}
local SHORT: {[string]: string}={}
local function fixtureRows(rig: any)
    if next(ROWS_OF) then return end
    for _,L in ipairs(rig.row_list) do ROWS_OF[L.slot]=ROWS_OF[L.slot] or {};table.insert(ROWS_OF[L.slot],L.id) end
    for _,c in pairs(Layout) do
        local slot=string.match(c.id,"^fx_(%d+)$");if slot then SHORT[slot]=c.label end
    end
end

-- --- faders ----------------------------------------------------------------------------------------------------------
-- The bank's attributes the selection carries, packed left (the Push's knobs, attribute_editor); with nothing selected,
-- the bank's own list, dead.
local function faderKeys(): ({string},any)
    local A=get("attribute_editor");local rig=get("static_rig")
    local bank=A.bank();local keys={}
    for _,k in ipairs(bank.attributes) do
        if #rig.status.selection==0 or A.count(k)>0 then table.insert(keys,k) end
    end
    return keys,bank
end
-- A stepped attribute's positions in fader order: a LOOK knob's musical order, else its choices 0..n-1.
local function positions(a: any): {number}?
    if a.sequence then return a.sequence end
    if a.choices then local t={};for v=0,#a.choices-1 do table.insert(t,v) end;return t end
    return nil
end
local function number(a: any,v: number): string
    if a.unit=="ratio" or a.unit=="cycle" then return string.format("%d%%",math.floor(v*100+.5)) end
    if a.unit=="rate" then return string.format("%.2gx",v) end
    return string.format("%.1f",v)
end
-- Where a fader sits for the selection (0..1), what its value reads, and whether it can program anything.
local function faderState(key: string): (number,string,boolean)
    local rig=get("static_rig");local A=get("attribute_editor")
    local a=C.attributes[key]
    if #rig.status.selection==0 or A.count(key)==0 then return 0,"--",false end
    local lo,hi=rig.range(key)
    if lo==nil or hi==nil then return 0,"--",false end
    local pos=positions(a)
    if pos then
        local k=table.find(pos,math.floor(lo+.5)) or 1
        return (k-1)/math.max(1,#pos-1),if math.abs(lo-hi)>.01 then "MIXED" else A.choice(key,a,lo),true
    end
    local text=if math.abs(lo-hi)<.005*(a.max-a.min) then number(a,lo) else number(a,lo)..".."..number(a,hi)
    return math.clamp(((lo+hi)/2-a.min)/(a.max-a.min),0,1),text,true
end
local function onFader(slot: number,v: number)
    local keys=faderKeys();local key=keys[slot]
    local rig=get("static_rig")
    if not key then return end
    if #rig.status.selection==0 then rig.message="Select fixtures first: click them on the map or pick a group";return end
    local a=C.attributes[key]
    v=math.clamp(v,0,1)
    local pos=positions(a)
    local gesture="desk:"..key
    if pos then
        local code=pos[math.clamp(math.floor(v*(#pos-1)+.5),0,#pos-1)+1]
        local lo,hi=rig.range(key)
        if lo==nil or hi==nil or math.abs(lo-code)>.01 or math.abs(hi-code)>.01 then
            rig.request("set",{attribute=key,value=code,absolute=true,gesture=gesture})
        end
    else
        -- A continuous fader moves the selection by the fader's travel: the same delta on every fixture.
        local now=host.time.now();local d=M.drag[slot]
        local last=if d and d.key==key and now-d.t<.5 then d.v else M.shown[slot]
        M.drag[slot]={v=v,t=now,key=key}
        if last==nil then return end
        local delta=(v-last)*(a.max-a.min)
        if math.abs(delta)<1e-6 then return end
        if rig.strobe[key] then
            rig.request("set",{attribute=key,value=a.min+v*(a.max-a.min),absolute=true,gesture=gesture})
        else
            rig.request("offset",{attribute=key,value=delta,gesture=gesture})
        end
    end
    local _,text=faderState(key)
    rig.message=a.label.." "..text
end

-- --- selection -------------------------------------------------------------------------------------------------------
local function layerFilter(name: string)
    local rig=get("static_rig");fixtureRows(rig)
    local fixtures=rig.status.fixtures or {}
    local ids={}
    if name=="all" then
        for _,slot in ipairs(fixtures) do table.insert(ids,slot) end
        rig.select(ids,false)
        rig.message=if #ids>0 then "Whole fixtures: every layer" else "Nothing selected"
        return
    end
    local kind=LAYER_KIND[name]
    local have={};for _,slot in ipairs(fixtures) do have[slot]=true end
    for _,L in ipairs(rig.row_list) do
        if L.kind==kind and (#fixtures==0 or have[L.slot]) and rig.active_fixture(rig.fixtures[L.fixture]) then
            table.insert(ids,L.id)
        end
    end
    if #ids==0 then rig.message="The selection has no "..LAYER_NAME[kind].." layer";return end
    rig.select(ids,false)
    rig.message=LAYER_NAME[kind].." layer of "..(if #fixtures>0 then #fixtures.." fixtures" else "every fixture")
end

-- --- looks and STORE ---------------------------------------------------------------------------------------------------
local function look(kind: string,slot: string)
    local rig=get("static_rig")
    if M.armed then
        M.armed=false
        -- STATIC, EFFECTS and COLOR keep the selected fixtures' part: with nothing selected, the whole rig's.
        if #rig.status.selection==0 and (kind=="static" or kind=="effects" or kind=="color") then rig.select({"all"},false) end
        local ok,err=run("preset","store",kind,slot)
        M.error=if ok then nil else tostring(err)
        return
    end
    local ok,err=run("preset","recall",kind,slot)
    M.error=if ok then nil else tostring(err)
end

local function act(name: string)
    local rig=get("static_rig")
    if name=="store" then
        M.armed=not M.armed
        rig.message=if M.armed then "STORE: press the look pad to store into" else "Store cancelled"
    elseif name=="update" then rig.request("update")
    elseif name=="undo" then rig.request("undo");rig.message="UNDO"
    elseif name=="reset" then
        if #rig.status.selection==0 then rig.message="RESET: select the fixtures to put back";return end
        rig.request("reset_selected");rig.message="RESET: selected fixtures back to the look"
    elseif name=="fxoff" then
        if #rig.status.selection==0 then rig.message="FX OFF: select the fixtures to stop";return end
        rig.clear_effects()
    elseif name=="release" then rig.request("release");rig.message="RELEASE: the programmer back to the last look"
    elseif name=="highlight" then
        M.highlight=not M.highlight
        host.sentinel.set(LIGHTING.."highlight",M.highlight)
        rig.message=if M.highlight then "HIGHLIGHT: the selected fixtures at full white" else "HIGHLIGHT off"
    end
end

function M.handle(records: {any})
    for _,r in ipairs(records) do
        local i=r.payload and r.payload[1]
        local c=i and Layout[math.floor(i+.5)]
        if c and c.action then
            local a=c.action;local down=r.event_type==PRESS
            if a[1]=="fader" then
                if r.event_type==VALUE then onFader(tonumber(a[2]) or 1,tonumber(r.payload[2]) or 0) end
            elseif a[1]=="hold" then
                if down or r.event_type==RELEASE then
                    M.held[c.id]=down or nil
                    run("momentary",a[2],if down then "1" else "0")
                end
            elseif down then
                local rig=get("static_rig")
                local ok,err=true,nil
                if a[1]=="preset" then look(a[2],a[3])
                elseif a[1]=="seqpad" then look(M.seq_kind,a[2])
                elseif a[1]=="seqkind" then M.seq_kind=SEQ_KINDS[a[2]] or "sequence";rig.message="SEQUENCES play on "..SEQ_NAMES[M.seq_kind]
                elseif a[1]=="fixture" then rig.select({a[2]},true)
                elseif a[1]=="group" then
                    if a[2]=="none" then rig.select({},false) else rig.select({a[2]},false) end
                elseif a[1]=="layer" then layerFilter(a[2])
                elseif a[1]=="bank" then ok,err=run("bank",a[2]);M.drag={}
                elseif a[1]=="act" then act(a[2])
                else ok,err=run(table.unpack(a)) end
                M.error=if ok then M.error else tostring(err)
                if ok and a[1]~="preset" and a[1]~="seqpad" then M.error=nil end
            end
        end
    end
end

-- --- feedback ----------------------------------------------------------------------------------------------------------
local function rgb(packed: number?): (number,number,number)
    local v=math.floor(packed or 0)
    return bit32.extract(v,16,8)/255,bit32.extract(v,8,8)/255,bit32.extract(v,0,8)/255
end
-- The colour a fixture's programmed palette slot plays in the palette that is up.
local function fixtureColour(rig: any,f: any,pal: number): (number,number,number)
    local i=tonumber(f.id)::number
    local row=if f.kind==0 then rig.rows[RigLayout.BEAM0+i+1] elseif f.kind==1 then rig.rows[RigLayout.LAYER2+i+1] else rig.rows[i+1]
    local slot=math.clamp(math.floor((row and row.beam_palette or 0)+.5),0,2)
    return rgb(tonumber(host.state.get(rig.root.."/pal"..pal..({"a","b","c"})[slot+1])))
end
-- The selection-dependent part (fixtures, groups, layers, banks, faders), rebuilt only when the programmer changes.
local function selectionFeedback(rig: any,want: any,set: any)
    fixtureRows(rig)
    local A=get("attribute_editor")
    local color=get("page:color")
    local pal=math.floor(tonumber(host.state.get(rig.root.."/"..color.params[1].key)) or color.params[1].value or 0)
    local key=rig.revision..":"..pal..":"..(rig.editor_bank.value or 1)
    if key~=M.cache_key then
        M.cache_key=key
        local cache={}
        local selected=rig.selection
        local kinds={};local nsel=0
        for _,id in ipairs(rig.status.selection) do
            nsel+=1;local L=rig.row_list[(tonumber(id)::number)+1];if L then kinds[L.kind]=true end
        end
        for _,f in ipairs(rig.fixtures) do
            local i=index["fx_"..f.id]
            if i then
                local rows=ROWS_OF[f.id] or {};local n=0
                for _,id in ipairs(rows) do if selected[id] then n+=1 end end
                local state=if not rig.active_fixture(f) then EMPTY elseif n==0 then LOADED elseif n==#rows then ACTIVE else SELECTED
                local r,g,b=fixtureColour(rig,f,pal)
                cache[i]={[STATE]=state,[COLOUR]={r,g,b}}
            end
        end
        for _,c in pairs(Layout) do
            local a=c.action;local i=index[c.id]
            if a and a[1]=="group" then
                local on=if a[2]=="none" then nsel==0 else rig.selected(a[2])
                cache[i]={[STATE]=if on then ACTIVE else LOADED}
            elseif a and a[1]=="layer" then
                local only=nil
                if a[2]~="all" then only=LAYER_KIND[a[2]] end
                local on=false
                if nsel>0 then
                    if only==nil then
                        -- whole fixtures: every selected fixture has all of its layers selected
                        on=true
                        for _,slot in ipairs(rig.status.fixtures or {}) do
                            for _,id in ipairs(ROWS_OF[slot] or {}) do if not selected[id] then on=false end end
                        end
                    else
                        on=kinds[only]==true;for k in pairs(kinds) do if k~=only then on=false end end
                    end
                end
                cache[i]={[STATE]=if on then ACTIVE else LOADED}
            end
        end
        local current=A.bank()
        for n,b in ipairs(C.banks) do
            local live=nsel==0
            for _,k in ipairs(b.attributes) do if A.count(k)>0 then live=true end end
            cache[index["bank_"..n]]={[STATE]=if b.id==current.id then ACTIVE elseif live then LOADED else EMPTY}
        end
        local keys=faderKeys()
        local captions,values={},{}
        for slot=1,8 do
            local k=keys[slot]
            local pos,text,ok=0,"--",false
            if k then pos,text,ok=faderState(k) end
            M.shown[slot]=if ok then pos else nil
            cache[index["fader_"..slot]]={[STATE]=if ok then LOADED else EMPTY,[FVALUE]=math.floor(pos*1000+.5)/1000}
            local a=k and C.attributes[k]
            captions[slot]=if a then (if current.id=="strobe" and CLOCK_CAPTION[k] then CLOCK_CAPTION[k] else a.label) else ""
            values[slot]=text
        end
        M.cache={feedback=cache,captions=captions,values=values}
    end
    for i,kinds in pairs(M.cache.feedback) do want[i]=kinds end
end
-- Desired per-control feedback, from the same state the Push shows.
function M.desired(): {[number]: {[number]: any}}
    local rig=get("static_rig");local fx=get("side_fx");local t=host.tempo.status()
    local want={}
    local function set(id,kind,value) local i=index[id];if i then want[i]=want[i] or {};want[i][kind]=value end end
    for _,c in pairs(Layout) do
        local a=c.action
        if a and (a[1]=="preset" or a[1]=="seqpad") then
            local kind=if a[1]=="seqpad" then M.seq_kind else a[2]
            local slot=if a[1]=="seqpad" then a[2] else a[3]
            set(c.id,STATE,if rig.is_lit(kind,tonumber(slot)) then ACTIVE elseif M.armed then SELECTED else LOADED)
        end
    end
    for cid,kind in pairs(SEQ_KINDS) do
        local any=false
        for slot=1,16 do if rig.is_lit(kind,slot) then any=true;break end end
        set("seqk_"..cid,STATE,if kind==M.seq_kind then ACTIVE else LOADED)
        set("seqk_"..cid,LIT,if any then 1 else 0)
    end
    set("play",STATE,if t.running then ACTIVE else LOADED)
    set("tap",LIT,if t.running and t.beat_phase<.15 then 1 else 0)
    set("blackout",STATE,if fx.blackout then ACTIVE else LOADED)
    set("strobe",STATE,if fx.strobe then ACTIVE else LOADED)
    set("act_store",STATE,if M.armed then ACTIVE else LOADED)
    set("act_undo",STATE,if rig.status.undo_available then LOADED else EMPTY)
    set("act_highlight",STATE,if M.highlight then ACTIVE else LOADED)
    selectionFeedback(rig,want,set)
    return want
end
-- The sequence that is up: "SCAN", or each type's when they differ ("BEAMS SCAN + BATTENS FALL").
local function seqLive(rig: any): string
    local parts={}
    for _,kind in ipairs(rig.FX_ORDER) do
        for slot=1,16 do if rig.is_lit(kind,slot) then
            local name=rig.fx_names[kind.." "..slot] or (Titles[kind] and Titles[kind][slot]) or ("SLOT "..slot)
            table.insert(parts,(if kind=="sequence" then "" else SEQ_NAMES[kind].." ")..name)
        end end
    end
    return if #parts>0 then string.sub(table.concat(parts," + "),1,40) else "none"
end
local function selectionText(rig: any): string
    local fixtures=rig.status.fixtures or {}
    if #fixtures==0 then return "NOTHING SELECTED" end
    local names={}
    for n,slot in ipairs(fixtures) do if n<=8 then table.insert(names,SHORT[slot] or slot) end end
    local text=#fixtures.." SELECTED  "..table.concat(names," ")..(if #fixtures>8 then " +"..(#fixtures-8) else "")
    local kinds={};local seen={}
    for _,id in ipairs(rig.status.selection) do
        local L=rig.row_list[(tonumber(id)::number)+1]
        if L and not seen[L.kind] then seen[L.kind]=true;table.insert(kinds,LAYER_NAME[L.kind]) end
    end
    -- a layer filter shows which layers are in play
    local whole=true
    for _,slot in ipairs(fixtures) do for _,id in ipairs(ROWS_OF[slot] or {}) do if not rig.selection[id] then whole=false end end end
    if not whole then text..="  ("..table.concat(kinds,"+")..")" end
    return string.sub(text,1,62)
end
function M.labels_now(): {[string]: string}
    local t=host.tempo.status();local rig=get("static_rig")
    local message=if M.error then "ERROR: "..M.error elseif M.armed then "STORE ARMED: press the look pad to store into" else (rig.message or "")
    local out={bpm=string.format("%.1f BPM",t.bpm),
        beat=string.format("BAR %d BEAT %d",math.floor(t.bar)+1,math.floor(t.beat%t.beats_per_bar)+1),
        status=string.upper(string.sub(message,1,62)),play=if t.running then "PAUSE" else "PLAY",
        seq_live=seqLive(rig),sel_info=selectionText(rig)}
    local cache=M.cache
    if cache.captions then
        for slot=1,8 do out["fcap_"..slot]=cache.captions[slot];out["fval_"..slot]=cache.values[slot] end
    end
    -- the sequence pads carry the names of the kind they play (an operator's stored name wins)
    for slot=1,16 do
        local name=rig.fx_names[M.seq_kind.." "..slot] or (Titles[M.seq_kind] and Titles[M.seq_kind][slot])
        if name then out["seq_"..slot]=name end
    end
    return out
end
-- Emit only changes; resend everything every 2 s so a reloaded Module relights.
function M.feedback(out: any,dt: number)
    M.refresh+=dt
    local full=M.refresh>2
    if full then M.refresh=0;M.labels={};M.cache_key="" end
    for i,kinds in pairs(M.desired()) do
        M.sent[i]=M.sent[i] or {}
        for kind,value in pairs(kinds) do
            local sig=if typeof(value)=="table" then table.concat(value,",") else value
            if full or M.sent[i][kind]~=sig then
                if typeof(value)=="table" then out:emit({event_type=kind,payload={i,value[1],value[2],value[3]}})
                else out:emit({event_type=kind,payload={i,value}}) end
                M.sent[i][kind]=sig
            end
        end
    end
    -- A missing or renamed desk fails every label write: retry only on the 2 s refresh, never per tick.
    if host.panel and (M.labels_ok or full) then
        M.labels_ok=true
        for id,text in pairs(M.labels_now()) do
            if M.labels[id]~=text then
                if host.panel.label(M.desk,id,text) then M.labels[id]=text else M.labels_ok=false;break end
            end
        end
    end
end
function M.service(node: any,dt: number)
    local input=node.inputs.panel
    if input then M.handle(input:read_events()) end
    local out=node.outputs.desk_feedback
    if out then M.feedback(out,dt) end
end
function M.stop()
    for id in pairs(M.held) do
        local c=Layout[index[id]];if c then run("momentary",c.action[2],"0") end
    end
    if M.highlight then host.sentinel.set(LIGHTING.."highlight",false) end
    M.held={};M.sent={};M.labels={};M.armed=false;M.highlight=false
end
return M
end
