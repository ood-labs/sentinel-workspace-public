// Aiming any moving head through its GDTF, for fixtures whose type is not PHAGE's own Halo Beam: the pan and tilt its
// DMX must carry to throw its beam along a stage direction, and back. The model is the fixture engine's
// (fe_rig.hlsli fePoseVector): in the type's profile frame the head turns by -tilt about +X, then the yoke by pan about
// +Y, each angle the decoded value times the type's axis sense (FE_PANTILT_DIR). The beam at home is the type's main
// light-casting emitter's face normal. Include after fe_tables.hlsli (GDTF_RENDER bound) and fe_rig.hlsli.
#ifndef PHAGE_AIM_HLSLI
#define PHAGE_AIM_HLSLI

// Profile frame -> stage, from the fixture's GDTF axes in the stage (its frame on the rig, carried by the truss).
float3x3 phAimFrame(uint t, float3 gx, float3 gy, float3 gz)
{
    float3x3 toGdtf = float3x3(frGdtfAxis(t, 0u), frGdtfAxis(t, 1u), frGdtfAxis(t, 2u));
    float3x3 toStage = transpose(float3x3(gx, gy, gz));
    return mul(toStage, toGdtf);
}

// The beam direction at home in the profile frame: the face normal of the first beam emitter, else the first wash.
float3 phAimHome(uint t)
{
    uint me = feMaxEmitters(), beam = 0xFFu, wash = 0xFFu;
    for (uint e = 0u; e < me; e++)
    {
        uint kind = FE_EMITTER_AT(t * me + e).x;
        beam = (kind == FE_EMITTER_BEAM && beam == 0xFFu) ? e : beam;
        wash = (kind == FE_EMITTER_WASH && wash == 0xFFu) ? e : wash;
    }
    uint pick = beam != 0xFFu ? beam : wash;
    if (pick == 0xFFu) return float3(0, -1, 0);
    uint face = (uint)(FE_DRAW_AT((t * me + pick) * 3u + 1u).w + 0.5);
    float3 n = FE_FACE_G_AT(face * 4u + 1u).xyz;
    return dot(n, n) > 1e-6 ? normalize(n) : float3(0, -1, 0);
}

// Where the beam points (stage) for decoded pan and tilt (degrees).
float3 phAimForward(uint t, float3x3 R, float panDeg, float tiltDeg)
{
    float2 sense = FE_PANTILT_DIR_AT(t);
    float3 v = fePoseVector(2u, phAimHome(t), panDeg * sense.x, tiltDeg * sense.y);
    return normalize(mul(R, v));
}

// The physical (lo, hi) of the value ranges on the channel that writes state slot `slot` in engine mode `mode`.
bool phAxisRange(uint mode, uint slot, out float2 r)
{
    r = float2(1e30, -1e30);
    bool found = false;
    uint4 mi = FE_MODE_INFO_AT(mode);
    for (uint p = 0u; p < mi.y; p++)
    {
        uint4 pi = FE_PART_INFO_AT(mi.x + p);
        for (uint e = 0u; e < pi.y; e++)
        {
            uint4 en = FE_ENTRY_AT(pi.x + e);
            bool hit = slot >= en.z && slot < en.z + 32u && ((en.w >> (slot - en.z)) & 1u) != 0u;
            if (hit)
            {
                uint4 ci = FE_CHAN_INFO_AT(en.y);
                for (uint i = 0u; i < ci.y; i++)
                {
                    uint rr = ci.x + i;
                    if ((FE_RANGE_AT(rr) >> 16) == FE_FN_VALUE)
                    {
                        float2 q = FE_RANGE_P_AT(rr);
                        r = float2(min(r.x, min(q.x, q.y)), max(r.y, max(q.x, q.y)));
                        found = true;
                    }
                }
            }
        }
    }
    return found;
}

// The type's pan and tilt ranges in mode `mode` (degrees as decoded), +-270 / +-135 where it has no such channel.
void phAimRanges(uint t, uint mode, out float2 panRange, out float2 tiltRange)
{
    uint2 pt = FE_PANTILT_AT(t);
    float2 r;
    panRange = float2(-270, 270);
    tiltRange = float2(-135, 135);
    if (pt.x != FE_SLOT_NONE && phAxisRange(mode, pt.x, r)) panRange = r;
    if (pt.y != FE_SLOT_NONE && phAxisRange(mode, pt.y, r)) tiltRange = r;
}

float phWrapInto(float a, float lo, float hi)
{
    for (uint i = 0u; i < 3u; i++) { a = a < lo ? a + 360.0 : a; a = a > hi ? a - 360.0 : a; }
    return a;
}

// Decoded (pan, tilt) in degrees that aim the beam along `dir` (stage), inside the given ranges; of the two solutions the
// one with the smaller tilt. False when neither fits.
bool phAimSolve(uint t, float3x3 R, float3 dir, float2 panRange, float2 tiltRange, out float2 panTilt)
{
    float2 sense = FE_PANTILT_DIR_AT(t);
    float3 d = normalize(mul(transpose(R), dir));
    float3 h = phAimHome(t);
    float rho = max(length(h.yz), 1e-6), phi = atan2(h.z, h.y);
    float a = acos(clamp(d.y / rho, -1.0, 1.0));
    panTilt = float2(0, 0);
    bool found = false;
    float best = 1e30;
    for (uint k = 0u; k < 2u; k++)
    {
        float T = k == 0u ? phi + a : phi - a;
        float3 w = float3(h.x, cos(T) * h.y + sin(T) * h.z, -sin(T) * h.y + cos(T) * h.z);
        float P = atan2(d.x, d.z) - atan2(w.x, w.z);
        float tilt = degrees(T) / (sense.y != 0.0 ? sense.y : 1.0);
        float pan = degrees(P) / (sense.x != 0.0 ? sense.x : 1.0);
        tilt = phWrapInto(tilt, tiltRange.x, tiltRange.y);
        pan = phWrapInto(pan, panRange.x, panRange.y);
        bool ok = tilt >= tiltRange.x - 0.01 && tilt <= tiltRange.y + 0.01 && pan >= panRange.x - 0.01 && pan <= panRange.y + 0.01;
        bool take = ok && abs(tilt) < best;
        panTilt = take ? float2(pan, tilt) : panTilt;
        best = take ? abs(tilt) : best;
        found = found || ok;
    }
    return found;
}

#endif
