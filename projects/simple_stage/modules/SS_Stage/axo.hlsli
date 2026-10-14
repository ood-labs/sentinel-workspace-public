// The axonometric shared by the marks, hover and preview passes and the layout: yaw -28 deg, pitch 16 deg, seen from
// the audience side. The stage (its bounds from tools/ss_stage.py, with a margin for the fixtures) is fitted and
// centred under the header.
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ss_slots.hlsli"
#include "../_shared/ss_stage.hlsli"
static const float AXO_YAW=radians(-28),AXO_PIT=radians(16);
static const float AXO_HX=SS_BOUNDS.x+.7,AXO_HZ=max(SS_BOUNDS.z,SS_RANK.y)+.7,AXO_TOP=SS_RANK.w+1.1;
static const float AXO_W=2*(AXO_HX*abs(cos(AXO_YAW))+AXO_HZ*abs(sin(AXO_YAW)));      // projected width (m)
static const float AXO_Z=AXO_HX*abs(sin(AXO_YAW))+AXO_HZ*abs(cos(AXO_YAW));
static const float AXO_VMAX=AXO_TOP*cos(AXO_PIT)+AXO_Z*sin(AXO_PIT);                  // highest projected point
static const float AXO_H=AXO_TOP*cos(AXO_PIT)+2*AXO_Z*sin(AXO_PIT);                   // projected height (m)
float axoS(float2 R){return max(ilCtx(R).s,.85);}
float axoHead(float2 R){return 34*axoS(R);}   // the header strip: the kit draws the title and counts
float axoScale(float2 R){return min((R.x-40)/AXO_W,(R.y-axoHead(R)-24)/AXO_H);}
float2 axoOrigin(float2 R){float s=axoScale(R),h=R.y-axoHead(R)-24;return float2(R.x*.5,axoHead(R)+12+AXO_VMAX*s+.5*(h-AXO_H*s));}
float2 axoAt(float3 p,float2 R){float x=cos(AXO_YAW)*p.x+sin(AXO_YAW)*p.z,z=-sin(AXO_YAW)*p.x+cos(AXO_YAW)*p.z;
 return axoOrigin(R)+float2(x,-(p.y*cos(AXO_PIT)-z*sin(AXO_PIT)))*axoScale(R);}
// Mark layout: 22 floor grid lines (1 m), the truss members, the solids, one mark per slot, then the counts record
// (tubes, solids, members, fixtures).
#define AM_GRID 0
#define AM_GRID_N 11
#define AM_MEMBERS 22
#define AM_SOLIDS (AM_MEMBERS+SS_MEMBERS)
#define AM_FIX (AM_SOLIDS+SS_SOLID_COUNT)
#define AM_MARKS (AM_FIX+SS_SLOTS)
#define AM_REC AM_MARKS
#define AM_TOTAL (AM_MARKS+1)
#define AM_MEMBER_KIND 50
#define AM_SOLID_KIND 51
#define AM_FIX_KIND 52
// A fixture's drawing anchor: a head's body centre (beside its mount, away from the truss), a strobe's face, the
// middle of a run.
float3 axoFixturePoint(SsMount m){return m.kind<.5?m.position+m.up*.28*SS_MOVER_SCALE:m.position;}
