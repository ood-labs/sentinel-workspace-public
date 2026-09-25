--!strict
-- Derived from native_frames' explicit native-binding root; now the public Runtime owns lifecycle.
local Runtime=require("@push2os/runtime")
local root="/ctrl/script/00_runtime_probe"
local runtime:any=Runtime.create({id="runtime-probe",root=root,midi_output_port="Ableton Push 2 1",
    persistence={group="runtime_probe",preset="current",schema_version=1},
    pages={function(api: any)
        local level={id="level",key="level",label="LEVEL",min=0,max=100,default=0,
            value=0,persist="bank",sink={kind="state",path="level"},fmt="%.2f"}
        return {id="main",label="RUNTIME",params={level},top_labels={"HOLD"},
            top={{kind="momentary",label="HOLD",on_press=function() state.set(root.."/held",true) end,
                on_release=function() state.set(root.."/held",false) end}},
            on_bind=function()
                state.register("held",false)
                state.register("fault",false)
            end,
            render=function(ctx: any)
                api.conventions.text(20,ctx.cy+8,"PUBLIC RUNTIME",22,0x85DCC4)
                if state.get(root.."/fault") then error("injected public Runtime render fault") end
                api.conventions.text(20,ctx.cy+40,"RESTORED LEVEL  "..string.format("%.2f",level.value),18,0xE0E8F0)
                api.conventions.text(20,ctx.cy+65,"ENCODER 1 / TOP 1 HOLD",12,0x839CAA)
            end,
        }
    end},
},Runtime.native({surface=surface,display=display,state=state,midi=midi,preset=preset,sentinel=sentinel,log=log}))
assert(runtime.ok,runtime.code)
return runtime.callbacks
