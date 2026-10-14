// The programmer: one thread per (fixture, state slot) builds the canonical state the console will send, from the
// look, the fixture's console role and each attribute's kind, so any type works: the tables come from the Fixture Rig
// node's FixtureRender port.
// RGB intent goes through each type's colour model: RGBW splits off its white, single-colour emitters take white,
// and a CMY fixture takes RGB transmission (its flags are set inside the fixture). Pixel attributes get the look's
// pattern across their emitter's cells. White goes where the colour model puts it: a colour emitter with its own white
// splits the white out of the RGB intent; a white-only beam emitter takes the beams level; any other white-only
// emitter, or one whose cells only have a dimmer, carries the white of the look, unless no wash, beam or strobe emitter
// of the type carries colour (a halo, a white bar, a blinder): then it takes the role level, so the look lights the
// fixture. On the FixtureRender port, attributes no look drives stay untouched (FE_STATE_UNTOUCHED) and the encoder
// sends their channel's GDTF default DMX value.
// Placeholders (types the engine cannot draw) are skipped.
#define GDTF_RENDER _Data1
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"

RWStructuredBuffer<float2> State : register(u0);

#define FE_STATE_UNTOUCHED float2(-1.0, 0.0)

float3 hsvRgb(float h, float s, float v)
{
    float3 k = saturate(abs(frac(h + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0);
    float3 c = v * lerp(1.0.xxx, k, s);
    return c * c;    // perceptual hue ramp -> linear-ish levels
}

// Cell position in its emitter: x across 0..1, y down 0..1 (ring: x = angle 0..1).
float2 cellPos(uint type, uint emitter, uint cell)
{
    uint4 em = FE_EMITTER_AT(type * feMaxEmitters() + emitter);
    uint cols = max((em.z >> 8) & 255u, 1u), rows = max((em.z >> 16) & 255u, 1u);
    return float2(((float)(cell % cols) + 0.5) / (float)cols, ((float)(cell / cols) + 0.5) / (float)rows);
}

// The look's level for a pixel at cell position cp on a fixture at world x.
float pattern(float2 cp, float wx, float t)
{
    if (look == 0) return 1.0;                                                    // Static
    if (look == 1) return 0.5 + 0.5 * sin(6.2831853 * (cp.x * 0.6 + wx * 0.07 - t * 0.35) + cp.y * 1.7);   // Wave
    if (look == 2) { float p = frac(t * 0.6 + wx * 0.05); return pow(saturate(1.0 - abs(cp.x - p) * 6.0), 2.0); } // Chase
    return frac(t * 2.0 + cp.x * 0.25) < 0.5 ? 1.0 : 0.1;                          // Pulse
}

// The intensity of a console role: 0 wash, 1 mover, 2 strobe, 3 bar or pixel.
float roleLevel(uint role)
{
    return role == 1u ? mover_level : (role == 2u ? strobe_level : (role == 3u ? bar_level : wash_level));
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint slot = id.x, inst = id.y;    // dispatch [16, FE_N_MAX]: x covers the state cap
    if (inst >= FE_N_MAX) return;
    uint stride = min(feStateStride(), FE_STATE_CAP);
    if (slot >= stride) return;
    float2 outv = float2(0.0, 0.0);
    bool active = inst < _Data0_Count && (_Data0[inst].flags & FE_INST_ACTIVE) != 0u
               && (_Data0[inst].flags & FE_INST_PLACEHOLDER) == 0u && _Data0[inst].type < feTypeCount();
    if (active)
    {
        uint type = _Data0[inst].type;
        uint4 ti = FE_TYPE_INFO_AT(type);
        if (slot < ti.z)
        {
            uint4 at = uint4(0, 1, 0, 255);
            bool scalarWhite = false;
            uint whiteMask = 0u, colourMask = 0u;   // emitters with celled white, with celled red, green or blue
            uint firstDimmer = 0xFFFFFFFFu;
            for (uint a = 0u; a < FE_TYPE_ATTRN_AT(type); a++)
            {
                uint4 x = FE_ATTR_AT(ti.w + a);
                at = (slot >= x.x && slot < x.x + x.y) ? x : at;
                bool celledX = x.y > 1u && x.w < 32u;
                scalarWhite = scalarWhite || (x.z == FE_KIND_WHITE && x.y == 1u);
                whiteMask |= (celledX && x.z == FE_KIND_WHITE) ? (1u << x.w) : 0u;
                colourMask |= (celledX && (x.z == FE_KIND_RED || x.z == FE_KIND_GREEN || x.z == FE_KIND_BLUE)) ? (1u << x.w) : 0u;
                firstDimmer = (x.z == FE_KIND_DIMMER && firstDimmer == 0xFFFFFFFFu) ? x.x : firstDimmer;
            }
            // The master dimmer: the outermost scalar dimmer bound to the type's first emitter, else its first dimmer.
            uint masterSlot = firstDimmer;
            for (uint e = 0u; e < feMaxEmitters(); e++)
            {
                if (FE_EMITTER_AT(type * feMaxEmitters() + e).x == 0u) continue;
                uint d = FE_BIND_AT((type * feMaxEmitters() + e) * 5u + 2u).x;
                masterSlot = (d != FE_SLOT_NONE && (d & FE_SLOT_CELLED) == 0u) ? d : firstDimmer;
                break;
            }
            // A type whose light-casting emitters (wash, beam, strobe) carry no colour is lit by intensity alone (a
            // tungsten-look halo, a white bar, a blinder): its dimmer-only cells and its whites take the role level.
            // A type with colour on one of them keeps its whites for the look's white content.
            bool mainColour = false;
            for (uint ce = 0u; ce < feMaxEmitters(); ce++)
            {
                uint4 cem = FE_EMITTER_AT(type * feMaxEmitters() + ce);
                bool casts = cem.x == FE_EMITTER_WASH || cem.x == FE_EMITTER_BEAM || cem.x == FE_EMITTER_STROBE;
                bool coloured = cem.y == FE_COLOUR_RGB || cem.y == FE_COLOUR_RGBW || cem.y == FE_COLOUR_CMY_WHITE;
                uint bk = (type * feMaxEmitters() + ce) * 5u;
                mainColour = mainColour || (casts && coloured
                                            && (FE_BIND_AT(bk).x != FE_SLOT_NONE || FE_BIND_AT(bk + 1u).x != FE_SLOT_NONE));
            }
            float level = roleLevel(feTypeRole(type));
            uint kind = at.z, cell = slot - at.x;
            bool celled = at.y > 1u;
            bool emitterColour = celled && at.w < 32u && ((colourMask >> at.w) & 1u) != 0u;
            bool emitterWhite = celled && at.w < 32u && ((whiteMask >> at.w) & 1u) != 0u;
            bool beamEmitter = celled && at.w < 32u && FE_EMITTER_AT(type * feMaxEmitters() + at.w).x == FE_EMITTER_BEAM;
            // Untouched attributes: the GDTF channel default goes out (the console loads what the GDTF says).
            outv = FE_STATE_UNTOUCHED;

            float3 wp = _Data0[inst].position;
            float t = _Time * speed;
            float h = hue + spread * wp.x / 14.0 + (look == 1 ? 0.03 * t : 0.0);
            float3 rgb = hsvRgb(h, saturation, 1.0);
            float lvl = celled ? pattern(cellPos(type, at.w, cell), wp.x, t) : 1.0;
            // RGB loses its white to a white channel of the same emitter (or, for scalars, of the fixture); a white-only
            // emitter's white channel takes the look's white content.
            bool split = celled ? (emitterWhite || !emitterColour) : scalarWhite;
            float w = split ? min(rgb.r, min(rgb.g, rgb.b)) : 0.0;
            float3 c = (rgb - w) * lvl;

            float whiteLevel = mainColour ? (w + white) * lvl : master * level * lvl;
            if (kind == FE_KIND_DIMMER && celled && !emitterColour && !emitterWhite)
                outv = float2(FE_FN_VALUE, beamEmitter ? beams * pattern(cellPos(type, at.w, cell), wp.x, t + 0.5)
                                                       : whiteLevel);   // a cell whose only control is its dimmer
            else if (kind == FE_KIND_DIMMER) outv = float2(FE_FN_VALUE, slot == masterSlot ? master * level : 1.0);
            else if (kind == FE_KIND_RED) outv = float2(FE_FN_VALUE, c.r);
            else if (kind == FE_KIND_GREEN) outv = float2(FE_FN_VALUE, c.g);
            else if (kind == FE_KIND_BLUE) outv = float2(FE_FN_VALUE, c.b);
            else if (kind == FE_KIND_CYAN) outv = float2(FE_FN_VALUE, 1.0 - c.r);
            else if (kind == FE_KIND_MAGENTA) outv = float2(FE_FN_VALUE, 1.0 - c.g);
            else if (kind == FE_KIND_YELLOW) outv = float2(FE_FN_VALUE, 1.0 - c.b);
            else if (kind == FE_KIND_WHITE && beamEmitter && !emitterColour)
                outv = float2(FE_FN_VALUE, beams * pattern(cellPos(type, at.w, cell), wp.x, t + 0.5));
            else if (kind == FE_KIND_WHITE) outv = float2(FE_FN_VALUE, emitterColour ? (w + white) * lvl : whiteLevel);
            else if (kind == FE_KIND_COOL_WHITE)
                outv = float2(FE_FN_VALUE, beams * (celled ? pattern(cellPos(type, at.w, cell), wp.x, t + 0.5) : 1.0));
            else if (kind == FE_KIND_PAN)
                outv = float2(FE_FN_VALUE, pan + movement * 40.0 * sin(0.55 * t + (float)inst * 0.45));
            else if (kind == FE_KIND_TILT)
                outv = float2(FE_FN_VALUE, tilt + movement * 22.0 * sin(0.8 * t + (float)inst * 0.7));
            else if (kind == FE_KIND_SHUTTER || kind == FE_KIND_STROBE_RATE)
                outv = strobe > 0.05 ? float2(FE_FN_STROBE, strobe) : float2(FE_FN_OPEN, 0.0);
            else if (kind == FE_KIND_STROBE_DURATION) outv = float2(FE_FN_VALUE, 0.3);
            else if (kind == FE_KIND_FROST) outv = float2(FE_FN_VALUE, 0.0);
        }
    }
    State[inst * stride + slot] = outv;
}
