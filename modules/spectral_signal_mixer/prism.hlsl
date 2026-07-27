RWTexture2D<float4> OutputUAV : register(u0);

float2 shapeUv(float2 uv) {
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - performance_center) * float2(aspect, 1.0);
    if (visual_mode == 1) {
        float a = atan2(p.y, p.x);
        float r = length(p);
        float sector = 6.2831853 / max(symmetry, 1.0);
        a = abs(fmod(a + sector * 0.5, sector) - sector * 0.5);
        p = float2(cos(a), sin(a)) * r;
    } else if (visual_mode == 2) {
        float2 cell = floor((uv + _Time * 0.007 * drift) * mosaic_cells);
        float2 local = frac((uv + _Time * 0.007 * drift) * mosaic_cells);
        local = abs(local - 0.5) * 2.0;
        uv = (cell + local) / mosaic_cells;
        p = (uv - performance_center) * float2(aspect, 1.0);
    }
    return p / float2(aspect, 1.0) + performance_center;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float2 q = saturate(shapeUv(uv));
    float2 radial = normalize(q - performance_center + float2(1e-4, 0.0));
    float2 tangent = float2(-radial.y, radial.x);
    float px = chroma_shift / max(_Resolution.y, 1.0);
    float wobble = sin(length(q - performance_center) * 42.0 - _Time * 0.6 * drift);
    float2 off = (radial + tangent * wobble * 0.45) * px;
    float3 src;
    src.r = _Tex0.SampleLevel(LinearSampler, saturate(q + off), 0).r;
    src.g = _Tex0.SampleLevel(LinearSampler, q, 0).g;
    src.b = _Tex0.SampleLevel(LinearSampler, saturate(q - off), 0).b;

    float2 texel = 1.0 / _Resolution.xy;
    float l = dot(_Tex0.SampleLevel(LinearSampler, saturate(q - float2(texel.x,0)),0).rgb, float3(0.299,0.587,0.114));
    float r = dot(_Tex0.SampleLevel(LinearSampler, saturate(q + float2(texel.x,0)),0).rgb, float3(0.299,0.587,0.114));
    float u = dot(_Tex0.SampleLevel(LinearSampler, saturate(q - float2(0,texel.y)),0).rgb, float3(0.299,0.587,0.114));
    float d = dot(_Tex0.SampleLevel(LinearSampler, saturate(q + float2(0,texel.y)),0).rgb, float3(0.299,0.587,0.114));
    float edge = saturate(length(float2(r-l,d-u)) * 4.0);
    float3 neon = lerp(float3(0.04,0.86,1.0), float3(1.0,0.08,0.56), uv.x + wobble * 0.1);
    float3 col = src + neon * edge * edge_gain;
    OutputUAV[id.xy] = float4(col, 1.0);
}
