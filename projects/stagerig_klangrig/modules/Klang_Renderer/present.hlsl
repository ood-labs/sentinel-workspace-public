float4 main(VS_OUTPUT In):SV_TARGET0{
 float3 sharp=_Tex0.SampleLevel(PointSampler,In.Uv,0).rgb;
 float3 soft=_Tex1.SampleLevel(LinearSampler,In.Uv,0).rgb;
 float3 streak=_Tex2.SampleLevel(LinearSampler,In.Uv,0).rgb;
 float3 c=(lerp(sharp,soft,saturate(bloom))+streak*streak_strength)*exposure;
 // Camera-style highlight shoulder: low exposure preserves chroma;
 // high exposure rolls hot saturated cores toward neutral clipping.
 float peak=max(c.r,max(c.g,c.b));
 float white=1-exp(-max(0,peak-sensor_white_start)*sensor_response);
 c=lerp(c,peak.xxx,white);
 c=1-exp(-c);return float4(pow(max(c,0),1/2.2),1);
}
