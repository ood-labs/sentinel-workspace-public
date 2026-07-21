RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<float4> CanvasState : register(t3);
StructuredBuffer<float4> KickEnvelope : register(t4);

static const float PI = 3.14159265359;
static const float TAU = 6.28318530718;

uint pcHash(uint value)
{
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

float pcRandom(uint hit, uint salt)
{
    uint value = hit ^ salt ^ asuint(seed + 0.12345);
    return (pcHash(value) & 0x00ffffffu) / 16777216.0;
}

float2 pcBorderPoint(float t, out float tangent)
{
    float edge = frac(t) * 4.0;
    if (edge < 1.0) {
        tangent = 0.0;
        return float2(lerp(0.10, 0.90, edge), 0.10);
    }
    if (edge < 2.0) {
        tangent = PI * 0.5;
        return float2(0.90, lerp(0.10, 0.90, edge - 1.0));
    }
    if (edge < 3.0) {
        tangent = PI;
        return float2(lerp(0.90, 0.10, edge - 2.0), 0.90);
    }
    tangent = -PI * 0.5;
    return float2(0.10, lerp(0.90, 0.10, edge - 3.0));
}

void pcPlacement(uint cycle, out float2 center, out float stampSize, out float angle)
{
    uint count = (uint)clamp(pattern_count, 4, 36);
    uint index = cycle % count;
    float i = (float)index;
    float n = max((float)count, 1.0);
    float pathAngle = 0.0;
    int mode = clamp(pattern_mode, 0, 4);

    if (mode == 0) {
        center = float2(lerp(0.09, 0.91, pcRandom(cycle, 11u)),
                        lerp(0.09, 0.91, pcRandom(cycle, 17u)));
    }
    else if (mode == 1) {
        uint columns = (uint)ceil(sqrt((float)count * 0.82));
        uint rows = (count + columns - 1u) / columns;
        uint shifted = (index + (uint)floor(pattern_phase * n)) % count;
        uint column = shifted % columns;
        uint row = shifted / columns;
        center = float2(((float)column + 0.5) / (float)columns,
                        ((float)row + 0.5) / (float)rows);
        center = lerp(0.10.xx, 0.90.xx, center);
    }
    else if (mode == 2) {
        float t = count > 1u ? i / (n - 1.0) : 0.0;
        float spiralAngle = i * 2.39996323 + pattern_phase * TAU;
        float radius = lerp(0.04, 0.38, sqrt(t));
        center = 0.5.xx + float2(cos(spiralAngle) * radius,
                                 sin(spiralAngle) * radius * 0.82);
        pathAngle = spiralAngle + PI * 0.5;
    }
    else if (mode == 3) {
        float t = (i + 0.5) / n;
        float wavePhase = t * TAU * 1.5 + pattern_phase * TAU;
        center = float2(lerp(0.08, 0.92, t), 0.5 + sin(wavePhase) * 0.30);
        float dx = 0.84;
        float dy = cos(wavePhase) * 0.30 * TAU * 1.5;
        pathAngle = atan2(dy, dx);
    }
    else {
        center = pcBorderPoint(i / n + pattern_phase, pathAngle);
    }

    float2 randomOffset = float2(pcRandom(cycle, 31u), pcRandom(cycle, 37u)) - 0.5;
    center = clamp(center + randomOffset * position_jitter, 0.04.xx, 0.96.xx);
    stampSize = cutout_scale * lerp(1.0 - scale_variation,
                                    1.0 + scale_variation,
                                    pcRandom(cycle, 43u));
    angle = radians(rotation + (pcRandom(cycle, 47u) - 0.5) * rotation_jitter);
    if (follow_pattern != 0 && mode >= 2) angle += pathAngle;
}

float4 pcStamp(float2 uv, uint cycle)
{
    float2 center;
    float stampSize;
    float angle;
    pcPlacement(cycle, center, stampSize, angle);

    float canvasAspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = float2((uv.x - center.x) * canvasAspect, uv.y - center.y);
    float cs = cos(angle);
    float sn = sin(angle);
    float2 q = float2(cs * p.x + sn * p.y, -sn * p.x + cs * p.y);

    float sourceWidth;
    float sourceHeight;
    _Tex0.GetDimensions(sourceWidth, sourceHeight);
    float sourceAspect = sourceWidth / max(sourceHeight, 1.0);
    float2 halfSize = float2(stampSize * sourceAspect, stampSize) * 0.5;
    float2 localUv = q / max(halfSize * 2.0, 0.0001.xx) + 0.5;
    float inside = step(0.0, localUv.x) * step(localUv.x, 1.0) *
                   step(0.0, localUv.y) * step(localUv.y, 1.0);

    float3 matteRgb = _Tex1.SampleLevel(LinearSampler, saturate(localUv), 0).rgb;
    float matte = max(matteRgb.r, max(matteRgb.g, matteRgb.b)) * inside;
    float alpha = smoothstep(matte_threshold - matte_feather,
                             matte_threshold + matte_feather,
                             matte) * opacity;
    float3 subject = _Tex0.SampleLevel(LinearSampler, saturate(localUv), 0).rgb;

    float shadowMatte = _Tex1.SampleLevel(LinearSampler,
        saturate(localUv + float2(-0.022, -0.018)), 0).r * inside;
    float shadow = smoothstep(0.10, 0.45, shadowMatte) * (1.0 - alpha) * drop_shadow;
    float3 layer = lerp(float3(0.0, 0.0, 0.0), subject, alpha);
    return float4(layer, saturate(alpha + shadow * 0.45));
}

float pcMirrorCoordinate(float value)
{
    float wrapped = frac(value * 0.5) * 2.0;
    return 1.0 - abs(wrapped - 1.0);
}

float3 pcFeedbackSample(float2 uv)
{
    float dt = clamp(_DeltaTime, 0.0, 0.1);
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 pivot = feedback_pivot;

    // Inverse-map this output pixel through the requested forward transform.
    // Positive zoom flies into the canvas; positive rotation turns clockwise
    // in the screen's top-left coordinate system; positive drift moves right/down.
    float2 p = float2((uv.x - pivot.x) * aspect, uv.y - pivot.y);
    // The shared ADSR envelope keeps texture feedback and Spawn Points locked.
    float kickAmount = saturate(KickEnvelope[0].x);
    float kick = lerp(1.0, max(feedback_kick, 1.0), kickAmount);
    float gain = max(control_gain, 0.0) * kick;
    float2 drift = float2(pan.x * aspect, pan.y) * (dt * gain);
    p -= drift;

    float angle = radians(feedback_rotation_speed) * dt * kick;
    float cs = cos(angle);
    float sn = sin(angle);
    float2 rotated = float2(cs * p.x + sn * p.y,
                            -sn * p.x + cs * p.y);
    // The host applies a fixed 0.02 wheel increment. A +/-0.5 parameter
    // range makes each notch exactly 2% of the full control span; this 2x
    // compensation preserves the same maximum feedback velocity.
    float zoomFactor = exp2((zoom * 2.0) * dt * gain);
    rotated /= max(zoomFactor, 0.0001);

    float2 sampleUv = pivot + float2(rotated.x / aspect, rotated.y);
    float inside = step(0.0, sampleUv.x) * step(sampleUv.x, 1.0) *
                   step(0.0, sampleUv.y) * step(sampleUv.y, 1.0);

    int edgeMode = clamp(feedback_edge_mode, 0, 3);
    if (edgeMode == 1) {
        sampleUv = saturate(sampleUv);
    }
    else if (edgeMode == 2) {
        sampleUv = frac(sampleUv);
    }
    else if (edgeMode == 3) {
        sampleUv = float2(pcMirrorCoordinate(sampleUv.x),
                          pcMirrorCoordinate(sampleUv.y));
    }

    float3 transformed = _Tex2.SampleLevel(LinearSampler, saturate(sampleUv), 0).rgb;
    if (edgeMode == 0) transformed = lerp(background_color, transformed, inside);

    float retain = exp(-max(feedback_fade, 0.0) * dt);
    return lerp(background_color, transformed, retain);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float4 previous = _Tex2.SampleLevel(LinearSampler, uv, 0);
    float4 state = CanvasState[0];
    float action = state.y;
    float3 color = previous.rgb;

    if (action < -0.5) {
        color = background_color;
    }
    else if (feedback_enabled != 0) {
        color = pcFeedbackSample(uv);
    }

    if (action > 0.5) {
        uint cycle = (uint)max(state.x, 0.0);
        float4 stamp = pcStamp(uv, cycle);
        color = lerp(color, stamp.rgb, stamp.a);
    }

    OutputUAV[pixel] = float4(color, 1.0);
}
