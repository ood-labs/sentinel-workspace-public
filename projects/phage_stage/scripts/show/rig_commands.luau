--!strict
-- Small shared automation seam; same operations as the desktop and Push 2.
return function(host,get)
local C=get("attribute_catalog")
local Codec=require("@show/rig_codec")
local M={last=""}
function M.bind(root)
    host.state.register("rig_command","")
    host.state.register("rig_command_ack","")
    M.last=host.state.get(root.."/rig_command") or ""
end
-- One code path for automation strings and the DESK view: args[1] is the caller's id.
function M.execute(rig,args)
    return pcall(function()
        if args[2]=="tempo" then
            local T=get("transport_keys");local op=args[3]
            local actions={tap=T.tap,play=T.play,sync=T.sync,stop=T.stop_transport}
            if actions[op] then local ok,err=actions[op]();if not ok then error(err,0) end
            elseif op=="pause" then assert(host.tempo.pause(),"Pause failed")
            elseif op=="start" then assert(host.tempo.start(),"Start failed")
            elseif op=="bpm" then assert(host.tempo.set_bpm(assert(tonumber(args[4]),"BPM must be a number")),"BPM write failed")
            else error("Unknown tempo command") end
        elseif args[2]=="momentary" then
            assert(args[3]=="blackout" or args[3]=="strobe","Unknown momentary effect")
            get("side_fx").set(if args[3]=="blackout" then 0 else 1,args[4]=="1")
        elseif args[2]=="select" then rig.select(string.split(args[3] or "",","),args[4]=="toggle")
        elseif args[2]=="pads" then
            -- The Push pad page (Octave Up / Down): 1 looks (STATIC / EFFECTS / COLOR / FULL), 2 the Halo Beams (MOVE /
            -- BEAM / HALO / HALO BEAMS), 3 the Linear Strobes (TUBE / PLATES / STROBES), 4 the Pixel Battens (PIXELS /
            -- CHASE / BATTENS).
            local ui=get("programmer_surface");ui.set_page(assert(tonumber(args[3]),"Pad page must be 1-4"));ui.lights()
        elseif args[2]=="bank" then
            -- The knob bank the Push shows: its number or id (position, levels, color, movement, chase, look, strobe).
            local n=tonumber(args[3])
            if not n then for i,b in ipairs(C.banks) do if b.id==args[3] then n=i end end end
            assert(n and C.banks[n],"Unknown knob bank")
            rig.editor_bank.value=n
        elseif args[2]=="name" then
            -- Name a fixture pad: name|<bank>|<slot>|<text>. An empty text drops the stored name, back to the
            -- generated title (or none).
            assert(rig.FX_FAMILIES[args[3]]~=nil,"Unknown fixture bank")
            local slot=assert(tonumber(args[4]),"Slot must be a number")
            assert(slot>=1 and slot<=16 and slot%1==0,"Slot out of range")
            local text=string.upper(string.sub(string.gsub(args[5] or "","[;=]",""),1,16))   -- names travel as k=v;k=v
            rig.fx_names[args[3].." "..slot]=if text~="" then text else nil
            rig.publish_fx_names()
        elseif args[2]=="encoder" then
            assert(C.attributes[args[3]]~=nil,"Unknown attribute")
            rig.request("encoder",{attribute=args[3],value=assert(tonumber(args[4])),absolute=args[5]=="absolute",discrete=true})
        elseif args[2]=="preset" then
            assert(table.find({"static","effects","color","rhythm","complete"},args[4]) or rig.FX_FAMILIES[args[4]]~=nil,"Unknown preset bank")
            rig.preset_kind=args[4];rig.mask=args[6] or "all"
            rig.mode=if args[3]=="store" then "store" else ""
            local slot=assert(tonumber(args[5]))
            assert(slot>=1 and slot<=16 and slot%1==0,"Slot out of range")
            rig.recall(slot)
        elseif args[2]=="rows" then
            -- Paste one packed partition into the live programmer (undoable, not stored); a partition packed before the
            -- layers existed (32 base rows) gains them as a stored bank does.
            assert(args[3]=="static" or args[3]=="effects","Unknown row kind")
            local bank=assert(tonumber(args[4]));assert(bank>=0 and bank<rig.bank_count and bank%1==0,"Bank out of range")
            rig.remember()
            Codec.unpack(args[5] or "",rig.rows,C[args[3]],rig.partitions[bank],C.attributes,args[3])
            rig.save_live()
        elseif args[2]=="camera" then
            -- Same as the Push 2 arrows / GLOBAL camera buttons: <up|down|left|right|in|out|home>, time, save, reset.
            local Cam=get("camera_orbit")
            if args[3]=="time" then Cam.step_time() elseif args[3]=="save" then Cam.save() elseif args[3]=="reset" then Cam.reset() else
                assert(table.find({"up","down","left","right","in","out","home"},args[3]),"Unknown camera command")
                Cam.step(args[3])
            end
        elseif args[2]=="group" then
            local slot=assert(tonumber(args[3]));assert(slot>=1 and slot<=8)
            rig.store_group(slot,args[4] or "Group "..slot)
        elseif table.find({"undo","reset_selected","release"},args[2]) then rig.request(args[2])
        else error("Unknown rig command") end
    end)
end
function M.service(rig)
    local text=host.state.get(rig.root.."/rig_command") or ""
    if text==M.last or text=="" then return end
    M.last=text
    local args=string.split(text,"|")
    local ok,err=M.execute(rig,args)
    host.state.set(rig.root.."/rig_command_ack",args[1]..":"..(if ok then "accepted" else tostring(err)))
end
return M
end
