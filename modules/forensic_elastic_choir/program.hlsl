struct EvidenceAgent
{
    float2 position;
    float2 direction;
    float weight;
    float radius;
    uint kind;
    uint sourceIndex;
    uint groupId;
    uint active;
    float phase;
    float pad;
};

StructuredBuffer<EvidenceAgent> Agents : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float stroke(float d, float width)
{
    float px = 1.35 / max(_Resolution.y, 1.0);
    return 1.0 - smoothstep(width, width + px, d);
}

float quadraticDistance(float2 p, float2 a, float2 b, float2 c)
{
    float d = 1000.0;
    float2 prev = a;
    [unroll]
    for (int s = 1; s <= 7; ++s)
    {
        float t = (float)s / 7.0;
        float omt = 1.0 - t;
        float2 q = omt * omt * a + 2.0 * omt * t * b + t * t * c;
        d = min(d, sdSegment(p, prev, q));
        prev = q;
    }
    return d;
}

float hashId(uint id)
{
    return frac(sin((float)id * 91.733) * 43758.5453);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = uv * float2(aspect, 1.0);
    float ph = frac(phase + _Time * animation_rate);

    float3 substrate = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float sourceLuma = dot(substrate, float3(0.2126, 0.7152, 0.0722));

    float2 macro = float2(0.5 * aspect, 0.5);
    float macroRadius = 0.18;
    float macroWeight = 0.0;
    [unroll]
    for (uint m = 0u; m < 64u; ++m)
    {
        EvidenceAgent a = Agents[m];
        if (a.active != 0u && a.kind == 1u && a.weight >= macroWeight)
        {
            macro = a.position * float2(aspect, 1.0);
            macroRadius = a.radius;
            macroWeight = a.weight;
        }
    }

    float pressureDistance = length(p - macro);
    float pressure = exp(-pressureDistance * pressureDistance / max(macroRadius * macroRadius * pressure_scale, 1e-4));
    float3 ink = float3(0.0035, 0.004, 0.004);
    float3 paper = float3(0.82, 0.84, 0.81);
    float3 graphite = float3(0.18, 0.195, 0.185);
    float3 current = current_color;

    float substrateLine = smoothstep(0.18, 0.52, sourceLuma);
    float3 col = ink + paper * substrateLine * substrate_gain * (0.22 + 0.42 * (1.0 - pressure));

    float routeInk = 0.0;
    float routeHalo = 0.0;
    float nodeInk = 0.0;
    float currentInk = 0.0;
    float incision = 0.0;

    [loop]
    for (uint i = 0u; i < 64u; ++i)
    {
        EvidenceAgent a = Agents[i];
        if (a.active == 0u) continue;

        float2 q = a.position * float2(aspect, 1.0);
        float2 dir = normalize(a.direction * float2(aspect, 1.0) + float2(1e-4, 0.0));
        float localPhase = frac(ph + a.phase);
        float pulse = 0.5 + 0.5 * sin(localPhase * 6.2831853);

        if (a.kind == 2u)
        {
            float side = (hashId(a.groupId) > 0.5 ? 1.0 : -1.0);
            float bendGain = topology_mode == 0 ? route_bend : (topology_mode == 1 ? route_bend * 0.25 : route_bend * 1.8);
            float2 normal = float2(-dir.y, dir.x);
            float2 control = lerp(q, macro, 0.48) + normal * side * bendGain * (0.35 + a.weight);
            float routeD = quadraticDistance(p, q, control, macro);
            float width = route_width * (0.55 + 0.75 * a.weight) / max(_Resolution.y, 1.0);
            float route = stroke(routeD, width);
            float halo = stroke(routeD, width * 4.2) * (1.0 - route);
            routeInk = max(routeInk, route * (0.35 + 0.65 * a.weight));
            routeHalo += halo * a.weight * 0.022;

            float radial = length(p - q);
            float ringRadius = voice_radius / max(_Resolution.y, 1.0) * (0.8 + pulse * 0.8);
            float voice = stroke(abs(radial - ringRadius), 0.0012);
            float tangent = stroke(sdSegment(p, q - dir * ringRadius * 1.8, q + dir * ringRadius * 1.8), 0.00075);
            nodeInk = max(nodeInk, voice * (0.25 + a.weight) + tangent * 0.4);

            float isCurrent = smoothstep(0.82, 1.0, pulse) * step(0.72, a.weight);
            currentInk = max(currentInk, (voice + route * 0.35) * isCurrent);
        }
        else if (a.kind == 3u)
        {
            float len = a.radius * (0.8 + line_extension);
            float mainCut = stroke(sdSegment(p, q - dir * len, q + dir * len), 0.0012);
            float2 n = float2(-dir.y, dir.x);
            float echoA = stroke(sdSegment(p, q - dir * len + n * 0.010, q + dir * len + n * 0.010), 0.0007);
            float echoB = stroke(sdSegment(p, q - dir * len - n * 0.010, q + dir * len - n * 0.010), 0.0007);
            incision = max(incision, mainCut * (0.4 + a.weight) + (echoA + echoB) * 0.25);
        }
    }

    // Pressure basin becomes an engraved exclusion ring and local hatch field.
    float basinRing = stroke(abs(pressureDistance - macroRadius * 0.92), 0.0022);
    float angle = atan2(p.y - macro.y, p.x - macro.x);
    float radialHatch = 0.5 + 0.5 * sin(angle * 38.0 + pressureDistance * 160.0 - ph * 6.2831853);
    float hatch = smoothstep(0.86, 0.96, radialHatch) * pressure * engraving_gain;

    if (topology_mode == 2)
    {
        float sever = step(0.62, frac((p.x + p.y * 0.43) * 17.0 + ph));
        float coreBreath = smoothstep(macroRadius * 0.24, macroRadius * 0.72, pressureDistance);
        routeInk *= sever * lerp(0.32, 1.0, coreBreath);
        incision *= 0.55 + 0.45 * sever;
    }

    col += graphite * routeHalo;
    col += paper * routeInk * route_gain;
    col += paper * nodeInk * voice_gain;
    col += graphite * incision * incision_gain;
    col += paper * basinRing * (0.4 + macroWeight);
    col += graphite * hatch * 0.36;
    col += current * currentInk * current_gain;

    // Outer forensic frame and phase registration.
    float frameD = abs(max(abs((uv.x - 0.5) * aspect) - aspect * 0.475, abs(uv.y - 0.5) - 0.445));
    col += paper * stroke(frameD, 0.0014) * 0.6;
    float phaseX = lerp(0.045, 0.955, ph);
    float phaseMark = stroke(abs(uv.x - phaseX), 0.0009) * step(0.925, uv.y);
    col += current * phaseMark * 0.8;

    // Hard limited finish keeps the language graphic rather than glowy.
    col = col / (1.0 + col * 0.35);
    float luminanceOut = dot(col, float3(0.2126, 0.7152, 0.0722));
    float quant = floor(luminanceOut * tone_steps + 0.5) / max(tone_steps, 1.0);
    col = lerp(col, col * (quant / max(luminanceOut, 1e-4)), tone_quantize);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
