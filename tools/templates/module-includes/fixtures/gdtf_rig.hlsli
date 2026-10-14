// Accessors for the Fixture Rig node's three data ports: Fixtures, SceneObjects and FixtureTypes (layout version 1).
// The layout is frozen in Sentinel's docs/knowledge/gdtf-mvr-import.md and mirrors src/fixtures/FixtureTablesPack.h;
// sentinel_gdtf_mvr_import_pack_tests checks every constant below against the C++ side.
//
// Before including, declare the ports as data inputs and name them:
//   data_inputs:
//     - { name: "Fixtures",     slot: 0, schema: [axis_x float4, axis_y float4, axis_z float4, origin float4,
//                                                 ids uint x4, dmx01 uint x4, dmx23 uint x4, meta uint x4] }
//     - { name: "FixtureTypes", slot: 1, schema: [{ name: w, type: uint, count: 4 }] }
//   #define GDTF_FIXTURES _Data0
//   #define GDTF_TYPES _Data1
// Module includes resolve against the Module's folder, so copy this file (and gdtf_attributes.hlsli,
// gdtf_decode.hlsli) into the project and include them in that order.
#ifndef SENTINEL_GDTF_RIG
#define SENTINEL_GDTF_RIG

#define GDTF_MAGIC 0x46544447u
#define GDTF_LAYOUT_VERSION 1u
#define GDTF_NONE 0xFFFFFFFFu
#define GDTF_SECTION_TABLE_ROW 1u

// Sections (row GDTF_SECTION_TABLE_ROW + s of the table holds first row, record count, rows per record).
#define GDTF_SECTION_TYPES 0u
#define GDTF_SECTION_MODES 1u
#define GDTF_SECTION_BREAKS 2u
#define GDTF_SECTION_CHANNELS 3u
#define GDTF_SECTION_FUNCTIONS 4u
#define GDTF_SECTION_SETS 5u
#define GDTF_SECTION_RELATIONS 6u
#define GDTF_SECTION_GEOMETRY 7u
#define GDTF_SECTION_WHEELS 8u
#define GDTF_SECTION_WHEEL_SLOTS 9u
#define GDTF_SECTION_EMITTERS 10u
#define GDTF_SECTION_FILTERS 11u
#define GDTF_SECTION_COLOR_SPACES 12u
#define GDTF_SECTION_GROUPS 13u
#define GDTF_SECTION_MEDIA 14u
#define GDTF_SECTION_ATTRIBUTE_NAMES 15u
#define GDTF_SECTION_CELLS 16u
#define GDTF_SECTION_STRINGS 17u

// Rows per record.
#define GDTF_STRIDE_TYPES 5u
#define GDTF_STRIDE_MODES 3u
#define GDTF_STRIDE_BREAKS 1u
#define GDTF_STRIDE_CHANNELS 3u
#define GDTF_STRIDE_FUNCTIONS 4u
#define GDTF_STRIDE_SETS 2u
#define GDTF_STRIDE_RELATIONS 1u
#define GDTF_STRIDE_GEOMETRY 8u
#define GDTF_STRIDE_WHEELS 1u
#define GDTF_STRIDE_WHEEL_SLOTS 2u
#define GDTF_STRIDE_EMITTERS 1u
#define GDTF_STRIDE_FILTERS 1u
#define GDTF_STRIDE_COLOR_SPACES 2u
#define GDTF_STRIDE_GROUPS 1u
#define GDTF_STRIDE_MEDIA 1u
#define GDTF_STRIDE_ATTRIBUTE_NAMES 1u
#define GDTF_STRIDE_CELLS 1u
#define GDTF_STRIDE_STRINGS 1u

// Flags and codes.
#define GDTF_CHANNEL_BYTES_MASK 0x0Fu
#define GDTF_CHANNEL_VIRTUAL 0x10u
#define GDTF_CHANNEL_SNAP 0x20u
#define GDTF_CHANNEL_MASTER_SHIFT 6u
#define GDTF_TYPE_STUB 1u
#define GDTF_SET_HAS_PHYSICAL 1u
#define GDTF_RELATION_MULTIPLY 1u
#define GDTF_RELATION_OVERRIDE 2u
#define GDTF_GEO_GEOMETRY 1u
#define GDTF_GEO_AXIS 2u
#define GDTF_GEO_BEAM 7u
#define GDTF_GEO_REFERENCE 12u

// Fixtures record flags (meta[1]).
#define GDTF_FIXTURE_ACTIVE 1u
#define GDTF_FIXTURE_FROM_LIBRARY 2u
#define GDTF_FIXTURE_BOUND 4u
#define GDTF_FIXTURE_ENGINES_FOLDED 8u
#define GDTF_FIXTURE_MULTIPATCH_CHILD 16u
#define GDTF_FIXTURE_PROBLEM 32u
#define GDTF_FIXTURE_EMBEDDED_STUB 64u

uint4 gdtfRow(uint r)
{
    return uint4(GDTF_TYPES[r].w[0], GDTF_TYPES[r].w[1], GDTF_TYPES[r].w[2], GDTF_TYPES[r].w[3]);
}

bool gdtfTablesValid()
{
    uint4 h = gdtfRow(0u);
    return h.x == GDTF_MAGIC && h.y == GDTF_LAYOUT_VERSION;
}

uint gdtfTypeCount() { return gdtfRow(0u).z; }
uint gdtfSectionFirst(uint s) { return gdtfRow(GDTF_SECTION_TABLE_ROW + s).x; }
uint gdtfSectionCount(uint s) { return gdtfRow(GDTF_SECTION_TABLE_ROW + s).y; }

// Byte i of a string whose first row within the Strings section is firstRow (as records reference strings).
uint gdtfStringByte(uint firstRow, uint i)
{
    uint4 r = gdtfRow(gdtfSectionFirst(GDTF_SECTION_STRINGS) + firstRow + i / 16u);
    uint k = (i % 16u) / 4u;
    uint w = k == 0u ? r.x : (k == 1u ? r.y : (k == 2u ? r.z : r.w));
    return (w >> (8u * (i % 4u))) & 255u;
}

// Row k of record i in section s.
uint4 gdtfRec(uint s, uint stride, uint i, uint k) { return gdtfRow(gdtfSectionFirst(s) + i * stride + k); }

uint4 gdtfType(uint t, uint k)      { return gdtfRec(GDTF_SECTION_TYPES, GDTF_STRIDE_TYPES, t, k); }
uint4 gdtfMode(uint m, uint k)      { return gdtfRec(GDTF_SECTION_MODES, GDTF_STRIDE_MODES, m, k); }
uint4 gdtfBreak(uint b)             { return gdtfRec(GDTF_SECTION_BREAKS, GDTF_STRIDE_BREAKS, b, 0u); }
uint4 gdtfChannel(uint c, uint k)   { return gdtfRec(GDTF_SECTION_CHANNELS, GDTF_STRIDE_CHANNELS, c, k); }
uint4 gdtfFunction(uint f, uint k)  { return gdtfRec(GDTF_SECTION_FUNCTIONS, GDTF_STRIDE_FUNCTIONS, f, k); }
uint4 gdtfSet(uint s, uint k)       { return gdtfRec(GDTF_SECTION_SETS, GDTF_STRIDE_SETS, s, k); }
uint4 gdtfRelation(uint r)          { return gdtfRec(GDTF_SECTION_RELATIONS, GDTF_STRIDE_RELATIONS, r, 0u); }
uint4 gdtfGeometry(uint g, uint k)  { return gdtfRec(GDTF_SECTION_GEOMETRY, GDTF_STRIDE_GEOMETRY, g, k); }
uint4 gdtfWheel(uint w)             { return gdtfRec(GDTF_SECTION_WHEELS, GDTF_STRIDE_WHEELS, w, 0u); }
uint4 gdtfWheelSlot(uint s, uint k) { return gdtfRec(GDTF_SECTION_WHEEL_SLOTS, GDTF_STRIDE_WHEEL_SLOTS, s, k); }
uint4 gdtfEmitter(uint e)           { return gdtfRec(GDTF_SECTION_EMITTERS, GDTF_STRIDE_EMITTERS, e, 0u); }
uint4 gdtfCell(uint c)              { return gdtfRec(GDTF_SECTION_CELLS, GDTF_STRIDE_CELLS, c, 0u); }

// A geometry node's local transform (rows 1 to 3 of its record: the 3x4 matrix, translation in column 3), its
// model dimensions (length, width, height in metres) and its beam (beam angle, field angle, flux, radius).
float3x4 gdtfGeometryLocal(uint g)
{
    return float3x4(asfloat(gdtfGeometry(g, 1u)), asfloat(gdtfGeometry(g, 2u)), asfloat(gdtfGeometry(g, 3u)));
}
float3 gdtfGeometryDims(uint g) { return asfloat(gdtfGeometry(g, 4u).xyz); }
float4 gdtfGeometryBeam(uint g) { return asfloat(gdtfGeometry(g, 5u)); }

// ---- Fixtures records

struct GdtfFixture
{
    uint type;    // rig type index (Types record)
    uint mode;    // mode index within the type; GDTF_NONE when unresolved
    uint4 b01;    // break 1 universe, address, break 2 universe, address (universes 1-based, 0 = unpatched)
    uint4 b23;    // breaks 3 and 4
};

bool gdtfFixtureActive(uint i)
{
    return GDTF_FIXTURES[i].origin.w > 0.5 && (GDTF_FIXTURES[i].meta[1] & GDTF_FIXTURE_ACTIVE) != 0u;
}

// True when record i has a resolved type and mode the tables hold (not an embedded stub).
bool gdtfFixtureDecodable(uint i)
{
    uint t = GDTF_FIXTURES[i].ids[0], m = GDTF_FIXTURES[i].ids[1];
    if (!gdtfFixtureActive(i) || m == GDTF_NONE || t >= gdtfTypeCount()) return false;
    if ((GDTF_FIXTURES[i].meta[1] & GDTF_FIXTURE_EMBEDDED_STUB) != 0u) return false;
    return m < gdtfType(t, 0u).y;
}

GdtfFixture gdtfFixture(uint i)
{
    GdtfFixture f;
    f.type = GDTF_FIXTURES[i].ids[0];
    f.mode = GDTF_FIXTURES[i].ids[1];
    f.b01 = uint4(GDTF_FIXTURES[i].dmx01[0], GDTF_FIXTURES[i].dmx01[1], GDTF_FIXTURES[i].dmx01[2], GDTF_FIXTURES[i].dmx01[3]);
    f.b23 = uint4(GDTF_FIXTURES[i].dmx23[0], GDTF_FIXTURES[i].dmx23[1], GDTF_FIXTURES[i].dmx23[2], GDTF_FIXTURES[i].dmx23[3]);
    return f;
}

// GDTF frame of record i in the stage frame: columns are the stage images of GDTF X, Y and Z (the home beam is
// -column 2), and the GDTF origin in stage metres.
float3x3 gdtfFixtureAxes(uint i)
{
    return transpose(float3x3(GDTF_FIXTURES[i].axis_x.xyz, GDTF_FIXTURES[i].axis_y.xyz, GDTF_FIXTURES[i].axis_z.xyz));
}
float3 gdtfFixtureOrigin(uint i) { return GDTF_FIXTURES[i].origin.xyz; }

uint gdtfModeGlobal(GdtfFixture f) { return gdtfType(f.type, 0u).x + f.mode; }

#endif
