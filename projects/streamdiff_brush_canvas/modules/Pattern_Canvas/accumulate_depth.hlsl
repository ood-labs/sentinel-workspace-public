RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<float4> CanvasState : register(t3);
StructuredBuffer<float4> KickEnvelope : register(t4);

struct StampPose
{
    float2 center;
    float size;
    float angle;
    uint cycle;
    uint visible;
    float2 padding;
};
StructuredBuffer<StampPose> ActiveStampPose : register(t5);

float pcMirrorCoordinate(float value)
{
    float wrapped = frac(value * 0.5) * 2.0;
    return 1.0 - abs(wrapped - 1.0);
}

float pcDepthFeedbackSample(float2 uv)
{
    float dt = clamp(_DeltaTime, 0.0, 0.1);
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 pivot = feedback_pivot;
    float2 p = float2((uv.x - pivot.x) * aspect, uv.y - pivot.y);

    float kickAmount = saturate(KickEnvelope[0].x);
    float kick = lerp(1.0, max(feedback_kick, 1.0), kickAmount);
    float gain = max(control_gain, 0.0) * kick;
    p -= float2(pan.x * aspect, pan.y) * (dt * gain);

    float angle = radians(feedback_rotation_speed) * dt * kick;
    float cs = cos(angle);
    float sn = sin(angle);
    float2 rotated = float2(cs * p.x + sn * p.y,
                            -sn * p.x + cs * p.y);
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

    float depth = _Tex2.SampleLevel(LinearSampler, saturate(sampleUv), 0).r;
    if (edgeMode == 0) depth *= inside;
    return depth;
}

float pcDepthStamp(float2 uv, int revealStage)
{
    StampPose pose = ActiveStampPose[0];
    if (pose.visible == 0u) return 0.0;

    int stage = reveal_sequence != 0 ? clamp(revealStage, 1, 3) : 3;
    float border = max(reveal_border, 0.0);
    float stageScale = stage == 1 ? 1.0 + border
                     : (stage == 2 ? 1.0 + border * 0.5 : 1.0);
    float stampSize = pose.size * stageScale;

    float canvasAspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = float2((uv.x - pose.center.x) * canvasAspect,
                      uv.y - pose.center.y);
    float cs = cos(pose.angle);
    float sn = sin(pose.angle);
    float2 q = float2(cs * p.x + sn * p.y,
                      -sn * p.x + cs * p.y);

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
                             matte);
    if (stage == 3) alpha *= opacity;

    if (stage == 1 && border > 0.0001) {
        float innerScale = 1.0 + border * 0.5;
        float2 innerHalfSize = float2((pose.size * innerScale) * sourceAspect,
                                      pose.size * innerScale) * 0.5;
        float2 innerUv = q / max(innerHalfSize * 2.0, 0.0001.xx) + 0.5;
        float innerInside = step(0.0, innerUv.x) * step(innerUv.x, 1.0) *
                            step(0.0, innerUv.y) * step(innerUv.y, 1.0);
        float3 innerMatteRgb = _Tex1.SampleLevel(
            LinearSampler, saturate(innerUv), 0).rgb;
        float innerMatte = max(innerMatteRgb.r,
                               max(innerMatteRgb.g, innerMatteRgb.b)) * innerInside;
        float innerAlpha = smoothstep(matte_threshold - matte_feather,
                                      matte_threshold + matte_feather,
                                      innerMatte);
        alpha *= 1.0 - innerAlpha;
    }

    float sourceDepth = _Tex0.SampleLevel(
        LinearSampler, saturate(localUv), 0).r;
    float shapedDepth = saturate(sourceDepth * depth_gain + depth_offset);
    return shapedDepth * saturate(alpha);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float4 state = CanvasState[0];
    float action = state.y;
    float previousDepth = _Tex2.SampleLevel(LinearSampler, uv, 0).r;

    if (action < -0.5) {
        previousDepth = 0.0;
    }
    else {
        if (feedback_enabled != 0) {
            previousDepth = pcDepthFeedbackSample(uv);
        }
        float dt = clamp(_DeltaTime, 0.0, 0.1);
        previousDepth *= exp(-max(depth_fade, 0.0) * dt);
    }

    if (action > 0.5) {
        int revealStage = (int)round(clamp(action, 1.0, 3.0));
        float stampDepth = pcDepthStamp(uv, revealStage);
        previousDepth = max(previousDepth, stampDepth);
    }

    float depth = saturate(previousDepth);
    OutputUAV[pixel] = float4(depth, depth, depth, 1.0);
}
