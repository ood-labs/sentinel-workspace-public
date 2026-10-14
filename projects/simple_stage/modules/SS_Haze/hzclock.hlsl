// SS_Haze / hzclock — the first pass of a frame: the tick, the time step, and the grid's place in the hall.
//
// The hall comes from the Venue (bounds = width, length, height, floor; finish.z = the hall's centre along
// z). The air grid's cell size is the largest that fits the hall in all three axes, and its origin puts the
// grid's x and z centres on the hall's. When the hall changes, or the layout version does, the field is
// marked fresh for a few frames: the force pass clears the air and the haze passes reseed.
//
// The hazers all fire together while Hazers Full is held, and on the drop: the frame the show's BUILD ramp
// (Show State S[11].w, ss_show.hlsli) lands on 1. T[3].y keeps the time of the last press or drop, T[3].w the
// ramp as it stood last frame.
#include "hz_grid.hlsli"
StructuredBuffer<float4> Venue : register(t0);
StructuredBuffer<float4> Show : register(t1);
RWStructuredBuffer<float4> T : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint vn, vs;
    Venue.GetDimensions(vn, vs);
    HzDomain d = hzVenueDomain(vn, vn > 4u ? Venue[3] : 0, vn > 4u ? Venue[4] : 0);
    float4 bounds = float4(d.W, d.L, d.Ht, d.floorY);
    float zc = d.zc;

    float4 t0 = T[0], t1 = T[1], t2 = T[2], t3 = T[3];
    bool ok = t0.x >= 0.0 && t0.x < 1.0e7 && abs(t3.z - HZ_VERSION) < 0.01;
    bool moved = any(abs(t2 - bounds) > 1e-3) || abs(t3.x - zc) > 1e-3;
    if (!ok) { t0 = 0; t3 = float4(zc, -1.0e3, HZ_VERSION, 0); }
    t0.x += 1.0;
    t0.y = _Time;
    // fresh for the first frames after a load, a reload or a new hall: the solid and seed passes run
    // over a field that may hold anything, so they get three frames to settle it
    t0.z = (!ok || moved) ? 3.0 : max(t0.z - 1.0, 0.0);
    t0.w = clamp(_DeltaTime, 0.0, 1.0 / 30.0);
    // all four together: held on by Hazers Full, fired by the drop
    uint sn, ss;
    Show.GetDimensions(sn, ss);
    float ramp = sn >= 12u ? saturate(Show[11].w) : 0.0;
    bool drop = ok && t3.w > 0.05 && t3.w < 0.999 && ramp >= 0.999;
    if (hazers_full != 0 || drop) t3.y = _Time;
    T[0] = t0;
    T[1] = float4(d.lo, d.h);
    T[2] = bounds;
    T[3] = float4(zc, t3.y, HZ_VERSION, ramp);
}
// rev 3 (headers changed: the shader cache keys on this file)
