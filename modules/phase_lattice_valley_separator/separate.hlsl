RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float3 source = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    float2 p = (uv - float2(0.5, 0.5) - separator_core) * float2(aspect, 1.0);
    float radius = length(p);
    float theta = atan2(p.y, p.x);

    // This is the exact moving five-fold phase used by the upstream Iris
    // aperture, so the separation follows the authored geometry.
    float lobePhase = sin(theta * 5.0 - _Time * 0.10);
    float valley = smoothstep(valley_gate, 1.0, -lobePhase);
    valley = pow(saturate(valley), valley_sharpness);

    float authoredBoundary = lobe_scale * (0.58 + 0.13 * lobePhase);
    float innerGate = smoothstep(
        inner_radius - edge_feather,
        inner_radius + edge_feather,
        radius);
    float outerGate = 1.0 - smoothstep(
        authoredBoundary + valley_reach - edge_feather,
        authoredBoundary + valley_reach + edge_feather,
        radius);
    float cut = valley * innerGate * outerGate * valley_depth;

    float warmDominance = saturate(source.r - max(source.g, source.b));
    float warmProtection = smoothstep(0.035, 0.16, warmDominance) * preserve_warm;
    cut *= 1.0 - warmProtection;

    float3 color = source * (1.0 - cut);
    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
