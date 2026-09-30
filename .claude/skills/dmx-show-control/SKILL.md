---
name: dmx-show-control
description: Receive and send DMX over Art-Net or sACN (E1.31), and send OSC, from Sentinel. Covers network and universe setup, driving Sentinel parameters from a lighting console, driving fixtures from Modules with DMX Out, testing with loopback, sACNView or QLC+, trial limits and troubleshooting. Use when a user mentions DMX, Art-Net, sACN, E1.31, a lighting console, fixtures, universes, or OSC output.
---

# DMX And OSC Show Control

Read `knowledge/lighting-and-show-control.md` first; it has every parameter,
the DMX data port layout and the OSC Out model. Ready Modules for the two
common jobs ship in `tools/templates/dmx/`.

## Nodes

- `dmxin` (DMX In): listens for Art-Net or sACN and publishes a `DMX` data
  port, up to 1,024 universes, with a live universe grid in the node body.
- `dmxout` (DMX Out): sends a `DMX` data port over Art-Net or sACN on its own
  clock.
- `oscout` (OSC Out): sends expression-driven values as OSC messages.

## Workflow: console into Sentinel

1. `sentinel_app action=ping`, then `sentinel_pipeline action=list_types`.
2. Ask which protocol and universe the console sends. Art-Net addresses start
   at 0 (console "Universe 1" is usually 0); sACN universes start at 1.
3. `sentinel_pipeline action=create type=dmxin name=Console_In`, then set
   `protocol`, `universe_start` and `universe_count`. With several network
   adapters, set `bind_address` to the lighting adapter.
4. Have the user move a fader. Read `packets_per_second` and
   `active_universes` from `sentinel_pipeline action=info`, and look at the
   grid. Zero packets: firewall, adapter or protocol. Packets but a dark grid:
   the universe number.
5. Copy `tools/templates/dmx/DMX_Channel_Reader` into the project's
   `modules/`, create it, link `Console_In`'s `DMX` output to its `DMX` input
   with `sentinel_graph action=add_link`, and set `record` and `channel`.
6. Drive parameters with `sentinel_expression action=set` and
   `ref("<reader>/control_outputs/value")` (0 to 1). One reader per channel.

## Workflow: Sentinel out to fixtures

1. Ask for each fixture's DMX start address, channel mode and universe, and
   the Art-Net node's IP if the rig uses Art-Net.
2. Copy `tools/templates/dmx/DMX_RGB_Fixture` (dimmer, red, green, blue) into
   `modules/`, adapt `emit.hlsl` to the fixture's channel order, create it and
   set `universe` and `address`.
3. Create `dmxout`, link the Module's `DMX` output to it, set `protocol`.
   Art-Net: set `destination_host` to the node or fixture IP (the default
   `127.0.0.1` reaches only this machine). sACN: set the Module's `universe`
   from 1 before switching; multicast reaches every receiver.
4. Drive the fixture Module's parameters with expressions (Audio In `level`,
   tracking, Conductor phases). `packets_per_second` climbs while values
   change and drops to the keepalive rate when they hold.
5. For crossfades between looks, blend fixture-level values before the
   universe is written; raw DMX universes switch without blending.

## Workflow: OSC out

Create `oscout`, set `target_host` and `target_port`, then add one message
per value with a single action:

```text
sentinel_state action=invoke path=/sentinel/pipelines/<id>/actions/add_message address=/live/brightness type=float expr=ref("audio_in/control_outputs/level")
```

`list_messages` shows each message and its last send.

## Proving it without a rig

Build the loop inside Sentinel: fixture Module → DMX Out → DMX In → channel
reader, over Art-Net to `127.0.0.1` or sACN multicast. The reader's `raw`
output must equal the level the fixture Module writes (for example red 0.5
reads 128). For traffic on the wire, sACNView lists sACN universes and their
sources; QLC+ can play console or monitor for either protocol.

## Trial limits

A trial sends 1 DMX universe and receives 4 across the whole project. Held
universes show the license badge and count in `trial_gated_universes`. Tell
the user rather than debugging the network.

## Troubleshooting

See the table in `knowledge/lighting-and-show-control.md`. The usual causes,
in order: universe number off by one, Art-Net `destination_host` left at
`127.0.0.1`, the Windows firewall prompt dismissed, the wrong network adapter,
and a second sACN source with a higher priority on the same universe.
