// CRYOGRAM / INTERPRETATION — heightfield march on the INTERNAL camera.
//
// Rays are built from the injected _InvViewProjMatrix / _CameraPos with the
// DirectX Y flip. There is no shader-local orbit, no authored eye position and
// no parallel camera equation anywhere in this module.
//
// G-buffer out (RGBA32F): (hit distance | -1 miss, elevation, grain id, orientation)

#include "common.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

// _Tex0 is now the COMBINED height field: .g is already world height with the
// kick swells composited in, so it must not be scaled again here.
float cryoHeight(float2 uv) {
    return cryoFieldBilinear(_Tex0, uv).g;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;

    float2 screenUV = ((float2)id.xy + 0.5) / _Resolution.xy;
    float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);

    float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nearW /= nearW.w;
    farW  /= farW.w;

    float3 ro = _CameraPos;
    float3 rd = normalize(farW.xyz - nearW.xyz);

    float tmax = march_distance;
    float t = 0.02;
    float prevT = t;
    float prevGap = 1e9;
    bool hit = false;

    int steps = (int)clamp(march_steps, 24, 320);

    [loop] for (int i = 0; i < steps; ++i) {
        float3 p = ro + rd * t;

        // escape upward once above the tallest possible surface — the ceiling
        // has to allow for an active swell, not just the base relief
        float ceiling = height_scale + pulse_amp * 1.15 + 0.03;
        if (rd.y > 0.0 && p.y > ceiling) break;

        float h = cryoHeight(cryoUvFromWorld(p));
        float gap = p.y - h;

        if (gap < 0.0) {
            // refine the crossing between prevT and t
            float lo = prevT, hi = t;
            [unroll] for (int r = 0; r < 7; ++r) {
                float mid = 0.5 * (lo + hi);
                float3 pm = ro + rd * mid;
                if (pm.y - cryoHeight(cryoUvFromWorld(pm)) < 0.0) hi = mid; else lo = mid;
            }
            t = hi;
            hit = true;
            break;
        }

        prevT = t;
        prevGap = gap;
        t += max(0.008, gap * 0.55 + t * 0.006);
        if (t > tmax) break;
    }

    if (!hit) {
        OutputUAV[id.xy] = float4(-1.0, 0.0, 0.0, 0.0);
        return;
    }

    float3 hp = ro + rd * t;
    float2 uv = cryoUvFromWorld(hp);
    float4 f = cryoFieldBilinear(_Tex0, uv);

    OutputUAV[id.xy] = float4(t, f.g * height_scale, f.a, f.b);
}
