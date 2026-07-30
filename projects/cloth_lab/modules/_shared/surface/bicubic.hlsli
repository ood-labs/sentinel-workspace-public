#ifndef SENTINEL_BICUBIC_HLSLI
#define SENTINEL_BICUBIC_HLSLI

// Catmull-Rom bicubic patch evaluation for grid surfaces.
//
// Why this exists: a simulation grid coarse enough to be cheap is too coarse to
// rasterise directly - its silhouette reads as a polygon. Subdividing the RENDER
// grid and evaluating a bicubic patch through the simulated points gives a smooth
// surface while the simulation stays small. That split (simulate coarse, render
// fine) is standard in production cloth, water, and terrain deformation.
//
// Catmull-Rom is the right basis here because it INTERPOLATES its control points
// rather than approximating them, so the rendered surface passes exactly through
// the simulated positions, and it is C1 continuous across cell boundaries, so
// adjacent cells produce no cracks and no normal discontinuity.
//
// Normals come from the patch's analytic tangents, which reuse the same 16
// control points already fetched - far cheaper and smoother than finite
// differencing the surface with extra evaluations.
//
// Control points are row-major 4x4: c[j * 4 + i] is column i, row j, covering
// cell indices (cx-1 .. cx+2, cy-1 .. cy+2). Clamp those indices to the grid at
// the border before fetching.

float4 srf_cr_weights(float t)
{
    float t2 = t * t;
    float t3 = t2 * t;
    return float4(-0.5 * t3 +       t2 - 0.5 * t,
                   1.5 * t3 - 2.5 * t2       + 1.0,
                  -1.5 * t3 + 2.0 * t2 + 0.5 * t,
                   0.5 * t3 - 0.5 * t2);
}

float4 srf_cr_deriv(float t)
{
    float t2 = t * t;
    return float4(-1.5 * t2 + 2.0 * t - 0.5,
                   4.5 * t2 - 5.0 * t,
                  -4.5 * t2 + 4.0 * t + 0.5,
                   1.5 * t2 -       t);
}

// Evaluates position and both surface tangents in one pass over the 16 points.
void srf_bicubic(float3 c[16], float tu, float tv,
                 out float3 pos, out float3 tanU, out float3 tanV)
{
    float4 wu = srf_cr_weights(tu);
    float4 wv = srf_cr_weights(tv);
    float4 du = srf_cr_deriv(tu);
    float4 dv = srf_cr_deriv(tv);

    pos  = float3(0.0, 0.0, 0.0);
    tanU = float3(0.0, 0.0, 0.0);
    tanV = float3(0.0, 0.0, 0.0);

    [unroll]
    for (int j = 0; j < 4; ++j)
    {
        float3 rowP = float3(0.0, 0.0, 0.0);
        float3 rowD = float3(0.0, 0.0, 0.0);
        [unroll]
        for (int i = 0; i < 4; ++i)
        {
            float3 p = c[j * 4 + i];
            rowP += p * wu[i];
            rowD += p * du[i];
        }
        pos  += rowP * wv[j];
        tanU += rowD * wv[j];
        tanV += rowP * dv[j];
    }
}

// Convenience: position plus a normalised normal.
void srf_bicubic_normal(float3 c[16], float tu, float tv,
                        out float3 pos, out float3 nrm)
{
    float3 tanU, tanV;
    srf_bicubic(c, tu, tv, pos, tanU, tanV);
    float3 n = cross(tanU, tanV);
    float l = length(n);
    nrm = (l > 1e-8) ? n / l : float3(0.0, 0.0, 1.0);
}

#endif // SENTINEL_BICUBIC_HLSLI
