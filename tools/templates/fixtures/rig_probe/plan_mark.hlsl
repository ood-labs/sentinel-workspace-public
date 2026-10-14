// Records the FixtureTypes generation the plan was built from and the format the plan pass wrote (Plan[0].r0.w),
// after every mode's thread of the plan pass ran.
#include "probe.hlsli"

RWStructuredBuffer<PlanRecord> Plan : register(u0);

[numthreads(1, 1, 1)]
void main()
{
    PlanRecord h;
    h.r0 = uint4(gdtfTablesValid() ? _Data1_Generation : 0u, gdtfTablesValid() ? gdtfSectionCount(GDTF_SECTION_MODES) : 0u,
                 Plan[0].r0.w, Plan[0].r0.w);
    h.r1 = 0u;
    Plan[0] = h;
}
