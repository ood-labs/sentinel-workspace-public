// Fixture-engine rig records and transforms. Include after fe_tables.hlsli. fePosePoint and feWorldPoint read the
// type tables, so they exist only in passes that bind the FixtureRender port (GDTF_RENDER).
//
// WORLD FRAME (every FE module): right-handed metres. +X to the audience's right, +Y up, +Z toward the
// audience; the stage floor is y = 0 and the stage lies at z <= 0. Renderers convert to Sentinel's
// left-handed view space with feView() at the very end.
//
// A fixture's own frame is its type's profile frame on the FixtureRender port (right-handed metres, home pose).
#ifndef FE_RIG_HLSLI
#define FE_RIG_HLSLI

#define FE_N_MAX 1024
#define FE_INST_ACTIVE 1u
#define FE_INST_FLOOR 2u      // stands on the deck: no truss pipe
#define FE_INST_PLACEHOLDER 8u // a type the engine cannot draw, shown as an alarm-colour placeholder (bit 4 is unused)
#define FE_PLACEHOLDER_M 0.3   // the placeholder body's edge in FE_Renderer (metres)

// One record per fixture instance, 80 bytes. Matches the FE_Rig "Rig" data schema field for field.
struct FeInst
{
    float3 position;  uint type;      // world position of the type's mount point; type: rig type (FixtureRender)
    float3 rotation;  uint mode;      // degrees: yaw about Y, pitch about X, roll about Z; R = Ry * Rx * Rz; engine mode
    uint u0; uint a0; uint u1; uint a1; // DMX part bases: universe (0-based), address 1..512 (0 = not patched)
    uint u2; uint a2; uint group; uint flags;
    uint u3; uint a3; uint r0; uint r1; // fourth part (types with four breaks), reserved
};

float3x3 feRotX(float a) { float c = cos(a), s = sin(a); return float3x3(1, 0, 0, 0, c, -s, 0, s, c); }
float3x3 feRotY(float a) { float c = cos(a), s = sin(a); return float3x3(c, 0, s, 0, 1, 0, -s, 0, c); }
float3x3 feRotZ(float a) { float c = cos(a), s = sin(a); return float3x3(c, -s, 0, s, c, 0, 0, 0, 1); }
float3x3 feInstRot(float3 yprDeg)
{
    float3 r = radians(yprDeg);
    return mul(feRotY(r.x), mul(feRotX(r.y), feRotZ(r.z)));
}

uint2 fePartBase(FeInst r, uint part)
{
    return part == 0 ? uint2(r.u0, r.a0) : (part == 1 ? uint2(r.u1, r.a1) : (part == 2 ? uint2(r.u2, r.a2) : uint2(r.u3, r.a3)));
}

#ifdef GDTF_RENDER
// Pan/tilt pose of a fixture's moving parts: pan degrees about the pan pivot's +Y (counter-clockwise
// seen from above), tilt degrees about the tilt pivot's +X, negative toward the fixture's front. The renderer's
// prep pass has already multiplied the decoded angles by the type's axis sense (FE_PANTILT_DIR).
// space: 0 base, 1 yoke (pan), 2 head (pan + tilt). Point in the fixture frame at home -> posed.
// On the FixtureRender port "pan" is the outer axis and "tilt" the inner one: a tilting head with panning mirrors
// puts its tilt first (FE_PANTILT, the pivots and the part spaces follow). An inner pivot with w 2 marks one axis per
// cell (the mirrors): each cell turns in place.
float3 fePosePoint(uint type, uint space, float3 p, float panDeg, float tiltDeg)
{
    if (space >= 2u)
    {
        float4 tp = FE_PIVOT_AT(type * 2u + 1u);
        if (tp.w < 1.5) p = tp.xyz + mul(feRotX(radians(-tiltDeg)), p - tp.xyz);
    }
    if (space >= 1u)
    {
        float3 pp = FE_PIVOT_AT(type * 2u).xyz;
        p = pp + mul(feRotY(radians(panDeg)), p - pp);
    }
    return p;
}
#endif

float3 fePoseVector(uint space, float3 v, float panDeg, float tiltDeg)
{
    if (space >= 2u) v = mul(feRotX(radians(-tiltDeg)), v);
    if (space >= 1u) v = mul(feRotY(radians(panDeg)), v);
    return v;
}

#ifdef GDTF_RENDER
// Fixture frame -> world.
float3 feWorldPoint(FeInst r, float3 p)
{
    return r.position + mul(feInstRot(r.rotation), p - FE_MOUNT_AT(r.type).xyz);
}
#endif

float3 feWorldVector(FeInst r, float3 v)
{
    return mul(feInstRot(r.rotation), v);
}

// Right-handed world -> Sentinel's left-handed view space (DirectX). Apply to points and vectors.
float3 feView(float3 w) { return float3(w.x, w.y, -w.z); }

#endif
