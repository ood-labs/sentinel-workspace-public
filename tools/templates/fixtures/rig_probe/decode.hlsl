// One thread per Fixtures record: the fixture state through gdtf_decode.hlsli.
#include "probe.hlsli"

RWStructuredBuffer<StateRecord> State : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= RP_FIXTURES) return;
    StateRecord r = (StateRecord)0;
    if (i < _Data0_Count && gdtfTablesValid() && gdtfFixtureDecodable(i))
    {
        GdtfFixture f = gdtfFixture(i);
        GdtfFixtureState s = gdtfFixtureState(f);
        r.s0 = float4(s.dimmer * (s.open ? 1.0 : 0.0), s.dimmer, s.pan, s.tilt);
        r.s1 = float4(s.rgb, s.open ? 1.0 : 0.0);
        r.s2 = float4((float)gdtfCellCount(f), (float)gdtfModeGlobal(f), 0.0, 1.0);
    }
    State[i] = r;
}
