struct Ctrl {
    float style; float melt; float sag; float spread;
    float explode; float primary; float secondary; float twist;
    float painterly; float facet; float hue; float heat;
    float scatter; float primary_mode; float secondary_mode; float marker;
};
RWStructuredBuffer<Ctrl> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    Ctrl c;
    c.style = (float)warp_style;
    c.melt = melt_macro; c.sag = sag_macro; c.spread = spread_macro; c.explode = explode_macro;
    c.primary = warp_primary; c.secondary = warp_secondary; c.twist = twist_macro;
    c.painterly = painterly_macro; c.facet = facet_macro; c.hue = hue_macro; c.heat = heat_macro;
    c.scatter = (float)scatter_macro;
    c.primary_mode = warp_style == 2 ? 5.0 : (warp_style == 3 ? 3.0 : 0.0);
    c.secondary_mode = warp_style == 2 ? 6.0 : 1.0;
    c.marker = 76221.0;
    OutputBuffer[0] = c;
}
