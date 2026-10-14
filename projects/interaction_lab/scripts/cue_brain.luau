--!strict
-- Cue Brain - the Desk station's logic: a cue stack run from a panel of host controls.
--
-- In   panel     (Event)  the Desk module's `panel` output: press 1 / release 2 / value 3,
--                         payload {control index, value, value2}; the index is the control's
--                         position in the Desk manifest
-- Out  feedback  (Event)  into the Desk's `panel_feedback`: lit 10 {index, 0|1}, value 11
--                         {index, v}, colour 12 {index, r, g, b}, state 13 {index, state, fade}
--      level     (Signal) what reaches the stage: master, or 0 in a blackout
--
-- The Script owns the show's logic and nothing visual: which cue is live and which is next, the
-- crossfade's progress on the 240 Hz clock (eased, written to the Stage's cue_a / cue_b / mix
-- with sentinel.set), master, and a GUARDED blackout - hold the pad 0.65 s to kill the stage
-- (the pad fills while you hold), tap it to restore. GO during a fade completes it; BACK during
-- a fade reverses it. The Desk module only draws what this tells it.
--
-- Feedback is sent when it changes, and all of it again every 1.5 s: feedback sent before the
-- cable existed is lost, and a re-sent frame costs nothing.

-- The looks themselves live in modules/Stage/stage.hlsli. A pad's colour is its look's key fixture
-- colour from that table, gamma-encoded (colour feedback is 0..1 per channel).
local CUES = {
	{ name = "PRESET", color = { 1.00, 0.80, 0.58 } }, -- tungsten
	{ name = "DAWN", color = { 1.00, 0.85, 0.73 } }, -- peach
	{ name = "AMBER WASH", color = { 1.00, 0.70, 0.35 } },
	{ name = "SPLIT", color = { 0.48, 0.88, 0.98 } }, -- the cyan half
	{ name = "COLD", color = { 0.62, 0.76, 1.00 } }, -- steel
	{ name = "SOLO", color = { 1.00, 0.97, 0.93 } }, -- open white
	{ name = "STORM", color = { 0.80, 0.70, 1.00 } }, -- lavender
	{ name = "FINALE", color = { 1.00, 0.94, 0.85 } },
}
local KILL = { 1.00, 0.25, 0.30 }
local N = #CUES

-- Desk controls, manifest order
local R_NOW, R_NEXT, GO, BACK, BLACKOUT, FADE, MASTER, CUE1 = 0, 1, 2, 3, 4, 5, 6, 7
local PRESS, RELEASE, VALUE = 1, 2, 3
local FB_LIT, FB_VALUE, FB_COLOUR, FB_STATE = 10, 11, 12, 13
local LOADED, SELECTED, FADING = 1, 3, 4
local HOLD_S = 0.65
local REFRESH_S = 1.5

local script = {}
script.manifest = {
	name = "Cue Brain",
	inputs = { { name = "panel", type = "event" } },
	outputs = { { name = "feedback", type = "event" }, { name = "level", type = "signal" } },
	params = {
		{ name = "stage", type = "string", default = "Stage" },
		{ name = "desk", type = "string", default = "Desk" },
		{ name = "fade_s", type = "float", default = 3, min = 0, max = 10 },
		{ name = "master", type = "float", default = 1, min = 0, max = 1 },
	},
}

local function wrap(c: number): number
	return (c - 1) % N + 1
end

function script.init(node)
	local st = node.state
	st.live = st.live or 1
	st.next = st.next or 2
	st.blackout = st.blackout or false
	st.fading, st.from, st.to, st.t, st.dur = false, st.live, st.live, 0, 0
	st.holding, st.holdT = false, 0
	st.sent = {} -- last feedback sent, per key
	st.labels = {} -- last readout text sent
	st.written = {} -- last Stage parameter values written
	st.refreshAt = 0
	st.labelRetryAt = 0
	st.mix = 0
	st.curve = {} -- the monitor's fade curve, allocated once
	for i = 1, 33 do
		st.curve[i] = { 0, 0 }
	end
end

-- the cue log: one line per transition in sentinel.log, as a show operator keeps one
local function cueLog(fmt: string, ...)
	log.info("Cue Brain: " .. string.format(fmt, ...))
end

local function startFade(st, to: number, dur: number, why: string)
	st.from, st.to, st.t, st.dur, st.fading = st.live, to, 0, dur, true
	cueLog("%s  %d %s > %d %s  over %.1f s", why, st.from, CUES[st.from].name, to, CUES[to].name, dur)
end

local function finishFade(st)
	st.live, st.fading, st.t = st.to, false, 0
	st.next = wrap(st.live + 1)
	cueLog("live  %d %s", st.live, CUES[st.live].name)
end

local function handle(node, e)
	local st, p = node.state, node.params
	local idx = math.floor((e.payload and e.payload[1] or -1) + 0.5)
	if e.event_type == VALUE then
		local v = math.clamp(e.payload[2] or 0, 0, 1)
		if idx == FADE then
			node.params.fade_s = v * 10
		elseif idx == MASTER then
			node.params.master = v
		end
		return
	end
	if idx == BLACKOUT then
		if e.event_type == PRESS then
			if st.blackout then
				st.blackout = false -- restoring needs no guard
				cueLog("blackout off")
			else
				st.holding, st.holdT = true, 0
			end
		elseif e.event_type == RELEASE and st.holding then
			st.holding = false -- let go early: nothing happens
			cueLog("blackout hold released at %.2f s: no change", st.holdT)
		end
		return
	end
	if e.event_type ~= PRESS then
		return
	end
	if idx >= CUE1 and idx < CUE1 + N then
		st.next = idx - CUE1 + 1
	elseif idx == GO then
		if st.fading then
			st.t = 1 -- GO during a fade completes it
			cueLog("GO during the fade: complete it")
		elseif st.next ~= st.live then
			startFade(st, st.next, p.fade_s, "GO")
		end
	elseif idx == BACK then
		if st.fading then
			st.from, st.to, st.t = st.to, st.from, 1 - st.t -- reverse, from where it is now
			st.live = st.from
			cueLog("BACK during the fade: reverse to %d %s", st.to, CUES[st.to].name)
		else
			startFade(st, wrap(st.live - 1), p.fade_s, "BACK")
		end
	end
end

-- send one piece of feedback when it differs from what was last sent (or on a refresh)
local function send(node, refresh: boolean, kind: number, idx: number, a: number, b: number?, c: number?)
	local key = kind * 256 + idx
	local sent = node.state.sent
	local last = sent[key]
	local bb, cc = b or 0, c or 0
	if refresh or last == nil or last[1] ~= a or last[2] ~= bb or last[3] ~= cc then
		if last then
			last[1], last[2], last[3] = a, bb, cc
		else
			sent[key] = { a, bb, cc }
		end
		node.outputs.feedback:emit({ event_type = kind, payload = { idx, a, bb, cc } })
	end
end

local function label(node, refresh: boolean, id: string, text: string, ctx)
	local st = node.state
	if (refresh or st.labels[id] ~= text) and ctx.time >= st.labelRetryAt then
		if panel.label(node.params.desk, id, text) then
			st.labels[id] = text
		else
			st.labelRetryAt = ctx.time + 2 -- the desk is gone or renamed: back off, do not spin
		end
	end
end

local function write(node, name: string, v: number | boolean)
	local st = node.state
	if st.written[name] ~= v then
		if sentinel.set("/sentinel/pipelines/" .. node.params.stage .. "/parameters/" .. name, v) then
			st.written[name] = v
		end
	end
end

function script.control_process(node, ctx)
	local st, p = node.state, node.params
	for _, e in node.inputs.panel:read_events() do
		handle(node, e)
	end

	if st.holding then
		st.holdT += ctx.dt
		if st.holdT >= HOLD_S then
			st.blackout, st.holding = true, false
			cueLog("blackout on after a %.2f s hold", st.holdT)
		end
	end

	local mix = 0
	if st.fading then
		if st.dur <= 0.02 then
			st.t = 1 -- a zero fade time is a cut
		else
			st.t = math.min(st.t + ctx.dt / st.dur, 1)
		end
		mix = 0.5 - 0.5 * math.cos(math.pi * st.t) -- ease in and out
		if st.t >= 1 then
			finishFade(st)
			mix = 0
		end
	end

	-- the Stage: which two looks, how far between them, and how much light
	if st.fading then
		write(node, "cue_a", st.from - 1)
		write(node, "cue_b", st.to - 1)
	else
		write(node, "cue_a", st.live - 1)
		write(node, "cue_b", st.live - 1)
	end
	st.mix = mix
	write(node, "mix", math.floor(mix * 1000 + 0.5) / 1000)
	write(node, "master", p.master)
	write(node, "blackout", st.blackout)
	node.outputs.level:set(if st.blackout then 0 else p.master)

	-- the Desk: lights, states, colours, fader positions, readouts
	local refresh = ctx.time >= st.refreshAt
	if refresh then
		st.refreshAt = ctx.time + REFRESH_S
	end
	local fadeQ = math.floor(st.t * 100 + 0.5) / 100
	for c = 1, N do
		local idx = CUE1 + c - 1
		send(node, refresh, FB_LIT, idx, if c == st.live then 1 else 0) -- live until the fade lands
		local state, fade = LOADED, 0
		if st.fading and c == st.to then
			state, fade = FADING, fadeQ
		elseif c == st.next and st.next ~= st.live and not st.fading then
			state = SELECTED -- no "next" while a fade runs: GO would complete the fade
		end
		send(node, refresh, FB_STATE, idx, state, fade)
		local col = CUES[c].color
		send(node, refresh, FB_COLOUR, idx, col[1], col[2], col[3])
	end
	send(node, refresh, FB_LIT, GO, if not st.fading and st.next ~= st.live then 1 else 0)
	send(node, refresh, FB_STATE, GO, if st.fading then FADING else LOADED, if st.fading then fadeQ else 0)
	send(node, refresh, FB_LIT, BLACKOUT, if st.blackout then 1 else 0)
	send(node, refresh, FB_COLOUR, BLACKOUT, KILL[1], KILL[2], KILL[3])
	send(node, refresh, FB_STATE, BLACKOUT, if st.holding then FADING else LOADED,
		if st.holding then math.floor(st.holdT / HOLD_S * 100 + 0.5) / 100 else 0)
	send(node, refresh, FB_VALUE, FADE, math.floor(p.fade_s / 10 * 1000 + 0.5) / 1000)
	send(node, refresh, FB_VALUE, MASTER, math.floor(p.master * 1000 + 0.5) / 1000)

	-- readouts: formatted only when what they say changes, not 240 times a second
	local key = st.live + 16 * st.next + 256 * (if st.fading then st.from + 16 * st.to else 0)
		+ 65536 * math.floor(st.dur * 10 + 0.5)
	if refresh or key ~= st.labelKey then
		st.labelKey = key
		label(node, refresh, "r_now", string.format("%d  %s", st.live, CUES[st.live].name), ctx)
		if st.fading then
			label(node, refresh, "r_next", string.format("FADING  %d > %d   %.1f s", st.from, st.to, st.dur), ctx)
		else
			label(node, refresh, "r_next", string.format("NEXT  %d  %s", st.next, CUES[st.next].name), ctx)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- control window: a monitor of what the Brain decided and what it wrote. The Desk is the surface;
-- this shows the logic behind it. The lab's instrument greys (modules/_shared/plan_theme.hlsli)
-- packed 0xAABBGGRR; amber marks the live cue and the fade's playhead, red only a blackout, and a
-- cue's own colour shows as a toned chip.
local INK, MID, DIM, RULE = { 230, 231, 224 }, { 153, 154, 148 }, { 97, 98, 94 }, { 56, 57, 55 }
local WELL, ACCENT, ALARM = { 22, 22, 23 }, { 255, 107, 23 }, { 255, 64, 76 }
local function c(rgb: { number }, a: number?): number
	local A = math.floor(math.clamp(a or 1, 0, 1) * 255 + 0.5)
	return A * 16777216 + rgb[3] * 65536 + rgb[2] * 256 + rgb[1]
end
-- a record's own colour pulled toward grey with its luminance flattened (ptSampleColour's rule),
-- so no chip outshines the accent
local CHIP = {}
for i, cue in CUES do
	local col = cue.color
	local k = 0.62 / math.max(0.2126 * col[1] + 0.7152 * col[2] + 0.0722 * col[3], 1e-3)
	local rgb = {}
	for j = 1, 3 do
		rgb[j] = math.floor(math.clamp(0.28 + 0.55 * math.min(col[j] * k, 1), 0, 1) * 255 + 0.5)
	end
	CHIP[i] = c(rgb)
end

-- Layout: drawn text scales with the UI and draw positions do not, so rows sit far apart and
-- captions sit under their own boxes; a spacer grid of the band's height gives the window its size.
local W = 640
local SY0, SY1 = 28, 74 -- the stack
local BY0, BY1 = 104, 200 -- crossfade and blackout boxes; their titles take the top 30 px
local XFADE, HOLD = { 0, 300 }, { 320, W }
local BAND_H = 232

function script.render(node, ui)
	local st, p = node.state, node.params
	if not st.curve then
		return
	end
	ui.text_at(0, 0, c(MID), "CUE BRAIN  -  the stack's logic; the Desk draws what it sends")

	-- the stack: the live cue framed in amber (it stays live until a fade lands), next in ink; the
	-- cue a fade is heading for fills along its foot
	local gap = 6
	local cw = (W - gap * (N - 1)) / N
	for i = 1, N do
		local x0 = (i - 1) * (cw + gap)
		local x1 = x0 + cw
		local live = i == st.live
		local incoming = st.fading and i == st.to
		ui.rect_filled(x0, SY0, x1, SY1, c(WELL))
		ui.rect_filled(x0 + 5, SY0 + 5, x1 - 5, SY0 + 8, CHIP[i])
		if incoming then
			ui.rect_filled(x0, SY1 - 4, x0 + cw * st.t, SY1, c(ACCENT))
		end
		if live then
			ui.rect(x0, SY0, x1, SY1, c(ACCENT), 2)
		elseif incoming or (i == st.next and st.next ~= st.live and not st.fading) then
			ui.rect(x0, SY0, x1, SY1, c(INK), 1.5)
		end
		ui.text_at(x0 + 8, SY0 + 16, c(if live or incoming then INK else DIM), tostring(i))
	end

	-- the crossfade: the eased curve the mix follows, with the fade's playhead on it
	local b = XFADE
	ui.rect_filled(b[1], BY0, b[2], BY1, c(WELL))
	ui.text_at(b[1] + 8, BY0 + 5, c(DIM), "CROSSFADE")
	local x0, x1, y0, y1 = b[1] + 12, b[2] - 12, BY1 - 10, BY0 + 32
	local pts = st.curve
	for i = 1, 33 do
		local t = (i - 1) / 32
		pts[i][1], pts[i][2] = x0 + (x1 - x0) * t, y0 + (y1 - y0) * (0.5 - 0.5 * math.cos(math.pi * t))
	end
	ui.line(x0, y0, x1, y0, c(RULE), 1)
	ui.polyline(pts, c(MID), 1.5)
	local caption
	if st.fading then
		local px = x0 + (x1 - x0) * st.t
		ui.line(px, y0, px, y1, c(RULE), 1)
		ui.circle_filled(px, y0 + (y1 - y0) * st.mix, 4, c(ACCENT))
		caption = string.format("cue %d > %d   mix %.2f", st.from, st.to, st.mix)
	else
		caption = string.format("idle   fade time %.1f s", p.fade_s)
	end
	ui.text_at(b[1] + 2, BY1 + 5, c(MID), caption)

	-- the guarded blackout: how far the hold has run toward 0.65 s
	b = HOLD
	ui.rect_filled(b[1], BY0, b[2], BY1, c(WELL))
	ui.text_at(b[1] + 8, BY0 + 5, c(DIM), "BLACKOUT HOLD")
	local tx0, tx1, ty = b[1] + 16, b[2] - 16, (BY0 + 32 + BY1 - 10) / 2
	local function hx(s: number): number
		return tx0 + (tx1 - tx0) * s / (HOLD_S * 1.25)
	end
	ui.rect_filled(tx0, ty - 3, tx1, ty + 3, c(RULE))
	if st.blackout then
		ui.rect_filled(tx0, ty - 3, tx1, ty + 3, c(ALARM))
	elseif st.holding then
		ui.rect_filled(tx0, ty - 3, hx(math.min(st.holdT, HOLD_S)), ty + 3, c(ACCENT))
	end
	ui.line(hx(HOLD_S), ty - 10, hx(HOLD_S), ty + 10, c(INK), 1.5)
	ui.text_at(hx(HOLD_S) + 6, ty - 26, c(DIM), string.format("%.2f s", HOLD_S))
	ui.text_at(b[1] + 2, BY1 + 5, c(if st.blackout then ALARM else MID),
		if st.blackout then "BLACKOUT  -  the stage is dark" else string.format("master %.2f   stage lit", p.master))

	ui.grid_begin("band", 1, 1, 8, BAND_H, 0, 0)
	ui.grid_cell(1, 1)
	ui.text("band_spacer", " ")
	ui.grid_end()
end

-- the stack position survives a reload and a project reopen
function script.serialize(node)
	local st = node.state
	return { version = 1, live = st.live or 1, next = st.next or 2, blackout = st.blackout or false }
end
function script.deserialize(node, saved)
	if saved and saved.version == 1 then
		node.state.live = math.clamp(saved.live, 1, N)
		node.state.next = math.clamp(saved.next, 1, N)
		node.state.blackout = saved.blackout == true
	end
end

return script
