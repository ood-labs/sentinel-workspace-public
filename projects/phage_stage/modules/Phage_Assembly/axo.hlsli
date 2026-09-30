// The axonometric shared by the marks pass and the preview: yaw -28 deg, pitch 16 deg, floor origin
// near the bottom centre, 46 m x 27 m fitted to the canvas.
float axoScale(float2 R){return min((R.x-40)/46.0,(R.y-80)/27.0);}
float2 axoOrigin(float2 R){return float2(R.x*.5,R.y-34);}
float2 axoAt(float3 p,float2 R){float yaw=radians(-28),pit=radians(16);float x=cos(yaw)*p.x+sin(yaw)*p.z,z=-sin(yaw)*p.x+cos(yaw)*p.z;
 return axoOrigin(R)+float2(x,-(p.y*cos(pit)-z*sin(pit)))*axoScale(R);}
// Mark layout: 18 floor grid lines, 138 members, 64 solids, then the counts record (tubes, solids).
#define AM_GRID 0
#define AM_MEMBERS 18
#define AM_SOLIDS 156
#define AM_MARKS 220
#define AM_REC 220
#define AM_TOTAL 221
#define AM_MEMBER_KIND 50
#define AM_SOLID_KIND 51
