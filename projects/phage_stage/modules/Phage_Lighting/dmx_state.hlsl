// Phage_Lighting / dmx_state - PHAGE's live output as each fixture's canonical state, the fixture engine's contract: one thread
// per (fixture, state slot), each slot a (function, value) pair the encoder turns into that channel's DMX through the
// type's own GDTF ranges. Which attribute a slot holds (dimmer, red, pan, a cell's blue, ...) comes from the
// FixtureRender tables, so a mode change in the Fixture Rig needs no code here.
//
//   Halo Beam      pan and tilt from the motors (phGdtfPan/phGdtfTilt), beam and halo levels as the desk sets them
//                  (Lighting's optics padding.y, no render gain) with their palette colours, zoom from the beam angle
//   Linear Strobe  tube and plate levels, the tube's warmth as colour temperature, the plates' colour
//   Pixel Batten   each pixel sampled from the LED texture where it sits along its run, less the show's pixel-bar
//                  peak (Show State row 1 z), the render gain pixels.hlsl multiplies in
// Which slot or run a fixture plays comes from the show's fixture table (inst.hlsl), so a fixture added to the rig plays
// the free slot it took. A head of another type than the plot's (not native) is aimed through its own GDTF
// (_shared/phage_aim.hlsli: the pan and tilt that throw its beam where the slot's beam goes, inside its ranges), its
// main beam or wash takes the slot's beam and any other emitter its halo; a strobe slot played by another type mixes
// the tube's white and the plates' colour on its own emitters.
// A slot no PHAGE output drives stays untouched and sends its channel's GDTF default.
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/phage_fixture.hlsli"
#include "dmx_common.hlsli"
#include "../_shared/phage_aim.hlsli"

StructuredBuffer<PhMoverPose> PoseIn : register(t2);
StructuredBuffer<PhOptical> OpticsIn : register(t3);
StructuredBuffer<PhRigFix> RigFix : register(t7);
StructuredBuffer<DmxInst> Inst : register(t0);
RWStructuredBuffer<float2> State : register(u0);

#define UNTOUCHED float2(-1.0, 0.0)

float2 value(float v) { return float2(FE_FN_VALUE, v); }

// The tube's colour temperature from its tint: Lighting draws a neutral tube (1, .96, .9) and the blinder look's warm
// hit (1, .55, .22); blue over red spans them.
float tubeKelvin(float3 tc)
{
    float ratio = tc.b / max(tc.r, 1e-3);
    return lerp(2200.0, 6500.0, saturate((ratio - 0.22) / (0.90 - 0.22)));
}

// Pixel Batten pixel k of run b, whose unit starts `startM` along the run: the LED texture where that pixel sits.
float3 battenPixel(uint b, float startM, float k)
{
    float total = 0.0;
    [unroll] for (uint j = 0u; j < BAR_PIECES; j++)
    {
        uint q = b * BAR_PIECES + j;
        total += (q < _Data4_Count && _Data4[q].w.z > 0.5) ? _Data4[q].w.x : 0.0;
    }
    // The run's length to the millimetre: Kinetics recomputes it from moving endpoints every frame, and its last-bit
    // jitter would flip a pixel sitting on a texel boundary between neighbours (a flicker the loopback caught).
    total = round(total * 1000.0) / 1000.0;
    uint tw, th;
    _Tex5.GetDimensions(tw, th);
    float u = (startM + (k + 0.5) * 0.05) / max(total, 1e-3);
    float peak = _Data1_Count >= 2u ? max(_Data1[1].value.z, 1e-3) : 1.0;
    return saturate(_Tex5.SampleLevel(PointSampler, float2(saturate(u), (b + 0.5) / max(th, 1u)), 0).rgb / peak);
}

// State slot `slot` of type t as the emitter bindings see it (FixtureRender's five rows per emitter, read the way the
// fixture engine's renderer reads them): the emitter whose colour, second colour layer or dimmers name the slot, the
// cell it addresses there, and whether that emitter has a dimmer of its own. The attribute row cannot say: a scalar
// dimmer's row names no emitter (255), and only the bindings tell the halo's dimmer from the beam's, or the plates'
// from the tube's. Emitter 255 when no emitter uses the slot (a master, or an attribute no binding reads).
struct SlotBind { uint emitter; uint cell; bool dimmed; };

bool bindHit(uint s, uint slot, uint cells, inout uint cell)
{
    bool celled = (s & FE_SLOT_CELLED) != 0u;
    uint base = s & 0x7FFFu;
    bool hit = s != FE_SLOT_NONE && (celled ? slot >= base && slot < base + cells : slot == base);
    cell = (hit && celled) ? slot - base : cell;
    return hit;
}

SlotBind slotBind(uint t, uint slot)
{
    SlotBind o;
    o.emitter = 255u; o.cell = 0u; o.dimmed = false;
    uint maxE = feMaxEmitters();
    for (uint e = 0u; e < maxE; e++)
    {
        uint4 em = FE_EMITTER_AT(t * maxE + e);
        uint cells = max((em.z >> 8) & 255u, 1u) * max((em.z >> 16) & 255u, 1u);
        uint b = (t * maxE + e) * 5u;
        uint4 bA = FE_BIND_AT(b), bB = FE_BIND_AT(b + 1u), bD = FE_BIND_AT(b + 2u);
        uint c = 0u;
        bool hit = false;
        hit = bindHit(bA.x, slot, cells, c) || hit;
        hit = bindHit(bA.y, slot, cells, c) || hit;
        hit = bindHit(bA.z, slot, cells, c) || hit;
        hit = bindHit(bA.w, slot, cells, c) || hit;
        hit = bindHit(bB.x, slot, cells, c) || hit;
        hit = bindHit(bB.y, slot, cells, c) || hit;
        hit = bindHit(bB.z, slot, cells, c) || hit;
        hit = bindHit(bB.w, slot, cells, c) || hit;
        hit = bindHit(bD.x, slot, cells, c) || hit;
        hit = bindHit(bD.y, slot, cells, c) || hit;
        hit = bindHit(bD.z, slot, cells, c) || hit;
        hit = bindHit(bD.w, slot, cells, c) || hit;
        bool take = em.x != 0u && hit && o.emitter == 255u;
        o.cell = take ? c : o.cell;
        o.dimmed = take ? (bD.x != FE_SLOT_NONE || bD.y != FE_SLOT_NONE || bD.z != FE_SLOT_NONE) : o.dimmed;
        o.emitter = take ? e : o.emitter;
    }
    return o;
}

bool multiCell(uint t, uint e)
{
    uint4 em = FE_EMITTER_AT(t * feMaxEmitters() + e);
    return max((em.z >> 8) & 255u, 1u) * max((em.z >> 16) & 255u, 1u) > 1u;
}

// The emitter that is a type's beam: its first beam emitter, else its first wash (phage_aim.hlsli's choice).
uint mainEmitter(uint t)
{
    uint me = feMaxEmitters(), beam = 0xFFu, wash = 0xFFu;
    for (uint e = 0u; e < me; e++)
    {
        uint kind = FE_EMITTER_AT(t * me + e).x;
        beam = (kind == FE_EMITTER_BEAM && beam == 0xFFu) ? e : beam;
        wash = (kind == FE_EMITTER_WASH && wash == 0xFFu) ? e : wash;
    }
    return beam != 0xFFu ? beam : wash;
}

float2 moverSlot(DmxInst d, uint inst, uint kind, uint slot)
{
    uint i = d.index;
    if (i >= 128u || i * PH_OPT_PER + PH_OPT_PER > 3248u) return UNTOUCHED;
    uint beam = i * PH_OPT_PER;
    if ((kind == FE_KIND_PAN || kind == FE_KIND_TILT) && DMX_NATIVE(d))
        return value(kind == FE_KIND_PAN ? phGdtfPan(PoseIn[i].pan) : phGdtfTilt(PoseIn[i].tilt));
    if (kind == FE_KIND_PAN || kind == FE_KIND_TILT)
    {
        float3x3 R = phAimFrame(d.type, RigFix[inst].x.xyz, RigFix[inst].y.xyz, RigFix[inst].z.xyz);
        float2 pr, tr, pt;
        phAimRanges(d.type, d.mode, pr, tr);
        phAimSolve(d.type, R, normalize(OpticsIn[beam].normal), pr, tr, pt);
        return value(kind == FE_KIND_PAN ? pt.x : pt.y);
    }
    if (kind == FE_KIND_ZOOM) return value(degrees(2.0 * atan(OpticsIn[beam].beam_tangent)));
    if (kind == FE_KIND_FROST) return value(saturate(OpticsIn[beam].frost));
    if (kind == FE_KIND_SHUTTER) return float2(FE_FN_OPEN, 0.0);
    // The halo is the emitter with many cells; a dimmer no emitter binds is a master and stays full. A colour on an
    // emitter with no dimmer of its own (the Pixel mode's halo cells) carries the level in it.
    SlotBind sb = slotBind(d.type, slot);
    bool bound = sb.emitter < feMaxEmitters();
    bool halo = bound && (DMX_NATIVE(d) ? multiCell(d.type, sb.emitter) : sb.emitter != mainEmitter(d.type));
    uint rec = halo ? beam + 1u + min(sb.cell, 23u) : beam;
    float level = saturate(OpticsIn[rec].padding.y);
    if (kind == FE_KIND_DIMMER) return value(bound ? level : 1.0);
    float3 c = saturate(OpticsIn[rec].colour) * (bound && !sb.dimmed ? level : 1.0);
    if (kind == FE_KIND_RED) return value(c.r);
    if (kind == FE_KIND_GREEN) return value(c.g);
    if (kind == FE_KIND_BLUE) return value(c.b);
    return UNTOUCHED;
}

float2 strobeSlot(DmxInst d, uint kind, uint slot)
{
    uint r = PH_OPT_STROBE0 + (d.index - PH_STROBE_SLOT0);
    if (r >= 3248u) return UNTOUCHED;
    // A strobe record rides the Optics layout (phage_fixture.hlsli's phStrobeOf).
    float tube = OpticsIn[r].local_id, plate = OpticsIn[r].intensity;
    float3 tubeCol = float3(OpticsIn[r].beam_tangent, OpticsIn[r].field_tangent, OpticsIn[r].reach);
    float3 plateCol = float3(OpticsIn[r].frost, OpticsIn[r].padding.x, OpticsIn[r].padding.y);
    if (OpticsIn[r].padding.z < 0.5) { tube = 0.0; plate = 0.0; }
    if (kind == FE_KIND_SHUTTER) return float2(FE_FN_OPEN, 0.0);
    if (kind == FE_KIND_CCT) return float2(FE_FN_KELVIN, tubeKelvin(tubeCol));
    SlotBind sb = slotBind(d.type, slot);
    bool bound = sb.emitter < feMaxEmitters();
    if (!DMX_NATIVE(d))
    {
        // Another type on a strobe slot: its dimmers carry the brighter of tube and plates, its colour the plates'
        // with the tube's white on a white channel (or folded into the colour where it has none).
        uint cs = bound ? FE_EMITTER_AT(d.type * feMaxEmitters() + sb.emitter).y : 0u;
        bool hasWhite = cs == FE_COLOUR_RGBW;
        float lvl = saturate(max(tube, plate));
        float inv = 1.0 / max(lvl, 1e-4);
        float3 rgb = saturate((saturate(plate) * saturate(plateCol) + (hasWhite ? 0.0 : saturate(tube) * saturate(tubeCol))) * inv);
        float w = saturate(tube * inv);
        float fold = bound && !sb.dimmed ? lvl : 1.0;
        if (kind == FE_KIND_DIMMER) return value(bound ? lvl : 1.0);
        if (kind == FE_KIND_RED) return value(rgb.r * fold);
        if (kind == FE_KIND_GREEN) return value(rgb.g * fold);
        if (kind == FE_KIND_BLUE) return value(rgb.b * fold);
        if (kind == FE_KIND_WHITE || kind == FE_KIND_COOL_WHITE) return value((cs == FE_COLOUR_W || cs == FE_COLOUR_CW ? 1.0 : w) * fold);
        if (kind == FE_KIND_CYAN) return value(1.0 - rgb.r);
        if (kind == FE_KIND_MAGENTA) return value(1.0 - rgb.g);
        if (kind == FE_KIND_YELLOW) return value(1.0 - rgb.b);
        return UNTOUCHED;
    }
    bool plates = bound && FE_EMITTER_AT(d.type * feMaxEmitters() + sb.emitter).y == FE_COLOUR_RGB;
    if (kind == FE_KIND_DIMMER) return value(!bound ? 1.0 : saturate(plates ? plate : tube));
    float3 c = saturate(plateCol) * (bound && !sb.dimmed ? saturate(plate) : 1.0);
    if (kind == FE_KIND_RED) return value(c.r);
    if (kind == FE_KIND_GREEN) return value(c.g);
    if (kind == FE_KIND_BLUE) return value(c.b);
    return UNTOUCHED;
}

float2 battenSlot(DmxInst d, uint kind, uint cell, uint cells)
{
    if (kind == FE_KIND_DIMMER) return value(1.0);
    // A pixel takes its own place on the run; a whole-bar colour (Bar mode) takes the unit's middle.
    float k = cells > 1u ? (float)cell : 9.5;
    float3 c = battenPixel(d.index, (float)d.custom / 1000.0, k);
    if (kind == FE_KIND_RED) return value(c.r);
    if (kind == FE_KIND_GREEN) return value(c.g);
    if (kind == FE_KIND_BLUE) return value(c.b);
    return UNTOUCHED;
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint slot = id.x, inst = id.y;
    if (inst >= INST_MAX || !frTablesValid()) return;
    uint stride = min(feStateStride(), FE_STATE_CAP);
    if (slot >= stride) return;
    DmxInst d = Inst[inst];
    float2 outv = UNTOUCHED;
    if (dmxActive(d))
    {
        uint4 ti = FE_TYPE_INFO_AT(d.type);
        uint4 at = uint4(0u, 0u, 0u, 255u);
        bool found = false;
        for (uint a = 0u; a < FE_TYPE_ATTRN_AT(d.type); a++)
        {
            uint4 x = FE_ATTR_AT(ti.w + a);
            bool hit = !found && slot >= x.x && slot < x.x + x.y;
            at = hit ? x : at;
            found = found || hit;
        }
        if (found && slot < ti.z)
        {
            uint kind = at.z, cell = slot - at.x;
            if (d.role == ROLE_MOVER) outv = moverSlot(d, inst, kind, slot);
            else if (d.role == ROLE_STROBE) outv = strobeSlot(d, kind, slot);
            else if (d.role == ROLE_BATTEN) outv = battenSlot(d, kind, cell, at.y);
        }
    }
    State[inst * stride + slot] = outv;
}
