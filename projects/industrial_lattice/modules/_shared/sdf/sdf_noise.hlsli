// sdf_noise.hlsli — procedural value-noise / fbm / triplanar for SDF surface detail.
// Self-contained: no nested includes. Include AFTER sdf_ops.hlsli in a module shader:
//   #include "../_shared/sdf/sdf_ops.hlsli"
//   #include "../_shared/sdf/sdf_noise.hlsli"    (this file)
//   #include "../_shared/sdf/sdf_shading.hlsli"
// sd_ prefix so these NEVER collide with the engine `sdf`/`noise` feature libraries.
#ifndef SDF_NOISE_HLSLI
#define SDF_NOISE_HLSLI

// 3D hash -> [0,1)
float sd_hash31(float3 p)
{
    p = frac(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return frac((p.x + p.y) * p.z);
}

// value noise in 3D (trilinear, smoothstep-interpolated), ~[0,1)
float sd_vnoise3(float3 p)
{
    float3 i = floor(p);
    float3 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = sd_hash31(i + float3(0, 0, 0));
    float n100 = sd_hash31(i + float3(1, 0, 0));
    float n010 = sd_hash31(i + float3(0, 1, 0));
    float n110 = sd_hash31(i + float3(1, 1, 0));
    float n001 = sd_hash31(i + float3(0, 0, 1));
    float n101 = sd_hash31(i + float3(1, 0, 1));
    float n011 = sd_hash31(i + float3(0, 1, 1));
    float n111 = sd_hash31(i + float3(1, 1, 1));
    float nx00 = lerp(n000, n100, f.x);
    float nx10 = lerp(n010, n110, f.x);
    float nx01 = lerp(n001, n101, f.x);
    float nx11 = lerp(n011, n111, f.x);
    return lerp(lerp(nx00, nx10, f.y), lerp(nx01, nx11, f.y), f.z);
}

// fractal brownian motion, `oct` octaves (<= 8), normalized ~[0,1)
float sd_fbm3(float3 p, int oct)
{
    float a = 0.5;
    float s = 0.0;
    float norm = 0.0;
    [loop]
    for (int i = 0; i < 8; i++)
    {
        if (i >= oct) break;
        s += a * sd_vnoise3(p);
        norm += a;
        p *= 2.02;
        a *= 0.5;
    }
    return s / max(norm, 1e-4);
}

// triplanar fbm: blend the 3 axis projections by the surface normal. `scale` in 1/world.
float sd_triplanar_fbm(float3 p, float3 n, float scale, int oct)
{
    float3 w = pow(abs(n), 4.0);
    w /= max(w.x + w.y + w.z, 1e-4);
    float3 ps = p * scale;
    float fx = sd_fbm3(ps.zyx, oct);   // X-facing plane samples (z,y)
    float fy = sd_fbm3(ps.xzy, oct);   // Y-facing plane samples (x,z)
    float fz = sd_fbm3(ps.xyz, oct);   // Z-facing plane samples (x,y)
    return fx * w.x + fy * w.y + fz * w.z;
}

// ridged multifractal turbulence: sharp ridges / thin lines — cracks, veins, rock. ~[0,1)
float sd_ridged3(float3 p, int oct)
{
    float a = 0.5, s = 0.0, norm = 0.0;
    [loop]
    for (int i = 0; i < 8; i++)
    {
        if (i >= oct) break;
        float v = 1.0 - abs(2.0 * sd_vnoise3(p) - 1.0);   // fold to a ridge
        s += a * v * v;
        norm += a;
        p *= 2.03;
        a *= 0.5;
    }
    return s / max(norm, 1e-4);
}

// domain-warped fbm: warp the sample point by a low-freq fbm before sampling, breaking
// the value-noise grid alignment -> more organic, less "stretched/blurry" patterns.
float sd_fbm3_warp(float3 p, int oct, float warp)
{
    float3 q = float3(sd_fbm3(p + 11.5, 2), sd_fbm3(p + 47.3, 2), sd_fbm3(p + 83.1, 2));
    return sd_fbm3(p + warp * (q - 0.5), oct);
}

#endif // SDF_NOISE_HLSLI
