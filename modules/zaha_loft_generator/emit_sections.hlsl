#include "types.hlsli"

RWStructuredBuffer<LoftSection> OutputBuffer : register(u0);

float profilePulse(float t, int mode) {
    if (mode == 0) return 0.86 + 0.18 * sin(t * 3.14159265);
    if (mode == 1) return 0.72 + 0.42 * pow(sin(t * 3.14159265), 0.55);
    if (mode == 2) return 0.64 + 0.50 * smoothstep(0.0, 0.42, t) * (1.0 - smoothstep(0.64, 1.0, t));
    return 0.74 + 0.26 * sin(t * 6.2831853 + 0.7) + 0.12 * sin(t * 18.849556);
}

[numthreads(64,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i >= 96u) return;

    LoftSection s = (LoftSection)0;
    float t = (float)i / 95.0;
    uint sampleIndex = (uint)round(t * 63.0);
    if (_Data0_Count == 0u || sampleIndex >= _Data0_Count || _Data0[sampleIndex].active < 0.5) {
        OutputBuffer[i] = s;
        return;
    }

    float2 gesture = _Data0[sampleIndex].pos;
    float2 gestureDir = normalize(_Data0[sampleIndex].dir + float2(1e-5, 0.0));
    float mx = morph_field.x * 2.0 - 1.0;
    float my = morph_field.y * 2.0 - 1.0;
    float tx = torsion_field.x * 2.0 - 1.0;
    float ty = torsion_field.y * 2.0 - 1.0;
    float pulse = profilePulse(t, profile_family);
    float taper = lerp(1.0, 0.30, pow(t, lerp(0.7, 2.2, taper_bias)));
    float waist = 1.0 - waist_depth * exp(-pow((t - waist_position) * 5.0, 2.0));
    float crown = 1.0 + crown_flare * smoothstep(0.72, 1.0, t);

    s.center = float3(
        gesture.x * lean_gain + mx * sin(t * 3.14159265) * 2.2,
        podium_height + t * tower_height + gesture.y * contour_gain,
        gesture.y * depth_drift + my * sin(t * 6.2831853) * 1.4
    );
    s.radius_x = max(0.35, base_width * pulse * taper * waist * crown * (1.0 + 0.16 * my * sin(t * 12.0)));
    s.radius_z = max(0.28, base_depth * pulse * taper * waist * (1.0 - 0.18 * mx * cos(t * 10.0)));
    s.rotation = radians(global_twist * t + tx * 150.0 * t * t + gesture.x * 7.0);
    s.curvature = length(gestureDir - normalize(_Data0[max((int)sampleIndex - 1, 0)].dir + float2(1e-5,0.0)));
    s.u = t;
    s.floor_band = frac(t * max((float)floor_count, 1.0));
    s.skin_bias = saturate(0.5 + 0.5 * sin(t * 17.0 + ty * 5.0));
    s.void_bias = saturate(canyon_void + 0.30 * sin(t * 9.0 + mx * 4.0));
    s.active = 1.0;
    s.tangent = normalize(float3(gestureDir.x * lean_gain, tower_height / 3.5, gestureDir.y * depth_drift) + 1e-5);
    s.seed = seed * 101.7 + (float)i * 13.37;
    OutputBuffer[i] = s;
}
