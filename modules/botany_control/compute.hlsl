// botany_control — drive the whole bouquet system from one node. Publishes master macros
// (seed, warp/melt, twist, spread, hue speed, frame drift, bloom) as control outputs. Wire to
// botany_layout (seed/spread), botany_render (warp/twist/hue), botany_frame (drift) via ref().
struct Ctrl { float seed; float warp; float twist; float spread; float hue_speed; float frame_drift; float bloom; float p7; };
RWStructuredBuffer<Ctrl> Out : register(u0);

[numthreads(1,1,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    Ctrl c;
    c.seed = master_seed;
    c.warp = warp_macro;
    c.twist = twist_macro;
    c.spread = spread_macro;
    c.hue_speed = hue_speed_macro;
    c.frame_drift = frame_drift_macro;
    c.bloom = bloom_macro;
    c.p7 = 0;
    Out[0] = c;
}
