struct GlitchField {
    float4 global_distortion;
    float4 slice_pattern;
    float4 fracture_pattern;
    float4 temporal_motion;
};
RWStructuredBuffer<GlitchField> OutputBuffer : register(u0);

[numthreads(1,1,1)]
void main(uint3 id : SV_DispatchThreadID) {
    float t=_Time*motion_rate;
    float pulseBoost=1.0+pulse*0.22;
    GlitchField f;
    f.global_distortion=float4(warp_amount*pulseBoost,twist_amount,fold_amount,quantize);
    f.slice_pattern=float4(slice_strength*pulseBoost,(float)slice_count,slice_width,seed);
    f.fracture_pattern=float4(0.17+quantize*0.7,0.31+warp_amount*0.4,0.13+slice_width,seed*1.73);
    f.temporal_motion=float4(t,sin(t*1.31+seed),cos(t*0.73+seed*0.37),pulse);
    OutputBuffer[0]=f;
}
