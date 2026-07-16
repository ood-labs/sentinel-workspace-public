// strata_control — the "drive the whole system from one node" macro. Publishes a master
// SEED (reshuffles every plate's arrangement at once → infinite variation) plus distortion
// macros (melt/twist for the solids, marble warp) as control outputs. Wire to each plate's
// seed + warp params via ref() expressions. This is the knob that makes strata infinitely
// variable while keeping palette + framing fixed.

struct Ctrl { float seed; float melt; float twist; float marble_warp; float spread; float wire_scale; float p6; float p7; };
RWStructuredBuffer<Ctrl> Out : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    Ctrl c;
    c.seed = master_seed;
    c.melt = melt_macro;
    c.twist = twist_macro;
    c.marble_warp = marble_warp_macro;
    c.spread = spread_macro;
    c.wire_scale = wire_scale_macro;
    c.p6 = 0; c.p7 = 0;
    Out[0] = c;
}
