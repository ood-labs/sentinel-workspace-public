// Motion-control canvas geometry shared by the marks pass, the preview and the layout: live plan
// (left) and front elevation (right) above the axis meters, sized from the live panel extent.
#include "../_shared/ui/il_core.hlsli"
float kvS(float2 R){return max(ilCtx(R).s,.85);}
float kvHead(float2 R){return 38*kvS(R);}
float kvSplit(float2 R){return floor(R.y*.6);}
float4 kvPlanRect(float2 R){return float4(12,kvHead(R),floor(R.x*.42),kvSplit(R));}
float4 kvElevRect(float2 R){return float4(floor(R.x*.42)+10,kvHead(R),R.x-12,kvSplit(R));}
float kvPlanScale(float2 R){float4 r=kvPlanRect(R);return min((r.z-r.x)/44,(r.w-r.y-20*kvS(R))/44);}
float2 kvPlanOrigin(float2 R){float4 r=kvPlanRect(R);return (r.xy+r.zw)*.5+float2(0,8*kvS(R));}
float kvElevScale(float2 R){float4 r=kvElevRect(R);return min((r.z-r.x)/40,(r.w-r.y-24*kvS(R))/24);}
float2 kvElevOrigin(float2 R){float4 r=kvElevRect(R);return float2((r.x+r.z)*.5,r.w-12*kvS(R));}
float2 kvPlan(float3 p,float2 R){return kvPlanOrigin(R)+p.xz*kvPlanScale(R);}
float2 kvElev(float3 p,float2 R){return kvElevOrigin(R)+float2(p.x,-p.y)*kvElevScale(R);}
// Meters: eight axis rows under the views (BODY, CAPSID, LEG 1-6), two channels each.
float kvRowTop(float2 R){return kvSplit(R)+8;}
float kvRowH(float2 R){return (R.y-kvSplit(R)-16)/8;}
// Marks: plan rest ghost (12 lines), plan members (189), live ankle rings (6), elevation rest ghost
// (12), elevation members (189). Clip 1 = plan, clip 2 = elevation.
#define KM_PGHOST 0
#define KM_PMEM 12
#define KM_PANK 201
#define KM_EGHOST 207
#define KM_EMEM 219
#define KM_MARKS 408
