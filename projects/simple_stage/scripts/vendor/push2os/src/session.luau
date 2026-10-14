--!strict
-- Construction is pure. Native lifecycle/restore are the next gated layer.
local factories = {
    theme = require("./internal/theme"), conventions = require("./internal/conventions"),
    widgets = require("./internal/widgets"), bands = require("./internal/bands"),
    button_menu = require("./internal/button_menu"), column_grid = require("./internal/column_grid"),
    core = require("./internal/core"), params = require("./internal/params"),
    persist = require("./internal/persist"), pads = require("./internal/pads"),
    editor = require("./internal/editor"),
    pad_window = require("./internal/pad_window"), pad_window_gesture = require("./internal/pad_window_gesture"),
    pad_desktop = require("./internal/pad_desktop"), pad_legacy_window = require("./internal/pad_legacy_window"),
}
local M = {}

local function failure(code: string, message: string, context: any): any
    return {ok=false, code=code, message=message, context=context}
end

function M.compose(config: any, host: any): any
    if typeof(host)~="table" then return failure("INVALID_ADAPTER","Explicit host adapter required",{}) end
    if typeof(config)~="table" or typeof(config.id)~="string" or config.id==""
        or typeof(config.root)~="string" or string.sub(config.root,1,1)~="/"
        or typeof(config.midi_output_port)~="string" or config.midi_output_port==""
        or typeof(config.persistence)~="table"
        or typeof(config.persistence.group)~="string" or config.persistence.group==""
        or typeof(config.persistence.preset)~="string" or config.persistence.preset==""
        or typeof(config.persistence.schema_version)~="number"
        or config.persistence.schema_version<1 or config.persistence.schema_version%1~=0
        or typeof(config.pages)~="table" or #config.pages<1 or #config.pages>8 then
        return failure("INVALID_CONFIG", "Explicit show identity, routes, persistence and 1..8 pages required", {})
    end
    config=table.clone(config)
    config.persistence=table.clone(config.persistence)
    local modules: any = {}
    local constructing: any = {}
    local function get(name: string): any
        if modules[name] then return modules[name] end
        assert(factories[name]~=nil, "Unknown internal module: "..name)
        assert(not constructing[name], "Internal dependency cycle: "..name)
        constructing[name]=true
        modules[name]=factories[name](host,get,config)
        constructing[name]=nil
        return modules[name]
    end
    -- Public construction/drawing helpers. Dispatch and legacy bridging stay private.
    local api: any = {}
    for _,name in ipairs({"theme","conventions","widgets","button_menu","column_grid","pad_window","editor"}) do
        api[name]=get(name)
    end
    -- Explicit versioned adapter for existing show-owned factories. It never
    -- imports show code; new pages should use the narrower helpers above.
    api.legacy_v1={}
    for _,name in ipairs({"theme","conventions","widgets","bands","button_menu","column_grid",
        "params","persist","pads","pad_window","pad_window_gesture","pad_desktop"}) do
        api.legacy_v1[name]=get(name)
    end
    local pages, ids, records, legacyRecords, paths, windows = {}, {}, {}, {}, {}, {}
    for index, factory in ipairs(config.pages) do
        if typeof(factory)~="function" then
            return failure("PAGE_FACTORY_REQUIRED", "Supply a factory creating fresh page records", {index=index})
        end
        local ok, page=pcall(factory,api,host)
        if not ok then return failure("PAGE_FACTORY_FAILED",tostring(page),{index=index}) end
        if typeof(page)~="table" or typeof(page.id)~="string" or page.id=="" or typeof(page.render)~="function" then
            return failure("INVALID_PAGE","Page requires stable id and render",{index=index})
        end
        if ids[page.id] then return failure("DUPLICATE_PAGE_ID",page.id,{index=index}) end
        ids[page.id]=true
        page.name=page.label or page.name or page.id
        if (page.params~=nil and typeof(page.params)~="table")
            or (page.records~=nil and typeof(page.records)~="table")
            or (page.windows~=nil and typeof(page.windows)~="table") then
            return failure("INVALID_PAGE_RECORDS",page.id,{})
        end
        -- Window records must exist before restore planning, not be appended
        -- by desktop.start after the saved-data coverage check.
        page.windows=page.windows or (if page.window then {page.window} else {})
        if #page.windows==0 and page.legacy_pads==true then
            page.windows={get("pad_legacy_window").attach(page,get("pads"),config.root)}
        end
        page.records=page.records or {}
        for _,window in ipairs(page.windows) do
            if typeof(window)~="table" or typeof(window.id)~="string" or window.id=="" then
                return failure("INVALID_WINDOW_ID",page.id,{})
            end
            if windows[window.id] then return failure("DUPLICATE_WINDOW_ID",window.id,{}) end
            windows[window.id]=true
            for _,field in ipairs({"width","height","row","col","pin","z"}) do
                local rec=window[field]
                if typeof(rec)~="table" then return failure("INVALID_WINDOW_RECORD",window.id,{field=field}) end
                if not table.find(page.records,rec) and not table.find(page.params or {},rec) then
                    table.insert(page.records,rec)
                end
            end
        end
        for _,list in ipairs({page.params or {},page.records or {}}) do
            for _,rec in ipairs(list) do
                if typeof(rec)~="table" then return failure("INVALID_RECORD",page.id,{}) end
                if rec.stage=="parked" then continue end
                local key=rec.id or rec.key
                if typeof(key)~="string" or key=="" then return failure("INVALID_RECORD_ID",page.id,{}) end
                rec.id=key
                rec.key=rec.legacy_key or key
                local identity=page.id.."/"..key
                if records[identity] then return failure("DUPLICATE_RECORD_ID",identity,{}) end
                records[identity]=true
                local oldIdentity=(page.legacy_id or page.id).."/"..rec.key
                if legacyRecords[oldIdentity] then return failure("DUPLICATE_LEGACY_RECORD_ID",oldIdentity,{}) end
                legacyRecords[oldIdentity]=true
                local path=if rec.sink and rec.sink.kind=="state" then rec.sink.path else rec.state_path
                if not path and (rec.persist=="bank" or rec.persist=="state") then path=rec.key end
                if path then
                    if typeof(path)~="string" or path=="" or string.sub(path,1,1)=="/"
                        or string.sub(path,-1)=="/" or string.find(path,"//",1,true)
                        or string.find("/"..path.."/","/./",1,true)
                        or string.find("/"..path.."/","/../",1,true) then
                        return failure("INVALID_STATE_PATH","Use a canonical relative StateTree path",{page=page.id})
                    end
                    if paths[path] then return failure("DUPLICATE_STATE_PATH",path,{}) end
                    paths[path]=true
                end
            end
        end
        table.insert(pages,page)
    end
    config.pages=pages
    return {ok=true, code="COMPOSED", message="Pure session composed; output not started", context={},
        api=api, pages=pages, config=config, _get=get}
end

return M
