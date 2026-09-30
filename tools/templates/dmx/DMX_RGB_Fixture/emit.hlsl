#include "dmx_schema_v2.hlsli"
struct DmxRecord { uint channels[512]; };
RWStructuredBuffer<DmxRecord> Records : register(u0);

uint level(float v) { return (uint)round(saturate(v) * 255.0); }

// One thread per record: the header, eight metadata records, one universe.
[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint r = id.x;
    if (r >= universeRecord(1)) return;
    [loop] for (uint c = 0; c < 512; ++c) Records[r].channels[c] = 0;
    if (r == 0) {
        Records[0].channels[0] = DMX_SCHEMA_VERSION;
        Records[0].channels[1] = 1;              // live universes
        Records[0].channels[2] = (uint)_Frame;   // generation
        Records[0].channels[8] = DMX_METADATA_RECORDS;
        Records[0].channels[9] = DMX_UNIVERSE_RECORD_BASE;
    }
    if (r == metadataRecord(0)) {
        Records[r].channels[metadataSlot(0)] = (uint)universe;  // Art-Net port address or sACN universe
        Records[r].channels[metadataSlot(0) + 2] = 512;         // payload length
    }
    if (r == universeRecord(0)) {
        uint a = (uint)address - 1;              // DMX addresses count from 1
        Records[r].channels[a + 0] = level(dimmer);
        Records[r].channels[a + 1] = level(red);
        Records[r].channels[a + 2] = level(green);
        Records[r].channels[a + 3] = level(blue);
    }
}
