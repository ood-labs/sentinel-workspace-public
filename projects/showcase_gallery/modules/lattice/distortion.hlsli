// Living Room-style world-space deformation adapted for the infinite lattice.
// The master is a true kill switch. Vertical bend/twist coordinates are bounded so
// an unbounded repeated field remains stable far away from the camera.

float2 latticeFxRot2(float2 p, float a)
{
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float3 latticeFxRotX(float3 p, float a) { p.yz = latticeFxRot2(p.yz, a); return p; }
float3 latticeFxRotY(float3 p, float a) { p.xz = latticeFxRot2(p.xz, a); return p; }

float3 latticeWarpField(float3 p, int mode, float f, float t)
{
    if (mode == 1)
    {
        float r = length(p.xz) + 1e-3;
        float w = sin(r * f * 2.0 - t * 2.0);
        return float3(p.x / r * w, sin(p.y * f + t), p.z / r * w) * 0.6;
    }
    if (mode == 2)
        return float3(sin(p.y * f + t), cos(p.x * f - t), sin(p.z * f + t * 1.3));
    if (mode == 3)
    {
        float3 w = float3(sin(p.y * f + t), sin(p.z * f * 1.3 + t), sin(p.x * f * 0.7 - t));
        w += 0.5 * float3(sin(p.y * f * 2.1 + t * 1.7), sin(p.z * f * 2.3 - t), sin(p.x * f * 1.9 + t));
        return w;
    }
    if (mode == 4)
    {
        float3 s = float3(sin(p.y * f + t), sin(p.z * f * 1.2 - t), sin(p.x * f * 0.8 + t));
        return lerp(s, round(s * 3.0) / 3.0, 0.85);
    }
    if (mode == 5)
    {
        float3 s = float3(sin(p.y * f + t), sin(p.x * f - t), sin(p.z * f * 1.3 + t));
        return clamp(s * 4.0, -1.0, 1.0) * 0.7;
    }
    if (mode == 6)
    {
        float3 cellId = floor(p * f * 0.6 + t * 0.1);
        float3 h = float3(
            frac(sin(dot(cellId, float3(12.9, 78.2, 37.7))) * 43758.5),
            frac(sin(dot(cellId, float3(39.3, 11.1, 83.2))) * 24634.6),
            frac(sin(dot(cellId, float3(73.1, 52.7, 9.7))) * 13451.2)) - 0.5;
        return h * 1.4;
    }
    return float3(
        sin(p.y * f + t) + 0.5 * sin(p.z * f * 1.7 - t * 1.3),
        sin(p.z * f * 0.9 + t) + 0.5 * sin(p.x * f * 1.5 + t * 1.1),
        sin(p.x * f * 1.1 - t) + 0.5 * sin(p.y * f * 1.3 + t * 0.7));
}

float3 latticeWarpLayer(float3 p, float amount, int mode, float freq, float speed,
                        float3 offset, float yaw, float pitch)
{
    if (amount < 0.001) return 0.0;
    float3 q = latticeFxRotX(latticeFxRotY(p - offset, yaw), pitch);
    float3 d = latticeWarpField(q, mode, freq, _Time * fx_speed * speed);
    d = latticeFxRotY(latticeFxRotX(d, -pitch), -yaw);
    return amount * d;
}

float3 latticeDomainDistort(float3 p)
{
    float master = saturate(fx_amount);
    if (master < 0.0001) return p;

    float3 center = float3(dist_cx, dist_cy, dist_cz);
    float3 q = p;
    float h = tanh((q.y - center.y) * 0.12) * 8.0;
    float t = _Time * fx_speed;

    if (abs(twist_amt) > 0.001)
        q.xz = latticeFxRot2(q.xz - center.xz, master * twist_amt * h * 0.35) + center.xz;
    if (abs(bend_amt) > 0.001)
        q.x += master * bend_amt * h * h * 0.06;
    if (abs(swirl_amt) > 0.001)
    {
        float2 d = q.xz - center.xz;
        q.xz = latticeFxRot2(d, master * swirl_amt * exp(-length(d) * 0.4)) + center.xz;
    }
    if (wave_amt > 0.001)
        q += master * wave_amt * sin(q.yzx * wave_freq + t) * 0.3;
    if (melt_amt > 0.001)
    {
        float3 d1 = latticeWarpLayer(q, w1_amt, w1_mode, w1_freq, w1_speed,
                                    float3(w1_ox, w1_oy, w1_oz), w1_yaw, w1_pitch);
        float3 d2 = latticeWarpLayer(q, w2_amt, w2_mode, w2_freq, w2_speed,
                                    float3(w2_ox, w2_oy, w2_oz), w2_yaw, w2_pitch);
        q += master * melt_amt * (d1 + d2);
    }
    return q;
}

float latticeDistortLip()
{
    float master = saturate(fx_amount);
    float warpF = melt_amt * (w1_amt * w1_freq + w2_amt * w2_freq) * 0.5;
    float gradient = warpF + wave_amt * wave_freq * 0.25 + abs(twist_amt) * 0.4
                   + abs(swirl_amt) * 0.3 + abs(bend_amt) * 0.3;
    return 1.0 / (1.0 + master * gradient);
}

