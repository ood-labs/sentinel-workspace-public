// VC_Env / rig.hlsl — publishes the studio's dominant light direction as control outputs.
//
// VC_Render needs a direction to trace the contact shadow along. It must not own a second
// copy of "where the key is" — that is the kind of duplicate that silently disagrees the
// first time anyone moves the light. Instead the studio publishes its own key vector here,
// and the renderer's shadow direction is driven from it by an expression.
#include "rig.hlsli"

RWStructuredBuffer<float4> Rig : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float kaz, kel;
    vcKeyAngles((int)light_rig, key_azimuth, key_elevation, kaz, kel);
    float3 d = vcDirFromAngles(kaz, kel);
    // xyz: unit vector from the subject TOWARD the key. w: the key's power, so a renderer can
    // scale a shadow's density with the light that casts it.
    Rig[0] = float4(d, key_gain);
    Rig[1] = float4(kaz, kel, (float)light_rig, 0.0);
}
