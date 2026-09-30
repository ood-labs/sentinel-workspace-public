float4 main(VS_OUTPUT input) : SV_TARGET0 {
    return float4(float3(red, green, blue) * dimmer, 1.0);
}
