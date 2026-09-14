# Lighting And Show Control: DMX In, DMX Out, OSC Out

Sentinel talks to lighting consoles, network fixtures, and show-control software through three Control nodes. `dmxin` receives DMX universes over Art-Net or sACN into a typed data port. `dmxout` sends a DMX data port to fixtures over Art-Net or sACN. `oscout` sends expression-driven values to any OSC receiver. None of them produce pixels; they carry data ports and control outputs and are wired like any other Control node.

Call `sentinel_pipeline action=list_types` first. Installs before 0.5.73 ship `artnetin` and `artnetout` instead of the DMX pair, and those ids still work as hidden aliases on current builds. Software and loopback verification is complete on every path below. Physical console and fixture verification is still an operator hardware gate, so treat a real rig as something to prove on site, not something Sentinel has already proven for you.

## DMX In

Create it with `sentinel_pipeline action=create type=dmxin name=<id>`. It listens on the network and publishes one data output named `DMX`.

Parameters that matter:

- `protocol`: `artnet` (default, UDP 6454) or `sacn` (E1.31, UDP 5568 with multicast joins).
- `universe_start` and `universe_count`: the first address and how many consecutive universes to receive, up to 1,024. Art-Net addresses are 0 to 32,767 (`Net:SubNet:Universe` packed as `(Net << 8) | (SubNet << 4) | Universe`); sACN universes are 1 to 63,999. The whole range must fit the protocol's address space.
- `bind_address`: the adapter to listen on. Leave `0.0.0.0` unless the machine has several adapters and the console lives on one of them.
- `timeout_ms` (default 2,500) and `hold_last_values` (default on): a universe that stops arriving is marked inactive after the timeout; with hold on it keeps its last channel values, with hold off it zeros them.
- sACN only: `sacn_unicast_only` skips multicast joins; `sacn_honor_sync` (default on) waits for the console's synchronization packet before publishing a multi-universe frame.

Control outputs: `packets_per_second`, `active_universes`, `last_packet_age_ms`, `dropped_packets`, and under sACN `sources_active` and `sequence_errors`. Drive any parameter from them with `sentinel_expression action=set`, for example `ref("dmx_in/control_outputs/packets_per_second")`.

Under sACN, several consoles can send the same universe. DMX In keeps the highest-priority source and, among equal priorities, takes each channel's maximum. A source that goes quiet for 2.5 seconds drops out; a console that sends stream-terminated drops out immediately.

## DMX Out

Create it with `type=dmxout` and wire a DMX-schema data output into its `DMX` input with `sentinel_graph action=add_link`. Any other schema is refused with a named reason. It sends every live universe in the port on its own clock, independent of render FPS.

Parameters that matter:

- `protocol`: `artnet` or `sacn`.
- `destination_host` and `destination_port`: the unicast target (Art-Net default `127.0.0.1:6454`). Under sACN with `sacn_multicast` on (default) the destination is the universe's multicast group and `destination_port` is ignored; with it off, packets go to `destination_host` on 5568.
- `send_rate_hz` (default 40, max 44) and `keepalive_hz` (default 1): changed universes send at the send rate, unchanged ones resend at the keepalive rate.
- `enabled_universes`: a zero-based record-index mask such as `0,2-4`; empty sends all live records. `port_address_offset` shifts every address after selection.
- Art-Net only: `legacy_broadcast` with an explicit `interface_address`. It is labeled non-conformant on purpose; unicast is the default and the right choice for Art-Net 4 gear.
- sACN only: `priority` (default 100, 0 to 200), `sacn_sync_address` (0 disables synchronization), `sacn_terminate_on_stop` (default on, tells receivers the stream ended).

Control outputs: `packets_per_second`, `universes_sent`, `readbacks_dropped`, `send_errors`. A climbing `send_errors` means the destination is unreachable or the adapter is wrong; `health_reasons` in `sentinel_pipeline info` names a bind problem.

Freeze and Bypass on DMX Out both stop the sender. It is a pure data sink, so Bypass has nothing to pass through.

## Universe preview

Both DMX nodes draw the selected universe in the node body as a 32 by 16 grid, one square per channel in row-major order, channel 1 at the top left. Stale universes draw at half intensity; a universe that has never carried data draws in the disabled tint. The header holds `<` and `>` arrows that step through universes with data, a jump field for a record index, and a label with the protocol address beside it. The selection is the `preview_universe` parameter, saves with the project, and the normal `P` button hides or shows the grid.

Use the grid as the first sanity check: if the console says it is sending and the grid stays dark, the universe range, adapter, or protocol is wrong before anything downstream is.

## The DMX data port for Module authors

The `DMX` port is a structured buffer of 2,048-byte records, each holding 512 `uint` channel values. Record 0 is a header, records 1 to 8 hold per-universe metadata, and universe `u` lives at record `9 + u`. The helper include ships at `tools/templates/module-includes/dmx_schema_v2.hlsli`; copy it into the project's `modules/_shared/` folder the way other shared includes are kept, include it, and use its helpers instead of hand-computing offsets:

```hlsl
#include "../_shared/dmx_schema_v2.hlsli"
// records is the DMX data input as StructuredBuffer<DmxRecord>
uint v = records[universeRecord(u)].channels[c];   // channel c (0-based) of universe u, 0..255
uint len = records[metadataRecord(u)].channels[metadataSlot(u) + 2]; // 0 means inactive
```

Header slot 0 is the schema version and reads 2 on current builds. Slot 1 is the number of live universes, slot 2 a generation counter that advances on every publication, slot 6 packets per second, slot 7 dropped packets. Metadata for each universe is four slots: address, last sequence, payload length (0 when inactive), and age in frames. A Module that produces DMX for DMX Out writes the same layout and must set slot 0 to 2; a version-1 port is refused with a status message asking you to re-save the producer.

Declare the port in a Module manifest as a data input or output with one field, `channels`, type `uint`, count 512, and read the live count from the header rather than assuming the configured capacity. Capacity is `elementCount - 9` records.

Readback for proof: `sentinel_pipeline action=capture_data_port pipeline_id=<id> port=DMX max_elements=<n>`. Set `max_elements` explicitly to reach the universe records you want; the default only covers the first few.

## OSC Out

Create it with `type=oscout`. A fresh node has no messages. Add each one with a single StateTree action that creates the message, registers its parameters, and binds its value source:

```text
sentinel_state action=invoke path=/sentinel/pipelines/<id>/actions/add_message address=/live/brightness type=float expr=ref("audio_in/control_outputs/level")
```

The response carries the message `id`, the writable `path` of its value parameter, and `expression_ok`. Without `expr`, the value parameter is a plain float you can write or drive later with `sentinel_expression action=set`. `list_messages` returns every message with its id, address, type, enabled flag, current value, expression, and last send time. `remove_message` takes an `id` and clears its expression. Ids are stable for the life of the project and never reused, so a remove in the middle of the list does not renumber anything.

Each message registers `msg_<id>_address`, `msg_<id>_type`, `msg_<id>_value`, and `msg_<id>_enabled` under the node's parameters. Addresses begin with `/`, contain no whitespace, and may be up to 1,023 bytes; an invalid address draws red in Properties and sends nothing.

Types on the wire:

- `float`: OSC float32.
- `int`: rounded and clamped to int32.
- `bool`: OSC `T` or `F` from value > 0.5.
- `trigger`: an argument-free message once per rising edge above 0.5.

Node-level settings: `target_host` (default `127.0.0.1`) and `target_port` (default 9010); `send_mode` `on_change` (default, with `change_epsilon`) or `continuous` at `send_rate_hz` (default 30, up to 200); `bundle` (default on) collects every enabled message into one timestamped bundle per tick. There is no message cap. When the enabled count exceeds what the send thread or the 65,507-byte datagram budget can carry, the node body shows a warning naming the limiting budget and the `over_budget` control output goes to 1; messages keep sending, and oversized bundles split across datagrams. Control outputs also include `active_slots` (the enabled message count) and `send_errors`.

For a human operator, the header `+` adds a message at `/` and focuses its address in Properties, which lists only the messages that exist. Add, remove, and edits made in the UI round-trip through undo.

OSC Out is independent of the global OSC feedback echo in Settings. Enabling both sends both streams. To prove a message loop inside Sentinel, point `target_port` at Sentinel's own OSC receive port (`/sentinel/osc/receive_port`, usually 9000) with an address that names a parameter, and watch that parameter follow the source; the default target 9010 avoids that port so a plain node never feeds itself by accident.

## A show-control pattern

1. `dmxin` receives the console's universes; a Module reads the port and renders the stage simulation, or a fixture's channels drive parameters through expressions built from a Module's control outputs.
2. A Module authors a DMX buffer from audio, tracking, or choreography and feeds `dmxout`, which sends it to real fixtures.
3. `oscout` mirrors whatever values the show needs elsewhere, one `add_message` per value, driven by `ref()` expressions on control outputs.

Wire the DMX ports with `sentinel_graph action=add_link`, never `set_input`. Watch `packets_per_second` on both DMX nodes and the universe grid before trusting the fixtures, and read `sentinel_pipeline info` for `health_reasons` when a node reports zero traffic.
