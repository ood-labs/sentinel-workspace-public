--!strict
local factories={
    side_fx=require("@show/side_fx"),
    camera_orbit=require("@show/camera_orbit"),
    transport_keys=require("@show/transport_keys"),
    attribute_catalog=require("@show/attribute_catalog"),
    attribute_editor=require("@show/attribute_editor"),
    static_rig=require("@show/static_rig"),
    rig_windows=require("@show/rig_windows"),
    programmer_surface=require("@show/programmer_surface"),
    selection_view=require("@show/selection_view"),
    sequence_grid=require("@show/sequence_grid"),
    sequence_layout=require("@show/sequence_layout"),
    sequence_model=require("@show/sequence_model"),
    sequence_store=require("@show/sequence_store"),
    sequence_view=require("@show/sequence_view"),
    rhythm=require("@show/rhythm"),
    look_store=require("@show/look_store"),
    rig_bridge=require("@show/rig_bridge"),
    rig_commands=require("@show/rig_commands"),
    desk=require("@show/desk"),
    desk_panel=require("@show/desk_panel"),
    rig_menus=require("@show/rig_menus"),
    ["page:sequence"]=require("@pages/sequence"),
    ["page:color"]=require("@pages/color"),
    ["page:global"]=require("@pages/global"),
    ["page:rig_static"]=require("@pages/rig_static"),
}
return function(host: any,legacy: any)
    local cache,loading={},{}
    local function get(id: string): any
        if legacy[id] then return legacy[id] end
        if cache[id] then return cache[id] end
        assert(factories[id],"Unknown Klang dependency: "..id)
        assert(not loading[id],"Dependency cycle: "..id)
        loading[id]=true;cache[id]=factories[id](host,get,{})
        loading[id]=nil;return cache[id]
    end
    return get
end
