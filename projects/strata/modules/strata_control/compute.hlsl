struct Ctrl {
    float seed; float melt; float twist; float marble_warp;
    float spread; float wire_scale; float palette; float blob_mix;
    float marble_mix; float wire_mix; float marks_mix; float feature_enabled;
    float feature_gain; float feature_count; float marker; float pad;
};

RWStructuredBuffer<Ctrl> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    Ctrl c;
    c.seed = master_seed;
    c.melt = melt_macro;
    c.twist = twist_macro;
    c.marble_warp = marble_warp_macro;
    c.spread = spread_macro;
    c.wire_scale = wire_scale_macro;
    c.palette = (float)palette_variant;
    c.blob_mix = blob_mix;
    c.marble_mix = marble_mix;
    c.wire_mix = wire_mix;
    c.marks_mix = marks_mix;
    c.feature_enabled = feature_enabled != 0 ? 1.0 : 0.0;
    c.feature_gain = feature_gain;
    c.feature_count = (float)_Data0_Count;
    c.marker = 75110.0;
    c.pad = 0.0;
    OutputBuffer[0] = c;
}
