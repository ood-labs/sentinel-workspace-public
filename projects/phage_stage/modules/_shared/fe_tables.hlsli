// The fixture engine's type tables: the Fixture Rig node's FixtureRender port (gdtf_render.hlsli), indexed by rig
// type, so any GDTF the rig holds draws with no per-type code and no recompile. Every shader reads the tables through
// the FE_*_AT() accessors below, one per port section.
//
// A pass binds the port as a data input and defines GDTF_RENDER before including this file (for example
// `#define GDTF_RENDER _Data2`). When the port carries no valid tables (no Fixture Rig node connected, or one with no
// rig) feTypeCount() is 0 and FE_Rig publishes no active records. A pass that reads only the renderer's frame and
// source buffers includes this file without GDTF_RENDER and gets the vocabulary and caps (fe_vocab.hlsli) alone.
#ifndef FE_TABLES_HLSLI
#define FE_TABLES_HLSLI
#include "../_shared/fe_vocab.hlsli"
#ifdef GDTF_RENDER
#include "../_shared/gdtf_render.hlsli"

#define FE_TABLE_U4(NAME, SECTION) uint4 NAME##_AT(uint i) { return frRow(frSectionFirst(SECTION) + i); }
#define FE_TABLE_U2(NAME, SECTION) uint2 NAME##_AT(uint i) { return frRow(frSectionFirst(SECTION) + i).xy; }
#define FE_TABLE_U1(NAME, SECTION) uint NAME##_AT(uint i) { return frRow(frSectionFirst(SECTION) + i).x; }
#define FE_TABLE_F4(NAME, SECTION) float4 NAME##_AT(uint i) { return asfloat(frRow(frSectionFirst(SECTION) + i)); }
#define FE_TABLE_F2(NAME, SECTION) float2 NAME##_AT(uint i) { return asfloat(frRow(frSectionFirst(SECTION) + i).xy); }

FE_TABLE_U4(FE_TYPE_INFO, FR_SECTION_TYPE_INFO)
FE_TABLE_U1(FE_TYPE_ATTRN, FR_SECTION_TYPE_ATTRN)
FE_TABLE_U1(FE_TYPE_SLOT0, FR_SECTION_TYPE_SLOT0)
FE_TABLE_U4(FE_ATTR, FR_SECTION_ATTR)
FE_TABLE_F2(FE_DEFAULT, FR_SECTION_DEFAULT)
FE_TABLE_U4(FE_MODE_INFO, FR_SECTION_MODE_INFO)
FE_TABLE_U4(FE_PART_INFO, FR_SECTION_PART_INFO)
FE_TABLE_U4(FE_ENTRY, FR_SECTION_ENTRY)
FE_TABLE_U4(FE_CHAN_INFO, FR_SECTION_CHAN_INFO)
FE_TABLE_U1(FE_CHAN_DEF, FR_SECTION_CHAN_DEF)
FE_TABLE_U1(FE_RANGE, FR_SECTION_RANGE)
FE_TABLE_F2(FE_RANGE_P, FR_SECTION_RANGE_P)
FE_TABLE_U4(FE_VIEW, FR_SECTION_VIEW)
FE_TABLE_F4(FE_SWATCH, FR_SECTION_SWATCH)
FE_TABLE_U4(FE_EMITTER, FR_SECTION_EMITTER)
FE_TABLE_F4(FE_EMITTER_OPT, FR_SECTION_EMITTER_OPT)
FE_TABLE_F4(FE_EMITTER_LUM, FR_SECTION_EMITTER_LUM)
FE_TABLE_U4(FE_TYPE_GEO, FR_SECTION_TYPE_GEO)
FE_TABLE_F4(FE_PART_G, FR_SECTION_PART_G)
FE_TABLE_F4(FE_PIVOT, FR_SECTION_PIVOT)
FE_TABLE_F4(FE_MOUNT, FR_SECTION_MOUNT)
FE_TABLE_F4(FE_FACE_G, FR_SECTION_FACE_G)
FE_TABLE_F4(FE_DRAW, FR_SECTION_DRAW)
FE_TABLE_U4(FE_BIND, FR_SECTION_BIND)
FE_TABLE_U2(FE_PANTILT, FR_SECTION_PAN_TILT)
FE_TABLE_F2(FE_PANTILT_DIR, FR_SECTION_PAN_TILT_DIR)
FE_TABLE_U1(FE_CELL_BASE, FR_SECTION_CELL_BASE)

uint feTypeCount() { return frTablesValid() ? frTypeCount() : 0u; }
uint feMaxEmitters() { return frEmittersPerType(); }
uint feStateStride() { return frStateStride(); }

// FR_STATUS_RENDERABLE, or why the engine cannot draw type t (blocked, over a cap).
uint feTypeStatus(uint t) { return frTypeStatus(t); }

// Emission cells of type t: the frame and source slots its emitters use (cell bases are packed from 0).
uint feTypeCells(uint t) { return min(frTypeMeta(t).z, FE_CELLS_CAP); }

// Additive colour k of emitter record ei (type * feMaxEmitters() + i): (slot | FE_SLOT_CELLED, r, g, b as float bits),
// the channels beyond red, green, blue and the whites.
#define FE_MIX_PER_EMITTER 4u
uint4 feEmitterMix(uint ei, uint k)
{
    if (frSectionCount(FR_SECTION_EMITTER_MIX) == 0u) return uint4(FE_SLOT_NONE, 0u, 0u, 0u);
    return frRow(frSectionFirst(FR_SECTION_EMITTER_MIX) + ei * FR_STRIDE_EMITTER_MIX + k);
}

// Emission cell c of type t (index over its emitters, as CELL_BASE counts): position (m, profile frame at rest) and
// size; beam direction.
float4 feCellPos(uint t, uint c) { return frCellPos(t, c); }
float3 feCellDir(uint t, uint c) { return frCellDir(t, c); }

// Console role of type t: FR_ROLE_WASH, FR_ROLE_MOVER, FR_ROLE_STROBE or FR_ROLE_BAR.
uint feTypeRole(uint t) { return frTypeRole(t); }

#endif  // GDTF_RENDER
#endif
