// Shared by the Lighting passes: slot layout, program rows, show state, the group definitions behind the canvas
// buttons (mirrored in scripts/show/static_rig.luau), and the two canvas projections (front elevation, plan).
#include "../_shared/ss_slots.hlsli"
#include "../_shared/ss_show.hlsli"
#include "../_shared/ss_fixture.hlsli"
#define SEL_MAGIC 260935
#define SEL_SLOT0 4
#define SEL_WORD0 (SEL_SLOT0+SS_SLOTS)
#define SEL_WORDS SS_PRESENCE_WORDS
#define SEL_ROWS (SEL_WORD0+SEL_WORDS)
#define GROUPS 16

// Groups behind the 16 canvas buttons: 0 ALL 1 NONE 2 HEADS 3 STROBES 4 WALL (by type) 5 FRONT ROW 6 BACK ROW
// (the two rows of heads) 7 LEFT 8 RIGHT 9 INNER 10 MIDDLE 11 OUTER (by distance from the centre line: under 2 m,
// 2-4 m, 4 m and out) 12 ODD 13 EVEN (index within its family) 14 TRUSS STROBES 15 FLOOR STROBES (the two strobe
// lines). Families are tools/ss_stage.py's: 0 front row, 1 back row, 10 truss strobes, 11 floor strobes, 20 the wall.
bool inGroup(uint g,SsMount m){
 if(m.active<.5)return false;uint f=(uint)round(m.extra.x),k=(uint)round(m.kind);float x=abs(m.rest.x);
 if(g==0)return true;if(g==1)return false;if(g>=2&&g<=4)return k==g-2;
 if(g==5)return k==0&&f==0;if(g==6)return k==0&&f==1;
 if(g==7)return m.rest.x<-.05;if(g==8)return m.rest.x>.05;
 if(g==9)return x<2.0;if(g==10)return x>=2.0&&x<4.0;if(g==11)return x>=4.0;
 if(g==12)return ((uint)round(m.extra.y)&1)==1;if(g==13)return ((uint)round(m.extra.y)&1)==0;
 if(g==14)return k==1&&f==10;return k==1&&f==11;
}

// Canvas layout in pixels (follow_panel): two rows of group buttons, then the front elevation (left) and the plan
// (right), then the footer. Both views fit the structure (ss_stage.hlsli SS_BOUNDS) with a margin.
float4 buttonRect(uint i,float2 R){uint row=i/8,col=i%8;float x0=.012+col*.1225,y0=.035+row*.06;return float4(x0,y0,x0+.115,y0+.05)*R.xyxy;}
// Landscape panels put the views side by side; portrait panels stack them.
float4 viewRect(uint v,float2 R){if(R.y>R.x*.9)return v==0?float4(.012,.17,.988,.55)*R.xyxy:float4(.012,.57,.988,.93)*R.xyxy;
 return v==0?float4(.012,.17,.56,.93)*R.xyxy:float4(.58,.17,.988,.93)*R.xyxy;}
float viewScale(uint v,float2 R){float4 r=viewRect(v,R);float w=r.z-r.x,h=r.w-r.y-24;float across=2*SS_BOUNDS.x+1.2;
 return v==0?min(w/across,h/(SS_BOUNDS.y+1.0)):min(w/across,h/(2*SS_BOUNDS.z+1.4));}
float2 toView(uint v,float3 p,float2 R){float4 r=viewRect(v,R);float s=viewScale(v,R);float cx=(r.x+r.z)*.5;
 return v==0?float2(cx+p.x*s,r.w-14-p.y*s):float2(cx+p.x*s,(r.y+r.w)*.5+8+p.z*s);}
