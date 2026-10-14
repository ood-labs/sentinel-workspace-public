// SS_Renderer / vis_emit - what an emitter cell emits, read from a fixture's decoded state through the type's emitter bindings
// (the FixtureRender port's five binding rows per emitter), the way the fixture engine's FE_Renderer prep reads them:
//   row 0  colour slots r, g, b, w (a white emitter's level in x)    row 1  a second colour layer (highest takes precedence)
//   row 2  dimmers x * y * z (w: layer 2's dimmer)                   row 3  shutters x, y; strobe rate z
//   row 4  y: the colour temperature slot
// A slot with FE_SLOT_CELLED indexes by cell. The includer declares `StructuredBuffer<float2> State` and includes
// fe_tables.hlsli first.
#ifndef SS_VIS_EMIT_HLSLI
#define SS_VIS_EMIT_HLSLI

struct VisEmit
{
    float3 colour;     // linear, before the dimmer
    float dim;         // the dimmers' product
    float gate;        // shutter and strobe now: 0 closed, 1 open
    float kelvin;      // the emitter's colour temperature, 0 when it has none
};

uint visStride() { return min(feStateStride(), FE_STATE_CAP); }

float2 visSlot(uint k, uint s, uint cell)
{
    uint slot = (s & FE_SLOT_CELLED) != 0u ? (s & 0x7FFFu) + cell : s;
    return State[k * visStride() + slot];
}

float visBound(uint k, uint s, uint cell, float fallback)
{
    if (s == FE_SLOT_NONE) return fallback;
    float2 fp = visSlot(k, s, cell);
    return (uint)(fp.x + 0.5) == FE_FN_VALUE ? fp.y : fallback;
}

float visGate(float2 fp)
{
    uint fn = (uint)(fp.x + 0.5);
    if (fn == FE_FN_CLOSED) return 0.0;
    if (fn == FE_FN_STROBE || fn == FE_FN_PULSE || fn == FE_FN_RANDOM) return frac(_Time * max(fp.y, 0.05)) < 0.25 ? 1.0 : 0.0;
    return 1.0;
}

VisEmit visEmit(uint k, uint type, uint e, uint cell)
{
    VisEmit o;
    o.colour = 0.0; o.dim = 0.0; o.gate = 0.0; o.kelvin = 0.0;
    if (e >= feMaxEmitters()) return o;
    uint b = (type * feMaxEmitters() + e) * 5u;
    uint4 bA = FE_BIND_AT(b), bB = FE_BIND_AT(b + 1u), bD = FE_BIND_AT(b + 2u), bS = FE_BIND_AT(b + 3u), bX = FE_BIND_AT(b + 4u);
    uint colour = FE_EMITTER_AT(type * feMaxEmitters() + e).y;
    float4 a = float4(visBound(k, bA.x, cell, 0.0), visBound(k, bA.y, cell, 0.0), visBound(k, bA.z, cell, 0.0),
                      visBound(k, bA.w, cell, 0.0));
    bool white = colour == FE_COLOUR_W || colour == FE_COLOUR_CW;
    // A white emitter with no level channel of its own (a lamp, a tube) emits full white under its dimmer.
    float3 c = white ? (bA.x == FE_SLOT_NONE ? 1.0 : a.x).xxx : (colour == FE_COLOUR_RGBW ? a.rgb + a.w * 0.85 : a.rgb);
    if (bB.x != FE_SLOT_NONE)
    {
        float4 l2 = float4(visBound(k, bB.x, cell, 0.0), visBound(k, bB.y, cell, 0.0), visBound(k, bB.z, cell, 0.0),
                           visBound(k, bB.w, cell, 0.0));
        c = max(c, (white ? l2.xxx : l2.rgb) * visBound(k, bD.w, cell, 1.0));
    }
    o.colour = saturate(c);
    o.dim = saturate(visBound(k, bD.x, cell, 1.0) * visBound(k, bD.y, cell, 1.0) * visBound(k, bD.z, cell, 1.0));
    o.gate = 1.0;
    if (bS.x != FE_SLOT_NONE) o.gate *= visGate(visSlot(k, bS.x, cell));
    if (bS.y != FE_SLOT_NONE) o.gate *= visGate(visSlot(k, bS.y, cell));
    if (bX.y != FE_SLOT_NONE)
    {
        float2 kv = visSlot(k, bX.y, cell);
        o.kelvin = (uint)(kv.x + 0.5) == FE_FN_KELVIN ? kv.y : 0.0;
    }
    return o;
}

#endif
