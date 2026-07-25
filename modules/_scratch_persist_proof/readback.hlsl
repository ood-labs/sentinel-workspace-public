// Expose the write cursor's neighbourhood so capture_data_port can see whether
// slots the poke pass did NOT touch this cook survived.
struct R { uint slot, cook, magic, extra; };
struct G { uint tau, theta, hit, pad; };
struct P { uint slot, cook, magic, extra; };

StructuredBuffer<R> Ring : register(t0);
StructuredBuffer<G> Grid : register(t1);
RWStructuredBuffer<P> Probe : register(u0);

static const uint RING = 800u;

[numthreads(8, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i >= 8u) return;

    uint n = Ring[RING - 1u].cook;
    uint s = n % (RING - 1u);

    P p;
    if (i < 5u) {
        // i=0 -> slot n, i=1 -> n-1, i=2 -> n-2, i=3 -> n-3, i=4 -> n-200
        uint back = (i == 4u) ? 200u : i;
        uint idx = (s + (RING - 1u) - back) % (RING - 1u);
        R r = Ring[idx];
        p.slot = r.slot; p.cook = r.cook; p.magic = r.magic; p.extra = r.extra;
    } else if (i == 5u) {
        p.slot = RING - 1u; p.cook = n; p.magic = 0u; p.extra = s;
    } else if (i == 6u) {
        // 2D dispatch corner: last valid (tau=99, theta=159)
        G g = Grid[99u * 160u + 159u];
        p.slot = g.tau; p.cook = g.theta; p.magic = g.hit; p.extra = g.pad;
    } else {
        // 2D dispatch interior sample (tau=50, theta=80)
        G g = Grid[50u * 160u + 80u];
        p.slot = g.tau; p.cook = g.theta; p.magic = g.hit; p.extra = g.pad;
    }
    Probe[i] = p;
}
