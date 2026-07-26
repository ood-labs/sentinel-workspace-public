// Write exactly ONE slot per cook. Slot 0 doubles as the cook counter.
struct R { uint slot, cook, magic, extra; };
RWStructuredBuffer<R> Ring : register(u0);

static const uint RING = 800u;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    // Slot 799 is the cursor/counter home. Everything else is ring payload.
    uint n = Ring[RING - 1u].cook + 1u;

    R c;
    c.slot = RING - 1u; c.cook = n; c.magic = 0xC0FFEEu; c.extra = 0u;
    Ring[RING - 1u] = c;

    uint s = n % (RING - 1u);
    R r;
    r.slot = s; r.cook = n; r.magic = 0xBEEFu; r.extra = n * 7u;
    Ring[s] = r;
    // Deliberately writes NOTHING else. If the buffer is cleared or reallocated
    // per cook, slots s-1 and s-2 will read back zeroed.
}
