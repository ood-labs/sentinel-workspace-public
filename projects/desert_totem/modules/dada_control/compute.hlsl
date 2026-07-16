// dada_control — a tiny "drive from outside" macro node. Publishes its slider values
// as control outputs so ONE node reshapes + distorts the whole scene: wire its
// outputs to dada_layout (spread/explode) and dada_render (melt/sag) via ref().

struct Ctrl { float melt; float sag; float spread; float explode; float p4; float p5; float p6; float p7; };
RWStructuredBuffer<Ctrl> Out : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    Ctrl c;
    c.melt = melt_macro;
    c.sag = sag_macro;
    c.spread = spread_macro;
    c.explode = explode_macro;
    c.p4 = 0; c.p5 = 0; c.p6 = 0; c.p7 = 0;
    Out[0] = c;
}
