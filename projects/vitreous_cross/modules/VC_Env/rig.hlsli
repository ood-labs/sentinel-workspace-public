// VC_Env / rig.hlsli — where the key actually points, per rig.
//
// One definition, used twice: env.hlsl places the emissive source with it, and rig.hlsl
// publishes it as a control output so VC_Render's contact shadow can be driven from it by an
// expression rather than by a second copy of the same numbers living in the renderer.
#ifndef VC_RIG_HLSLI
#define VC_RIG_HLSLI

void vcKeyAngles(int rig, float az, float el, out float kaz, out float kel)
{
    kaz = az;
    kel = el;
    if (rig == 1)      kel = el * 0.5;    // Twin Strip: the dominant strip sits lower
    else if (rig == 2) kel = 1.22;        // Overhead Wash: fixed ceiling source
}

float3 vcDirFromAngles(float az, float el)
{
    float ce = cos(el), se = sin(el);
    return float3(ce * sin(az), se, ce * cos(az));
}

#endif
