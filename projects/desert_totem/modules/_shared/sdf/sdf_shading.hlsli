// sdf_shading.hlsli — shared raymarch shading kit: normals, AO, lighting, camera.
// CONTRACT: the including shader must define, anywhere in the file,
//     float2 sceneMap(float3 p);   // x = distance, y = material id
// This header forward-declares it (HLSL allows prototypes), so include order
// relative to your sceneMap definition does not matter.
// Requires sdf_ops.hlsli included first. No nested includes.
#ifndef SDF_SHADING_HLSLI
#define SDF_SHADING_HLSLI

float2 sceneMap(float3 p);

float3 sdf_calcNormal(float3 p)
{
    // tetrahedron taps, LOOPED so sceneMap is inlined ONCE (not 4x) — critical for
    // compile time when sceneMap is large (heavy instanced/data-driven fields).
    const float e = 0.0009;
    float3 n = float3(0.0, 0.0, 0.0);
    [loop] for (int i = 0; i < 4; i++)
    {
        float3 k = (i == 0) ? float3(1.0, -1.0, -1.0)
                 : (i == 1) ? float3(-1.0, -1.0, 1.0)
                 : (i == 2) ? float3(-1.0, 1.0, -1.0)
                 :            float3(1.0, 1.0, 1.0);
        n += k * sceneMap(p + k * e).x;
    }
    return normalize(n);
}

float sdf_calcAO(float3 p, float3 n)
{
    float occ = 0.0;
    float sca = 1.0;
    [loop] for (int i = 1; i <= 5; i++)
    {
        float h = 0.02 + 0.06 * (float)i;
        occ += (h - sceneMap(p + n * h).x) * sca;
        sca *= 0.74;
    }
    return saturate(1.0 - 2.1 * occ);
}

// classic soft shadow; call with origin nudged off the surface
float sdf_softShadow(float3 ro, float3 rd, float k, float maxT)
{
    float res = 1.0;
    float t = 0.02;
    [loop] for (int i = 0; i < 48; i++)
    {
        float h = sceneMap(ro + rd * t).x;
        if (h < 0.0004) return 0.0;
        res = min(res, k * h / t);
        t += clamp(h, 0.01, 0.25);
        if (t > maxT) break;
    }
    return saturate(res);
}

// sphere-trace helper: returns t, hit material in outMat (-1 = miss)
float sdf_march(float3 ro, float3 rd, float maxT, int maxSteps, out float outMat)
{
    outMat = -1.0;
    float t = 0.0;
    [loop] for (int i = 0; i < 256; i++)
    {
        if (i >= maxSteps) break;
        float3 pos = ro + rd * t;
        float2 h = sceneMap(pos);
        if (h.x < 0.0007 * t + 0.0002) { outMat = h.y; return t; }
        t += h.x;
        if (t > maxT) break;
    }
    return -1.0;
}

// deterministic orbit camera (angles in degrees). ndc: aspect-corrected, y-up.
void sdf_orbitRay(float az_deg, float el_deg, float dist, float3 target, float2 ndc,
                  float focal, out float3 ro, out float3 rd)
{
    float az = radians(az_deg);
    float el = radians(el_deg);
    ro = target + dist * float3(cos(el) * cos(az), sin(el), cos(el) * sin(az));
    float3 fwd = normalize(target - ro);
    float3 rightV = normalize(cross(fwd, float3(0.0, 1.0, 0.0)));
    float3 upV = cross(rightV, fwd);
    rd = normalize(fwd * focal + ndc.x * rightV + ndc.y * upV);
}

// direction of a sun given azimuth/elevation in degrees (points TOWARD the sun)
float3 sdf_sunDir(float az_deg, float el_deg)
{
    float az = radians(az_deg);
    float el = radians(el_deg);
    return normalize(float3(cos(el) * cos(az), sin(el), cos(el) * sin(az)));
}

// simple studio shade: key + wrap fill + spec + rim, all pre-shadowed by sha/ao
float3 sdf_shade(float3 albedo, float3 n, float3 rd, float3 keyDir,
                 float sha, float ao, float specAmt, float specPow)
{
    float dif = saturate(dot(n, keyDir)) * sha;
    float3 fillDir = normalize(float3(-keyDir.x, 0.25, -keyDir.z));
    float fil = saturate(dot(n, fillDir)) * 0.28;
    float3 hv = normalize(keyDir - rd);
    float spec = pow(saturate(dot(n, hv)), specPow) * specAmt * sha;
    float rim = pow(1.0 - saturate(dot(n, -rd)), 3.5) * 0.18;
    return albedo * (0.10 + dif * 0.95 + fil) * ao + spec + rim * ao;
}

#endif // SDF_SHADING_HLSLI
