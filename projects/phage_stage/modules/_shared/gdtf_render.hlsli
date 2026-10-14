// Accessors for the Fixture Rig node's FixtureRender data port (layout version 1): each rig type's render facts,
// derived from its GDTF by Sentinel's fixtures/FixtureRender (generic rules, then refinements). The layout is
// documented in Sentinel's docs/knowledge/fixture-ingestion.md and mirrors src/fixtures/FixtureRender.h;
// sentinel_fixture_ingestion_render_tests checks every constant below against the C++ side.
//
// Types are indexed as in FixtureTypes and the Fixtures records (the rig type index). Before including, declare the
// port as a data input and name it:
//   data_inputs:
//     - { name: "FixtureRender", slot: 2, schema: [{ name: w, type: uint, count: 4 }] }
//   #define GDTF_RENDER _Data2
// Module includes resolve against the Module's folder, so copy this file into the project.
//
// Floats travel as IEEE bits (asfloat). Positions and sizes are metres in the type's profile frame at rest: the
// frame the type's FR_SECTION_GDTF_AXES rows relate to GDTF, with pan about the profile's vertical axis.
#ifndef SENTINEL_GDTF_RENDER
#define SENTINEL_GDTF_RENDER

#define FR_MAGIC 0x44524546u
#define FR_LAYOUT_VERSION 1u
#define FR_SECTION_TABLE_ROW 1u
#define FR_SECTION_SLOTS 48u
#define FR_FIRST_RECORD_ROW 49u

// Engine caps.
#define FR_MAX_EMITTERS 8u
#define FR_MAX_BODY_PARTS 8u
#define FR_MAX_FACES 8u
#define FR_MAX_EMIT_CELLS 128u
#define FR_MAX_PARTS 4u
#define FR_STATE_STRIDE_MAX 1024u
#define FR_SLOT_NONE 0xFFFFu
#define FR_SLOT_CELLED 0x8000u

// Sections (row FR_SECTION_TABLE_ROW + s of the table holds first row, record count, rows per record).
#define FR_SECTION_TYPE_INFO 0u
#define FR_SECTION_TYPE_ATTRN 1u
#define FR_SECTION_TYPE_SLOT0 2u
#define FR_SECTION_ATTR 3u
#define FR_SECTION_DEFAULT 4u
#define FR_SECTION_MODE_INFO 5u
#define FR_SECTION_PART_INFO 6u
#define FR_SECTION_ENTRY 7u
#define FR_SECTION_CHAN_INFO 8u
#define FR_SECTION_CHAN_DEF 9u
#define FR_SECTION_RANGE 10u
#define FR_SECTION_RANGE_P 11u
#define FR_SECTION_VIEW 12u
#define FR_SECTION_SWATCH 13u
#define FR_SECTION_EMITTER 14u
#define FR_SECTION_EMITTER_OPT 15u
#define FR_SECTION_EMITTER_LUM 16u
#define FR_SECTION_TYPE_GEO 17u
#define FR_SECTION_PART_G 18u
#define FR_SECTION_PIVOT 19u
#define FR_SECTION_MOUNT 20u
#define FR_SECTION_FACE_G 21u
#define FR_SECTION_DRAW 22u
#define FR_SECTION_BIND 23u
#define FR_SECTION_PAN_TILT 24u
#define FR_SECTION_PAN_TILT_DIR 25u
#define FR_SECTION_CELL_BASE 26u
#define FR_SECTION_GDTF_AXES 27u
#define FR_SECTION_TYPE_META 28u
#define FR_SECTION_TYPE_NATIVE 29u
#define FR_SECTION_NATIVE_MODE 30u
#define FR_SECTION_TYPE_CELL 31u
#define FR_SECTION_CELL 32u
#define FR_SECTION_GLOBAL 33u
// Added within layout version 1 in a free table slot: a port without it has no rows in the section.
#define FR_SECTION_EMITTER_MIX 34u

// Rows per record.
#define FR_STRIDE_PART_G 3u
#define FR_STRIDE_PIVOT 2u
#define FR_STRIDE_FACE_G 4u
#define FR_STRIDE_DRAW 3u
#define FR_STRIDE_BIND 5u
#define FR_STRIDE_GDTF_AXES 3u
#define FR_STRIDE_CELL 2u
#define FR_STRIDE_EMITTER_MIX 4u

// TypeMeta status and role.
#define FR_STATUS_RENDERABLE 0u
#define FR_STATUS_BLOCKED 1u
#define FR_STATUS_OVER_LIMIT 2u
#define FR_ROLE_WASH 0u
#define FR_ROLE_MOVER 1u
#define FR_ROLE_STROBE 2u
#define FR_ROLE_BAR 3u

// Emitter record: kind + 1 (0 = no emitter), colour system, layout | cols << 8 | rows << 16, cells.
#define FR_EMITTER_WASH 1u
#define FR_EMITTER_BEAM 2u
#define FR_EMITTER_STROBE 3u
#define FR_EMITTER_BACKLIGHT 4u
#define FR_COLOUR_RGB 0u
#define FR_COLOUR_RGBW 1u
#define FR_COLOUR_W 2u
#define FR_COLOUR_CW 3u
#define FR_COLOUR_CMY_WHITE 4u
#define FR_LAYOUT_GRID 0u
#define FR_LAYOUT_LINE 1u
#define FR_LAYOUT_RING 2u
#define FR_LAYOUT_SINGLE 3u

uint4 frRow(uint r)
{
    return uint4(GDTF_RENDER[r].w[0], GDTF_RENDER[r].w[1], GDTF_RENDER[r].w[2], GDTF_RENDER[r].w[3]);
}

bool frTablesValid()
{
    uint4 h = frRow(0u);
    return h.x == FR_MAGIC && h.y == FR_LAYOUT_VERSION;
}

uint frTypeCount() { return frRow(0u).z; }
uint frSectionFirst(uint s) { return frRow(FR_SECTION_TABLE_ROW + s).x; }
uint frSectionCount(uint s) { return frRow(FR_SECTION_TABLE_ROW + s).y; }

// Row k of record i in section s (s's rows per record from the section table).
uint4 frRec(uint s, uint i, uint k)
{
    uint4 e = frRow(FR_SECTION_TABLE_ROW + s);
    return frRow(e.x + i * e.z + k);
}
float4 frRecF(uint s, uint i, uint k) { return asfloat(frRec(s, i, k)); }

// Global record: state slots per fixture (the largest renderable type, rounded up to 8), emitter records per type,
// the most DMX breaks and the most emission cells of any renderable type.
uint4 frGlobal() { return frRec(FR_SECTION_GLOBAL, 0u, 0u); }
uint frStateStride() { return frGlobal().x; }
uint frEmittersPerType() { return frGlobal().y; }

// Per type t.
uint4 frTypeInfo(uint t) { return frRec(FR_SECTION_TYPE_INFO, t, 0u); }   // mode_first, mode_count, slots, attr_first
uint frTypeAttrN(uint t) { return frRec(FR_SECTION_TYPE_ATTRN, t, 0u).x; }
uint frTypeSlot0(uint t) { return frRec(FR_SECTION_TYPE_SLOT0, t, 0u).x; }
uint4 frTypeMeta(uint t) { return frRec(FR_SECTION_TYPE_META, t, 0u); }   // status, role, emission cells, max breaks
uint frTypeStatus(uint t) { return frTypeMeta(t).x; }
uint frTypeRole(uint t) { return frTypeMeta(t).y; }
uint4 frTypeGeo(uint t) { return frRec(FR_SECTION_TYPE_GEO, t, 0u); }     // part_first, part_count, face_first, faces
float4 frPivot(uint t, uint k) { return frRecF(FR_SECTION_PIVOT, t, k); }  // k 0 outer, 1 inner: xyz, w 1 (2: per cell)
float4 frMount(uint t) { return frRecF(FR_SECTION_MOUNT, t, 0u); }
uint2 frPanTilt(uint t) { return frRec(FR_SECTION_PAN_TILT, t, 0u).xy; }    // state slot of the outer and inner angle (pan, tilt)
float2 frPanTiltDir(uint t) { return frRecF(FR_SECTION_PAN_TILT_DIR, t, 0u).xy; }
float3 frGdtfAxis(uint t, uint k) { return frRecF(FR_SECTION_GDTF_AXES, t, k).xyz; }  // profile image of GDTF X, Y, Z
uint4 frTypeCell(uint t) { return frRec(FR_SECTION_TYPE_CELL, t, 0u); }   // first Cell record, emission cells

// The engine mode of a fixture's GDTF mode (file order), or 0xFFFFFFFF when the type has no engine mode for it.
uint frEngineMode(uint t, uint gdtfMode)
{
    uint4 n = frRec(FR_SECTION_TYPE_NATIVE, t, 0u);
    return gdtfMode < n.y ? frRec(FR_SECTION_NATIVE_MODE, n.x + gdtfMode, 0u).x : 0xFFFFFFFFu;
}

// Attributes, state defaults, modes, parts and slot entries (global indices).
uint4 frAttr(uint a) { return frRec(FR_SECTION_ATTR, a, 0u); }             // slot_base, cells, kind, emitter or 255
float2 frDefault(uint slot) { return frRecF(FR_SECTION_DEFAULT, slot, 0u).xy; }   // fn, param
uint4 frModeInfo(uint m) { return frRec(FR_SECTION_MODE_INFO, m, 0u); }    // part_first, parts, footprint, type
uint4 frPartInfo(uint p) { return frRec(FR_SECTION_PART_INFO, p, 0u); }    // entry_first, entries, footprint, optional
uint4 frEntry(uint e) { return frRec(FR_SECTION_ENTRY, e, 0u); }          // offset | bits16 << 10, channel, slot, mask

// Channels and their decode ranges.
uint4 frChanInfo(uint c) { return frRec(FR_SECTION_CHAN_INFO, c, 0u); }    // range_first, ranges, swatch_first, swatches
uint frChanDef(uint c) { return frRec(FR_SECTION_CHAN_DEF, c, 0u).x; }
uint frRange(uint r) { return frRec(FR_SECTION_RANGE, r, 0u).x; }          // lo | hi << 8 | fn << 16
float2 frRangeP(uint r) { return frRecF(FR_SECTION_RANGE_P, r, 0u).xy; }
uint4 frView(uint v) { return frRec(FR_SECTION_VIEW, v, 0u); }
float4 frSwatch(uint s) { return frRecF(FR_SECTION_SWATCH, s, 0u); }

// Emitters: record t * frEmittersPerType() + i.
uint frEmitterIndex(uint t, uint i) { return t * frEmittersPerType() + i; }
uint4 frEmitter(uint t, uint i) { return frRec(FR_SECTION_EMITTER, frEmitterIndex(t, i), 0u); }
float4 frEmitterOpt(uint t, uint i) { return frRecF(FR_SECTION_EMITTER_OPT, frEmitterIndex(t, i), 0u); }
float4 frEmitterLum(uint t, uint i) { return frRecF(FR_SECTION_EMITTER_LUM, frEmitterIndex(t, i), 0u); }
float4 frDraw(uint t, uint i, uint k) { return frRecF(FR_SECTION_DRAW, frEmitterIndex(t, i), k); }
uint4 frBind(uint t, uint i, uint k) { return frRec(FR_SECTION_BIND, frEmitterIndex(t, i), k); }
uint frCellBase(uint t, uint i) { return frRec(FR_SECTION_CELL_BASE, frEmitterIndex(t, i), 0u).x; }

// Additive colour k (k < FR_STRIDE_EMITTER_MIX) of emitter i: (slot | FR_SLOT_CELLED when per cell, r, g, b as float
// bits), the channels beyond red, green, blue and the whites at their linear sRGB colour; slot FR_SLOT_NONE when unused
// or when the port has no EmitterMix rows.
uint4 frEmitterMix(uint t, uint i, uint k)
{
    if (frSectionCount(FR_SECTION_EMITTER_MIX) == 0u) return uint4(FR_SLOT_NONE, 0u, 0u, 0u);
    return frRec(FR_SECTION_EMITTER_MIX, frEmitterIndex(t, i), k);
}

// Body parts and faces (global indices from frTypeGeo).
float4 frPartG(uint p, uint k) { return frRecF(FR_SECTION_PART_G, p, k); }
float4 frFaceG(uint f, uint k) { return frRecF(FR_SECTION_FACE_G, f, k); }

// Emission cell c of type t (in emitter order): position and size, beam direction.
float4 frCellPos(uint t, uint c) { return frRecF(FR_SECTION_CELL, frTypeCell(t).x + c, 0u); }
float3 frCellDir(uint t, uint c) { return frRecF(FR_SECTION_CELL, frTypeCell(t).x + c, 1u).xyz; }

#endif
