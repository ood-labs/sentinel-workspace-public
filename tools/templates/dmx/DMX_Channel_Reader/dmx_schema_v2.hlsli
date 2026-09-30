#ifndef SENTINEL_DMX_SCHEMA_V2
#define SENTINEL_DMX_SCHEMA_V2
static const uint DMX_SCHEMA_VERSION = 2;
static const uint DMX_METADATA_RECORDS = 8;
static const uint DMX_UNIVERSE_RECORD_BASE = 9;
static const uint DMX_MAX_UNIVERSES = 1024;
static const uint DMX_MAX_RECORDS = 1033;
uint metadataRecord(uint u) { return 1 + u / 128; }
uint metadataSlot(uint u) { return 4 * (u % 128); }
uint universeRecord(uint u) { return DMX_UNIVERSE_RECORD_BASE + u; }
#endif
