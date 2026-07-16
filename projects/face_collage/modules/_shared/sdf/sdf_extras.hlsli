// sdf_extras.hlsli — additional SDF techniques harvested from scene builds.
// Requires sdf_ops.hlsli included FIRST (uses sd_capsule / sd_cyl / sd_sphere /
// sd_cone / sd_torus). No nested includes. Include AFTER sdf_ops, alongside
// sdf_objects / sdf_shading. Harvested from the dada_totem assemblage build.
#ifndef SDF_EXTRAS_HLSLI
#define SDF_EXTRAS_HLSLI

// Quadratic-bezier tube: sweep a capsule of radius r along the curve A->B->C,
// approximated by 8 straight segments. The "spline" transport for wires, rigging,
// hanging cables and bent arcs — cheap, robust, and Lipschitz-safe (min of capsules).
// For a straight cable pass B = (A+C)*0.5.
float sd_bezierTube(float3 p, float3 a, float3 b, float3 c, float r)
{
    float d = 1e9;
    float3 prev = a;
    [unroll] for (int i = 1; i <= 8; i++)
    {
        float t = (float)i / 8.0;
        float3 pt = lerp(lerp(a, b, t), lerp(b, c, t), t);
        d = min(d, sd_capsule(p, prev, pt, r));
        prev = pt;
    }
    return d;
}

// Turned baluster / chess-pawn finial: a lathe-like stack of primitives revolved
// about Y (foot disc, lower bulb, neck cone, collar torus, upper bulb, tip). `base`
// is the world-space foot centre; total height ~1.16 in local units. Scale by moving
// `base` and pre-scaling p. The reusable stand-in for turned-wood / spindle finials.
float obj_baluster(float3 p, float3 base)
{
    float3 q = p - base;
    float d = sd_cyl(q - float3(0, 0.04, 0), 0.04, 0.14);           // foot disc
    d = min(d, sd_sphere(q - float3(0, 0.26, 0), 0.155));           // lower bulb
    d = min(d, sd_cone(q - float3(0, 0.52, 0), 0.20, 0.12, 0.05));  // neck
    d = min(d, sd_torus(q - float3(0, 0.74, 0), 0.085, 0.028));     // collar
    d = min(d, sd_sphere(q - float3(0, 0.94, 0), 0.11));            // upper bulb
    d = min(d, sd_sphere(q - float3(0, 1.12, 0), 0.055));           // finial tip
    return d;
}

#endif // SDF_EXTRAS_HLSLI
