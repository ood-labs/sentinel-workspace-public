--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
-- Push 2 OS core. Owns the page registry, the input routing, the 60 Hz frame
-- gate, the two bands, and the snapshot. It does not know the name of any
-- page: dispatch is data-driven from the show descriptor's page list, so
-- adding a page is one new file plus one array entry.
--
-- No host-binding work happens at this module's top level. `start(show)` is
-- called from the root script's `on_start`, which is what makes every
-- handler and every state path attribute to the root (host Phase 19.1a).

local C = get("conventions")
local P = get("params")
local B = get("bands")
local D = get("pads")
local Desktop = get("pad_desktop")
local Menu = get("button_menu")

local M = {}

-- Set by start(). The root's own path prefix, so the panel writes only under
-- itself.
local root_prefix = ""
local pages: { any } = {}
local page_count = 0
local page_index = 0            -- 0-based, matches the bottom button slot
local frame_accum = 0.0
local frame_count = 0
local elapsed = 0.0
local global_row: { any } = {}
local guest_port = ""
-- Per top-slot verb state, in one table so the module stays inside the
-- 30-local rule. `down` is the physical button; `since` is when it went down,
-- for `hold` verbs; `fired` stops a held verb firing every tick.
local top_state: { [number]: any } = {}
-- Pages that raised, keyed by page index: the message to show and the frame
-- at which to try that page again.
local page_err: { [number]: { msg: string, retry_at: number } } = {}

-- The panel's two error tallies, in one table. `page` counts raises out of a
-- page's own render, which `safe_render` isolates; `frame` counts raises from
-- anywhere else in the frame, which the tick's pcall isolates. `last` is the
-- most recent frame message, so a frame that raises sixty times a second is
-- logged once. Both are published under the panel root. One table rather than
-- two locals because the module sits exactly on the 30-local rule.
local errs = { page = 0, frame = 0, last = "" }

local function path(rel: string): string
    return root_prefix .. "/" .. rel
end

-- A page whose render raises must not take the panel down with it, and its
-- half-drawn frame must not be left on the glass under the error text.
--
-- Painting an opaque band over the partial frame does not work: the host
-- renderer composites text after shapes, so a rect issued later in the same
-- frame still ends up behind the page's text. So a page that raises is
-- SUPPRESSED instead. Its render is not called again until the retry frame,
-- which means the error frame contains no page commands at all. Retrying
-- once a second lets a page that has been fixed on disk come back without
-- needing a reload, and stops a broken page burning 60 renders a second.
local function safe_render(page: any, ctx: any)
    local st = page_err[page_index]

    if st ~= nil and frame_count < st.retry_at then
        C.text(ctx.cx + 24, ctx.cy + 24, "ERR", C.TEXT.large, 0xFF3020)
        -- The tail of the message, not the head: the head is an absolute
        -- path, the same for every page, and tells you nothing. Trim to 57
        -- plus the ellipsis, because both text paths truncate at 60 at the
        -- call boundary and would otherwise cut the message back off.
        local msg = st.msg
        if #msg > 60 then
            msg = "..." .. string.sub(msg, #msg - 56)
        end
        C.text(ctx.cx + 24, ctx.cy + 58, msg, C.TEXT.body, 0xC08070)
        return
    end

    local ok, err = pcall(page.render, ctx)
    if ok then
        page_err[page_index] = nil
        return
    end

    errs.page += 1
    host.state.set(path("page_errors"), errs.page)
    page_err[page_index] = {
        msg = tostring(err),
        retry_at = frame_count + C.FRAME_HZ,
    }
    -- Caught errors still invalidate this native transaction.
    host.display.abort_frame()
    error(tostring(err))
end

-- Background work for EVERY page, not just the visible one.
--
-- A page that follows an external clock, an analyzer or a cue list has to keep
-- following it while the operator is on another tab. Doing that work inside
-- `render` would tie it to which tab happens to be up, so the panel would
-- behave differently during a show than it did in rehearsal. This is the same
-- rule the boot-time registration pass follows: a page is live from `start`,
-- not from the first time somebody looks at it.
--
-- Each page is called under its own pcall, so one page that raises does not
-- stop the others from being serviced. The raise is counted with the frame
-- errors and logged once per distinct message.
--
-- The third argument says whether this page is the one on the glass. Work that
-- reaches a SURFACE belongs behind it: the pad grid is shared by every page and
-- the transient layer composites above every region, so a page that pulses a
-- pad while another tab is up lights that pad on the other page.
local function service_pages(dt: number)
    for i, page in ipairs(pages) do
        D.activate(page)
        if typeof(page.on_frame) == "function" then
            local ok, err = pcall(page.on_frame, dt, elapsed, i == page_index + 1)
            if not ok then
                errs.frame += 1
                host.state.set(path("frame_errors"), errs.frame)
                local msg = tostring(err)
                if msg ~= errs.last then
                    errs.last = msg
                    host.log.warn("[push2os] on_frame raised for page '" ..
                             tostring(page.name) .. "': " .. msg)
                end
            end
        end
    end
    D.activate(pages[page_index + 1])
end

local function publish_frame(dt: number)
    assert(host.display.begin_frame(0x000000), "Complete-frame ownership lost")
    B.draw_top(pages[page_index + 1], top_state,if Menu.active() then Menu.render_cell else nil)
    B.draw_bottom(pages, page_index, Desktop.solo_index(), Desktop.overview())

    local page = pages[page_index + 1]
    if page ~= nil and typeof(page.render) == "function" then
        safe_render(page, {
            cx = 0, cy = C.PAGE_Y, cw = C.W, ch = C.PAGE_H,
            t = elapsed, dt = dt, frame = frame_count,
        })
        if page.params ~= nil then
            P.draw_strip()
        end
    else
        -- An unfilled tab is inert, not an error.
        C.text(24, C.PAGE_Y + 44, "NO PAGE", C.TEXT.large, 0x505868)
    end

    assert(host.display.complete_frame(), "Frame completion refused")
    frame_count += 1
end

local function set_page(next_index: number)
    if next_index < 0 or next_index >= C.CELLS then
        return
    end
    if pages[next_index + 1] == nil then
        return -- unfilled tab: inert
    end
    Menu.close()
    if next_index == page_index then
        Desktop.focus(pages[next_index + 1], elapsed)
        return
    end
    -- Finish the outgoing encoder gesture before replacing its slot list.
    -- Otherwise a turn followed by a tab press in one frame loses its write.
    P.service(elapsed)
    if typeof(pages[page_index + 1].on_leave) == "function" then
        pcall(pages[page_index + 1].on_leave)
    end
    page_index = next_index
    Desktop.focus(pages[page_index + 1], elapsed)
    host.state.set(path("page"), page_index)
    -- A top button that is still physically down belongs to the page it was
    -- pressed on. Carrying its entry across the switch indexes the incoming
    -- page's verb array by that slot, so a `hold` verb there fires with no
    -- press, its release routes to the wrong page, and the wrong band cell
    -- lights. The press is abandoned; the operator has to press again on the
    -- new page.
    for slot,held in pairs(top_state) do
        local verb=held.verb
        if verb and (verb.kind=="momentary" or (verb.kind=="hold" and held.fired))
            and typeof(verb.on_release)=="function" then pcall(verb.on_release,slot) end
    end
    table.clear(top_state)
    -- Rebind the encoder strip and page-local drawing context. The desktop
    -- keeps every page's pad regions alive and composes their windows.
    local page = pages[page_index + 1]
    D.activate(pages[page_index + 1])
    -- A page with no params must unbind the outgoing page's, or its records
    -- keep polling readback and a later flush writes the previous page's
    -- sinks from this one.
    P.bind(page ~= nil and page.params or {}, root_prefix)

end

-- What actually keeps a visiting player off the panel is the controller
-- profile: `push2-user-mode` binds to the Push 2 port by glob, so the host
-- only ever raises a `push2.*` semantic event for MIDI that arrived on that
-- port. A guest device produces no semantic event at all.
--
-- This check is the belt to that braces, and today it is inert: a semantic
-- event carries `id`, `profile`, `kind`, `row`, `col`, `index` and `time`,
-- and no `port` (host `sentinel_ctrl.d.luau`, the `Semantic*Event` types).
-- It is kept because it costs one comparison and starts working the day the
-- host adds the field. Do not treat it as the thing protecting the panel,
-- and do not delete the profile's port glob on the strength of it.
local function from_guest(ev: any): boolean
    return guest_port ~= "" and typeof(ev) == "table" and ev.port == guest_port
end

local function on_bottom(ev: any)
    if from_guest(ev) then return end
    if ev.pressed ~= true then return end
    local slot = ev.index
    if typeof(slot) ~= "number" then return end
    Menu.close()
    Desktop.tab(slot, elapsed)
end

local function on_top(ev: any)
    if from_guest(ev) then return end
    -- A release belongs to the verb pressed, even if a menu opened meanwhile.
    local held=top_state[ev.index]
    if ev.pressed==false and held and held.verb then
        top_state[ev.index]=nil
        local verb=held.verb
        if (verb.kind=="momentary" or (verb.kind=="hold" and held.fired)) and verb.on_release then pcall(verb.on_release,ev.index) end
        return
    end
    if Menu.route(ev) then return end
    if Desktop.top(ev, elapsed) then return end
    local slot = ev.index
    if typeof(slot) ~= "number" then return end

    local page = pages[page_index + 1]
    if page == nil then return end

    local verbs = page.top
    local verb = verbs and verbs[slot + 1] or nil
    if verb == nil then return end

    local kind = verb.kind
    if ev.pressed then
        top_state[slot] = { down = true, since = elapsed, fired = false, verb=verb }
        -- A `hold` verb does not fire on press. It fires once the button has
        -- been down for `hold_s`, which the tick checks. Everything else
        -- fires immediately.
        if kind=="menu" then P.service(elapsed);pcall(Menu.open,verb.menu)
        elseif kind ~= "hold" and typeof(verb.on_press) == "function" then
            pcall(verb.on_press, slot)
        end
    else
        local st = top_state[slot]
        top_state[slot] = nil
        -- Momentary verbs receive both edges; delayed holds release only after
        -- firing. Triggers and toggles still fire once on press.
        if st ~= nil and (kind == "momentary" or (kind == "hold" and st.fired))
           and typeof(verb.on_release) == "function" then
            pcall(verb.on_release, slot)
        end
    end
end

-- Fire any `hold` verb whose button has been down long enough. Called once
-- per published frame, which is 60 Hz, so the granularity is ~17 ms.
local function service_holds()
    if Menu.active() then return end
    local page = pages[page_index + 1]
    if Desktop.top({}, elapsed) then return end
    local verbs = page and page.top or nil
    if verbs == nil then return end
    for slot, st in pairs(top_state) do
        if st.down and not st.fired then
            local verb = verbs[slot + 1]
            if verb ~= nil and verb.kind == "hold" then
                local wait = verb.hold_s or 0.5
                if (elapsed - st.since) >= wait then
                    st.fired = true
                    if typeof(verb.on_fire) == "function" then
                        pcall(verb.on_fire, slot)
                    end
                end
            end
        end
    end
end

local function on_encoder(ev: any)
    if from_guest(ev) then return end
    if Menu.active() then Menu.close() end
    local page = pages[page_index + 1]
    if page == nil then return end
    -- A page that declares params gets the engine's delta model. A page that
    -- wants raw ticks can still take them.
    if page.params ~= nil then
        -- Two clocks on purpose. `elapsed` is the tick clock the frame service
        -- compares against; `ev.time` is the event's own stamp, which is the
        -- only one fine enough to measure how fast the knob is turning.
        P.on_delta(ev.index, ev.delta, elapsed, ev.time)
    end
    if typeof(page.on_encoder) == "function" then
        pcall(page.on_encoder, ev.index, ev.delta)
    end
end

local function on_pad(ev: any)
    if from_guest(ev) then return end
    if Menu.active() and ev.pressed then Menu.close() end
    local row, col = ev.row, ev.col
    if typeof(row) ~= "number" or typeof(col) ~= "number" then return end

    local desktop_ok, consumed = pcall(Desktop.pad, ev, D, elapsed)
    if not desktop_ok then host.log.warn("[push2os] pad desktop: " .. tostring(consumed)); return end
    if consumed then return end
    if Desktop.solo_index() >= 0 and not D.is_global(row, col) then return end

    -- A held placement gesture consumes input before any pad layer acts.
    local capture_page = pages[page_index + 1]
    if capture_page ~= nil and typeof(capture_page.on_pad_capture) == "function" then
        local ok, capture_consumed = pcall(capture_page.on_pad_capture, ev)
        if not ok or capture_consumed then return end
    end

    -- A declared region owns its pads outright, on whichever layer. The
    -- compositor is the only thing that lights them, so a page must not also
    -- see the event and light something itself.
    if D.on_pad(ev) then
        return
    end

    -- Legacy callback declarations may still claim individual bottom-row pads.
    if row == 0 then
        for _, pad in ipairs(global_row) do
            if pad.col == col and typeof(pad.on_event) == "function" then
                pcall(pad.on_event, ev)
                return
            end
        end
    end

    local page = pages[page_index + 1]
    if page ~= nil and typeof(page.on_pad) == "function" then
        pcall(page.on_pad, ev)
    end
end

-- The lit state of the eight top cells, computed once per frame and given to
-- both the display band and the LED compositor so they cannot disagree.
function M.top_lit_now(): { boolean }
    local page = pages[page_index + 1]
    local out: { boolean } = {}
    for i = 0, C.CELLS - 1 do
        out[i + 1] = if Menu.item(i) then Menu.lit(i) else B.verb_is_lit(page, top_state, i)
    end
    return out
end

-- start(show) is the whole API the root script uses. It returns the
-- serialize pair for the root to re-export, so the root stays under 150
-- lines and owns no logic.
function M.start(show: any)
    assert(show.restore_prepared==true, "Restore preflight required before core startup")
    root_prefix = show.root
    Menu.start(root_prefix)
    guest_port = show.guest_port or ""
    global_row = show.global_row or {}
    errs.page = 0
    frame_count = 0
    elapsed = 0.0
    top_state = {}
    page_err = {}
    errs = { page = 0, frame = 0, last = "" }
    -- A fresh session starts on the first tab. The host gives a reloaded
    -- module a new thread, so this local would be zero anyway there; setting
    -- it makes `start` mean the same thing wherever it is called from, and
    -- `on_deserialize` puts the saved tab back straight after.
    page_index = 0
    for index,page in ipairs(show.pages) do
        if page.id==show.restored_page_id then page_index=index-1 end
    end

    pages = {}
    page_count = 0
    for i, page in ipairs(show.pages) do
        pages[i] = page
        page_count += 1
    end

    host.state.register("page", 0)
    host.state.register("page_errors", 0)
    host.state.register("frame_errors", 0)
    host.state.register("page_count", 0)
    host.state.register("frames", 0)
    host.state.set(path("page"), page_index)
    host.state.set(path("page_errors"), errs.page)
    host.state.set(path("frame_errors"), errs.frame)
    host.state.set(path("page_count"), page_count)

    -- Pages register their own state here, not at their module top level. A
    -- required module is cached and shared, so a top-level `host.state.register`
    -- would belong to whichever root required it first.
    for _, page in ipairs(pages) do
        if typeof(page.on_bind) == "function" then
            local ok, err = pcall(page.on_bind, root_prefix)
            if not ok then
                error("[push2os] on_bind failed for "..tostring(page.id)..": "..tostring(err))
            end
        end
    end

    D.bind(root_prefix)
    Desktop.start(pages, root_prefix, set_page, D)
    P.reset(root_prefix)

    -- Registration pass over EVERY page, not just the visible one. A page's
    -- records and regions go live when its tab is selected, but its state
    -- paths and its readback subscriptions have to exist from the first read.
    -- A path that appears when somebody presses a tab is a path nothing else
    -- in the show can depend on, and this is the only place that runs inside
    -- the root's `on_start`.
    for i, page in ipairs(pages) do
        local page_id = page.legacy_id or page.id
        if page.params ~= nil then
            P.register_page(page_id, page.params, root_prefix)
        end
        -- Durable non-encoder records (for example sequencer step masks)
        -- have the same registration/persistence contract as visible knobs.
        if page.records ~= nil then
            P.register_page(page_id, page.records, root_prefix)
        end
        D.mount(page)
    end

    for _, pad in ipairs(global_row) do
        if typeof(pad.register) == "function" then
            pad.register(root_prefix)
        end
        -- A show pad may declare itself as a region on the global layer, which
        -- is what gives it an LED that survives a tab switch.
        if typeof(pad.declare) == "function" then
            pcall(pad.declare, D)
        end
    end

    local first = pages[page_index + 1]
    if first ~= nil and first.params ~= nil then
        P.bind(first.params, root_prefix)
    end
    D.activate(first)

    Desktop.focus(first, elapsed)
    for i = 0, C.CELLS - 1 do
        host.midi.on("push2.button.bottom." .. i, "momentary", on_bottom)
        host.midi.on("push2.button.top." .. i, "momentary", on_top)
        host.midi.on("push2.encoder." .. i, "encoder_relative", on_encoder)
    end
    host.midi.on("push2.button.layout", "momentary", function(ev: any)
        if not from_guest(ev) then
            if ev.pressed then Menu.close() end
            Desktop.layout(ev,elapsed)
        end
    end)
    host.midi.on("push2.button.shift", "momentary", function(ev: any)
        if not from_guest(ev) then Desktop.shift(ev, elapsed) end
    end)
    host.midi.on("push2.button.select", "momentary", function(ev: any)
        if from_guest(ev) then return end
        if ev.pressed then Menu.close() end
        if Desktop.select(ev, elapsed) then
            if ev.pressed then table.clear(top_state) end
            return
        end
        local page = pages[page_index + 1]
        if page ~= nil and typeof(page.on_select) == "function" then
            pcall(page.on_select, ev)
        end
    end)
    for row = 0, 7 do
        for col = 0, 7 do
            host.midi.on("push2.pad." .. row .. "." .. col, "pad", on_pad)
        end
    end

    return {
        on_render = function()
            P.flush_bank()
            -- Optional background I/O service uses the wider UI callback budget.
            -- Display publishing and musical integration remain on the tick gate.
            for _,page in ipairs(pages) do
                if typeof(page.on_service)=="function" then
                    local ok,err=pcall(page.on_service)
                    if not ok then host.log.warn("[push2os] service raised: "..tostring(err)) end
                end
            end
        end,
        on_tick = function(dt: number)
            elapsed += dt
            frame_accum += dt
            if frame_accum < C.FRAME_INTERVAL then
                return
            end
            frame_accum -= C.FRAME_INTERVAL
            if frame_accum > C.FRAME_INTERVAL then
                frame_accum = 0.0 -- a long stall must not burst frames
            end

            -- The host latches `has_error` on any raise out of `on_tick` and
            -- then skips the module for the rest of the session, so a panel
            -- that throws once during a show is dead until somebody reloads
            -- it by hand. `safe_render` protects the page's own draw; this
            -- protects everything around it. One frame is lost, the error is
            -- counted, and the next frame is attempted normally.
            local page_errors_before=errs.page
            get("pad_window")._begin_read_batch()
            local ok, err = pcall(function()
                service_holds()
                service_pages(C.FRAME_INTERVAL)
                P.service(elapsed)
                Desktop.compose(D, elapsed, true)
                D.flush(M.top_lit_now(), page_index, page_count, elapsed)
                -- The frame delta, not the tick delta. A page integrating
                -- `x += v * ctx.dt` would otherwise run at a quarter speed,
                -- because the host ticks at 240 and this publishes at 60.
                publish_frame(C.FRAME_INTERVAL)
                if frame_count % 60 == 0 then
                    host.state.set(path("frames"), frame_count)
                end
            end)
            get("pad_window")._end_read_batch()
            if not ok then
                host.display.abort_frame()
                if errs.page==page_errors_before then
                    errs.frame += 1
                    host.state.set(path("frame_errors"), errs.frame)
                end
                -- Log the first of each distinct message only. A frame that
                -- raises every time raises 60 times a second.
                local msg = tostring(err)
                if msg ~= errs.last then
                    errs.last = msg
                    host.log.warn("[push2os] frame raised: " .. msg)
                end
            end
        end,

        -- The other half of `on_bind`. A page that acquires a host resource at
        -- bind time, a mapping being the one that matters, has to release it
        -- when the script is reloaded or the VM torn down. The host fires
        -- `on_stop` on every module before both, and without this a reload
        -- would leave the old mappings behind and create a second set.
        on_stop = function()
            for slot,held in pairs(top_state) do
                local verb=held.verb
                if verb and (verb.kind=="momentary" or (verb.kind=="hold" and held.fired))
                    and typeof(verb.on_release)=="function" then pcall(verb.on_release,slot) end
            end
            table.clear(top_state)
            Desktop.stop()
            for _, page in ipairs(pages) do
                if typeof(page.on_stop) == "function" then
                    local ok, err = pcall(page.on_stop)
                    if not ok then
                        host.log.error("[push2os] on_stop failed for page '" ..
                                  tostring(page.name) .. "': " .. tostring(err))
                    end
                end
            end
        end,

        on_serialize = function(): { [string]: any }
            -- One versioned table for the whole panel: the tab, plus every
            -- param record whose class is `snapshot`.
            return {
                version = 1,
                page = page_index,
                params = P.snapshot(),
            }
        end,

        on_deserialize = function(saved: { [string]: any })
            if typeof(saved) ~= "table" then return end
            if saved.version ~= 1 then
                host.log.warn("[push2os] snapshot version " ..
                         tostring(saved.version) .. " != " ..
                         tostring(1) .. "; clamping")
            end
            -- Restore only onto a tab that still exists. A show that drops a
            -- page would otherwise leave the panel on a dead tab that renders
            -- NO PAGE and cannot be reasoned about from the state path.
            local p = saved.page
            local target = 0
            if typeof(p) == "number" and p >= 0 and p < C.CELLS
               and pages[p + 1] ~= nil then
                target = p
            end
            -- Through `set_page`, not by assigning `page_index`. A restored
            -- tab needs its records bound and its pad regions declared exactly
            -- as a tab press does; assigning the index alone left the panel
            -- rendering the restored page's body under the FIRST page's
            -- readout strip and pads, which is what a restart onto any tab but
            -- the first looked like. `set_page` is a no-op when the target is
            -- already current, which is the case when the restore is onto the
            -- first page and `start` has already bound it.
            set_page(target)
            -- start() published the pre-restore index, because the host calls
            -- on_deserialize after on_start's core.start(). Publish again or
            -- the state path reports page 0 while the panel is visibly on
            -- another page.
            host.state.set(path("page"), page_index)

            if typeof(saved.params) == "table" then
                P.restore(saved.params)
            end
        end,
    }
end

return M

end
