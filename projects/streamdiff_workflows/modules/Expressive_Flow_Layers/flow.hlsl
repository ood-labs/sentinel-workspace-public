// Three-layer geometric flow-map generator.
// Encoded output: neutral flow is RGB 0.5,0.5,0.5; R/G carry signed XY flow.

#include "../_shared/show_timeline.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.28318530718;

float2 rotate2(float2 p, float a) {
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float2 safeNorm(float2 v) {
    float l = length(v);
    return (l > 1e-5) ? v / l : float2(0.0, 0.0);
}

float angleCycles(float2 p) {
    return atan2(p.y, p.x) / TAU;
}

float2 warpPoint(float2 p, float freq, float freq2, float spin, float amount) {
    if (amount <= 0.0001) return p;
    float2 np = p * float2(max(freq, 0.001), max(freq2, 0.001));
    float n1 = fbm2D(np + spin, 4);
    float n2 = fbm2D(np * 1.37 + float2(17.3, -9.1) - spin, 4);
    return p + (float2(n1, n2) - 0.5) * amount;
}

float2 curlNoise(float2 p, float freq, float freq2, float spin, float detail) {
    float eps = 0.0025;
    float2 scale = float2(max(freq, 0.001), max(freq2, 0.001));
    float octaveBoost = lerp(0.5, 2.0, saturate(detail));
    int oct = (int)clamp(round(2.0 + detail * 4.0), 2.0, 6.0);
    float nL = fbm2D((p + float2(-eps, 0.0)) * scale * octaveBoost + spin, oct);
    float nR = fbm2D((p + float2( eps, 0.0)) * scale * octaveBoost + spin, oct);
    float nD = fbm2D((p + float2(0.0, -eps)) * scale * octaveBoost + spin, oct);
    float nU = fbm2D((p + float2(0.0,  eps)) * scale * octaveBoost + spin, oct);
    float2 grad = float2(nR - nL, nU - nD) / (2.0 * eps);
    return safeNorm(float2(grad.y, -grad.x));
}

float cellField(float2 p, float freq, float freq2, float spin) {
    float2 q = p * float2(max(freq, 0.001), max(freq2, 0.001)) + spin;
    float2 cell = floor(q);
    float2 f = frac(q);
    float minD = 10.0;
    [unroll]
    for (int y = -1; y <= 1; y++) {
        [unroll]
        for (int x = -1; x <= 1; x++) {
            float2 g = float2((float)x, (float)y);
            float2 rnd = float2(hash21(cell + g), hash21(cell + g + 19.37));
            float2 d = g + rnd - f;
            minD = min(minD, dot(d, d));
        }
    }
    return sqrt(minD);
}

float2 modeField(int mode, float2 p, float2 uv, float freq, float freq2,
                 float spin, float ph, float swirl, float shape, float noiseAmount) {
    float2 q = p;
    q = warpPoint(q, freq, freq2, spin, noiseAmount);
    float r = length(q);
    float2 radial = safeNorm(q);
    float2 tangent = float2(-radial.y, radial.x);
    float a = atan2(q.y, q.x);
    float ac = angleCycles(q);
    float x = q.x * freq;
    float y = q.y * freq2;
    float t = spin + ph;

    if (mode == 0) {
        float ring = sin((r * freq - t) * TAU);
        return lerp(radial, tangent, swirl) * ring;
    }
    if (mode == 1) {
        float wx = sin((y + t) * TAU);
        float wy = cos((x - t) * TAU);
        return float2(wx, wy);
    }
    if (mode == 2) {
        float turns = max(1.0, round(max(freq2, shape)));
        float s = sin((r * freq + ac * turns - t) * TAU);
        return lerp(radial, tangent, 0.65 + 0.35 * swirl) * s;
    }
    if (mode == 3) {
        float petalsN = max(2.0, round(max(freq2, shape)));
        float petals = sin((ac * petalsN + r * max(freq, 0.001) - t) * TAU);
        float pulse = cos((r * max(freq, 0.001) - t) * TAU);
        return lerp(radial, tangent, 0.5 + 0.5 * petals * swirl) * petals * pulse;
    }
    if (mode == 4) {
        float gx = sin((x + t) * TAU);
        float gy = sin((y - t) * TAU);
        float cx = cos((x * 0.5 - t) * TAU);
        float cy = cos((y * 0.5 + t) * TAU);
        return normalize(float2(gx + cy * 0.35, gy - cx * 0.35) + 1e-5);
    }
    if (mode == 5) {
        float sides = max(3.0, round(max(freq2, shape)));
        float facet = cos(a * sides);
        float band = sin((r * freq + facet * 0.35 - t) * TAU);
        return lerp(radial, tangent, saturate(swirl + 0.25 * facet)) * band;
    }
    if (mode == 6) {
        float ripple = sin((r * freq * 1.75 - t) * TAU);
        float shear = cos((uv.x + uv.y) * freq * TAU + t * TAU);
        return radial * ripple + tangent * shear * swirl;
    }
    if (mode == 8) {
        return curlNoise(q, freq, freq2, spin, shape);
    }
    if (mode == 9) {
        int oct = (int)clamp(round(2.0 + saturate(shape / 8.0) * 4.0), 2.0, 6.0);
        float n = fbm2D(q * float2(max(freq, 0.001), max(freq2, 0.001)) + spin, oct);
        float ring = sin((r * freq + n * max(shape, 0.001) - t) * TAU);
        return lerp(radial, tangent, swirl) * ring;
    }
    if (mode == 10) {
        float c = cellField(q, freq, freq2, spin);
        float edge = sin((c * max(shape, 0.001) - t) * TAU);
        return lerp(radial, tangent, swirl) * edge;
    }

    float pinTurns = max(1.0, round(max(freq2, shape)));
    float pin = sin((ac * pinTurns + t) * TAU);
    float tunnel = cos((r * freq - t) * TAU);
    return tangent * pin + radial * tunnel * (1.0 - swirl);
}

float2 layerField(float2 uv, float2 center, float mode, float strength,
                  float freq, float freq2, float speed, float rotation, float layerPhase,
                  float swirl, float shape, float noiseAmount, float t) {
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - center) * float2(aspect, 1.0);
    p = rotate2(p, rotation);
    float2 v = modeField((int)round(mode), p, uv, max(freq, 0.001), max(freq2, 0.001),
                         t * speed, layerPhase, saturate(swirl), shape, noiseAmount);
    return v * strength;
}

float auxValue(float2 uv, float2 flow, float2 l1, float2 l2, float2 l3) {
    int mode = (int)round(blue_mode);
    if (mode == 0) return length(flow);
    if (mode == 1) return abs(sin(length((uv - layer1_center) * _Resolution.xy) / max(layer1_frequency, 0.001) * 0.02));
    if (mode == 2) return length(l1 + l2 + l3) - length(l1) - length(l2) - length(l3);
    if (mode == 3) return length(l1);
    if (mode == 4) return length(l2);
    return length(l3);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float mp = stMasterPhase(phase, animation_speed, _Time);
    float life = stLife(mp, in_end, out_start);
    float body = stBody(mp, in_end, out_start);
    float t = (time_mode >= 0.5) ? loop_phase + body : stCycleClock(loop_phase, loop_speed, _Time);

    float2 l1 = layerField(uv, layer1_center, layer1_mode, layer1_enabled ? layer1_strength : 0.0,
                           layer1_frequency, layer1_frequency_y, layer1_speed, layer1_rotation,
                           layer1_phase, layer1_swirl, layer1_shape, layer1_noise, t);
    float2 l2 = layerField(uv, layer2_center, layer2_mode, layer2_enabled ? layer2_strength : 0.0,
                           layer2_frequency, layer2_frequency_y, layer2_speed, layer2_rotation,
                           layer2_phase, layer2_swirl, layer2_shape, layer2_noise, t);
    float2 l3 = layerField(uv, layer3_center, layer3_mode, layer3_enabled ? layer3_strength : 0.0,
                           layer3_frequency, layer3_frequency_y, layer3_speed, layer3_rotation,
                           layer3_phase, layer3_swirl, layer3_shape, layer3_noise, t);

    float2 flow = (l1 + l2 + l3) * master_strength * life;
    if (normalize_flow) {
        float m = length(flow);
        flow = (m > 1.0) ? flow / m : flow;
    }
    if (invert_flow) flow = -flow;

    float aux = auxValue(uv, flow, l1, l2, l3);
    float b = 0.5 + aux * blue_gain + blue_offset;
    float r = 0.5 + flow.x * red_gain + red_offset;
    float g = 0.5 + flow.y * green_gain + green_offset;

    OutputUAV[pixel] = float4(saturate(float3(r, g, b)), 1.0);
}
