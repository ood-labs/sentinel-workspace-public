// FE_Rig's records: the Fixture Rig node's Fixtures records (data slot 0), each with its rig type as the engine type
// and the FixtureRender port (data slot 1, GDTF_RENDER) for the tables, so any GDTF the rig holds draws with no
// per-type code. Include after fe_tables.hlsli and fe_rig.hlsli, in a pass that binds data:0 and data:1.
//
// A Fixtures record is the GDTF mount frame in the stage frame (right-handed metres, +Y up, +Z toward the audience,
// the same frame as the engine's world): axis_x, axis_y and axis_z are the stage images of GDTF X, Y and Z, and
// origin is the GDTF origin. A type's profile frame mounts at the GDTF origin, so the record's origin is the engine
// position and its rotation is the axes composed with the type's GDTF axes on the port.
#ifndef FE_RIG_RECORDS_HLSLI
#define FE_RIG_RECORDS_HLSLI

#define FE_RIG_HELD 0u        // status: Fixtures records with FixtureRender tables
#define FE_RIG_NONE 1u        // status: no Fixtures records, or no FixtureRender tables: an empty rig

#define FE_FLOOR_M 0.3        // a fixture whose origin is below this stands on the deck

bool feFixtureActive(uint i)
{
    return i < _Data0_Count && _Data0[i].origin.w > 0.5;
}

// (yaw, pitch, roll) in degrees with R = Ry(yaw) Rx(pitch) Rz(roll), as feInstRot composes them.
float3 feEulerYXZ(float3x3 R)
{
    float s = clamp(-R[1][2], -1.0, 1.0);
    float pitch = asin(s);
    float yaw, roll;
    if (sqrt(max(1.0 - s * s, 0.0)) > 1e-4)
    {
        yaw = atan2(R[0][2], R[2][2]);
        roll = atan2(R[1][0], R[1][1]);
    }
    else
    {
        pitch = s > 0.0 ? 1.5707963 : -1.5707963;
        yaw = atan2(-R[2][0], R[0][0]);
        roll = 0.0;
    }
    return degrees(float3(yaw, pitch, roll));
}

// How far below the mount the type's lowest body point sits at this rotation (metres), from its body parts.
float feLowestBodyPoint(uint type, float3 rotation)
{
    float3x3 Ri = feInstRot(rotation);
    float3 mount = FE_MOUNT_AT(type).xyz;
    float low = 1e9;
    uint4 g = FE_TYPE_GEO_AT(type);
    for (uint p = 0u; p < g.y; p++)
    {
        float4 a = FE_PART_G_AT((g.x + p) * 3u);
        float3 c = FE_PART_G_AT((g.x + p) * 3u + 1u).xyz;
        float4 sz = FE_PART_G_AT((g.x + p) * 3u + 2u);
        float3 ext = (a.x == 2.0)
            ? (sz.w == 0.0 ? float3(sz.y * 0.5, sz.x, sz.x) : (sz.w == 1.0 ? float3(sz.x, sz.y * 0.5, sz.x) : float3(sz.x, sz.x, sz.y * 0.5)))
            : sz.xyz * 0.5;
        for (uint k = 0u; k < 8u; k++)
        {
            float3 corner = c + ext * float3((k & 1u) ? 1.0 : -1.0, (k & 2u) ? 1.0 : -1.0, (k & 4u) ? 1.0 : -1.0);
            low = min(low, mul(Ri, corner - mount).y);
        }
    }
    return g.y > 0u ? low : 0.0;
}

// On the deck: rest the lowest body point at the MVR height (Depence writes floor fixtures with the origin on the deck
// whatever the type's origin is).
void feRestOnDeck(inout FeInst r)
{
    if (r.position.y >= FE_FLOOR_M) return;
    r.position.y -= feLowestBodyPoint(r.type, r.rotation);
    r.flags |= FE_INST_FLOOR;
}

// DMX: engine part p is GDTF break p + 1. Fixtures universes are 1-based as MVR counts; the engine's are 0-based.
void feBreaksFromFixtures(uint i, uint parts, inout FeInst r)
{
    uint4 b01 = uint4(_Data0[i].dmx01[0], _Data0[i].dmx01[1], _Data0[i].dmx01[2], _Data0[i].dmx01[3]);
    uint4 b23 = uint4(_Data0[i].dmx23[0], _Data0[i].dmx23[1], _Data0[i].dmx23[2], _Data0[i].dmx23[3]);
    uint2 bk[4] = { b01.xy, b01.zw, b23.xy, b23.zw };
    uint2 base[4] = { uint2(0u, 0u), uint2(0u, 0u), uint2(0u, 0u), uint2(0u, 0u) };
    for (uint q = 0u; q < min(parts, 4u); q++)
        base[q] = (bk[q].x > 0u && bk[q].y > 0u) ? uint2(bk[q].x - 1u, bk[q].y) : uint2(0u, 0u);
    r.u0 = base[0].x; r.a0 = base[0].y;
    r.u1 = base[1].x; r.a1 = base[1].y;
    r.u2 = base[2].x; r.a2 = base[2].y;
    r.u3 = base[3].x; r.a3 = base[3].y;
}

// Profile frame -> stage of Fixtures record i, given the profile-frame directions of GDTF X, Y and Z.
float3 feMountRotation(uint i, float3 gx, float3 gy, float3 gz)
{
    float3x3 toGdtf = float3x3(gx, gy, gz);
    float3x3 toStage = transpose(float3x3(_Data0[i].axis_x.xyz, _Data0[i].axis_y.xyz, _Data0[i].axis_z.xyz));
    return feEulerYXZ(mul(toStage, toGdtf));
}

// The plot group of a type from its FixtureRender role (movers, strobes, then washes and bars).
uint feRigGroup(uint type)
{
    uint role = frTypeRole(type);
    return role == FR_ROLE_MOVER ? 0u : (role == FR_ROLE_STROBE ? 1u : 2u);
}

// x: active Fixtures records the engine can hold, y: those with no rig type or no engine mode for their GDTF mode,
// z: records past FE_N_MAX, w: records whose type the engine cannot draw (drawn as placeholders).
uint4 feRigCensus()
{
    uint4 c = 0u;
    if (!frTablesValid()) return c;
    [loop] for (uint i = 0u; i < _Data0_Count; i++)
    {
        if (!feFixtureActive(i)) continue;
        if (i >= FE_N_MAX) { c.z++; continue; }
        c.x++;
        uint t = _Data0[i].ids[0];
        if (t >= frTypeCount()) { c.y++; continue; }
        if (frTypeStatus(t) != FR_STATUS_RENDERABLE) { c.w++; continue; }
        if (frEngineMode(t, _Data0[i].ids[1]) == 0xFFFFFFFFu) c.y++;
    }
    return c;
}

// The rig record of Fixtures record i: the rig type, its engine mode, the mount pose through the type's FixtureRender
// frame, and up to four breaks. A type the engine cannot draw (an embedded stub, a blocked or over-cap type) stays
// active as a placeholder; a record with no rig type or engine mode is inactive.
FeInst feRigRecord(uint i)
{
    FeInst r = (FeInst)0;
    if (!feFixtureActive(i) || !frTablesValid()) return r;
    uint t = _Data0[i].ids[0];
    if (t >= frTypeCount()) return r;
    bool renderable = frTypeStatus(t) == FR_STATUS_RENDERABLE;
    uint m = frEngineMode(t, _Data0[i].ids[1]);
    if (renderable && m == 0xFFFFFFFFu) return r;
    r.type = t;
    r.mode = renderable ? m : 0xFFFFFFFFu;
    r.group = feRigGroup(t);
    r.rotation = feMountRotation(i, frGdtfAxis(t, 0u), frGdtfAxis(t, 1u), frGdtfAxis(t, 2u));
    r.position = _Data0[i].origin.xyz;
    r.flags = FE_INST_ACTIVE | (renderable ? 0u : FE_INST_PLACEHOLDER);
    if (renderable) feRestOnDeck(r);
    else if (r.position.y < FE_FLOOR_M) r.flags |= FE_INST_FLOOR;
    feBreaksFromFixtures(i, renderable ? frModeInfo(m).y : FE_PARTS_CAP, r);
    return r;
}

#endif
