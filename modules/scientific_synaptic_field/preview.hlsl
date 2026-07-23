RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float4 field = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float2 flow = normalize((field.rg * 2.0 - 1.0) + float2(1e-5, 0.0));
    float energy = field.b;
    float occupancy = field.a;
    float px = 1.0 / _Resolution.y;

    float contour = 1.0 - smoothstep(0.02, 0.09, abs(frac(energy * contour_bands) - 0.5));
    float vectorGrain = 0.5 + 0.5 * sin(dot(uv * float2(16.0 / 9.0, 1.0), flow) * vector_frequency);
    float registration = smoothstep(0.016, 0.0,
        min(abs(frac(uv.x * 24.0) - 0.5), abs(frac(uv.y * 14.0) - 0.5)));

    float3 col = background_ink;
    col += field_ink * energy * field_gain;
    col += contour_ink * contour * energy * contour_gain;
    col += vector_ink * vectorGrain * occupancy * vector_visibility;
    col += registration * 0.025;

    float border = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    col += smoothstep(px * 1.5, px * 0.25, border) * 0.22;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
