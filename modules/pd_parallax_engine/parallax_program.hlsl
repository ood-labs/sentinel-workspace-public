#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct DebtQuantum
{
    float2 position;
    float2 axis;
    float mass;
    float radius;
    uint kind;
    uint sourceIndex;
    uint ledgerId;
    uint active;
    float phase;
    float age;
};

StructuredBuffer<DebtQuantum> DebtInput : register(t2);

float pdLuma(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

float pdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float pdBox(float2 p, float2 halfExtent)
{
    float2 d = abs(p) - halfExtent;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float pdStroke(float distanceValue, float width)
{
    float aa = 1.5 / max(_Resolution.y, 1.0);
    return 1.0 - smoothstep(width, width + aa, distanceValue);
}

float pdRing(float distanceValue, float radius, float width)
{
    return pdStroke(abs(distanceValue - radius), width);
}

float2 pdRotateBasis(float2 value, float2 axis, float2 side)
{
    return float2(dot(value, axis), dot(value, side));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float phaseValue = frac(phase);

    float4 field = _Tex1.SampleLevel(LinearSampler, uv, 0.0);
    float2 displacement = (field.xy - 0.5) * 2.0;
    float liabilityDepth = field.z;
    float stress = field.w;
    float2 warpedUv = uv + displacement * warp_gain * float2(1.0 / aspect, 1.0);

    uint sourceWidth;
    uint sourceHeight;
    _Tex0.GetDimensions(sourceWidth, sourceHeight);
    float2 sourceTexel = 1.0 / max(float2((float)sourceWidth, (float)sourceHeight), float2(1.0, 1.0));

    float3 black = float3(0.0025, 0.003, 0.0027);
    float3 white = float3(0.88, 0.895, 0.86);
    float3 graphite = float3(0.16, 0.175, 0.16);
    float3 liability = liability_color;

    float3 sourceColor = _Tex0.SampleLevel(LinearSampler, warpedUv, 0.0).rgb;
    float sourceLuma = pdLuma(sourceColor);

    float3 layerStack = float3(0.0, 0.0, 0.0);
    float totalLayerWeight = 0.0;
    [loop]
    for (int layerIndex = 0; layerIndex < 8; ++layerIndex)
    {
        if (layerIndex >= slice_count) break;
        float normalizedLayer = slice_count > 1 ? (float)layerIndex / (float)(slice_count - 1) : 0.0;
        float centeredLayer = normalizedLayer - 0.5;
        float phaseBias = an_stagger_index((float)layerIndex, (float)max(slice_count, 1), 0.18);
        float layerMotion = sin((phaseValue - phaseBias) * AN_TAU) * 0.35 + 0.65;
        float2 layerOffset =
            displacement * parallax_depth * centeredLayer * float2(1.0 / aspect, 1.0) +
            float2(centeredLayer * liabilityDepth * 0.018, -centeredLayer * stress * 0.012);
        float layerLuma = pdLuma(_Tex0.SampleLevel(LinearSampler, warpedUv + layerOffset, 0.0).rgb);
        float weight = exp(-normalizedLayer * slice_falloff);
        float3 layerColor = lerp(graphite, white, normalizedLayer * 0.72 + 0.18);
        layerStack += layerColor * layerLuma * weight * layerMotion;
        totalLayerWeight += weight;
    }
    layerStack /= max(totalLayerWeight, 0.001);

    float lumaLeft = pdLuma(_Tex0.SampleLevel(LinearSampler, warpedUv - float2(sourceTexel.x, 0.0), 0.0).rgb);
    float lumaRight = pdLuma(_Tex0.SampleLevel(LinearSampler, warpedUv + float2(sourceTexel.x, 0.0), 0.0).rgb);
    float lumaUp = pdLuma(_Tex0.SampleLevel(LinearSampler, warpedUv - float2(0.0, sourceTexel.y), 0.0).rgb);
    float lumaDown = pdLuma(_Tex0.SampleLevel(LinearSampler, warpedUv + float2(0.0, sourceTexel.y), 0.0).rgb);
    float sourceEdge = length(float2(lumaRight - lumaLeft, lumaDown - lumaUp));

    float3 color = black;
    color += layerStack * slice_gain;
    color += white * sourceEdge * source_edge_gain;
    color += sourceColor * source_gain;
    color += graphite * liabilityDepth * depth_body_gain;

    float macroMarks = 0.0;
    float hingeMarks = 0.0;
    float hingeBodies = 0.0;
    float railMarks = 0.0;
    float relationMarks = 0.0;
    float currentMarks = 0.0;

    float2 leverageP = leverage_focus * float2(aspect, 1.0) * 0.5;
    float2 macroTarget = leverageP;
    DebtQuantum macroQuantum = DebtInput[0];
    if (macroQuantum.active != 0u && macroQuantum.kind == 1u)
    {
        macroTarget = (macroQuantum.position - 0.5) * float2(aspect, 1.0);
    }

    [loop]
    for (uint i = 0u; i < 64u; ++i)
    {
        DebtQuantum quantum = DebtInput[i];
        if (quantum.active == 0u) continue;

        float2 center = (quantum.position - 0.5) * float2(aspect, 1.0);
        float2 axis = normalize(quantum.axis * float2(1.0, -1.0));
        float2 side = float2(-axis.y, axis.x);
        float localPhase = frac(phaseValue + quantum.phase);
        float pulse = 0.5 + 0.5 * an_loop_harmonic(localPhase, 1.0, 1.0, (float)quantum.kind);

        if (quantum.kind == 1u)
        {
            float radius = max(0.045, quantum.radius * macro_mark_scale);
            float distanceValue = length((p - center) * float2(0.82, 1.0));
            macroMarks = max(macroMarks, pdRing(distanceValue, radius, 0.0022));
            macroMarks = max(macroMarks, pdRing(distanceValue, radius * (0.42 + 0.08 * pulse), 0.0011));
            currentMarks = max(currentMarks, pdRing(distanceValue, radius * (0.78 + 0.11 * pulse), 0.0010));
        }
        else if (quantum.kind == 2u)
        {
            float hingeSize = lerp(0.012, 0.046, quantum.mass) * hinge_scale;
            float2 q = pdRotateBasis(p - center, axis, side);
            q.y += sin(localPhase * AN_TAU) * q.x * hinge_torsion;
            float blade = 1.0 - smoothstep(-0.001, 0.002, pdBox(q - float2(hingeSize * 0.55, 0.0), float2(hingeSize * 0.55, hingeSize * 0.13)));
            float mirroredBlade = 1.0 - smoothstep(-0.001, 0.002, pdBox(q - float2(0.0, hingeSize * 0.55), float2(hingeSize * 0.13, hingeSize * 0.55)));
            hingeBodies = max(hingeBodies, max(blade, mirroredBlade) * quantum.mass);
            hingeMarks = max(hingeMarks, pdStroke(pdSegment(p, center - axis * hingeSize, center + axis * hingeSize), 0.0012));
            hingeMarks = max(hingeMarks, pdStroke(pdSegment(p, center - side * hingeSize, center + side * hingeSize), 0.0012));

            float2 relationTarget = leverageP;
            if (topology_mode == 1) relationTarget = macroTarget;
            if (topology_mode == 2) relationTarget = center + axis * (0.28 + quantum.mass * 0.25);
            relationMarks = max(relationMarks, pdStroke(pdSegment(p, center, relationTarget), 0.00065));
            currentMarks = max(currentMarks, pdRing(length(p - center), hingeSize * (1.25 + 0.35 * pulse), 0.0009));
        }
        else if (quantum.kind == 3u)
        {
            float halfLength = max(0.04, quantum.radius * rail_scale);
            float railDistance = pdSegment(p, center - axis * halfLength, center + axis * halfLength);
            railMarks = max(railMarks, pdStroke(abs(railDistance - rail_separation), 0.0011));
            railMarks = max(railMarks, pdStroke(pdSegment(p, center - axis * halfLength, center + axis * halfLength), 0.0006));
            currentMarks = max(
                currentMarks,
                pdStroke(pdSegment(p, center - axis * halfLength * pulse, center + axis * halfLength * pulse), 0.0011)
            );
        }
    }

    color = lerp(color, graphite, hingeBodies * hinge_body_gain);
    color += white * hingeMarks * hinge_line_gain;
    color += graphite * railMarks * rail_gain;
    color += graphite * relationMarks * relation_gain;
    color += liability * macroMarks * macro_gain;
    color += liability * currentMarks * current_gain;
    color += liability * pow(stress, 2.0) * field_current_gain;

    float steps = max(2.0, tone_steps);
    float3 quantized = floor(saturate(color) * steps + 0.5) / steps;
    color = lerp(color, quantized, tone_quantize);

    float2 registrationUv = frac(uv * float2(32.0, 18.0));
    float registration = step(0.965, registrationUv.x) * step(0.965, registrationUv.y);
    color += graphite * registration * registration_gain * (0.25 + stress);

    float vignette = saturate(1.0 - dot(p * float2(0.46, 0.82), p * float2(0.46, 0.82)));
    color *= lerp(0.32, 1.0, vignette);

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
