// Four independent per-pixel countdown lanes. Each new stamp chooses one lane,
// so a later stamp cannot erase an earlier delayed trace before it has fired.
// The field runs at half resolution; all coordinates derive from its real size.
RWTexture2D<float4> OutputUAV : register(u0);

struct StampPose
{
    float2 center;
    float size;
    float angle;
    uint cycle;
    uint visible;
    float2 padding;
};

StructuredBuffer<StampPose> LatestPose : register(t2);
StructuredBuffer<float4> CanvasState : register(t3);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint fieldWidth, fieldHeight;
    _Tex0.GetDimensions(fieldWidth, fieldHeight);
    if (DTid.x >= fieldWidth || DTid.y >= fieldHeight) return;

    float dt = clamp(_DeltaTime, 0.0, 0.1);
    float4 timers = max(_Tex0.Load(int3(DTid.xy, 0))
                      - float4(dt, dt, dt, dt),
                        float4(0.0, 0.0, 0.0, 0.0));
    float action = CanvasState[0].y;

    if (action < -0.5)
    {
        OutputUAV[DTid.xy] = float4(0.0, 0.0, 0.0, 0.0);
        return;
    }

    bool newStamp = action > 0.5 && action < 1.5;
    StampPose pose = LatestPose[0];
    if (newStamp && pose.visible != 0u)
    {
        float2 fieldSize = float2(fieldWidth, fieldHeight);
        float2 uv = ((float2)DTid.xy + 0.5) / fieldSize;
        float canvasAspect = fieldSize.x / max(fieldSize.y, 1.0);
        float2 p = float2((uv.x - pose.center.x) * canvasAspect,
                          uv.y - pose.center.y);
        float cs = cos(pose.angle);
        float sn = sin(pose.angle);
        float2 q = float2(cs * p.x + sn * p.y,
                         -sn * p.x + cs * p.y);

        float sourceAspect = clamp(stamp_aspect, 0.05, 20.0);
        float2 halfSize = float2(pose.size * sourceAspect, pose.size) * 0.5;
        float2 localUv = q / max(halfSize * 2.0, 0.0001.xx) + 0.5;
        float inside = step(0.0, localUv.x) * step(localUv.x, 1.0)
                     * step(0.0, localUv.y) * step(localUv.y, 1.0);

        float3 matteRgb = _Tex1.SampleLevel(LinearSampler, saturate(localUv), 0).rgb;
        float matte = max(matteRgb.r, max(matteRgb.g, matteRgb.b)) * inside;
        float mask = smoothstep(matte_threshold - matte_feather,
                                matte_threshold + matte_feather,
                                matte);
        float countdown = max(latest_outline_delay, 0.0)
                        + max(latest_outline_hold, 0.01);
        float scheduled = countdown * step(0.5, mask);
        uint lane = pose.cycle & 3u;
        if (lane == 0u) timers.x = max(timers.x, scheduled);
        else if (lane == 1u) timers.y = max(timers.y, scheduled);
        else if (lane == 2u) timers.z = max(timers.z, scheduled);
        else timers.w = max(timers.w, scheduled);
    }

    OutputUAV[DTid.xy] = timers;
}
