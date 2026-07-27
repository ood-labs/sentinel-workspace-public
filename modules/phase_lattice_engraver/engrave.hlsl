RWTexture2D<float4> OutputUAV : register(u0);

float engrave_luma(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - float2(0.5, 0.5) - engrave_core) * float2(aspect, 1.0);
    float radius = length(p);

    float3 centerColor = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float lumC = engrave_luma(centerColor);
    float lumL = engrave_luma(_Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0.0), 0).rgb);
    float lumR = engrave_luma(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).rgb);
    float lumU = engrave_luma(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y), 0).rgb);
    float lumD = engrave_luma(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).rgb);

    float2 gradient = float2(lumR - lumL, lumD - lumU);
    float laplacian = abs(lumL + lumR + lumU + lumD - lumC * 4.0);
    float edgeResponse = length(gradient) * edge_gain + laplacian * 0.72;

    float focalMask = 1.0 - smoothstep(0.30, 0.78, radius);
    float coreMask = (1.0 - smoothstep(0.07, 0.29, radius)) * center_clarity;
    float localEdgeThreshold = edge_threshold *
        (1.0 + coreMask * 1.85 + (1.0 - focalMask) * 0.72);
    float etchedEdge = smoothstep(localEdgeThreshold, localEdgeThreshold + 0.10, edgeResponse);

    float localBodyThreshold = body_threshold + coreMask * 0.20;
    float brightBody = smoothstep(localBodyThreshold, localBodyThreshold + 0.16, lumC);
    float tonalDepth = pow(saturate(lumC), 1.25);
    float subjectMask = smoothstep(0.14, 0.38, lumC) * focalMask;
    float contrastLum = pow(saturate((lumC - 0.055) / 0.945), 1.42);
    float subjectRelief = subjectMask * saturate(contrastLum * 1.38);
    float bodyRelief = max(
        brightBody * (1.0 - focalMask) * 0.10,
        subjectRelief * lerp(1.0, 0.34, coreMask));
    float edgeRelief = etchedEdge * lerp(0.18, 0.38, focalMask) *
        lerp(0.42, 1.0, tonalDepth) * lerp(1.0, 0.67, coreMask);
    float neutralStructure = max(edgeRelief, bodyRelief);

    float fineLine = smoothstep(localEdgeThreshold * 0.66, localEdgeThreshold + 0.055, edgeResponse);
    float3 neutral = neutralStructure * float3(0.92, 0.94, 0.90);
    neutral += fineLine * (1.0 - brightBody) * lerp(0.025, 0.085, focalMask) *
        float3(0.58, 0.60, 0.57);

    float redDominance = max(0.0, centerColor.r - max(centerColor.g, centerColor.b));
    float ringDistance = (radius - accent_radius) / max(accent_width, 0.001);
    float gravitationalBand = exp(-ringDistance * ringDistance);
    float accent = smoothstep(accent_gate, accent_gate + 0.18, redDominance);
    accent *= gravitationalBand * smoothstep(localEdgeThreshold * 0.5, localEdgeThreshold + 0.08, edgeResponse);

    float3 color = lerp(neutral, float3(1.0, 0.115, 0.025), accent * 0.93);

    float2 corePx = p * _Resolution.y;
    float coreMark =
        (1.0 - smoothstep(0.0, 0.70, abs(corePx.x))) * step(abs(corePx.y), 9.0) +
        (1.0 - smoothstep(0.0, 0.70, abs(corePx.y))) * step(abs(corePx.x), 9.0);
    color += saturate(coreMark) * float3(0.14, 0.14, 0.13);

    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
