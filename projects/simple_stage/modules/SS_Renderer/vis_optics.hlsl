// SS_Renderer / vis_optics - what every optic emits, in Lighting's Optics layout (SS_MOVERS movers x 25 records, then SS_STROBES
// strobes as SsStrobe), read from each fixture's decoded DMX through its GDTF rather than from Lighting:
//   Halo Beam      the beam emitter's dimmer, colour, zoom and frost, and each halo cell's colour under the halo
//                  dimmer; a closed shutter darkens, a strobe function flashes at its rate
//   Linear Strobe  the tube's dimmer and colour temperature (back to Lighting's tube tint), the plates' dimmer and
//                  colour; a strobe slot takes PHAGE's own strobe (FixtureID) or, for slot 47, the rig's next one
//   a guest        (after them, from VIS_GSOURCE0) one source per guest the renderer draws from its GDTF: its first
//                  beam emitter, else wash, else strobe, from that emitter's face along its posed normal, with the mean
//                  output of its cells; padding.x 3 marks a narrow source (a beam, or a wash of 22 degrees or less),
//                  4 a wide one, as FE_Renderer's sources pass splits them
// Levels arrive as the desk sent them; optic_beam_gain and optic_halo_gain put back the render gain Lighting applies
// (8 x 2^boost and 0.2 x 2^boost at boost 3).
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"
#include "../_shared/ss_fixture.hlsli"
#include "vis_common.hlsli"

StructuredBuffer<SsMoverPose> Poses : register(t0);
StructuredBuffer<SsRigInst> Inst : register(t1);
StructuredBuffer<VisFrame> Frames : register(t2);
StructuredBuffer<float2> State : register(t3);
StructuredBuffer<float4> GFrame : register(t6);
StructuredBuffer<uint> List : register(t7);
RWStructuredBuffer<SsOptical> Optics : register(u0);

static uint gStride;
#include "vis_emit.hlsli"

// Decoded value of a scalar attribute `kind` (zoom, frost) of rig fixture k, or `fallback` when the mode has none.
float scalarOf(uint k, uint type, uint kind, float fallback)
{
    uint4 row;
    if (!visAttr(type, kind, VIS_ANY_EMITTER, row)) return fallback;
    float2 fp = State[k * gStride + row.x];
    return (uint)(fp.x + 0.5) == FE_FN_VALUE ? fp.y : fallback;
}

SsOptical opticalOfStrobe(SsStrobe s)
{
    SsOptical o;
    o.position = s.position; o.fixture_id = s.fixture_id; o.normal = s.fwd; o.local_id = s.tube; o.colour = s.up;
    o.intensity = s.plate; o.beam_tangent = s.tube_colour.x; o.field_tangent = s.tube_colour.y; o.reach = s.tube_colour.z;
    o.active = s.length; o.frost = s.plate_colour.x; o.padding = float3(s.plate_colour.yz, s.active);
    return o;
}

// Guest g's source (see the header); inactive when it has no light-casting emitter.
SsOptical guestSource(uint g)
{
    SsOptical o = (SsOptical)0;
    FePose pose;
    FE_LOAD_POSE(GFrame, g, pose);
    if (g >= List[0] || pose.pt.z < 0.5) return o;
    uint type = (uint)(pose.pt.w + 0.5), me = feMaxEmitters();
    uint beam = 0xFFu, wash = 0xFFu, strobe = 0xFFu;
    for (uint i = 0u; i < me; i++)
    {
        uint kind = FE_EMITTER_AT(type * me + i).x;
        beam = (kind == FE_EMITTER_BEAM && beam == 0xFFu) ? i : beam;
        wash = (kind == FE_EMITTER_WASH && wash == 0xFFu) ? i : wash;
        strobe = (kind == FE_EMITTER_STROBE && strobe == 0xFFu) ? i : strobe;
    }
    uint e = beam != 0xFFu ? beam : (wash != 0xFFu ? wash : strobe);
    if (e == 0xFFu) return o;
    uint ei = type * me + e;
    uint4 em = FE_EMITTER_AT(ei);
    float4 opt = FE_EMITTER_OPT_AT(ei);
    uint first = FE_CELL_BASE_AT(ei), cells = max(em.w, 1u);
    float3 sum = 0.0;
    for (uint c = 0u; c < cells; c++) sum += GFrame[g * VIS_GFRAME_STRIDE + FE_FRAME_EMIT + first + c].rgb;
    float3 mean = sum / (float)cells;
    float level = max(mean.r, max(mean.g, mean.b));
    uint face = (uint)(FE_DRAW_AT(ei * 3u + 1u).w + 0.5);
    float4 fc = FE_FACE_G_AT(face * 4u);
    float3 nrm = FE_FACE_G_AT(face * 4u + 1u).xyz;
    uint space = (uint)(fc.w + 0.5);
    float3 n = normalize(feRotate(pose, fePoseVector(space, nrm, pose.pt.x, pose.pt.y)));
    float3 cd = feCellDir(type, first);
    if (dot(cd, cd) > 0.25) n = normalize(feRotate(pose, fePoseVector(space, normalize(cd), pose.pt.x, pose.pt.y)));
    bool narrow = em.x == FE_EMITTER_BEAM || (em.x == FE_EMITTER_WASH && opt.x <= 22.0);
    o.position = feToWorld(pose, fePosePoint(type, space, fc.xyz, pose.pt.x, pose.pt.y)) + n * 0.02;
    o.normal = n;
    o.fixture_id = (float)List[1u + g];
    o.local_id = (float)e;
    o.colour = mean / max(level, 1e-4);
    o.intensity = level * (narrow ? optic_beam_gain : optic_beam_gain / 16.0);
    o.beam_tangent = tan(radians(0.5 * clamp(opt.x, 0.5, 170.0)));
    o.field_tangent = tan(radians(0.5 * clamp(max(opt.y, opt.x), 0.5, 170.0)));
    o.reach = narrow ? reach : 34.0;
    o.active = 1.0;
    o.padding = float3(narrow ? 3.0 : 4.0, level, 0.0);
    return o;
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= VIS_GSOURCE0 && i < VIS_GSOURCE0 + VIS_GUESTS)
    {
        SsOptical o = (SsOptical)0;
        if (frTablesValid()) o = guestSource(i - VIS_GSOURCE0);
        Optics[i] = o;
        return;
    }
    if (i >= SS_OPT_COUNT) return;
    gStride = min(feStateStride(), FE_STATE_CAP);
    bool tables = frTablesValid();
    if (i < SS_OPT_STROBE0)
    {
        uint parent = i / SS_OPT_PER, kk = i % SS_OPT_PER;
        SsMoverPose r = Poses[parent];
        SsOptical o = (SsOptical)0;
        if (tables && r.active > 0.5)
        {
            uint k = (uint)(r.fixture_id + 0.5), type = Inst[k].type;
            uint beamE = visEmitter(type, 1u), haloE = visEmitter(type, 2u);
            bool ring = kk > 0u;
            uint e = ring ? haloE : beamE, cell = ring ? kk - 1u : 0u;
            VisEmit em = visEmit(k, type, e, cell);
            float level = em.dim;
            float zoom = clamp(scalarOf(k, type, FE_KIND_ZOOM, 3.0), 0.5, 60.0);
            o.colour = em.colour;
            o.intensity = level * em.gate * (ring ? optic_halo_gain : optic_beam_gain);
            float a = (float)cell * 6.2831853 / 24.0;
            float3 local = ring ? float3(sin(a) * 0.086, cos(a) * 0.086, -0.074) : float3(0, 0, -0.07);
            o.position = ssHeadPoint(r, local);
            o.normal = ssHeadNormal(r, float3(0, 0, -1));
            o.fixture_id = (float)parent;
            o.local_id = (float)cell;
            o.active = 1.0;
            o.beam_tangent = tan(radians(ring ? 55.0 : zoom * 0.5));
            o.field_tangent = tan(radians(ring ? 80.0 : zoom * 0.75));
            o.reach = reach;
            o.frost = ring ? 0.0 : saturate(scalarOf(k, type, FE_KIND_FROST, 0.0));
            o.padding = float3(ring ? 1.0 : 0.0, level, 0.0);
        }
        Optics[i] = o;
        return;
    }
    uint s = i - SS_OPT_STROBE0;
    SsStrobe st = (SsStrobe)0;
    if (tables && s < SS_RIG_STROBE_SLOTS)
    {
        uint own = 0xFFFFFFFFu;
        for (uint k = 0u; k < SS_RIG_MAX; k++)
        {
            SsRigInst d = Inst[k];
            own = (ssRigActive(d) && d.role == ROLE_STROBE && d.index == SS_RIG_STROBE_SLOT0 + s && own == 0xFFFFFFFFu) ? k : own;
        }
        if (own != 0xFFFFFFFFu && Frames[own].o.w > 0.5)
        {
            uint type = Inst[own].type;
            VisFrame f = Frames[own];
            uint tubeE = visEmitterColour(type, FE_COLOUR_W), plateE = visEmitterColour(type, FE_COLOUR_RGB);
            VisEmit tube = visEmit(own, type, tubeE, 0u), plate = visEmit(own, type, plateE, 0u);
            float kelvin = tube.kelvin > 0.0 ? tube.kelvin : 6500.0;
            st.fwd = -f.z.xyz;
            st.up = f.x.xyz;
            st.position = f.o.xyz + st.fwd * 0.135;      // the housing's back is the GDTF origin, the face is the mount
            st.fixture_id = (float)(SS_RIG_STROBE_SLOT0 + s);
            st.tube = tube.dim * tube.gate;
            st.tube_colour = lerp(float3(1.0, 0.55, 0.22), float3(1.0, 0.96, 0.9), saturate((kelvin - 2200.0) / 4300.0));
            st.plate = plate.dim * plate.gate;
            st.plate_colour = plate.colour;
            st.length = SS_STROBE_LENGTH;
            st.active = 1.0;
        }
    }
    Optics[i] = opticalOfStrobe(st);
}
