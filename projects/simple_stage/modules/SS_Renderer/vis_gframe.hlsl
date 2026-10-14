// SS_Renderer / vis_gframe - each listed guest's pose and light in the fixture engine's frame layout (fe_render.hlsli), for
// the renderer's generic body, face and source passes: per guest 6 rows (profile frame -> stage as rows of R with t in
// w; pan and tilt in degrees times the type's axis sense, active, type; no truss pipe), then the radiance of every
// emission cell from its decoded state, read through the type's emitter bindings as FE_Renderer's prep reads them.
// The profile frame reaches the stage through the guest's live frame (frames.hlsl): its GDTF axes and origin.
// One thread per (guest slot, cell slot); cell slot 0 writes the pose.
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"
#include "vis_common.hlsli"

StructuredBuffer<SsRigInst> Inst : register(t0);
StructuredBuffer<VisFrame> Frames : register(t1);
StructuredBuffer<float2> State : register(t2);
StructuredBuffer<uint> List : register(t3);
RWStructuredBuffer<float4> GFrame : register(u0);

static uint gStride;

float2 stateAt(uint k, uint slot) { return State[k * gStride + slot]; }

uint fnOf(float2 fp) { return (uint)(fp.x + 0.5); }

float boundValue(uint k, uint s, uint cell, float fallback)
{
    if (s == FE_SLOT_NONE) return fallback;
    uint slot = (s & FE_SLOT_CELLED) != 0u ? (s & 0x7FFFu) + cell : s;
    float2 fp = stateAt(k, slot);
    return fnOf(fp) == FE_FN_VALUE ? fp.y : fallback;
}

// FE_Renderer prep's shutter and strobe gates.
float gateOf(float2 fp, float t, float phase, float duty)
{
    uint fn = fnOf(fp);
    float hz = max(fp.y, 0.05);
    float x = frac(t * hz + phase);
    float period = floor(t * hz + phase);
    if (fn == FE_FN_CLOSED) return 0.0;
    if (fn == FE_FN_STROBE) return x < duty ? 1.0 : 0.0;
    if (fn == FE_FN_PULSE) return pow(sin(3.14159265 * x), 4.0);
    if (fn == FE_FN_RANDOM) return (feHash11(period + phase * 17.0) > 0.45 && x < duty) ? 1.0 : 0.0;
    if (fn == FE_FN_RAMP_UP) return x;
    if (fn == FE_FN_RAMP_DOWN) return 1.0 - x;
    if (fn == FE_FN_RAMP_UPDOWN) return 1.0 - abs(2.0 * x - 1.0);
    if (fn == FE_FN_LIGHTNING) return feHash11(floor(t * 24.0) + phase * 31.0) > 0.86 ? 1.0 : 0.0;
    if (fn == FE_FN_SPIKES) return feHash11(floor(t * 18.0) + phase * 13.0) > 0.9 ? 1.0 : 0.15;
    return 1.0;
}

float rateGate(float2 rate, float duration, float2 wave, float t, float phase)
{
    if (fnOf(rate) != FE_FN_STROBE) return 1.0;
    float hz = max(rate.y, 0.05);
    uint w = fnOf(wave);
    float duty = lerp(0.04, 0.9, saturate(duration));
    if (w == FE_FN_NONE || w == FE_FN_OPEN) return gateOf(rate, t, phase, duty);
    return gateOf(float2((float)w, hz), t, phase, duty);
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint g = id.x / FE_CELLS_CAP, cellSlot = id.x % FE_CELLS_CAP;
    if (g >= VIS_GUESTS) return;
    gStride = min(feStateStride(), FE_STATE_CAP);
    uint k = g < List[0] ? List[1u + g] : 0xFFFFFFFFu;
    bool active = k < SS_RIG_MAX && frTablesValid() && Frames[k].o.w > 0.5;
    uint type = active ? Inst[k].type : 0u;
    uint b = g * VIS_GFRAME_STRIDE;
    if (cellSlot == 0u)
    {
        float4 r0 = 0.0, r1 = 0.0, r2 = 0.0, pt = 0.0;
        if (active)
        {
            VisFrame f = Frames[k];
            // Profile vector -> GDTF coordinates (rows gx, gy, gz) -> stage (the frame's axes as columns).
            float3x3 toGdtf = float3x3(frGdtfAxis(type, 0u), frGdtfAxis(type, 1u), frGdtfAxis(type, 2u));
            float3x3 toStage = transpose(float3x3(f.x.xyz, f.y.xyz, f.z.xyz));
            float3x3 R = mul(toStage, toGdtf);
            float3 t = f.o.xyz - mul(R, FE_MOUNT_AT(type).xyz);
            r0 = float4(R[0], t.x);
            r1 = float4(R[1], t.y);
            r2 = float4(R[2], t.z);
            uint2 ps = FE_PANTILT_AT(type);
            float pan = ps.x != FE_SLOT_NONE ? stateAt(k, ps.x).y * FE_PANTILT_DIR_AT(type).x : 0.0;
            float tilt = ps.y != FE_SLOT_NONE ? stateAt(k, ps.y).y * FE_PANTILT_DIR_AT(type).y : 0.0;
            pt = float4(pan, tilt, 1.0, (float)type);
        }
        GFrame[b] = r0; GFrame[b + 1u] = r1; GFrame[b + 2u] = r2;
        GFrame[b + 3u] = pt; GFrame[b + 4u] = 0.0; GFrame[b + 5u] = 0.0;
    }
    float3 rad = 0.0;
    if (active && cellSlot < feTypeCells(type))
    {
        uint me = feMaxEmitters();
        uint e = 0xFFu, cell = 0u;
        for (uint i = 0u; i < me; i++)
        {
            uint4 em = FE_EMITTER_AT(type * me + i);
            uint first = FE_CELL_BASE_AT(type * me + i);
            bool hit = em.x != 0u && cellSlot >= first && cellSlot < first + em.w && e == 0xFFu;
            e = hit ? i : e;
            cell = hit ? cellSlot - first : cell;
        }
        if (e != 0xFFu)
        {
            float phase = feHash11((float)k * 0.61803);
            uint q = (type * me + e) * 5u;
            uint4 bA = FE_BIND_AT(q), bB = FE_BIND_AT(q + 1u), bD = FE_BIND_AT(q + 2u), bS = FE_BIND_AT(q + 3u), bX = FE_BIND_AT(q + 4u);
            uint colour = FE_EMITTER_AT(type * me + e).y;
            float4 a = float4(boundValue(k, bA.x, cell, 0.0), boundValue(k, bA.y, cell, 0.0),
                              boundValue(k, bA.z, cell, 0.0), boundValue(k, bA.w, cell, 0.0));
            float3 c;
            if (colour == FE_COLOUR_RGBW) c = a.rgb + a.w * float3(0.85, 0.85, 0.82);
            else if (colour == FE_COLOUR_W || colour == FE_COLOUR_CW) c = a.x * float3(0.92, 0.96, 1.0);
            else c = a.rgb;
            [unroll] for (uint m = 0u; m < FE_MIX_PER_EMITTER; m++)
            {
                uint4 mx = feEmitterMix(type * me + e, m);
                if (mx.x != FE_SLOT_NONE) c += boundValue(k, mx.x, cell, 0.0) * asfloat(mx.yzw);
            }
            if (bB.x != FE_SLOT_NONE)
            {
                float4 l2 = float4(boundValue(k, bB.x, cell, 0.0), boundValue(k, bB.y, cell, 0.0),
                                   boundValue(k, bB.z, cell, 0.0), boundValue(k, bB.w, cell, 0.0));
                float3 cb = (colour == FE_COLOUR_W || colour == FE_COLOUR_CW) ? l2.x * float3(0.92, 0.96, 1.0) : l2.rgb;
                c = max(c, cb * boundValue(k, bD.w, cell, 1.0));
            }
            float dim = boundValue(k, bD.x, cell, 1.0) * boundValue(k, bD.y, cell, 1.0) * boundValue(k, bD.z, cell, 1.0);
            float gate = 1.0;
            if (bS.x != FE_SLOT_NONE) gate *= gateOf(stateAt(k, bS.x), _Time, phase, 0.2);
            if (bS.y != FE_SLOT_NONE) gate *= gateOf(stateAt(k, bS.y), _Time, phase, 0.2);
            if (bS.z != FE_SLOT_NONE)
                gate *= rateGate(stateAt(k, bS.z), boundValue(k, bS.w, cell, 0.5),
                                 bX.x != FE_SLOT_NONE ? stateAt(k, bX.x) : float2(0, 0), _Time, phase);
            if (bX.y != FE_SLOT_NONE)
            {
                float2 k2 = stateAt(k, bX.y);
                if (fnOf(k2) == FE_FN_KELVIN) c *= feKelvinTint(k2.y, colour == FE_COLOUR_CMY_WHITE ? 7500.0 : 6500.0);
            }
            if (colour == FE_COLOUR_CMY_WHITE) c *= float3(0.95, 0.97, 1.0);
            rad = c * dim * gate;
        }
    }
    GFrame[b + FE_FRAME_EMIT + cellSlot] = float4(rad, 0.0);
}
