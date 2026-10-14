--!strict
-- Isolated host fault diagnostic, not the full public Runtime example.
local Session=require("@push2os/session")
local root="/ctrl/script/01_native_frames"
local composed=Session.compose({id="native-frames",root=root,midi_output_port="Ableton Push 2 1",
    persistence={group="native_frames",preset="current",schema_version=1},
    pages={function() return {id="probe",render=function() end} end},
},{display=display})
assert(composed.ok)
local C=composed.api.conventions
local token=0
local elapsed=0
return {
    on_start=function()
        local claimed=surface.claim()
        assert(claimed.ok,claimed.code)
        token=claimed.token
        state.register("fault",0)
        state.register("variant",0)
    end,
    on_tick=function(dt: number)
        elapsed+=dt
        if elapsed<1/60 then return end
        elapsed%=1/60
        local fault=state.get(root.."/fault")
        local variant=state.get(root.."/variant")
        assert(display.begin_frame(0x101014))
        if fault==1 then return end
        if fault==4 then while true do end end
        if fault==6 then error("injected after clear") end
        display.rect(0,0,960,18,0x802020,true)
        C.text(8,2,"PARTIAL FRAME MUST NEVER REACH USB",12,0xFFFFFF)
        if fault==2 then return end
        if fault==3 then
            local ok=pcall(function() error("caught page error") end)
            assert(not ok)
            assert(display.abort_frame())
            return
        end
        if fault==5 then while true do end end
        if fault==7 then error("injected after partial drawing") end
        if fault==8 then display.complete_frame();error("injected after complete") end
        if fault==9 then display.release();return end
        -- Clear within an explicit transaction discards partial work.
        display.clear(0x101014)
        local color=if variant==0 then 0x275A48 else 0x284878
        display.rect(0,0,960,18,color,true)
        display.rect(0,144,960,16,color,true)
        C.text(8,35,if variant==0 then "COMPLETE FRAME A" else "COMPLETE FRAME B",24,0xFFFFFF)
        C.text(8,88,"NATIVE TRANSACTION / SUCCESSFUL USB SEND PROOF",14,0x80C8B8)
        assert(display.complete_frame())
    end,
    on_stop=function() if token~=0 then surface.stop(token);token=0 end end,
}
