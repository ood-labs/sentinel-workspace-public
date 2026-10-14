// One thread per (fixture, cell): the cell's colour mix and its own dimmer level. CellColour[i * RP_CELLS + c].
#include "probe.hlsli"

RWStructuredBuffer<float4> CellColour : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x / RP_CELLS, c = id.x % RP_CELLS;
    if (i >= min(_Data0_Count, RP_FIXTURES) || !gdtfTablesValid() || !gdtfFixtureDecodable(i)) return;
    GdtfFixture f = gdtfFixture(i);
    if (c >= gdtfCellCount(f)) return;
    CellColour[id.x] = float4(gdtfColour(f, c), gdtfCellIntensity(f, c));
}
