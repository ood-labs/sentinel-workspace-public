struct MarbleProfile {
    float4 stone_color_roughness;
    float4 vein_color_scale;
    float4 vein_contrast_pore_scale;
    float4 cavity_subsurface_micro_normal;
};

RWStructuredBuffer<MarbleProfile> OutputBuffer : register(u0);

[numthreads(1,1,1)]
void main(uint3 id : SV_DispatchThreadID) {
    MarbleProfile p;
    p.stone_color_roughness = float4(stone_color, roughness);
    p.vein_color_scale = float4(vein_color, vein_scale);
    p.vein_contrast_pore_scale = float4(vein_contrast, pore_scale, 0.0, 0.0);
    p.cavity_subsurface_micro_normal = float4(cavity_depth, subsurface, micro_normal, 0.0);
    OutputBuffer[0] = p;
}
