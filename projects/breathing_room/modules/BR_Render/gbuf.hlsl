// BR_Render / gbuf.hlsl -- primary visibility.
//
// Hybrid march: from inside the room the six box faces are intersected ANALYTICALLY and only the
// detail field is sphere traced (step = min(detail, distance to the box face along the ray)), so
// a floor seen at a grazing angle costs one step instead of two hundred. Where the analytic face
// is open (a window, a door, the firebox mouth) the ray carries on with the full field and either
// hits the reveal/frame or leaves the building (flagged EXTERIOR with the exit distance).
// The normal is taken from four tetrahedral taps that reuse the SAME map call site as the march.
//
// This is where the camera enters the chain: texels (0..19, 0) carry the camera and jitter these
// rays were cast with (br_camtexels.hlsli). shade and fog read this G-buffer a cook later, when
// the live camera has already moved on, and build their rays from THAT header, not the live one.
#include "render_common.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    // the render region (render_common: renderRes); the jitter is in ITS pixels, so a still camera
    // sweeps every sample across the full-resolution pixels it covers
    int2 RR = renderRes(int2(W, H));
    if ((int)tid.x >= RR.x || (int)tid.y >= RR.y) return;
    float2 res = float2(RR);
    float4 fr = scFrame();
    float3 ro, rd;
    camRayJ(float2(tid.xy), res, fr.yz, ro, rd);
    float pa = pixelAngle(float2(W, H));

    bool inRoom = insideRoomBox(ro, 0.0005);
    float3 faceN = float3(0, 1, 0);
    float tBox = inRoom ? boxExit(ro, rd, faceN) : 1e9;
    bool passed = !inRoom;

    const float3 TET[4] = { float3(1, -1, -1), float3(-1, -1, 1), float3(-1, 1, -1), float3(1, 1, 1) };
    float t = 0.0;
    int phase = 0;              // 0 march, 1 normal taps, 2 done
    int tap = 0;
    SHit hit = shit(1e9, 0, 0, -1);
    float3 hp = ro;
    float3 nrm = float3(0, 0, 0);
    uint flags = 0u;
    uint steps = 0u;
    float lastD = 1e9;
    int maxSteps = clamp(march_steps, 16, 600);

    [loop] for (int i = 0; i < 620; i++)
    {
        if (phase == 2) break;
        if (phase == 0 && (int)steps >= maxSteps)
        {
            // an exhausted march that was still close to something HIT it -- it just could not afford
            // to prove it (grazing faces); a far one left the scene
            if (lastD < 0.01 + t * pa * 4.0) { phase = 1; hp = ro + rd * t; }
            else { flags |= G_FLAG_MISS; phase = 2; }
            if (phase == 2) break;
        }
        float tapE = 0.0004 + max(t, 0.5) * pa * 0.35;
        float3 x = (phase == 0) ? ro + rd * t : hp + TET[tap] * tapE;
        SHit slab;
        SHit det = mapSplit(x, slab, false);
        float dFull = min(det.d, slab.d);
        if (phase == 0)
        {
            steps++;
            float eps = max(0.00025, t * pa * 0.55);
            lastD = dFull;
            if (!passed)
            {
                float toBox = tBox - t;
                if (det.d < eps)
                {
                    hit = det; hp = x; phase = 1;
                }
                else if (toBox < eps)
                {
                    float3 xb = ro + rd * tBox;
                    if (boxFacePassable(xb))
                    {
                        passed = true;
                        t = tBox + 0.003;
                    }
                    else
                    {
                        hit = slab; hit.d = 0.0;
                        hp = xb; t = tBox; nrm = faceN;
                        flags |= G_FLAG_BOXHIT;
                        phase = 2;
                    }
                }
                else
                {
                    t += min(det.d, toBox);
                }
            }
            else
            {
                if (dFull < eps)
                {
                    if (slab.d < det.d) hit = slab; else hit = det; hp = x; phase = 1;
                }
                else
                {
                    t += dFull;
                    if (outsideBuilding(x) || t > 80.0) { flags |= G_FLAG_EXTERIOR; phase = 2; }
                }
            }
        }
        else
        {
            nrm += TET[tap] * dFull;
            tap++;
            if (tap >= 4) { nrm = normalize(nrm + 1e-9); phase = 2; }
        }
    }

    if ((flags & (G_FLAG_EXTERIOR | G_FLAG_MISS)) != 0u)
        OutputUAV[tid.xy] = packG(t, -rd, 0, 0, -1, steps, flags);
    else
        OutputUAV[tid.xy] = packG(length(hp - ro), nrm, hit.mat, hit.part, hit.obj, steps, flags);
    if (isCamTexel(int2(tid.xy)))
        OutputUAV[tid.xy] = camHeaderTexel(camLive(_ViewProjMatrix, _InvViewProjMatrix, _CameraPos, fr.yz, fr.x), (int)tid.x);
}
