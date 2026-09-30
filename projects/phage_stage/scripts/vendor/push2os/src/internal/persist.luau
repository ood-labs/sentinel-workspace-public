--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
local log = host.log
local preset = host.preset
local state = host.state
-- Push 2 OS persistence. A param record declares its durability once, in its
-- `persist` field, and this module derives everything that follows. Adding a
-- value to a bank is a one-word edit in a page file and no edit anywhere else.
--
-- The four classes:
--
--   none      the value lives and dies with the panel session
--   snapshot  the value joins the versioned `on_serialize` table, so it
--             survives a hot reload and a project load
--   state     the value is mirrored to a path under the panel root, so the
--             rest of the show, the MCP surface, and a host mapping can read
--             it; the path is registered at boot and published on change
--   bank      `state`, plus the value is saved into the `push2_banks` preset
--             group, so it survives the host process exiting
--
-- `bank` is a preset group over panel-root paths rather than a file this
-- module writes, because the host preset engine only writes its own
-- StateTree, and because a group is the thing an operator can already recall,
-- morph and inspect. The group file has to exist on disk for the engine to
-- know the paths: see `ctrl/stagerig/presets/push2_banks.json`.
--
-- No host-binding work at module top level. `bind` runs from the param
-- engine, which the core calls from the root's `on_start`.

-- This module needs no layout constants, so it requires nothing: it is the
-- one library module with no dependency on `conventions`.

local M = {}

M.SNAPSHOT_VERSION = 1

local BANK_GROUP = config.persistence.group
local BANK_PRESET = config.persistence.preset
-- A turned encoder produces a value every frame. Saving a preset per frame
-- would rewrite the group file 60 times a second, so a bank write waits for
-- the operator to stop moving.
local BANK_DEBOUNCE_S = 0.35
-- The group file is hot-loaded by a file watcher, so at a cold start it may
-- not be there yet when the panel's first tick runs.

local root_prefix = ""
local slots: { any } = {}
local registered: { [string]: boolean } = {}
local bank_dirty_at = -1.0
local bank_writes = 0
local has_bank = false
local save_ready = false
local bank_paths: {string} = {}
local bank_path_seen: {[string]:boolean} = {}
local last_now = 0

local function path(rel: string): string
    return root_prefix .. "/" .. rel
end

-- The name under the panel root where this record's value lives, whoever
-- writes it. A `state` sink already owns a path, so that one wins.
local function state_name_of(rec: any): string?
    if rec.sink ~= nil and rec.sink.kind == "state" then
        return rec.sink.path
    end
    if rec.persist == "state" or rec.persist == "bank" then
        return rec.state_path or rec.key
    end
    return nil
end

-- The name persistence itself registers and publishes. `bank` is `state` plus
-- durability, so both classes want a mirror, but a record whose sink is
-- already a `state` sink gets nil: registering that path twice and writing it
-- twice a frame would be the same value arriving by two routes.
local function mirror_of(rec: any): string?
    if rec.persist ~= "state" and rec.persist ~= "bank" then
        return nil
    end
    if rec.sink ~= nil and rec.sink.kind == "state" then
        return nil
    end
    return rec.state_path or rec.key
end

local function is_bank(rec: any): boolean
    return rec.persist == "bank"
end

-- Start a panel session. Called once from `on_start`, before any page is
-- registered.
function M.reset(root: string)
    assert(config.restore_prepared==true, "Restore preflight required before persistence registration")
    root_prefix = root
    slots = {}
    registered = {}
    has_bank = false
    bank_writes = 0
    bank_dirty_at = -1.0
    save_ready = false
    bank_paths = {}
    bank_path_seen = {}
    last_now = 0
end

-- Register every path one page's records need, from inside `on_start`.
--
-- This runs for EVERY page at boot, not only the visible one. A page's records
-- are bound when its tab is selected, but its paths have to exist from the
-- first read: a path that appears when somebody presses a tab is a path
-- nothing else in the show can depend on. It also means a snapshot and a bank
-- cover the whole panel rather than whichever tab happened to be up.
--
-- Snapshot keys are qualified by page, because a record key is only required
-- to be unique within its page and two pages may both call a slot `level`.
function M.register_page(page_id: string, records: { any }, root: string)
    root_prefix = root
    for _, rec in ipairs(records) do
        if rec.stage ~= "parked" then
            if rec.key ~= nil then
                rec.persist_id = page_id .. "/" .. rec.key
            end
            table.insert(slots, rec)

            local name = mirror_of(rec)
            if name ~= nil and not registered[name] then
                state.register(name, rec.value)
                registered[name] = true
            end
            if is_bank(rec) then
                has_bank = true
                local bank_path=path(state_name_of(rec) :: string)
                if not bank_path_seen[bank_path] then
                    table.insert(bank_paths,bank_path)
                    bank_path_seen[bank_path]=true
                end
            end
        end
    end

    if has_bank and not registered["#bank_writes"] then
        state.register("bank_writes", 0)
        registered["#bank_writes"] = true
    end
end

-- Publish a record's mirror and mark the bank dirty. Called by the param
-- engine whenever a value actually moves, not once per frame.
function M.publish(rec: any, now: number)
    local name = mirror_of(rec)
    if name ~= nil then
        state.set(path(name), rec.value)
    end
    if is_bank(rec) then
        bank_dirty_at = now
        save_ready = false
    end
end

local function save_bank()
    local ok, res = pcall(preset.save, BANK_GROUP, BANK_PRESET,{paths=bank_paths,merge_existing=true})
    if ok and res == true then
        bank_writes += 1
        state.set(path("bank_writes"), bank_writes)
        return true
    else
        log.warn("[push2os] bank save failed: " .. tostring(res))
        return false
    end
end

-- Called once per published frame from the param engine.
function M.service(now: number)
    last_now=now
    if bank_dirty_at >= 0.0 and (now - bank_dirty_at) >= BANK_DEBOUNCE_S then
        save_ready = true
    end
end

-- Disk I/O belongs to the host's UI callback (8 ms budget), not its musical
-- tick (2 ms). A 90-path bank save was measured exceeding the tick watchdog.
function M.flush_ready()
    if save_ready then
        local saved=save_bank()
        save_ready = false
        bank_dirty_at = if saved then -1.0 else last_now
    end
end

-- The versioned table the root re-exports from `on_serialize`. Values sit in
-- their own sub-table so `version` can never collide with a record key.
function M.snapshot(): { [string]: any }
    -- A reload can land during the debounce window after a pad edit.
    -- Bank records live on disk, so finish their pending save before the
    -- next instance recalls that bank over its freshly registered defaults.
    if bank_dirty_at >= 0.0 then
        if save_bank() then bank_dirty_at = -1.0;save_ready = false end
    end
    local values: { [string]: any } = {}
    for _, rec in ipairs(slots) do
        if rec.persist == "snapshot" and rec.persist_id ~= nil then
            values[rec.persist_id] = rec.value
        end
    end
    return { version = M.SNAPSHOT_VERSION, values = values }
end

-- Restore a snapshot. A value outside the record's current range is clamped
-- and logged rather than refused: a range narrowed since the snapshot was
-- taken is a normal edit, and losing the panel over it is not acceptable.
function M.restore(saved: { [string]: any }, clamp: (any) -> ())
    if typeof(saved) ~= "table" then
        return
    end
    if saved.version ~= nil and saved.version ~= M.SNAPSHOT_VERSION then
        log.warn("[push2os] param snapshot version " ..
                 tostring(saved.version) .. " != " ..
                 tostring(M.SNAPSHOT_VERSION) .. "; clamping what it can")
    end
    local values = saved.values
    if typeof(values) ~= "table" then
        return
    end
    for _, rec in ipairs(slots) do
        if rec.persist == "snapshot" and rec.persist_id ~= nil then
            local v = tonumber(values[rec.persist_id])
            if v ~= nil then
                rec.value = v
                clamp(rec)
                if rec.value ~= v then
                    log.warn("[push2os] restored " .. tostring(rec.persist_id) ..
                             " " .. tostring(v) .. " clamped to " ..
                             tostring(rec.value))
                end
                rec.dirty = true
            end
        end
    end
end

-- Exposed for the offline spec.
M.BANK_GROUP = BANK_GROUP
M.BANK_PRESET = BANK_PRESET
M.BANK_DEBOUNCE_S = BANK_DEBOUNCE_S
M.mirror_of = mirror_of
M.state_name_of = state_name_of

return M

end
