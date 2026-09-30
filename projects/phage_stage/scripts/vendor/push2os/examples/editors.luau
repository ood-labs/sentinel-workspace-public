--!strict
-- Public grid/list example derived from the executing Runtime root.
local Runtime=require("@push2os/runtime")
local root="/ctrl/script/00_editor_probe"
local function pageFactory(mode: string)
    return function(api: any)
        local items={}
        if mode=="grid" then
            for i=1,12 do items[i]={id="choice_"..i,label=string.format("%02d",i),value=i} end
        else
            for i,label in ipairs({"SLOW","STEADY","FAST","BURST","REST"}) do
                items[i]={id="choice_"..i,label=label,value=i}
            end
        end
        local selected={id="selection",state_path=mode.."_selection",persist="state",default=1,min=1,max=#items,value=1}
        local selections=0
        local editor=api.editor.new({id=mode.."_editor",mode=mode,items=items,rows=3,
            bounds={x=120,y=18,w=118,h=84},selected_id="choice_1",
            on_select=function(_,value)
                selected.value=value
                state.set(root.."/"..mode.."_selection",value)
                selections+=1
                state.set(root.."/"..mode.."_commits",selections)
            end})
        local function publish()
            local info=editor.status()
            state.set(root.."/"..mode.."_first",info.first)
            state.set(root.."/"..mode.."_last",info.last)
            state.set(root.."/"..mode.."_focus",info.focus_id)
        end
        return {id=mode,label=string.upper(mode),records={selected},
            top_labels={"","COMMIT","MENU"},
            top={{},
                {kind="trigger",on_press=function() editor.commit();publish() end},
                {kind="menu",menu={title="SPEED",items={
                    {label="SLOW",on_select=function() state.set(root.."/menu_choice",1) end},
                    {label="FAST",on_select=function() state.set(root.."/menu_choice",2) end}}}}},
            on_bind=function()
                for key,value in pairs({[mode.."_first"]=1,[mode.."_last"]=0,[mode.."_focus"]="",
                    [mode.."_commits"]=0,menu_choice=0}) do state.register(key,value) end
                editor.focus("choice_"..selected.value)
                publish()
            end,
            on_encoder=function(slot: number,delta: number)
                if slot==1 then editor.move(delta);publish() end
            end,
            render=function(ctx: any)
                editor.selected("choice_"..selected.value)
                editor.render()
                api.conventions.text(255,ctx.cy+10,if mode=="grid" then "12 CHOICES / 9 VISIBLE" else "SPEED LIST / 3 VISIBLE",20,0x85DCC4)
                api.conventions.text(255,ctx.cy+40,"ENCODER 2: BROWSE   TOP 2: COMMIT",14,0xD0D0CE)
                api.conventions.text(255,ctx.cy+64,"BROWSING LEAVES SELECTION UNCHANGED",12,0x959593)
                api.conventions.text(126,110,"SELECTED "..selected.value,12,0xE0E8F0)
            end,
        }
    end
end
local runtime=Runtime.create({id="editor-probe",root=root,midi_output_port="Ableton Push 2 1",
    persistence={group="new_editor_probe",preset="current",schema_version=1,new_empty=true},
    pages={pageFactory("grid"),pageFactory("list")}},
    Runtime.native({surface=surface,display=display,state=state,midi=midi,preset=preset,sentinel=sentinel,log=log}))
assert(runtime.ok,runtime.code)
return runtime.callbacks
