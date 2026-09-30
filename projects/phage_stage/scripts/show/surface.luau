--!strict
local Runtime=require("@push2os/runtime")
local Registry=require("@show/registry")
return function(native: any, options: any?)
    options=options or {}
    local get=nil
    local factories={}
    for _,id in ipairs({"sequence","global","rig_static","color"}) do
        table.insert(factories,function(api: any,host: any)
            if not get then get=Registry(host,api.legacy_v1) end
            local page=get("page:"..id)
            -- Show-owned camera panel drawn over every page (the pinned framework has no overlay hook).
            if not page.camera_overlay then
                local render=page.render
                page.render=function(ctx) if render then render(ctx) end;get("camera_orbit").overlay(ctx) end
                page.camera_overlay=true
            end
            page.id=id;page.legacy_id=page.name
            page.legacy_window_id=string.lower(page.name)
            page.legacy_pads=page.windows==nil and page.window==nil
            return page
        end)
    end
    local runtime=Runtime.create({id="phage_stage",root=options.root or "/sentinel/pipelines/Phage_Surface/state",
        midi_output_port=options.midi_output_port or "Ableton Push 2",guest_port=options.guest_port or "",
        persistence={group="phage_stage_push2",preset=options.preset or "current",schema_version=1,new_empty=true,
            legacy_page_ids={"sequence","global","rig_static","color"}},pages=factories},native)
    -- Show-owned diagnostics; the pinned framework remains unchanged.
    runtime.rig=function() return if get then get("static_rig") else nil end
    runtime.color=function() return if get then get("page:color") else nil end
    runtime.global=function() return if get then get("page:global") else nil end
    runtime.desk=function() return if get then get("desk") else nil end
    runtime.desk_panel=function() return if get then get("desk_panel") else nil end
    return runtime
end
