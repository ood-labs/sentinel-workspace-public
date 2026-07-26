// CRYO / Pulse Baseline — publish the accepted-onset ring as a typed data output.
//
// BASELINE ONLY. modules/cryo_pulse has no data_outputs, so MCP-polled scalar
// counters cannot supply the per-hit timing a +/-25 ms F1 window needs. This
// pass copies the ring analyze.hlsl writes at pstate[655..1166] into a typed
// {lane_id, onset_serial, hop_index, sample_position} buffer.
//
// One thread per hit slot. Unwritten slots carry onset_serial == 0, which the
// harness treats as empty. Serials start at 1 and increase monotonically, so a
// consumer dedupes by serial and detects ring wrap by a serial gap.

struct PS { float a, b, c, d, e, f, g, h; };
struct Hit { uint lane_id, onset_serial, hop_index, sample_position; };

StructuredBuffer<PS> Src : register(t0);
RWStructuredBuffer<Hit> Dst : register(u0);

static const uint HITS_BASE = 655u;
static const uint HITCAP    = 512u;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i >= HITCAP) return;

    PS r = Src[HITS_BASE + i];

    Hit h;
    h.lane_id         = (uint)max(r.a, 0.0);
    h.onset_serial    = (uint)max(r.b, 0.0);
    h.hop_index       = (uint)max(r.c, 0.0);
    h.sample_position = (uint)max(r.d, 0.0);
    Dst[i] = h;
}
