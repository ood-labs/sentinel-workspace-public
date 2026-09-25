--!strict
-- Public construction example. Real-host execution follows after Phase 20 gates.
local Session=require("../src/session")
local config={
    id="example",root="/ctrl/script/example",midi_output_port="example-midi",
    persistence={group="example_ui",preset="current",schema_version=1},
    pages={function(api: any)
        return {id="level",label="LEVEL",params={
            {id="amount",persist="snapshot",min=0,max=1,default=0.5},
        },render=function(ctx: any)
            api.conventions.text(ctx.cx,ctx.cy,"LEVEL",12,api.theme.ink.body)
        end}
    end},
}
local composed=Session.compose(config,{})
assert(composed.ok, composed.message)
assert(composed.pages[1].params[1].key=="amount")
print("PASS: public composition example has no show catalog or runtime dependency")
