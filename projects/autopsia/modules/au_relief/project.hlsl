// AUTOPSIA — project the agents into screen space ONCE per frame.
// Doing this per-pixel would mean a 4x4 transform per agent per pixel; here 64
// lanes do it once and the compose pass only runs cheap 2D segment tests.
// Uses the injected internal camera _ViewProjMatrix — same camera as the march.
#include "scene.hlsli"

struct AgentRec {
    float2 position;
    float2 velocity;
    float scale;
    float confidence;
    float angle;
    float age;
    uint stable_id;
    uint kind;
    uint source_index;
    uint flags;
    float4 aux;
};

struct Marker {
    float2 baseUV;    // screen uv of the pin foot
    float2 topUV;     // screen uv of the pin head
    float baseDist;   // distance from camera, for depth testing
    float conf;
    float visible;    // 1 = in front of camera and on screen
    float established; // 1 = long-lived, high confidence
};

RWStructuredBuffer<Marker> Markers : register(u0);

float2 clipToUV(float4 clip, out bool ok) {
    ok = clip.w > 1e-4;
    float2 ndc = clip.xy / max(clip.w, 1e-4);
    return float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

[numthreads(64, 1, 1)]
void main(uint3 gtid : SV_GroupThreadID) {
    uint i = gtid.x;

    Marker m;
    m.baseUV = float2(-10.0, -10.0);
    m.topUV = float2(-10.0, -10.0);
    m.baseDist = 1e9;
    m.conf = 0.0;
    m.visible = 0.0;
    m.established = 0.0;

    if (i < _Data0_Count) {
        AgentRec a = _Data0[i];
        if ((a.flags & 1u) != 0u) {
            float h = auHeightClamped(_Tex0, LinearSampler,
                                      auUVToWorld(a.position, 0.0).xz, height_scale);
            float3 wBase = auUVToWorld(a.position, h);
            float3 wTop = wBase + float3(0.0, pin_height * (0.35 + 0.65 * a.confidence), 0.0);

            bool okA, okB;
            float2 bUV = clipToUV(mul(_ViewProjMatrix, float4(wBase, 1.0)), okA);
            float2 tUV = clipToUV(mul(_ViewProjMatrix, float4(wTop, 1.0)), okB);

            m.baseUV = bUV;
            m.topUV = tUV;
            m.baseDist = distance(_CameraPos, wBase);
            m.conf = saturate(a.confidence);
            m.visible = (okA && okB) ? 1.0 : 0.0;
            m.established = (a.confidence >= 0.88 && a.age >= 4.0) ? 1.0 : 0.0;
        }
    }

    Markers[i] = m;
}
