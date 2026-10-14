// Shared by the rig probe's passes: the ports, the DMX universe table, the Sentinel fixture includes (copies of
// Sentinel's resources/module-includes/fixtures, since Module includes resolve against this folder) and the
// views' geometry.
#include "dmx_schema_v2.hlsli"
#include "gdtf_attributes.hlsli"

#define GDTF_FIXTURES _Data0
#define GDTF_TYPES _Data1
#include "gdtf_rig.hlsli"

#define RP_FIXTURES 4096u
#define RP_ENTRIES 192u        // plan entries (geometry nodes drawn) per mode, and item slots per fixture
#define RP_MODES 1024u         // modes the plan holds
#define RP_CELLS 128u          // cells per fixture with their own colour
#define RP_PLAN_STRIDE 193u    // plan records per mode: a header, then the entries
#define RP_SKIP_OWN 1u         // plan entry flag: a template root, posed by its reference
#define RP_PLAN_FORMAT 1u      // stamped into the plan; raise it after editing plan.hlsl (buffers outlive hot reloads)
#define RP_PAD 1.5             // metres of margin around the rig
#define RP_MARGIN 28.0         // pixels of margin inside each view
#define RP_CANVAS_W 1280u
#define RP_CANVAS_H 720u

StructuredBuffer<uint> Table : register(t3);   // index pass: port address -> DMX record index + 1

// Fixture Rig universes count from 1 as MVR does; the DMX port's addresses are Art-Net port addresses (universe - 1).
uint GDTF_READ_BYTE(uint universe, uint address)
{
    uint port = universe - 1u;
    uint r = port < DMX_MAX_UNIVERSES ? Table[port] : 0u;
    return r > 0u ? (_Data2[DMX_UNIVERSE_RECORD_BASE + r - 1u].channels[address - 1u] & 255u) : 0u;
}

#include "gdtf_decode.hlsli"

struct StateRecord
{
    float4 s0;   // intensity (dimmer level x open), dimmer level, pan, tilt
    float4 s1;   // fixture-level colour mix (linear), open
    float4 s2;   // cells, global mode index, 0, 1 when decodable
};

// The draw plan, rebuilt when the FixtureTypes generation or RP_PLAN_FORMAT changes. Record 0: (generation, modes,
// format stamped, format the plan pass last wrote).
// Mode m: record 1 + m * RP_PLAN_STRIDE is (entries, root geometry, 1 when entries were dropped, 0), then one
// record per entry, parents before children: r0 = (geometry, parent entry or none, cell or none, flags),
// r1 = (Pan or Tilt channel turning this geometry or none, 0 Pan / 1 Tilt, 0, 0).
struct PlanRecord
{
    uint4 r0, r1;
};

uint rpPlanHeader(uint mode) { return 1u + mode * RP_PLAN_STRIDE; }

// One item per (fixture, plan entry): a = (origin, geometry index), b = rotation quaternion,
// c = (beam colour, beam intensity), zero for a geometry that is not a Beam.
struct Item
{
    float4 a, b, c;
};

float3 rpRotate(float4 q, float3 v) { return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v); }
float3 rpRotateInv(float4 q, float3 v) { return rpRotate(float4(-q.xyz, q.w), v); }

// Rotation quaternion of the orthonormal basis whose columns are x, y and z.
float4 rpQuat(float3 x, float3 y, float3 z)
{
    float tr = x.x + y.y + z.z;
    float4 q;
    if (tr > 0.0)
    {
        float s = sqrt(tr + 1.0) * 2.0;
        q = float4((y.z - z.y) / s, (z.x - x.z) / s, (x.y - y.x) / s, 0.25 * s);
    }
    else if (x.x > y.y && x.x > z.z)
    {
        float s = sqrt(1.0 + x.x - y.y - z.z) * 2.0;
        q = float4(0.25 * s, (y.x + x.y) / s, (z.x + x.z) / s, (y.z - z.y) / s);
    }
    else if (y.y > z.z)
    {
        float s = sqrt(1.0 + y.y - x.x - z.z) * 2.0;
        q = float4((y.x + x.y) / s, 0.25 * s, (z.y + y.z) / s, (z.x - x.z) / s);
    }
    else
    {
        float s = sqrt(1.0 + z.z - x.x - y.y) * 2.0;
        q = float4((z.x + x.z) / s, (z.y + y.z) / s, 0.25 * s, (x.y - y.x) / s);
    }
    return normalize(q);
}

// The two views share one scale: plan on the left (stage x across, downstage at the bottom), front on the right
// (stage x across, up is up, seen from the audience). Bounds[0] = (min x, min y, min z, fixtures), Bounds[1] = max.
struct RigView
{
    float2 centre[2];
    float2 mid[2];
    float scale;
    float topY, frontZ;          // ray starts above the rig and in front of it
    float2 depthTop, depthFront; // (offset, span) normalizing depth to 0..1
    float panelW;
};

RigView rpView(float4 lo, float4 hi, uint w, uint h)
{
    RigView v;
    if (lo.w < 0.5) { lo = float4(-5.0, 0.0, -3.0, 0.0); hi = float4(5.0, 5.0, 3.0, 0.0); }
    float minY = min(lo.y, 0.0) - RP_PAD, maxY = hi.y + RP_PAD;
    float spanX = hi.x - lo.x + 2.0 * RP_PAD, spanZ = hi.z - lo.z + 2.0 * RP_PAD, spanY = maxY - minY;
    v.panelW = (float)w * 0.5;
    v.scale = min((v.panelW - 2.0 * RP_MARGIN) / spanX, ((float)h - 2.0 * RP_MARGIN) / max(spanZ, spanY));
    v.centre[0] = float2(v.panelW * 0.5, (float)h * 0.5);
    v.centre[1] = float2(v.panelW * 1.5, (float)h * 0.5);
    v.mid[0] = float2((lo.x + hi.x) * 0.5, (lo.z + hi.z) * 0.5);
    v.mid[1] = float2((lo.x + hi.x) * 0.5, (minY + maxY) * 0.5);
    v.topY = maxY + 10.0;
    v.frontZ = hi.z + RP_PAD + 10.0;
    v.depthTop = float2(minY, spanY);
    v.depthFront = float2(lo.z - RP_PAD, spanZ);
    return v;
}

float2 rpProject(RigView v, uint panel, float3 p)
{
    float2 q = panel == 0u ? float2(p.x - v.mid[0].x, p.z - v.mid[0].y) : float2(p.x - v.mid[1].x, -(p.y - v.mid[1].y));
    return v.centre[panel] + q * v.scale;
}

// The orthographic viewing ray through a pixel centre, and the depth (0 far, 1 near) of a world point.
void rpRay(RigView v, uint panel, float2 px, out float3 o, out float3 d)
{
    float2 q = (px - v.centre[panel]) / v.scale;
    if (panel == 0u) { o = float3(q.x + v.mid[0].x, v.topY, q.y + v.mid[0].y); d = float3(0.0, -1.0, 0.0); }
    else             { o = float3(q.x + v.mid[1].x, -q.y + v.mid[1].y, v.frontZ); d = float3(0.0, 0.0, -1.0); }
}

float rpDepth(RigView v, uint panel, float3 p)
{
    return panel == 0u ? saturate((p.y - v.depthTop.x) / v.depthTop.y) : saturate((p.z - v.depthFront.x) / v.depthFront.y);
}
