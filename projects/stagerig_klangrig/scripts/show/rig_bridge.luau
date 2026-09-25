--!strict
return function(host,get)
local B={sent={},queue={},cursor=1,revision=-1,selection="",selection_revision=0,viewport_revision=nil}
local groupNames={"all","spine","wings","upper","lower","left","right","led","none","bay1","bay2","bay3","custom1","custom2","custom3","custom4","custom5","custom6","custom7","custom8"}
local fields={"pan","tilt","level","ring","beam_palette","ring_palette","move_lane","int_lane","color_lane","pan_amp","tilt_amp","spread","width","offset","reverse","led_pattern"}
local function path(node,key) return "/sentinel/pipelines/"..node.."/parameters/"..key end
local function write(node,key,value)
    local p=path(node,key)
    if B.sent[p]~=value then
        if host.sentinel.set(p,value)==false then return false end
        B.sent[p]=value
    end
    return true
end
local function read(node,key)
    local p="/sentinel/pipelines/"..node.."/control_outputs/"..key
    host.sentinel.subscribe(p);return tonumber(host.sentinel.get(p))
end
function B.service(rig)
    if not rig.loaded then return end
    local request=read("stagerig_klangrig_Lighting","group_request_sequence")
    if request and request~=B.group_sequence then
        local previous=B.group_sequence;B.group_sequence=request
        local index=read("stagerig_klangrig_Lighting","group_request")
        if previous~=nil and request>0 and groupNames[index] then rig.select({groupNames[index]}) end
    end
    if B.group_revision~=rig.revision then
        local mask=0
        for i,name in ipairs(groupNames) do if rig.selected(name) then mask+=2^(i-1) end end
        if #rig.status.selection==0 then mask+=2^8 end
        if not write("stagerig_klangrig_Lighting","group_selected",mask) then return end
        for i,g in ipairs(rig.custom) do
            local name=string.sub(string.upper(g.name.value or g.name.default)..string.rep(" ",12),1,12)
            for j=0,3 do
                local value=0;for c=0,2 do value+=string.byte(name,j*3+c+1)*2^(8*c) end
                if not write("stagerig_klangrig_Lighting","group_label_"..i.."_"..j,value) then return end
            end
        end
        B.group_revision=rig.revision
    end
    -- A newer combined look supersedes an unfinished upload. Already written
    -- parameter values stay staged until the newest complete revision commits.
    if B.revision~=rig.revision and B.cursor<=#B.queue then B.queue={};B.cursor=1 end
    if B.revision~=rig.revision and B.cursor>#B.queue then
        if B.build_revision~=rig.revision then B.build_revision=rig.revision;B.build_cursor=1;B.build_queue={} end
        for i=B.build_cursor,math.min(B.build_cursor+95,#rig.rows) do local row=rig.rows[i];for _,key in ipairs(fields) do
            local name="f"..(i-1).."_"..key;local p=path("stagerig_klangrig_Program",name)
            if B.sent[p]~=row[key] then table.insert(B.build_queue,{name,row[key]}) end
        end end
        B.build_cursor+=96
        if B.build_cursor>#rig.rows then B.queue=B.build_queue;B.cursor=1;B.revision=rig.revision;B.build_revision=nil end
    end
    local budget=96
    while B.cursor<=#B.queue and budget>0 do
        local item=B.queue[B.cursor]
        if not write("stagerig_klangrig_Program",item[1],item[2]) then return end
        B.cursor+=1;budget-=1
    end
    if B.cursor>#B.queue and B.revision==rig.revision and B.revision>=0 then
        if B.applied_revision~=B.revision then
            if not write("stagerig_klangrig_Program","commit_revision",math.floor(host.time.now()*1000)%10000000) then return end
            B.applied_revision=B.revision
        end
        write("stagerig_klangrig_Show","native_control",1)
    end
    rig.fast_pending=B.revision~=rig.revision or B.cursor<=#B.queue
    local global=get("page:global")
    local function value(r) return tonumber(host.state.get(rig.root.."/"..r.key)) or r.value or r.default end
    local side=get("side_fx")
    write("stagerig_klangrig_Show","global_strobe",side.strobe)
    local master=if global.blackout or side.blackout then 0 else value(global.params[1])*value(rig.master)
    write("stagerig_klangrig_Program","master",master);write("stagerig_klangrig_Program","pitch",value(rig.pitch))
    for i=2,8 do
        local r=global.params[i];local key=string.sub(r.key,8)
        write("stagerig_klangrig_Renderer",if key=="sensor_white_response" then "sensor_response" else key,value(r))
    end
    if B.revision~=rig.revision or B.cursor<=#B.queue or (rig.job and (rig.job.kind=="complete" or rig.job.kind=="color") and not rig.job.store) then return end
    local rhythm=get("rhythm")
    for key,r in pairs(rig.strobe) do write("stagerig_klangrig_LED",key,value(r)) end
    local ledLane=rhythm.lanes[math.floor(rig.rows[289].int_lane)]
    write("stagerig_klangrig_LED","strobe_cycle_beats",if ledLane then value(ledLane.cycle) else 1)
    for i,lane in ipairs(rhythm.lanes) do
        write("stagerig_klangrig_Show","lane"..i.."_phase",lane.phase)
        write("stagerig_klangrig_Show","lane"..i.."_active",if lane.active then 1 else 0)
        write("stagerig_klangrig_Show","lane"..i.."_trigger",lane.trigger)
    end
    local color=get("page:color");local pal=math.floor(value(color.params[1]))
    for _,key in ipairs({"a","b","c"}) do
        local rgb=tonumber(host.state.get(rig.root.."/pal"..pal..key))
        if rgb then write("stagerig_klangrig_Show","palette_"..key,rgb) end
    end
    local seq=read("stagerig_klangrig_Lighting","selection_sequence")
    if seq and seq~=B.viewport_revision then
        local ids={};local valid=true
        for w=0,17 do
            local bits=read("stagerig_klangrig_Lighting","selection_word"..w)
            if not bits then valid=false;break end
            for bit=0,15 do if bit32.band(math.floor(bits+.5),bit32.lshift(1,bit))~=0 then table.insert(ids,tostring(w*16+bit)) end end
        end
        if valid then local previous=B.viewport_revision;B.viewport_revision=seq;if previous~=nil and seq>0 then rig.select(ids) end end
    end
    local signature=table.concat(rig.status.selection,",")
    if B.selection~=signature then
        if not write("stagerig_klangrig_Lighting","remote_led_selection",rig.selection["288"]==true) then return end
        local words={};for w=1,18 do words[w]=0 end
        for _,id in ipairs(rig.status.selection) do local i=tonumber(id);if i<288 then local w=math.floor(i/16)+1;words[w]+=2^(i%16) end end
        for w=0,17 do if not write("stagerig_klangrig_Lighting","remote_selection"..w,words[w+1]) then return end end
        B.selection_revision=math.floor(host.time.now()*1000)%10000000
        if not write("stagerig_klangrig_Lighting","selection_apply",B.selection_revision) then return end
        B.selection=signature
    end
end
return B
end
