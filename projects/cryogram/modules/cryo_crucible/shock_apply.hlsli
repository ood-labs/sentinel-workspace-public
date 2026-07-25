// CRYOGRAM / SPECIMEN — shock evaluation.
//
// Include AFTER declaring `StructuredBuffer<Shock> Shocks : register(tN);`.
//
// The radial ripple displacement that used to live here has been REMOVED. It
// read as a smaller copy of the kick's swell no matter how it was tuned, and
// feeding it to the detector also destroyed track continuity. The snare's
// visual now lives entirely in the 3D layer as a volumetric noise burst.
//
// What remains is the structural half: a brief liquefaction at the impact
// point, so a snare genuinely removes material that then has to regrow.

#ifndef CRYO_SHOCK_APPLY_HLSLI
#define CRYO_SHOCK_APPLY_HLSLI

float cryoShockMelt(float2 uv, float aspect, float now) {
    float m = 0.0;
    [loop] for (uint i = 0u; i < CRYO_MAXSHOCK; ++i) {
        Shock s = Shocks[i];
        if (s.active < 0.5) continue;
        float age = now - s.birth;
        if (age < 0.0 || age > shock_melt_time) continue;

        float2 v = (uv - s.center) * float2(aspect, 1.0);
        float d = length(v);
        float r = shock_melt_radius * s.strength;
        if (d > r) continue;
        m = max(m, 1.0 - smoothstep(r * 0.55, r, d));
    }
    return m;
}

#endif
