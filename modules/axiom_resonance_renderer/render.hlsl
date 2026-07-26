RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float4 fieldSample = _Tex1.SampleLevel(LinearSampler, uv, 0);
    float4 topologyPlate = _Tex2.SampleLevel(LinearSampler, uv, 0);
    float2 flow = (fieldSample.rg * 2.0 - 1.0) / float2(aspect, 1.0);
    float topology = fieldSample.b;
    float gesture = fieldSample.a;
    float warpAmount = feature_warp * (0.34 + topology * 0.92 + gesture * 0.78);
    float2 warpedUv = uv + flow * warpAmount;

    float3 echoSum = 0.0;
    float echoWeight = 0.0;
    float decay = 1.0;
    [loop]
    for (int i = 0; i < 7; ++i)
    {
        if (i >= echo_count) break;
        float fi = (float)i;
        float side = (i % 2 == 0) ? 1.0 : -1.0;
        float2 echoUv = warpedUv + flow * echo_spacing * fi * side;
        float3 echoColor = _Tex0.SampleLevel(LinearSampler, echoUv, 0).rgb;
        echoSum += echoColor * decay;
        echoWeight += decay;
        decay *= echo_decay;
    }
    float3 source = echoSum / max(echoWeight, 1e-4);
    float sourceLuma = luminance(source);
    float printMask = smoothstep(threshold - threshold_softness,
                                 threshold + threshold_softness,
                                 sourceLuma);

    float2 px = 1.0 / _Resolution.xy;
    float topologyX = _Tex1.SampleLevel(LinearSampler, uv + float2(px.x * 2.0, 0.0), 0).b;
    float topologyY = _Tex1.SampleLevel(LinearSampler, uv + float2(0.0, px.y * 2.0), 0).b;
    float topologyEdge = saturate(length(float2(topologyX - topology, topologyY - topology)) * 7.0);
    float fault = smoothstep(0.18, 0.78, topology * gesture + topologyEdge * 0.72);

    // Offset copies of the explicit topology plate turn the real route graph
    // into a layered engraving rather than an invisible deformation source.
    float4 topologyEchoA = _Tex2.SampleLevel(LinearSampler, uv + flow * topology_echo, 0);
    float4 topologyEchoB = _Tex2.SampleLevel(LinearSampler, uv - flow * topology_echo * 1.7, 0);
    float routeLayer = saturate(topologyPlate.r + topologyEchoA.r * 0.52 + topologyEchoB.r * 0.28);
    float nodeLayer = saturate(topologyPlate.g + topologyEchoA.g * 0.36);
    float vectorLayer = saturate(topologyPlate.b + topologyEchoB.b * 0.42);
    float explicitAccent = saturate(topologyPlate.a + topologyEchoA.a * 0.55);

    float3 col;
    if (composition_mode == 1)
    {
        float xray = saturate(abs(sourceLuma - threshold) * 4.2 + topology * 0.72);
        col = lerp(ink_color, paper_color, xray);
    }
    else if (composition_mode == 2)
    {
        float bands = step(0.58, frac((uv.y + flow.x * 0.09) * 18.0));
        float ruptureMask = saturate(printMask * lerp(0.42, 1.0, bands) + topology * 0.34);
        col = lerp(ink_color, paper_color, ruptureMask);
    }
    else
    {
        float3 darkPaper = paper_color * dark_paper_gain;
        float carvedPlate = printMask * (0.54 + topology * 0.18);
        col = lerp(ink_color, darkPaper, carvedPlate);
    }

    float topologyLine = smoothstep(0.22, 0.82, topology) * topology_ink;
    col = lerp(col, paper_color * 0.64, saturate(topologyLine * (1.0 - printMask) * 0.55));
    col = max(col, paper_color * routeLayer * route_overlay * 0.66);
    col = max(col, paper_color * nodeLayer * node_overlay * 0.82);
    col = max(col, paper_color * vectorLayer * vector_overlay * 0.48);
    float accentLayer = saturate(fault * fault_accent + explicitAccent * fault_accent * 0.72);
    col = lerp(col, accent_color, accentLayer);

    // Registration frame and a data-derived bottom cadence strip.
    float border = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    col = lerp(col, paper_color, smoothstep(0.0032, 0.0012, border) * 0.52);
    if (uv.y > 0.965 && uv.y < 0.988)
    {
        float cadence = step(frac(uv.x * 48.0), saturate(topology * 0.72 + gesture * 0.28));
        col = lerp(col, paper_color, cadence * 0.48);
    }

    col *= exposure;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
