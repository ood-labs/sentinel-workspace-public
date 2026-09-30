// Motion-control canvas geometry shared by the marks pass and the preview: live plan (left) and
// front elevation (right) above the axis meters.
#define KV_HEAD 38.0
float4 kvPlanRect(float2 R){return float4(12,KV_HEAD,R.x*.42,R.y*.6);}
float4 kvElevRect(float2 R){return float4(R.x*.42+10,KV_HEAD,R.x-12,R.y*.6);}
float kvPlanScale(float2 R){float4 r=kvPlanRect(R);return min((r.z-r.x)/44,(r.w-r.y-20)/44);}
float2 kvPlanOrigin(float2 R){float4 r=kvPlanRect(R);return (r.xy+r.zw)*.5+float2(0,8);}
float kvElevScale(float2 R){float4 r=kvElevRect(R);return min((r.z-r.x)/40,(r.w-r.y-24)/24);}
float2 kvElevOrigin(float2 R){float4 r=kvElevRect(R);return float2((r.x+r.z)*.5,r.w-12);}
float2 kvPlan(float3 p,float2 R){return kvPlanOrigin(R)+p.xz*kvPlanScale(R);}
float2 kvElev(float3 p,float2 R){return kvElevOrigin(R)+float2(p.x,-p.y)*kvElevScale(R);}
// Marks: plan rest ghost (12 lines), plan members (189), live ankle rings (6), elevation rest ghost
// (12), elevation members (189). Clip 1 = plan, clip 2 = elevation.
#define KM_PGHOST 0
#define KM_PMEM 12
#define KM_PANK 201
#define KM_EGHOST 207
#define KM_EMEM 219
#define KM_MARKS 408
