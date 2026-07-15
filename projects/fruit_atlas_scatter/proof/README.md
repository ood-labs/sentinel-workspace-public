# Fruit Transit Chamber proof

Proof captured on 2026-07-15 from the live Sentinel project.

- `fruit-transit-chamber.png`: active **Live Fill** output with continuous Atlas replacement, three clones per occupied identity, and the Hero camera.
- `motion-console.png`: responsive Canvas output from the monochrome four-lane Fruit Motion Console.
- Deterministic motion capture: 180/180 frames written, 0 dropped, normalized lifecycle played twice.
- Motion evaluation: smoothness 8.5/10, temporal consistency 9/10; forward swarm and depth acceleration read clearly, with no bounce in Flythrough and a virtually seamless loop.
- Atlas target state: 24 slots, 3 texture columns, `128x224` cells, interval capture enabled at 120 frames.
- Final endpoint: exactly one Group Output.
- Scene Group: one flat group, zero child groups, eight direct controls, five group presets.
- Node presets: `Four Lane Flight` and `Transit Chamber`; the latter includes a 2048-byte durable card-state payload.

The motion MP4 is intentionally kept out of the portable project to avoid shipping a large generated artifact. It can be reproduced with a `phase` sweep from 0 to 1 while `spawn_rate=0`, then restoring the Live Fill preset.
