--!strict
-- Pulse Bus - strikes found on the GPU become notes, and every note played is echoed back.
--
-- In   impacts (Event)  Impact records from the Pulse module's EventOut "Impacts":
--                       payload = {bar, normal speed px/s, contact along 0..1, stamp s}
-- Out  notes   (Event)  NoteOn / NoteOff for MIDI Out, stamped with the strike's own time
--      echo    (Event)  on to Resonance's EventIn "Echo" (not back to Pulse: the graph is
--                       acyclic, so a node cannot receive the answer to its own events):
--                         NoteOn  {bar*128 + note, velocity, strike stamp, seq}  played
--                         Trigger {bar*128 + note, 0, -1, seq}                   retune
--      rate    (Signal) notes per second, smoothed
--
-- The script owns the music (which note a bar plays, how loud, how long); Pulse owns the physics,
-- and Resonance shows only what comes back. Every echo carries a running sequence number, so the
-- receiving module applies each record once however many cooks it is handed to.
--
-- Control window (open the node's Window): the decision itself, live. Scale pads (one press, every
-- choice in view) and Mute; the speed -> velocity curve with the last 4 s of strikes on it (filled:
-- played; hollow: dropped by the restrike guard, the per-tick cap or Mute); a keyboard lighting the
-- notes that are sounding now. Pads act on the control tick through ui.next_edge().

local SCALES = {
	{ name = "Major pentatonic", steps = { 0, 2, 4, 7, 9 } },
	{ name = "Minor pentatonic", steps = { 0, 3, 5, 7, 10 } },
	{ name = "Dorian", steps = { 0, 2, 3, 5, 7, 9, 10 } },
	{ name = "Lydian", steps = { 0, 2, 4, 6, 7, 9, 11 } },
	{ name = "Whole tone", steps = { 0, 2, 4, 6, 8, 10 } },
	{ name = "Hirajoshi", steps = { 0, 2, 3, 7, 8 } },
}
local SCALE_NAMES = {}
for i, s in ipairs(SCALES) do
	SCALE_NAMES[i] = s.name
end
local SCALE_SHORT = { "Maj pent", "Min pent", "Dorian", "Lydian", "Whole", "Hirajoshi" }
local SCALE_PAD = {} -- pad id -> scale index
local SCALE_IDS = {}
for i = 1, #SCALES do
	SCALE_IDS[i] = "scale" .. i
	SCALE_PAD[SCALE_IDS[i]] = i
end

local BARS = 12
local EV_TRIGGER, EV_NOTEON, EV_NOTEOFF, EV_IMPACT = 1, 2, 3, 5
local RESTRIKE_S = 0.04 -- a bar cannot be replayed faster than this (bounce chatter)
local MAX_PER_TICK = 6
local RETUNE_EVERY_S = 2 -- re-send the bar -> note map, for listeners that joined (or reloaded) late
local RING = 64 -- strikes remembered for the window
local WINDOW_S = 4
local WHY_PLAYED, WHY_GUARD, WHY_CAP, WHY_MUTE = 0, 1, 2, 3

local script = {}
script.manifest = {
	name = "Pulse Bus",
	inputs = { { name = "impacts", type = "event" } },
	outputs = {
		{ name = "notes", type = "event" },
		{ name = "echo", type = "event" },
		{ name = "rate", type = "signal" },
	},
	params = {
		{ name = "scale", type = "enum", values = SCALE_NAMES, default = "Major pentatonic" },
		{ name = "root", type = "int", default = 60, min = 36, max = 84 },
		{ name = "gate_ms", type = "float", default = 240, min = 20, max = 2000 },
		{ name = "soft_speed", type = "float", default = 90, min = 0, max = 2000 },
		{ name = "hard_speed", type = "float", default = 1300, min = 100, max = 4000 },
		{ name = "mute", type = "bool", default = false },
	},
}

local function scaleIndex(v: any): number
	if type(v) == "number" then
		return math.clamp(math.floor(v) + 1, 1, #SCALES)
	end
	for i, s in ipairs(SCALES) do
		if s.name == v then
			return i
		end
	end
	return 1
end

-- bar 0 is the lowest (longest) bar: scale degrees climb with the bar index
local function noteFor(bar: number, scale: number, root: number): number
	local steps = SCALES[scale].steps
	local n = #steps
	local note = root + steps[(bar % n) + 1] + 12 * math.floor(bar / n)
	return math.clamp(note, 0, 127)
end

local function velocityFor(speed: number, soft: number, hard: number): number
	local v = math.clamp((speed - soft) / math.max(hard - soft, 1), 0, 1)
	return math.floor(1 + 126 * math.sqrt(v) + 0.5)
end

local function nextSeq(node): number
	node.state.seq = (node.state.seq or 0) + 1
	return node.state.seq
end

local function retune(node, scale: number, root: number)
	for bar = 0, BARS - 1 do
		local note = noteFor(bar, scale, root)
		node.outputs.echo:emit({ event_type = EV_TRIGGER, payload = { bar * 128 + note, 0, -1, nextSeq(node) } })
	end
	node.state.tuned = scale * 1000 + root
	node.state.retuned_at = nil
end

function script.init(node)
	node.state.seq = node.state.seq or 0
	node.state.offs = {} -- pending note-offs: {note, due (ctx.time s), stamp ns, gen}
	node.state.gen = {} -- per-note retrigger generation
	node.state.held = {} -- notes sounding now
	node.state.last = {} -- per-bar last play time
	node.state.rate = 0
	node.state.tuned = -1
	-- every strike, played or not, for the window; preallocated so a strike allocates nothing
	node.state.ring = table.create(RING)
	for i = 1, RING do
		node.state.ring[i] = { t = -1e9, speed = 0, vel = 0, why = WHY_PLAYED }
	end
	node.state.ringAt = 0
	node.state.curve = table.create(49)
	for i = 1, 49 do
		node.state.curve[i] = { 0, 0 }
	end
end

local function remember(node, t: number, speed: number, vel: number, why: number)
	local k = node.state.ringAt % RING + 1
	node.state.ringAt = k
	local r = node.state.ring[k]
	r.t, r.speed, r.vel, r.why = t, speed, vel, why
end

-- the window's pads, applied on the control tick (they work the same with the window closed)
local function drainEdges(node)
	while true do
		local id, kind = ui.next_edge()
		if not id then
			break
		end
		if kind == "press" then
			local i = SCALE_PAD[id]
			if i then
				node.params.scale = SCALES[i].name
			elseif id == "mute" then
				node.params.mute = not node.params.mute
			end
		end
	end
end

function script.control_process(node, ctx)
	drainEdges(node)
	local p = node.params
	local scale, root = scaleIndex(p.scale), p.root
	if node.state.tuned ~= scale * 1000 + root or ctx.time - (node.state.retuned_at or ctx.time) >= RETUNE_EVERY_S then
		retune(node, scale, root)
	end
	node.state.retuned_at = node.state.retuned_at or ctx.time

	local played = 0
	for _, e in node.inputs.impacts:read_events() do
		if e.event_type == EV_IMPACT and e.payload then
			local bar = math.floor(e.payload[1] + 0.5)
			local speed, stamp = e.payload[2], e.payload[4]
			local last = node.state.last[bar] or -1
			local vel = velocityFor(speed, p.soft_speed, p.hard_speed)
			local why = WHY_PLAYED
			if p.mute then
				why = WHY_MUTE
			elseif ctx.time - last < RESTRIKE_S then
				why = WHY_GUARD
			elseif played >= MAX_PER_TICK then
				why = WHY_CAP
			end
			if bar >= 0 and bar < BARS then
				remember(node, ctx.time, speed, vel, why)
			end
			if bar >= 0 and bar < BARS and why == WHY_PLAYED then
				node.state.last[bar] = ctx.time
				local note = noteFor(bar, scale, root)
				-- a retrigger ends the still-sounding note first; the generation makes its
				-- pending off a no-op, so it cannot cut the new note short
				local gen = (node.state.gen[note] or 0) + 1
				node.state.gen[note] = gen
				if node.state.held[note] then
					node.outputs.notes:emit({ event_type = EV_NOTEOFF, timestamp_ns = e.timestamp_ns, payload = { note, 0 } })
				end
				node.outputs.notes:emit({ event_type = EV_NOTEON, timestamp_ns = e.timestamp_ns, payload = { note, vel } })
				node.state.held[note] = true
				table.insert(node.state.offs, { note, ctx.time + p.gate_ms / 1000, e.timestamp_ns + p.gate_ms * 1e6, gen })
				node.outputs.echo:emit({ event_type = EV_NOTEON, payload = { bar * 128 + note, vel, stamp, nextSeq(node) } })
				played += 1
			end
		end
	end

	-- note-offs that fell due; one whose note was retriggered since is dropped
	local offs = node.state.offs
	local i = 1
	while i <= #offs do
		local o = offs[i]
		if ctx.time >= o[2] then
			if node.state.gen[o[1]] == o[4] then
				node.outputs.notes:emit({ event_type = EV_NOTEOFF, timestamp_ns = o[3], payload = { o[1], 0 } })
				node.state.held[o[1]] = false
			end
			table.remove(offs, i)
		else
			i += 1
		end
	end

	node.state.rate = node.state.rate + (played / math.max(ctx.dt, 1e-4) - node.state.rate) * math.min(ctx.dt * 2, 1)
	node.outputs.rate:set(node.state.rate)
end

-- ---------------------------------------------------------------------------------------------
-- control window
-- The lab's instrument greys (modules/_shared/plan_theme.hlsli) packed 0xAABBGGRR; amber is kept
-- for live readings only: the newest strike and the notes sounding now.
local INK, MID, DIM, RULE = { 230, 231, 224 }, { 153, 154, 148 }, { 97, 98, 94 }, { 56, 57, 55 }
local KEY_W, KEY_B, WELL, ACCENT = { 48, 49, 48 }, { 14, 14, 15 }, { 22, 22, 23 }, { 255, 107, 23 }
local function c(rgb: { number }, a: number?): number
	local A = math.floor(math.clamp(a or 1, 0, 1) * 255 + 0.5)
	return A * 16777216 + rgb[3] * 65536 + rgb[2] * 256 + rgb[1]
end

local Y0 = 74 -- below the title and the pads
local W = 640
local PX0, PX1 = 52, W - 18 -- speed axis
local PY0, PY1 = Y0 + 196, Y0 + 30 -- velocity 1 .. 127
local KY0, KY1 = PY0 + 50, PY0 + 108 -- keyboard
local WHITE_OF = { 0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6 } -- pitch class -> white key in its octave
local IS_BLACK = { false, true, false, true, false, false, true, false, true, false, true, false }

function script.render(node, ui)
	local p, st = node.params, node.state
	if not st.ring then
		return
	end
	local now = time.now()
	local scale, root = scaleIndex(p.scale), p.root

	ui.text("title", "PULSE BUS  -  bar to note, strike speed to velocity")
	ui.strip_begin("scales", "horizontal", 70, 4)
	for i = 1, #SCALES do
		ui.pad(SCALE_IDS[i], SCALE_SHORT[i], "radio", if i == scale then "selected" else "loaded", "neutral", nil, nil, 70, 28)
	end
	ui.strip_end()
	ui.same_line()
	ui.pad("mute", "Mute", "toggle", if p.mute then "active" else "loaded", "kill", nil, nil, 52, 28)

	-- the curve, with the last few seconds of strikes on it
	local smax = math.max(1600, p.hard_speed * 1.15)
	local function sx(speed: number): number
		return PX0 + (PX1 - PX0) * math.clamp(speed / smax, 0, 1)
	end
	local function vy(vel: number): number
		return PY0 + (PY1 - PY0) * (vel - 1) / 126
	end
	ui.rect_filled(0, Y0, W, PY0 + 34, c(WELL))
	ui.text_at(PX0 + 8, PY1 - 8, c(DIM), "velocity")
	ui.text_at(PX1 - 150, PY0 + 10, c(DIM), "strike speed px/s")
	ui.text_at(PX0 - 30, PY1 - 8, c(DIM), "127")
	ui.text_at(PX0 - 14, PY0 - 8, c(DIM), "1")
	ui.line(PX0, PY0, PX1, PY0, c(RULE), 1)
	ui.line(PX0, PY0, PX0, PY1, c(RULE), 1)
	for _, th in { p.soft_speed, p.hard_speed } do
		local x = sx(th)
		ui.line(x, PY1, x, PY0, c(RULE), 1)
	end
	ui.text_at(sx(p.soft_speed) + 4, PY0 + 10, c(DIM), string.format("soft %d", p.soft_speed))
	ui.text_at(sx(p.hard_speed) + 4, PY1 - 2, c(DIM), string.format("hard %d", p.hard_speed))
	local curve = st.curve
	for i = 1, 49 do
		local s = smax * (i - 1) / 48
		curve[i][1], curve[i][2] = sx(s), vy(velocityFor(s, p.soft_speed, p.hard_speed))
	end
	ui.polyline(curve, c(MID, 0.8), 1.5)

	local counts = { 0, 0, 0, 0 }
	local newest, newestT = nil, -1e9
	for i = 1, RING do
		local r = st.ring[i]
		local age = now - r.t
		if age >= 0 and age < WINDOW_S then
			counts[r.why + 1] += 1
			local x, y = sx(r.speed), vy(r.vel)
			local fade = 1 - 0.7 * age / WINDOW_S
			if r.why == WHY_PLAYED then
				ui.circle_filled(x, y, 3.5, c(INK, fade))
				if r.t > newestT then
					newest, newestT = r, r.t
				end
			else
				ui.circle(x, y, 4, c(DIM, fade), 1)
			end
		end
	end
	if newest and now - newestT < 0.35 then
		ui.circle_filled(sx(newest.speed), vy(newest.vel), 5, c(ACCENT))
	end

	-- the keyboard: four octaves from the root's C; dots mark the bars' notes, amber is sounding
	local lo = 12 * math.floor(root / 12)
	local barNote = {}
	for bar = 0, BARS - 1 do
		barNote[noteFor(bar, scale, root)] = true
	end
	local kw = W / 28
	for pass = 1, 2 do
		for n = lo, lo + 47 do
			local pc = n % 12
			local black = IS_BLACK[pc + 1]
			if (pass == 1) ~= black then
				local wx = (math.floor((n - lo) / 12) * 7 + WHITE_OF[pc + 1]) * kw
				local x0, x1, y1 = wx + 1, wx + kw - 1, KY1
				if black then
					x0, x1, y1 = wx + kw * 0.68, wx + kw * 1.32, KY0 + 34
				end
				local held = st.held[n] == true
				ui.rect_filled(x0, KY0, x1, y1, if held then c(ACCENT) else c(if black then KEY_B else KEY_W))
				if barNote[n] and not held then
					ui.circle_filled((x0 + x1) / 2, y1 - 7, 2.5, c(MID))
				end
				if pc == 0 then
					ui.text_at(x0 + 2, KY1 + 3, c(DIM), string.format("C%d", math.floor(n / 12) - 1))
				end
			end
		end
	end

	ui.text_at(0, KY1 + 26, c(MID), string.format("last %d s   played %d   guard %d   cap %d   muted %d      %.1f notes/s",
		WINDOW_S, counts[1], counts[2], counts[3], counts[4], st.rate or 0))
end

-- the sequence survives a reload, so the module's watermark keeps accepting echoes
function script.serialize(node)
	return { version = 1, seq = node.state.seq or 0 }
end
function script.deserialize(node, saved)
	if saved and saved.version == 1 then
		node.state.seq = saved.seq
	end
end

return script
