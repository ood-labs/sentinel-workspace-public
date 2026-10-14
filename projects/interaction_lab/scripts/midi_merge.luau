--!strict
-- MIDI Merge - an event input takes ONE link (a second link into it replaces the first), so two note
-- streams reach one MIDI Out through here.
--
-- In   a, b   (Event)  anything - here the Pulse Bus's and the Pattern Bus's NoteOn / NoteOff
-- Out  notes  (Event)  every record from both, passed on unchanged, timestamps kept (so MIDI Out
--                      still places each note at the time its bus stamped)
--
-- Control window: how many records each input has passed, and how long since its last one.

local script = {}
script.manifest = {
	name = "MIDI Merge",
	inputs = { { name = "a", type = "event" }, { name = "b", type = "event" } },
	outputs = { { name = "notes", type = "event" } },
	params = {},
}

local INPUTS = { "a", "b" }

function script.init(node)
	node.state.count = { a = 0, b = 0 }
	node.state.last = { a = -1e9, b = -1e9 }
end

function script.control_process(node, ctx)
	local st = node.state
	for _, name in INPUTS do
		for _, e in node.inputs[name]:read_events() do
			node.outputs.notes:emit({ event_type = e.event_type, timestamp_ns = e.timestamp_ns, payload = e.payload })
			st.count[name] += 1
			st.last[name] = ctx.time
		end
	end
end

function script.render(node, ui)
	local st = node.state
	if not st.count then
		return
	end
	local now = time.now()
	ui.text("title", "MIDI MERGE  -  two note streams into one MIDI Out")
	for _, name in INPUTS do
		local age = now - st.last[name]
		ui.text("in_" .. name, string.format("%s   %6d records   %s", name, st.count[name], if age < 1e6 then string.format("last %.1f s ago", age) else "none yet"))
	end
end

return script
