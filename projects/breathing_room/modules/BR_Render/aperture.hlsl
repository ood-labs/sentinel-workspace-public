// BR_Render / aperture.hlsl -- what each opening shows of the outside, for the probes' window light.
//
// One group per opening slot, 48 threads: three ROWS of the opening (bottom, middle, top) x 16
// stratified directions each, seen from sitting eye height in the middle of the room. Each row's
// mean exterior radiance (street and trees low, canopy and skyline in the middle, sky above),
// already through the glass and the sheers, becomes a small area light that probes.hlsl adds to
// every probe ANALYTICALLY. Tracing random rays out of a window is what made the walls and ceiling
// boil: a probe found the bright opening with one or two rays out of 32.
#include "render_common.hlsli"

StructuredBuffer<float4> SkyLut : register(t1);
RWStructuredBuffer<float4> Aper : register(u0);

groupshared float3 gsA[48];

bool isAperture(BROpening o) { return o.active && (brOpenIsGlazed(o.kind) || o.kind == OPEN_ARCH); }

[numthreads(48, 1, 1)]
void main(uint3 gid : SV_GroupID, uint3 gtid : SV_GroupThreadID)
{
    int j = (int)gid.x;
    int k = (int)gtid.x;
    int row = k / 16, s = k % 16;
    BRRoom R = scRoom();
    BROpening o = scOpen(clamp(j, 0, SHELL_OPEN_MAX - 1));
    BRSkyCtx S = scSkyCtx();
    S.wind = 0.0;                     // window light for the GI: the canopy at rest (see probes.hlsl)
    float3 L = 0;
    bool ok = j < SHELL_OPEN_MAX && isAperture(o);
    if (ok)
    {
        float u = ((float)(s % 4) + 0.5) / 4.0, v = ((float)(s / 4) + 0.5) / 4.0;
        float a = o.a + (u - 0.5) * o.width * 0.9;
        float y = o.sill + o.height * ((float)row + v) / 3.0;
        float2 wp = brWallPoint(R, o.wall, a, -R.T - 0.01);          // just past the street face
        float3 xo = float3(wp.x, y, wp.y);
        float3 eye = float3((R.x0 + R.x1) * 0.5, 1.2, (R.z0 + R.z1) * 0.5);
        float3 d = normalize(xo - eye);
        L = brExterior(xo, d, 0.0, S, SkyLut, false);
        if (o.kind != OPEN_ARCH) L *= veilTransmitOpening(eye, d, o, R, sheerOpacity());
        if (!(abs(L.r) < 1e5 && abs(L.g) < 1e5 && abs(L.b) < 1e5)) L = 0;
    }
    gsA[k] = L;
    GroupMemoryBarrierWithGroupSync();
    if (s == 0 && j < SHELL_OPEN_MAX)
    {
        float3 sum = 0;
        [loop] for (int i = 0; i < 16; i++) sum += gsA[row * 16 + i];
        Aper[j * 3 + row] = float4(sum / 16.0, ok ? 1.0 : 0.0);
    }
}
