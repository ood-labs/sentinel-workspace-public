// Decodes a fixture's DMX through the FixtureTypes tables: channel words, active functions, physical values,
// relations, mode-master gates, colour mixing and per-cell colour. src/fixtures/FixtureDecode.cpp is its CPU twin,
// function for function, and the unit tests check that twin against the GDTF oracle.
//
// Include gdtf_attributes.hlsli and gdtf_rig.hlsli first, and define the DMX read before including:
//   uint GDTF_READ_BYTE(uint universe, uint address)   // universe as the Fixtures record stores it (MVR's
//                                                      // 1-based numbering), address 1 to 512
//
// Rules: a channel's word is its slots most significant first; a channel whose break is unpatched takes its default.
// The active function is the first whose DMX span holds the word and whose mode-master gate passes. Physical values
// interpolate linearly over the span. When the master is a DMX channel, a Multiply relation scales the follower by
// the master's word as a fraction of full and an Override relation replaces the follower's physical value with the
// master's while the master is not at zero. A virtual channel (no DMX offset) is a console-side control whose effect
// is already in the DMX a console sends: it never scales or overrides a decoded value and attribute lookups skip it;
// as a mode master it gates at its default. An attribute lookup takes the first DMX channel of the requested cell
// (GDTF_NONE for fixture-level channels) that carries the attribute.
//
// A cell is a GeometryReference instance or a Beam geometry that carries channels (pixels, zones, backlight
// lines), numbered in the order of their first DMX slot. Covered: Dimmer, Pan, Tilt, Zoom, ColorAdd_*, ColorRGB_*,
// ColorSub_*, CTO, CTC, the Color(n) wheel, Shutter(n) with its strobe functions, and per-cell colour. Any other
// attribute decodes to its function, set and physical value through gdtfAttribute.
#ifndef SENTINEL_GDTF_DECODE
#define SENTINEL_GDTF_DECODE

#define GDTF_ATTR_COLOR1 (GDTF_ATTR_COLOR_N | (1u << 16))

struct GdtfValue
{
    uint channel;
    uint function;
    uint set;
    uint word;
    float physical;
    bool found;    // a channel carries the attribute
    bool active;   // its active function is that attribute
};

struct GdtfFixtureState
{
    float dimmer;           // level 0..1 (gdtfLevel), relations applied; 1 without a dimmer channel
    float pan, tilt;        // degrees, GDTF sense (right-hand about the axis geometry's Z and X)
    float zoom;             // degrees, 0 without a zoom channel
    float3 rgb;             // linear sRGB of the fixture-level colour mix, not including the dimmer
    float cto, ctc;         // kelvin, 0 when absent or inactive
    uint color1Slot;        // 1-based colour wheel slot, 0 for none
    uint shutterAttribute;  // attribute id of the shutter channel's active function, 0 without one
    float shutterPhysical;
    float strobeHz;         // when a strobe function is active
    bool open;              // no shutter channel, an open shutter function, or a strobe
};

GdtfValue gdtfValueNone()
{
    GdtfValue v;
    v.channel = GDTF_NONE; v.function = GDTF_NONE; v.set = GDTF_NONE; v.word = 0u;
    v.physical = 0.0; v.found = false; v.active = false;
    return v;
}

float3 gdtfNormalized(float3 c) { return c / max(max(c.x, max(c.y, c.z)), 1e-6); }
float3 gdtfOneHot(uint i) { return float3(i == 0u ? 1.0 : 0.0, i == 1u ? 1.0 : 0.0, i == 2u ? 1.0 : 0.0); }

// Linear sRGB of a blackbody at `kelvin`, largest component 1 (Planckian locus, Kim et al. 2002).
float3 gdtfKelvinToLinear(float kelvin)
{
    float t = clamp(kelvin, 1667.0, 25000.0);
    float t2 = t * t, t3 = t2 * t;
    float x = t <= 4000.0 ? -0.2661239e9 / t3 - 0.2343589e6 / t2 + 0.8776956e3 / t + 0.179910
                          : -3.0258469e9 / t3 + 2.1070379e6 / t2 + 0.2226347e3 / t + 0.240390;
    float x2 = x * x, x3 = x2 * x;
    float y = t <= 2222.0 ? -1.1063814 * x3 - 1.34811020 * x2 + 2.18555832 * x - 0.20219683
            : (t <= 4000.0 ? -0.9549476 * x3 - 1.37418593 * x2 + 2.09137015 * x - 0.16748867
                           : 3.0817580 * x3 - 5.87338670 * x2 + 3.75112997 * x - 0.37001483);
    float3 XYZ = float3(x / y, 1.0, (1.0 - x - y) / y);
    float3 lin = float3(dot(float3(3.2404542, -1.5371385, -0.4985314), XYZ),
                        dot(float3(-0.9692660, 1.8760108, 0.0415560), XYZ),
                        dot(float3(0.0556434, -0.2040259, 1.0572252), XYZ));
    return gdtfNormalized(max(lin, 0.0));
}

float3 gdtfAdditiveColour(uint a)
{
    if (a == GDTF_ATTR_COLORADD_R) return float3(1, 0, 0);
    if (a == GDTF_ATTR_COLORADD_R + 1u) return float3(0, 1, 0);      // G
    if (a == GDTF_ATTR_COLORADD_R + 2u) return float3(0, 0, 1);      // B
    if (a == GDTF_ATTR_COLORADD_R + 3u) return float3(0, 1, 1);      // C
    if (a == GDTF_ATTR_COLORADD_R + 4u) return float3(1, 0, 1);      // M
    if (a == GDTF_ATTR_COLORADD_R + 5u) return float3(1, 1, 0);      // Y
    if (a == GDTF_ATTR_COLORADD_R + 6u) return float3(1, 0.5, 0);    // RY amber
    if (a == GDTF_ATTR_COLORADD_R + 7u) return float3(0.5, 1, 0);    // GY lime
    if (a == GDTF_ATTR_COLORADD_R + 8u) return float3(0, 1, 0.5);    // GC
    if (a == GDTF_ATTR_COLORADD_R + 9u) return float3(0, 0.5, 1);    // BC
    if (a == GDTF_ATTR_COLORADD_R + 10u) return float3(0.5, 0, 1);   // BM
    if (a == GDTF_ATTR_COLORADD_R + 11u) return float3(1, 0, 0.5);   // RM
    if (a == GDTF_ATTR_COLORADD_R + 12u) return float3(1, 1, 1);     // W
    if (a == GDTF_ATTR_COLORADD_R + 13u) return gdtfKelvinToLinear(3000.0);  // WW
    if (a == GDTF_ATTR_COLORADD_R + 14u) return gdtfKelvinToLinear(6500.0);  // CW
    if (a == GDTF_ATTR_COLORADD_UV) return float3(0.25, 0, 1);
    return float3(0, 0, 0);
}

// One bit per colour attribute a mix reads: ColorAdd (0-15), ColorRGB (16-18), ColorSub (19-24), Color(n) wheel
// (25), CTO (26), CTC (27); -1 for any other attribute.
int gdtfColourBit(uint a)
{
    if (a >= GDTF_ATTR_COLORADD_R && a <= GDTF_ATTR_COLORADD_UV) return (int)(a - GDTF_ATTR_COLORADD_R);
    if (a >= GDTF_ATTR_COLORRGB_RED && a <= GDTF_ATTR_COLORRGB_BLUE) return 16 + (int)(a - GDTF_ATTR_COLORRGB_RED);
    if (a >= GDTF_ATTR_COLORSUB_R && a <= GDTF_ATTR_COLORSUB_Y) return 19 + (int)(a - GDTF_ATTR_COLORSUB_R);
    uint base = a & 0xFFFFu;
    if (base == GDTF_ATTR_COLOR_N || base == GDTF_ATTR_COLOR_NWHEELINDEX) return 25;
    if (a == GDTF_ATTR_CTO) return 26;
    if (a == GDTF_ATTR_CTC) return 27;
    return -1;
}

uint gdtfChannelMax(uint ch)
{
    uint bytes = clamp(gdtfChannel(ch, 0u).w & GDTF_CHANNEL_BYTES_MASK, 1u, 4u);
    return bytes >= 4u ? 0xFFFFFFFFu : (1u << (8u * bytes)) - 1u;
}

uint gdtfChannelWord(GdtfFixture f, uint ch)
{
    uint4 r0 = gdtfChannel(ch, 0u), slots = gdtfChannel(ch, 1u), r2 = gdtfChannel(ch, 2u);
    if ((r0.w & GDTF_CHANNEL_VIRTUAL) != 0u || r0.z < 1u || r0.z > 4u) return r2.z;
    uint2 brk = r0.z == 1u ? f.b01.xy : (r0.z == 2u ? f.b01.zw : (r0.z == 3u ? f.b23.xy : f.b23.zw));
    if (brk.x == 0u || brk.y == 0u) return r2.z;
    uint word = 0u;
    [unroll] for (uint k = 0u; k < 4u; k++)
    {
        uint s = slots[k];
        if (s == 0u) break;
        uint a = brk.y + s - 1u;
        word = (word << 8u) | (a <= 512u ? (GDTF_READ_BYTE(brk.x, a) & 255u) : 0u);
    }
    return word;
}

bool gdtfGatePasses(GdtfFixture f, uint fn)
{
    uint4 r3 = gdtfFunction(fn, 3u);
    if (r3.x == GDTF_NONE) return true;
    uint w = gdtfChannelWord(f, r3.x);
    return w >= r3.y && w <= r3.z;
}

uint gdtfActiveFunction(GdtfFixture f, uint ch, uint word)
{
    uint4 r0 = gdtfChannel(ch, 0u);
    [loop] for (uint k = r0.x; k < r0.x + r0.y; k++)
    {
        uint4 fr = gdtfFunction(k, 0u);
        if (word >= fr.y && word <= fr.z && gdtfGatePasses(f, k)) return k;
    }
    return GDTF_NONE;
}

float gdtfFunctionPhysical(uint fn, uint word)
{
    uint4 r0 = gdtfFunction(fn, 0u);
    float2 p = asfloat(gdtfFunction(fn, 1u).xy);
    float span = (float)r0.z - (float)r0.y;
    float t = span > 0.0 ? ((float)word - (float)r0.y) / span : 0.0;
    return p.x + t * (p.y - p.x);
}

uint gdtfActiveSet(uint fn, uint word)
{
    uint4 r1 = gdtfFunction(fn, 1u);
    [loop] for (uint s = r1.z; s < r1.z + r1.w; s++)
    {
        uint4 sr = gdtfSet(s, 0u);
        if (word >= sr.x && word <= sr.y) return s;
    }
    return GDTF_NONE;
}

float gdtfPhysicalRaw(GdtfFixture f, uint ch, out uint fn, out uint word)
{
    word = gdtfChannelWord(f, ch);
    fn = gdtfActiveFunction(f, ch, word);
    return fn == GDTF_NONE ? 0.0 : gdtfFunctionPhysical(fn, word);
}

// A channel's value with relations applied.
GdtfValue gdtfChannelValue(GdtfFixture f, uint ch)
{
    GdtfValue v = gdtfValueNone();
    v.channel = ch;
    uint fn, word;
    v.physical = gdtfPhysicalRaw(f, ch, fn, word);
    v.function = fn;
    v.word = word;
    v.set = fn == GDTF_NONE ? GDTF_NONE : gdtfActiveSet(fn, word);
    uint4 m1 = gdtfMode(gdtfModeGlobal(f), 1u);
    [loop] for (uint r = m1.x; r < m1.x + m1.y; r++)
    {
        uint4 rel = gdtfRelation(r);
        if (rel.y != ch || rel.x == GDTF_NONE) continue;
        if ((gdtfChannel(rel.x, 0u).w & GDTF_CHANNEL_VIRTUAL) != 0u) continue;   // console-side master
        uint mfn, mword;
        float mphys = gdtfPhysicalRaw(f, rel.x, mfn, mword);
        if (rel.w == GDTF_RELATION_MULTIPLY)
            v.physical *= (float)mword / (float)gdtfChannelMax(rel.x);
        else if (rel.w == GDTF_RELATION_OVERRIDE && mword > 0u)
            v.physical = mphys;
    }
    v.found = true;
    return v;
}

uint gdtfFindChannel(uint mode, uint attr, uint cell)
{
    uint4 m0 = gdtfMode(mode, 0u);
    [loop] for (uint c = m0.x; c < m0.x + m0.y; c++)
    {
        uint4 r0 = gdtfChannel(c, 0u);
        if ((r0.w & GDTF_CHANNEL_VIRTUAL) != 0u || gdtfChannel(c, 2u).y != cell) continue;
        [loop] for (uint k = r0.x; k < r0.x + r0.y; k++)
            if (gdtfFunction(k, 0u).x == attr) return c;
    }
    return GDTF_NONE;
}

GdtfValue gdtfAttribute(GdtfFixture f, uint attr, uint cell)
{
    uint ch = gdtfFindChannel(gdtfModeGlobal(f), attr, cell);
    if (ch == GDTF_NONE) return gdtfValueNone();
    GdtfValue v = gdtfChannelValue(f, ch);
    v.active = v.function != GDTF_NONE && gdtfFunction(v.function, 0u).x == attr;
    return v;
}

uint gdtfCellCount(GdtfFixture f) { return gdtfMode(gdtfModeGlobal(f), 1u).w; }

uint gdtfCellNode(GdtfFixture f, uint cell)
{
    uint4 m1 = gdtfMode(gdtfModeGlobal(f), 1u);
    return cell < m1.w ? gdtfCell(m1.z + cell).x : GDTF_NONE;
}

// The colour mix of a cell, or of the fixture with cell = GDTF_NONE: ColorRGB and ColorAdd summed (white when the
// cell has neither), then subtractive filters, the colour wheel slot and CTO/CTC tints multiplied in.
float3 gdtfColour(GdtfFixture f, uint cell)
{
    uint4 m0 = gdtfMode(gdtfModeGlobal(f), 0u);
    uint seen = 0u;
    bool hasRgb = false, hasAdd = false;
    float3 rgb = 0.0, add = 0.0, filt = 1.0;
    [loop] for (uint c = m0.x; c < m0.x + m0.y; c++)
    {
        uint4 r0 = gdtfChannel(c, 0u);
        if ((r0.w & GDTF_CHANNEL_VIRTUAL) != 0u || gdtfChannel(c, 2u).y != cell) continue;
        uint attr = 0u;
        int bit = -1;
        [loop] for (uint k = r0.x; k < r0.x + r0.y && bit < 0; k++)
        {
            attr = gdtfFunction(k, 0u).x;
            bit = gdtfColourBit(attr);
        }
        if (bit < 0 || ((seen >> (uint)bit) & 1u) != 0u) continue;
        seen |= 1u << (uint)bit;
        GdtfValue v = gdtfChannelValue(f, c);
        if (v.function == GDTF_NONE) continue;
        uint active = gdtfFunction(v.function, 0u).x;
        if (bit < 16)
        {
            if (active != attr) continue;
            uint emitter = gdtfFunction(v.function, 2u).y;
            float3 e = emitter != GDTF_NONE ? gdtfNormalized(asfloat(gdtfEmitter(emitter).xyz)) : gdtfAdditiveColour(attr);
            add += v.physical * e;
            hasAdd = true;
        }
        else if (bit < 19)
        {
            if (active != attr) continue;
            float3 m = gdtfOneHot((uint)(bit - 16));
            rgb = rgb * (1.0 - m) + v.physical * m;
            hasRgb = true;
        }
        else if (bit < 25)
        {
            if (active != attr) continue;
            float k = saturate(v.physical);
            uint which = attr - GDTF_ATTR_COLORSUB_R;   // R, G, B pass their own primary; C, M, Y remove one
            if (which < 3u)
                filt *= (1.0 - k) + k * gdtfOneHot(which);
            else
                filt *= 1.0 - k * gdtfOneHot(which - 3u);
        }
        else if (bit == 25)
        {
            uint wheel = gdtfFunction(v.function, 2u).x;
            if (wheel == GDTF_NONE || v.set == GDTF_NONE) continue;
            uint slot = gdtfSet(v.set, 0u).z;
            uint4 wr = gdtfWheel(wheel);
            if (slot == 0u || slot > wr.y) continue;
            filt *= gdtfNormalized(asfloat(gdtfWheelSlot(wr.x + slot - 1u, 0u).xyz));
        }
        else
        {
            if (active != attr || v.physical <= 0.0) continue;
            float3 kc = gdtfKelvinToLinear(v.physical), w = gdtfKelvinToLinear(6504.0);
            filt *= gdtfNormalized(kc / max(w, 1e-6));
        }
    }
    float3 outc = (hasRgb || hasAdd) ? (hasRgb ? rgb : 0.0) + (hasAdd ? add : 0.0) : float3(1, 1, 1);
    return outc * filt;
}

uint gdtfLowerAscii(uint b) { return (b >= 65u && b <= 90u) ? b + 32u : b; }

// Whether the first 64 bytes of a string hold `pattern`, ignoring ASCII case: n (1 to 4) lower-case bytes packed
// with the first byte most significant ("open" is 0x6F70656E).
bool gdtfStringHas(uint firstRow, uint len, uint pattern, uint n)
{
    uint window = 0u, mask = n >= 4u ? 0xFFFFFFFFu : ((1u << (8u * n)) - 1u);
    uint m = min(len, 64u);
    [loop] for (uint i = 0u; i < m; i++)
    {
        window = (window << 8) | gdtfLowerAscii(gdtfStringByte(firstRow, i));
        if (i + 1u >= n && (window & mask) == pattern) return true;
    }
    return false;
}

// Whether a Shutter(n) value opens the shutter. GDTF states no physical meaning for Shutter(n), and files disagree
// (0 to 1, 1 to 0, a constant), while the channel set names agree: the active set's name decides when it holds
// "open" (open) or "clos" or starts with "off" (closed); otherwise a physical value of 0.5 or more is open.
bool gdtfShutterOpen(GdtfValue v)
{
    if (v.set != GDTF_NONE)
    {
        uint4 r1 = gdtfSet(v.set, 1u);
        if (gdtfStringHas(r1.z, r1.w, 0x6F70656Eu, 4u)) return true;   // "open"
        if (gdtfStringHas(r1.z, r1.w, 0x636C6F73u, 4u)) return false;  // "clos"
        if (r1.w >= 3u && gdtfLowerAscii(gdtfStringByte(r1.z, 0u)) == 111u && gdtfLowerAscii(gdtfStringByte(r1.z, 1u)) == 102u
            && gdtfLowerAscii(gdtfStringByte(r1.z, 2u)) == 102u)
        {
            uint next = r1.w > 3u ? gdtfLowerAscii(gdtfStringByte(r1.z, 3u)) : 32u;
            if (next < 97u || next > 122u) return false;                // "off", "OFF 1"
        }
    }
    return v.physical >= 0.5;
}

// A dimmer value as a level from 0 to 1: its physical value within the active function's physical range, since a
// GDTF dimmer can state its physical values in lumens or percent as well as from 0 to 1.
float gdtfLevel(GdtfValue v)
{
    if (v.function == GDTF_NONE) return saturate(v.physical);
    uint4 r1 = gdtfFunction(v.function, 1u);
    float pf = asfloat(r1.x), pt = asfloat(r1.y);
    float span = abs(pt - pf);
    return span > 0.0 ? saturate((v.physical - min(pf, pt)) / span) : saturate(v.physical);
}

// A cell's own dimmer level (relations applied), 1 without one.
float gdtfCellIntensity(GdtfFixture f, uint cell)
{
    GdtfValue v = gdtfAttribute(f, GDTF_ATTR_DIMMER, cell);
    return v.found ? gdtfLevel(v) : 1.0;
}

GdtfFixtureState gdtfFixtureState(GdtfFixture f)
{
    GdtfFixtureState s;
    GdtfValue dim = gdtfAttribute(f, GDTF_ATTR_DIMMER, GDTF_NONE);
    s.dimmer = dim.found ? gdtfLevel(dim) : 1.0;
    GdtfValue pan = gdtfAttribute(f, GDTF_ATTR_PAN, GDTF_NONE), tilt = gdtfAttribute(f, GDTF_ATTR_TILT, GDTF_NONE);
    s.pan = pan.active ? pan.physical : 0.0;
    s.tilt = tilt.active ? tilt.physical : 0.0;
    GdtfValue zoom = gdtfAttribute(f, GDTF_ATTR_ZOOM, GDTF_NONE);
    s.zoom = zoom.active ? zoom.physical : 0.0;
    s.rgb = gdtfColour(f, GDTF_NONE);
    GdtfValue cto = gdtfAttribute(f, GDTF_ATTR_CTO, GDTF_NONE), ctc = gdtfAttribute(f, GDTF_ATTR_CTC, GDTF_NONE);
    s.cto = cto.active ? cto.physical : 0.0;
    s.ctc = ctc.active ? ctc.physical : 0.0;
    GdtfValue c1 = gdtfAttribute(f, GDTF_ATTR_COLOR1, GDTF_NONE);
    s.color1Slot = (c1.active && c1.set != GDTF_NONE) ? gdtfSet(c1.set, 0u).z : 0u;
    s.shutterAttribute = 0u;
    s.shutterPhysical = 0.0;
    s.strobeHz = 0.0;
    s.open = true;
    // The shutter channel: the first fixture-level channel whose first function is Shutter(n).
    uint4 m0 = gdtfMode(gdtfModeGlobal(f), 0u);
    [loop] for (uint c = m0.x; c < m0.x + m0.y; c++)
    {
        uint4 r0 = gdtfChannel(c, 0u), r2 = gdtfChannel(c, 2u);
        if ((r0.w & GDTF_CHANNEL_VIRTUAL) != 0u || r2.y != GDTF_NONE || (r2.w & 0xFFFFu) != GDTF_ATTR_SHUTTER_N) continue;
        GdtfValue v = gdtfChannelValue(f, c);
        if (v.function == GDTF_NONE) break;
        uint a = gdtfFunction(v.function, 0u).x;
        uint base = a & 0xFFFFu;
        s.shutterAttribute = a;
        s.shutterPhysical = v.physical;
        if ((base >= GDTF_ATTR_SHUTTER_NSTROBE && base <= GDTF_ATTR_SHUTTER_NSTROBEEFFECT) || a == GDTF_ATTR_STROBEFREQUENCY)
        {
            s.strobeHz = v.physical;
            s.open = true;
        }
        else if (base == GDTF_ATTR_SHUTTER_N)
        {
            s.open = gdtfShutterOpen(v);
        }
        break;
    }
    return s;
}

#endif
