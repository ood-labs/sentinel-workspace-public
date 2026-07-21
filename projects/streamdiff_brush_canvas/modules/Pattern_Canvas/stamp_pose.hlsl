#include "placement.hlsli"

// Active reveal pose. The first stage captures placement; later stages advance
// it through the exact forward transform applied to the feedback canvas.
struct StampPose
{
    float2 center;
    float size;
    float angle;
    uint cycle;
    uint visible;
    float2 padding;
};

RWStructuredBuffer<StampPose> OutputBuffer : register(u0);
StructuredBuffer<float4> KickEnvelope : register(t1);
StructuredBuffer<float4> CanvasState : register(t2);

float pcMirrorPoseCoordinate(float value)
{
    float wrapped = frac(value * 0.5) * 2.0;
    return 1.0 - abs(wrapped - 1.0);
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    StampPose pose = OutputBuffer[0];
    float4 canvasState = CanvasState[0];
    int stage = (int)round(clamp(canvasState.y, -1.0, 3.0));

    if (stage < 0) {
        pose.visible = 0u;
    }
    else if (stage == 1) {
        float2 center;
        float stampSize;
        float angle;
        uint cycle = (uint)max(canvasState.x, 0.0);
        pcPlacement(cycle, center, stampSize, angle);
        pose.center = center;
        pose.size = stampSize;
        pose.angle = angle;
        pose.cycle = cycle;
        pose.visible = 1u;
    }
    else if (stage >= 2 && pose.visible != 0u && feedback_enabled != 0) {
        float dt = clamp(_DeltaTime, 0.0, 0.1);
        float aspect = _Resolution.x / max(_Resolution.y, 1.0);
        float2 pivot = feedback_pivot;
        float kickAmount = saturate(KickEnvelope[0].x);
        float kick = lerp(1.0, max(feedback_kick, 1.0), kickAmount);
        float gain = max(control_gain, 0.0) * kick;
        float2 drift = float2(pan.x * aspect, pan.y) * (dt * gain);
        float zoomFactor = exp2((zoom * 2.0) * dt * gain);
        float angleDelta = radians(feedback_rotation_speed) * dt * kick;
        float cs = cos(angleDelta);
        float sn = sin(angleDelta);

        float2 p = float2((pose.center.x - pivot.x) * aspect,
                          pose.center.y - pivot.y);
        p = float2(cs * p.x - sn * p.y,
                   sn * p.x + cs * p.y) * zoomFactor + drift;
        pose.center = pivot + float2(p.x / aspect, p.y);
        pose.size *= zoomFactor;
        pose.angle += angleDelta;

        int edgeMode = clamp(feedback_edge_mode, 0, 3);
        if (edgeMode == 0) {
            bool inside = pose.center.x >= 0.0 && pose.center.x <= 1.0 &&
                          pose.center.y >= 0.0 && pose.center.y <= 1.0;
            pose.visible = inside ? 1u : 0u;
        }
        else if (edgeMode == 1) {
            pose.center = saturate(pose.center);
        }
        else if (edgeMode == 2) {
            pose.center = frac(pose.center);
        }
        else {
            pose.center = float2(pcMirrorPoseCoordinate(pose.center.x),
                                 pcMirrorPoseCoordinate(pose.center.y));
        }
    }

    OutputBuffer[0] = pose;
}
