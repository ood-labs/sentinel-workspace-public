// The axonometric shared by the marks, hover and preview passes and the layout: yaw -28 deg, pitch
// 16 deg. The scene projects from 26.5 m above the floor origin (the capsid, at the back) to 6 m
// below it (the front feet), so that 32.5 m band by 46 m across is fitted and centred under the header.
#include "../_shared/ui/il_core.hlsli"
float axoS(float2 R){return max(ilCtx(R).s,.85);}
float axoHead(float2 R){return 34*axoS(R);}   // the header strip: the kit draws the title and counts
float axoScale(float2 R){return min((R.x-40)/46.0,(R.y-axoHead(R)-24)/32.5);}
float2 axoOrigin(float2 R){float s=axoScale(R),h=R.y-axoHead(R)-24;return float2(R.x*.5,axoHead(R)+12+26.5*s+.5*(h-32.5*s));}
float2 axoAt(float3 p,float2 R){float yaw=radians(-28),pit=radians(16);float x=cos(yaw)*p.x+sin(yaw)*p.z,z=-sin(yaw)*p.x+cos(yaw)*p.z;
 return axoOrigin(R)+float2(x,-(p.y*cos(pit)-z*sin(pit)))*axoScale(R);}
// Mark layout: 18 floor grid lines, 138 members, 64 solids, then the counts record (tubes, solids,
// members).
#define AM_GRID 0
#define AM_MEMBERS 18
#define AM_SOLIDS 156
#define AM_MARKS 220
#define AM_REC 220
#define AM_TOTAL 221
#define AM_MEMBER_KIND 50
#define AM_SOLID_KIND 51
