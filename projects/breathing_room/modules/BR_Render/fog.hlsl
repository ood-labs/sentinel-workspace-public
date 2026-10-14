// BR_Render / fog.hlsl -- sunbeams in dusty air, at quarter resolution.
//
// Sun visibility inside the room is ANALYTIC: a point is in a beam only if the ray toward the sun
// leaves the room box through an opening, clears the sash frame and muntins where it crosses the
// frame plane, clears the outer reveal, and then survives glass, sheer and the street trees. So
// the beams carry the window's own mullion pattern and the leaves' dapple without marching the
// scene. Dust is a slowly drifting density field; the phase is a dual lobe normalised so that
// isotropic scattering is 1 (the ambient term beside it is in the same units).
//
// Rays come from the camera the G-buffer carries (it reaches this pass a cook after it was cast),
// and alpha packs transmittance with the ray's length (render_common: fogPack). Texels (0..19, 0)
// carry that camera on to fogtaa.
#include "render_common.hlsli"

StructuredBuffer<float4> SkyLut : register(t1);
StructuredBuffer<float> SunVol : register(t3);
StructuredBuffer<ProbeRec> Probes : register(t4);
RWTexture2D<float4> OutputUAV : register(u0);

float hgPhase(float c, float g) { return (1.0 - g * g) / pow(max(1.0 + g * g - 2.0 * g * c, 1e-4), 1.5); }

// Does a ray from x toward the sun get out through a window, and how much of it?
float beamVisibility(float3 x, float3 L, BRSkyCtx S, BRRoom R)
{
    float3 fN;
    float te = boxExit(x, L, fN);
    float3 xe = x + L * te;
    if (fN.y != 0.0) return 0.0;                         // through floor or ceiling: no openings there
    float vis = 0.0;
    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = scOpen(i);
        if (!o.active || !brOpenIsGlazed(o.kind)) continue;
        float3 lq = openLocal(xe, o, R);
        float hw = o.width * 0.5;
        if (abs(lq.z) > 0.02 || abs(lq.x) > hw || lq.y < 0.0 || lq.y > o.height) continue;
        // where the ray crosses the frame plane and the street face
        float2 n2 = brWallNormal(o.wall);
        float ln = dot(L, float3(n2.x, 0.0, n2.y));
        if (ln > -1e-4) continue;
        float dc = -R.T + 0.075;
        float3 xc = xe + L * ((dc - 0.0) / ln);
        float3 lc = openLocal(xc, o, R);
        float3 lo = openLocal(xe + L * ((-R.T) / ln), o, R);
        if (abs(lo.x) > hw || lo.y < 0.0 || lo.y > o.height) continue;   // clipped by the outer reveal
        SHit fh = shit(1e9, 0, 0, -1);
        windowFrame(lc, o, R.T, fh, i);
        if (fh.d < 0.0) continue;                                         // a sash bar or muntin
        vis = 1.0;
        vis *= veilTransmitOpening(xe - L * 0.2, L, o, R, sheerOpacity());
        float tOut = R.T / max(-ln, 0.05);
        vis *= 0.88 * brCanopyTransmitPen(xe + L * tOut, L, S, 0.0, te + tOut, scSunSoft());
        break;
    }
    return vis;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;
    uint FW, FH;
    _Tex2.GetDimensions(FW, FH);
    int2 GR = renderRes(int2(FW, FH));            // the G-buffer's render region (render_common)
    FW = (uint)GR.x; FH = (uint)GR.y;
    float2 fres = float2(FW, FH);
    float2 scale = fres / float2(W, H);
    float2 fullPix = (float2(tid.xy) + 0.5) * scale - 0.5;
    float4 fr = scFrame();
    CamHdr gc = camHeader(_Tex2);
    if (!gc.ok) gc = camLive(_ViewProjMatrix, _InvViewProjMatrix, _CameraPos, fr.yz, fr.x);
    if (isCamTexel(int2(tid.xy))) { OutputUAV[tid.xy] = camHeaderTexel(gc, (int)tid.x); return; }
    float3 ro, rd;
    camRay(gc, fullPix, fres, float2(0, 0), ro, rd);
    GSample g = unpackG(_Tex2.Load(int3(clamp((int2)round(fullPix), int2(0, 0), int2(FW - 1, FH - 1)), 0)));
    BRRoom R = scRoom();
    BRSkyCtx S = scSkyCtx();
    float3 L = S.sunDir;

    float tEnd = g.t;
    if ((g.flags & (G_FLAG_EXTERIOR | G_FLAG_MISS)) != 0u)
    {
        float3 fN;
        tEnd = insideRoomBox(ro, 0.0) ? boxExit(ro, rd, fN) : 0.0;
    }
    int N = clamp(fog_steps, 0, 128);
    float dens0 = fog_density;
    if (N == 0 || dens0 <= 0.0 || S.sunDir.y < -0.05)
    {
        OutputUAV[tid.xy] = float4(0, 0, 0, fogPack(1.0, tEnd));
        return;
    }
    // stratified in space AND time: interleaved gradient noise, advanced by the golden ratio each
    // frame. White noise re-rolled per texel flashed in 4x4 blocks wherever a beam is cut by a
    // leaf or a muntin; this converges in a few frames and its residue is spread evenly.
    float ign = frac(52.9829189 * frac(dot(float2(tid.xy), float2(0.06711056, 0.00583715))));
    float jitter = frac(ign + fr.x * 0.61803399);
    float dt = tEnd / (float)N;
    float c = dot(rd, L);
    float phase = lerp(hgPhase(c, 0.62), hgPhase(c, -0.2), 0.30);
    phase = min(phase, 7.0);
    float3 acc = 0;
    float T = 1.0;
    float time = scFrameB().w;
    [loop] for (int i = 0; i < N; i++)
    {
        float t = ((float)i + jitter) * dt;
        float3 x = ro + rd * t;
        float dust = 0.55 + 0.9 * saturate(brFbm3(x * 1.7 + float3(time * 0.02, time * 0.011, -time * 0.015), 3, 0.0) + 0.35);
        dust = lerp(1.0, dust, dust_amount);
        float sig = dens0 * dust;
        float vis = beamVisibility(x, L, S, R);
        if (vis > 0.0) vis *= sunVolAt(SunVol, x);          // the breast, the furniture
        float3 amb = probeAvgRadiance(Probes, x) * gi_gain;
        float3 Ls = S.sunRad * vis * phase + amb;
        float a = exp(-sig * dt);
        acc += T * Ls * sig * dt;
        T *= a;
    }
    OutputUAV[tid.xy] = float4(acc, fogPack(T, tEnd));
}
