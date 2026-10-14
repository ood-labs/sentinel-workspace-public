// Per instance: its pose (mount transform, pan/tilt from the decoded state, truss pipe segment). Per emitter
// cell: linear radiance from the state through the type's mapper binding: colour source A, HTP source B, additive
// colours beyond RGB and the whites (port types), dimmers, strobe/shutter gates and colour temperature. One thread per
// (instance, cell slot); cell 0 writes the pose, and slots past a fixture's own cells are left alone (no pass reads them).
// The tables are the Fixture Rig node's FixtureRender port.
#define GDTF_RENDER _Data2
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"

RWStructuredBuffer<float4> Frame : register(u0);

static uint gStride;

// The state row of an instance, at the tables' stride; without a State input every slot reads its default.
float2 stateAt(uint inst, uint type, uint slot)
{
    uint idx = inst * gStride + slot;
    if (idx < _Data1_Count)
        return _Data1[idx].v;
    return FE_DEFAULT_AT(FE_TYPE_SLOT0_AT(type) + slot);
}

uint fnOf(float2 fp) { return (uint)(fp.x + 0.5); }

// A bound value: celled slots index by cell. `fallback` stands in when unbound or not a value.
float boundValue(uint inst, uint type, uint s, uint cell, float fallback)
{
    if (s == FE_SLOT_NONE) return fallback;
    uint slot = (s & FE_SLOT_CELLED) != 0u ? (s & 0x7FFFu) + cell : s;
    float2 fp = stateAt(inst, type, slot);
    return fnOf(fp) == FE_FN_VALUE ? fp.y : fallback;
}

// Strobe/shutter function as a 0..1 gate at time t. duty is the flash length where the chart has one.
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
    return 1.0;   // open, none, value
}

// A strobe on its own channels: a rate channel (open / strobe Hz), a duration and a waveform select. A waveform channel
// at no effect reads none or Open (a GDTF StrobeEffect function's first set): both strobe plainly.
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
    uint inst = id.x / FE_CELLS_CAP;
    uint cellSlot = id.x % FE_CELLS_CAP;
    if (inst >= FE_N_MAX) return;
    uint flags = inst < _Data0_Count ? _Data0[inst].flags : 0u;
    gStride = min(feStateStride(), FE_STATE_CAP);
    // Placeholders (types the engine cannot draw: blocked or over a cap) get a pose with active -1, which
    // every pass but bodies skips; bodies draws them as an alarm-colour box.
    bool active = inst < _Data0_Count && (flags & FE_INST_ACTIVE) != 0u && (flags & FE_INST_PLACEHOLDER) == 0u
               && _Data0[inst].type < feTypeCount() && feTypeStatus(_Data0[inst].type) == 0u;
    bool placeholder = inst < _Data0_Count && (flags & FE_INST_ACTIVE) != 0u && !active;
    uint type = active ? _Data0[inst].type : 0u;
    uint me = feMaxEmitters();
    float phase = feHash11((float)inst * 0.61803);

    if (cellSlot == 0u)
    {
        FePose p = (FePose)0;
        if (active)
        {
            float3 pos = _Data0[inst].position;
            float3x3 R = feInstRot(_Data0[inst].rotation);
            float3 t = pos - mul(R, FE_MOUNT_AT(type).xyz);
            p.r0 = float4(R[0], t.x);
            p.r1 = float4(R[1], t.y);
            p.r2 = float4(R[2], t.z);
            uint2 pt = FE_PANTILT_AT(type);
            // Decoded angles times the sense of the type's pan and tilt axes (FE_PANTILT_DIR).
            float pan = pt.x != FE_SLOT_NONE ? stateAt(inst, type, pt.x).y * FE_PANTILT_DIR_AT(type).x : 0.0;
            float tilt = pt.y != FE_SLOT_NONE ? stateAt(inst, type, pt.y).y * FE_PANTILT_DIR_AT(type).y : 0.0;
            p.pt = float4(pan, tilt, 1.0, (float)type);
            // Truss pipe: from halfway to the previous fixture on the same row to halfway to the next.
            float3 body = FE_PART_G_AT(FE_TYPE_GEO_AT(type).x * 3u + 1u).xyz;
            float3 outward = FE_MOUNT_AT(type).xyz - body;
            outward = dot(outward, outward) > 1e-8 ? normalize(outward) : float3(0, 1, 0);
            float3 centre = pos + mul(R, outward) * 0.05;
            float3 left = centre - float3(0.3, 0, 0), right = centre + float3(0.3, 0, 0);
            if (inst > 0u && _Data0[inst - 1u].group == _Data0[inst].group && (_Data0[inst - 1u].flags & FE_INST_ACTIVE) != 0u
                && abs(_Data0[inst - 1u].position.z - pos.z) < 0.01 && abs(_Data0[inst - 1u].position.y - pos.y) < 0.01)
                left = float3(0.5 * (_Data0[inst - 1u].position.x + pos.x), centre.y, centre.z);
            if (inst + 1u < _Data0_Count && _Data0[inst + 1u].group == _Data0[inst].group && (_Data0[inst + 1u].flags & FE_INST_ACTIVE) != 0u
                && abs(_Data0[inst + 1u].position.z - pos.z) < 0.01 && abs(_Data0[inst + 1u].position.y - pos.y) < 0.01)
                right = float3(0.5 * (_Data0[inst + 1u].position.x + pos.x), centre.y, centre.z);
            p.pipeA = float4(left, 0.024);
            p.pipeB = float4(right, (_Data0[inst].flags & FE_INST_FLOOR) != 0u ? 0.0 : 1.0);   // no pipe under a floor fixture
        }
        else if (placeholder)
        {
            // The record's mount frame, the box centre standing on the deck for a floor fixture, else hanging below.
            float3 pos = _Data0[inst].position;
            float3x3 R = feInstRot(_Data0[inst].rotation);
            float3 t = pos + float3(0.0, (flags & FE_INST_FLOOR) != 0u ? FE_PLACEHOLDER_M * 0.5 : -FE_PLACEHOLDER_M * 0.5, 0.0);
            p.r0 = float4(R[0], t.x);
            p.r1 = float4(R[1], t.y);
            p.r2 = float4(R[2], t.z);
            p.pt = float4(0.0, 0.0, -1.0, 0.0);
        }
        uint b = inst * FE_FRAME_STRIDE;
        Frame[b] = p.r0; Frame[b + 1u] = p.r1; Frame[b + 2u] = p.r2;
        Frame[b + 3u] = p.pt; Frame[b + 4u] = p.pipeA; Frame[b + 5u] = p.pipeB;
    }

    if (!active || cellSlot >= feTypeCells(type)) return;

    // Which emitter this cell belongs to.
    float3 rad = 0.0;
    {
        uint e = 0xFFu, cell = 0u;
        for (uint i = 0u; i < me; i++)
        {
            uint4 em = FE_EMITTER_AT(type * me + i);
            uint first = FE_CELL_BASE_AT(type * me + i);
            if (em.x != 0u && cellSlot >= first && cellSlot < first + em.w && e == 0xFFu)
            {
                e = i;
                cell = cellSlot - first;
            }
        }
        if (e != 0xFFu)
        {
            uint k = (type * me + e) * 5u;
            uint4 bA = FE_BIND_AT(k), bB = FE_BIND_AT(k + 1u), bD = FE_BIND_AT(k + 2u), bS = FE_BIND_AT(k + 3u), bX = FE_BIND_AT(k + 4u);
            uint colour = FE_EMITTER_AT(type * me + e).y;
            float4 a = float4(boundValue(inst, type, bA.x, cell, 0.0), boundValue(inst, type, bA.y, cell, 0.0),
                              boundValue(inst, type, bA.z, cell, 0.0), boundValue(inst, type, bA.w, cell, 0.0));
            float3 c;
            if (colour == FE_COLOUR_RGBW) c = a.rgb + a.w * float3(0.85, 0.85, 0.82);
            else if (colour == FE_COLOUR_W || colour == FE_COLOUR_CW) c = a.x * float3(0.92, 0.96, 1.0);
            else c = a.rgb;    // rgb, and cmy_white (the RGB channels are the flags' transmission of a white source)
            // Amber, lime and the other additive colours, each at its emitter's colour (the FixtureRender port only).
            [unroll] for (uint m = 0u; m < FE_MIX_PER_EMITTER; m++)
            {
                uint4 mx = feEmitterMix(type * me + e, m);
                if (mx.x != FE_SLOT_NONE) c += boundValue(inst, type, mx.x, cell, 0.0) * asfloat(mx.yzw);
            }
            if (bB.x != FE_SLOT_NONE)
            {
                float4 b = float4(boundValue(inst, type, bB.x, cell, 0.0), boundValue(inst, type, bB.y, cell, 0.0),
                                  boundValue(inst, type, bB.z, cell, 0.0), boundValue(inst, type, bB.w, cell, 0.0));
                float3 cb = (colour == FE_COLOUR_W || colour == FE_COLOUR_CW) ? b.x * float3(0.92, 0.96, 1.0) : b.rgb;
                c = max(c, cb * boundValue(inst, type, bD.w, cell, 1.0));   // HTP
            }
            float dim = boundValue(inst, type, bD.x, cell, 1.0) * boundValue(inst, type, bD.y, cell, 1.0)
                      * boundValue(inst, type, bD.z, cell, 1.0);
            float gate = 1.0;
            if (bS.x != FE_SLOT_NONE) gate *= gateOf(stateAt(inst, type, bS.x), _Time, phase, 0.2);
            if (bS.y != FE_SLOT_NONE) gate *= gateOf(stateAt(inst, type, bS.y), _Time, phase, 0.2);
            if (bS.z != FE_SLOT_NONE)
                gate *= rateGate(stateAt(inst, type, bS.z), boundValue(inst, type, bS.w, cell, 0.5),
                                 bX.x != FE_SLOT_NONE ? stateAt(inst, type, bX.x) : float2(0, 0), _Time, phase);
            if (bX.y != FE_SLOT_NONE)
            {
                float2 k2 = stateAt(inst, type, bX.y);
                if (fnOf(k2) == FE_FN_KELVIN)
                    c *= feKelvinTint(k2.y, colour == FE_COLOUR_CMY_WHITE ? 7500.0 : 6500.0);
            }
            if (colour == FE_COLOUR_CMY_WHITE) c *= float3(0.95, 0.97, 1.0);
            rad = c * dim * gate;
        }
    }
    Frame[inst * FE_FRAME_STRIDE + FE_FRAME_EMIT + cellSlot] = float4(rad, 0.0);
}
