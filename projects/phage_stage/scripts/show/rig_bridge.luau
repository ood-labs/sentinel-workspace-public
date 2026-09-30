--!strict
-- The programmer's only way into the graph. Program rows go out in bounded batches and commit
-- together; the Show gets the strobe clock, palettes, rhythm lanes and the BUILD origin; the
-- Lighting canvas and this programmer mirror each other's selection; GLOBAL drives the renderer.
return function(host,get)
local B={sent={},queue={},cursor=1,revision=-1,selection="",selection_revision=0,viewport_revision=nil,recall_serial=0}
local C=get("attribute_catalog")
local fields=C.fields
local PROGRAM,SHOW,LIGHTING,RENDERER,KINETICS="Phage_Program","Phage_Show","Phage_Lighting","Phage_Renderer","Phage_Kinetics"
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
    -- A newer combined look supersedes an unfinished upload. Already written
    -- parameter values stay staged until the newest complete revision commits.
    if B.revision~=rig.revision and B.cursor<=#B.queue then B.queue={};B.cursor=1 end
    if B.revision~=rig.revision and B.cursor>#B.queue then
        if B.build_revision~=rig.revision then B.build_revision=rig.revision;B.build_cursor=1;B.build_queue={} end
        for i=B.build_cursor,math.min(B.build_cursor+95,#rig.rows) do local row=rig.rows[i];for _,key in ipairs(fields) do
            local name="f"..(i-1).."_"..key;local p=path(PROGRAM,name)
            if B.sent[p]~=row[key] then table.insert(B.build_queue,{name,row[key]}) end
        end end
        B.build_cursor+=96
        if B.build_cursor>#rig.rows then B.queue=B.build_queue;B.cursor=1;B.revision=rig.revision;B.build_revision=nil end
    end
    local budget=96
    while B.cursor<=#B.queue and budget>0 do
        local item=B.queue[B.cursor]
        if not write(PROGRAM,item[1],item[2]) then return end
        B.cursor+=1;budget-=1
    end
    if B.cursor>#B.queue and B.revision==rig.revision and B.revision>=0 then
        if B.applied_revision~=B.revision then
            if not write(PROGRAM,"commit_revision",math.floor(host.time.now()*1000)%10000000) then return end
            B.applied_revision=B.revision
        end
        write(SHOW,"native_control",1)
        -- The programmer owns the truss once it is live; Demo / Manual stay one Properties click away.
        if not B.engaged then B.engaged=true;host.sentinel.set(path(KINETICS,"drive"),0) end
    end
    rig.fast_pending=B.revision~=rig.revision or B.cursor<=#B.queue
    local global=get("page:global")
    local function value(r) return tonumber(host.state.get(rig.root.."/"..r.key)) or r.value or r.default end
    local side=get("side_fx")
    write(SHOW,"global_strobe",side.strobe)
    write(SHOW,"blackout",global.blackout or side.blackout)
    write(PROGRAM,"master",value(global.params[1])*value(rig.master));write(PROGRAM,"pitch",value(rig.pitch))
    for i=2,8 do
        local r=global.params[i];local key=string.sub(r.key,8)
        write(RENDERER,if key=="sensor_white_response" then "sensor_response" else key,value(r))
    end
    if B.revision~=rig.revision or B.cursor<=#B.queue or (rig.job and (rig.job.kind=="complete" or rig.job.kind=="color") and not rig.job.store) then return end
    -- BUILD restarts on the next beat after the latest effects / full-look recall. The write is
    -- kept pending until the host accepts it, so a busy frame cannot silently drop a build.
    if (rig.recall_serial or 0)~=B.recall_serial then
        B.recall_serial=rig.recall_serial or 0
        if rig.recall_kind=="effects" or rig.recall_kind=="complete" then
            B.build_origin=math.max(0,math.ceil(tonumber(host.tempo.status().beat) or 0))
        end
    end
    if B.build_origin and write(SHOW,"build_origin",B.build_origin) then B.build_origin=nil end
    for key,r in pairs(rig.strobe) do write(SHOW,key,value(r)) end
    -- REPEAT lanes run on the GPU from the Clock (Show lane_source Internal); a STEPS lane needs
    -- the sequencer, so then all three lanes come from here (Surface).
    local rhythm=get("rhythm")
    local steps=false
    for i,lane in ipairs(rhythm.lanes) do
        write(SHOW,"lane"..i.."_cycle",value(lane.cycle));write(SHOW,"lane"..i.."_rest",value(lane.rest))
        write(SHOW,"lane"..i.."_offset",value(lane.offset))
        if value(lane.mode)>.5 then steps=true end
    end
    write(SHOW,"lane_source",if steps then 1 else 0)
    if steps then for i,lane in ipairs(rhythm.lanes) do
        write(SHOW,"lane"..i.."_phase",lane.phase)
        write(SHOW,"lane"..i.."_active",if lane.active then 1 else 0)
        write(SHOW,"lane"..i.."_trigger",lane.trigger)
        write(SHOW,"lane"..i.."_envelope",if lane.active then 1-lane.phase else 0)
    end end
    local color=get("page:color");local pal=math.floor(value(color.params[1]))
    for _,key in ipairs({"a","b","c"}) do
        local rgb=tonumber(host.state.get(rig.root.."/pal"..pal..key))
        if rgb then write(SHOW,"palette_"..key,rgb) end
    end
    -- Canvas -> programmer: a new canvas gesture replaces the programmer selection.
    local seq=read(LIGHTING,"selection_sequence")
    if seq and seq~=B.viewport_revision then
        local ids={};local valid=true
        for w=0,15 do
            local bits=read(LIGHTING,"selection_word"..w)
            if not bits then valid=false;break end
            for bit=0,15 do if bit32.band(math.floor(bits+.5),bit32.lshift(1,bit))~=0 then table.insert(ids,tostring(w*16+bit)) end end
        end
        if valid then local previous=B.viewport_revision;B.viewport_revision=seq;if previous~=nil and seq>0 then rig.select(ids) end end
    end
    -- Programmer -> canvas.
    local signature=table.concat(rig.status.selection,",")
    if B.selection~=signature then
        local words={};for w=1,16 do words[w]=0 end
        for _,id in ipairs(rig.status.selection) do local i=tonumber(id);if i<256 then local w=math.floor(i/16)+1;words[w]+=2^(i%16) end end
        for w=0,15 do if not write(LIGHTING,"remote_selection"..w,words[w+1]) then return end end
        B.selection_revision=math.floor(host.time.now()*1000)%10000000
        if not write(LIGHTING,"selection_apply",B.selection_revision) then return end
        B.selection=signature
    end
end
return B
end
