// Deck reflections, ported from PHAGE's floor_reflections: current-frame, depth-tested screen-space
// reflections of the surfaces (fixture faces, bodies, rigging) in the stage deck, with a Fresnel term and a
// roughness blur. No temporal history. Works directly in Sentinel's view space; the deck is y = 0 either way.
RWTexture2D<float4> OutputUAV : register(u0);

bool project(float3 p, out float2 uv)
{
    float4 q = mul(_ViewProjMatrix, float4(p, 1.0));
    uv = float2(q.x, -q.y) / max(q.w, 0.00001) * 0.5 + 0.5;
    return q.w > 0.0 && all(uv > 0.001) && all(uv < 0.999);
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    OutputUAV[id.xy] = 0.0;
    if (floor_gloss <= 0.0) return;
    float2 uv = ((float2)id.xy + 0.5) / float2(w, h), ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 farW = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    float3 rd = normalize(farW.xyz / farW.w - _CameraPos);
    float4 base = _Tex0.SampleLevel(PointSampler, uv, 0);
    if (base.a <= 0.0) return;
    float3 p = _CameraPos + rd * base.a;
    if (abs(p.y) > 0.025) return;
    float3 dir = reflect(rd, float3(0, 1, 0));
    float t = 0.12, previous = t;
    float2 hitUV = 0.0;
    bool found = false;
    float hitDepth = 0.0;
    [loop] for (uint k = 0u; k < 36u; k++)
    {
        float3 q = p + float3(0, 0.035, 0) + dir * t;
        float2 suv;
        if (!project(q, suv)) break;
        float d = _Tex0.SampleLevel(PointSampler, suv, 0).a, rayDepth = length(q - _CameraPos);
        if (d > 0.0 && rayDepth > d && rayDepth - d < max(0.35, t * 0.12))
        {
            float lo = previous, hi = t;
            [unroll] for (uint j = 0u; j < 5u; j++)
            {
                float mid = (lo + hi) * 0.5;
                float3 m = p + float3(0, 0.035, 0) + dir * mid;
                float2 mu;
                project(m, mu);
                float md = _Tex0.SampleLevel(PointSampler, mu, 0).a;
                if (md > 0.0 && length(m - _CameraPos) > md) hi = mid; else lo = mid;
            }
            float3 qh = p + float3(0, 0.035, 0) + dir * hi;
            project(qh, hitUV);
            hitDepth = _Tex0.SampleLevel(PointSampler, hitUV, 0).a;
            found = abs(length(qh - _CameraPos) - hitDepth) < 0.4;
            break;
        }
        previous = t;
        t += 0.12 + t * 0.18;
    }
    if (!found) return;
    float2 pixel = 1.0 / float2(w, h);
    float radius = 1.0 + floor_rough * floor_rough * 16.0;
    float3 color = 0.0;
    float weight = 0.0;
    [unroll] for (uint k2 = 0u; k2 < 5u; k2++)
    {
        float2 offset = k2 == 0u ? float2(0, 0) : (k2 == 1u ? float2(1, 0) : (k2 == 2u ? float2(-1, 0) : (k2 == 3u ? float2(0, 1) : float2(0, -1))));
        float4 tap = _Tex0.SampleLevel(LinearSampler, hitUV + offset * pixel * radius, 0);
        float a = exp(-abs(tap.a - hitDepth) * 0.4);
        color += tap.rgb * a;
        weight += a;
    }
    float edge = saturate(min(min(hitUV.x, 1.0 - hitUV.x), min(hitUV.y, 1.0 - hitUV.y)) * 20.0);
    float fresnel = 0.04 + 0.96 * pow(1.0 - saturate(-rd.y), 5.0);
    OutputUAV[id.xy] = float4(color / max(weight, 0.001) * fresnel * floor_gloss * (1.0 - floor_rough * 0.65) * edge, 1.0);
}
