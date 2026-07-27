RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8,8,1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float2 tap = 0.5 / float2(1280.0, 720.0);
    float3 c = _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(-tap.x,-tap.y)),0).rgb;
    c += _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(tap.x,-tap.y)),0).rgb;
    c += _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(-tap.x,tap.y)),0).rgb;
    c += _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(tap.x,tap.y)),0).rgb;
    c *= 0.25;
    float y = dot(c,float3(0.2126,0.7152,0.0722));
    c = lerp(y.xxx,c,color_retention);
    c = (c - 0.5) * analysis_contrast + 0.5 + luma_bias;
    OutputUAV[id.xy] = float4(saturate(c),1.0);
}
