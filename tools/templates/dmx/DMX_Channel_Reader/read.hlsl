#include "dmx_schema_v2.hlsli"
struct Level { float value; float raw; float live; float pad; };
RWStructuredBuffer<Level> Out : register(u0);

// record is the universe's position in the port (0 is DMX In's first
// universe); channel counts from 1 like a console.
[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    Level l = (Level)0;
    uint u = (uint)record;
    if (_Data0_Count > universeRecord(u) && _Data0[0].channels[0] == DMX_SCHEMA_VERSION) {
        uint length = _Data0[metadataRecord(u)].channels[metadataSlot(u) + 2];
        uint c = (uint)channel - 1;
        if (length > c) {
            uint v = _Data0[universeRecord(u)].channels[c];
            l.raw = (float)v;
            l.value = v / 255.0;
            l.live = 1.0;
        }
    }
    Out[0] = l;
}
