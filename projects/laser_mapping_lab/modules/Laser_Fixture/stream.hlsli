// The fixture's own copy of its Scan Signal input, taken once per cook by the snapshot pass.
// A Laser Out Sent Stream is published from Laser Out's sender thread and can change between two
// passes of the same cook: curve_map would index one stream and project draw another, which put
// random lit lines across the picture. Every pass after snapshot reads this copy instead.
#ifndef FIXTURE_STREAM_HLSLI
#define FIXTURE_STREAM_HLSLI
struct StreamScan { float4 endpoints, color0, color1, timing, meta; };
StructuredBuffer<StreamScan> Stream : register(t2);
uint StreamCount() { return 1024; }
#endif
