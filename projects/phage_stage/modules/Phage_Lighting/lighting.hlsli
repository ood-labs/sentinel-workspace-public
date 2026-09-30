// Shared by the Lighting passes: slot layout, program rows, show state, the group definitions
// behind the canvas buttons, and the two canvas projections (front elevation, plan).
#include "../_shared/phage_slots.hlsli"
#include "../_shared/phage_show.hlsli"
#include "../_shared/phage_fixture.hlsli"
#define SEL_MAGIC 260935
#define SEL_SLOT0 4
#define SEL_WORD0 252
#define SEL_ROWS 268
#define GROUPS 16

// Groups behind the 16 canvas buttons: 0 ALL 1 NONE 2 MOVERS 3 STROBES 4 BARS 5 AXES 6 LEFT 7 RIGHT
// 8 PLATE 9 CAPSID 10 COLLAR 11 KNEES 12 FEET 13 BOOTH 14 LEGS 15 ODD (odd index within its family).
bool famIs(uint f,uint a,uint b,uint c,uint d){return f==a||f==b||f==c||f==d;}
bool inGroup(uint g,PhMount m){
 if(m.active<.5)return false;uint f=(uint)round(m.extra.x),k=(uint)round(m.kind);
 if(g==0)return true;if(g==1)return false;if(g>=2&&g<=5)return k==g-2;
 if(g==6)return m.rest.x<-.05;if(g==7)return m.rest.x>.05;
 if(g==8)return famIs(f,0,1,11,22);if(g==9)return famIs(f,2,14,25,26)||f==31;
 if(g==10)return famIs(f,4,10,23,24);if(g==11)return famIs(f,3,12,3,12);if(g==12)return famIs(f,6,13,6,13);
 if(g==13)return famIs(f,5,15,27,27);if(g==14)return famIs(f,3,6,12,13)||famIs(f,20,21,32,32);
 return ((uint)round(m.extra.y)&1)==1;
}

// Canvas layout in pixels (follow_panel): two rows of group buttons, then the front elevation
// (left) and the plan (right), then the footer.
float4 buttonRect(uint i,float2 R){uint row=i/8,col=i%8;float x0=.012+col*.1225,y0=.035+row*.06;return float4(x0,y0,x0+.115,y0+.05)*R.xyxy;}
// Landscape panels put the views side by side; portrait panels stack them.
float4 viewRect(uint v,float2 R){if(R.y>R.x*.9)return v==0?float4(.012,.17,.988,.55)*R.xyxy:float4(.012,.57,.988,.93)*R.xyxy;
 return v==0?float4(.012,.17,.56,.93)*R.xyxy:float4(.58,.17,.988,.93)*R.xyxy;}
float viewScale(uint v,float2 R){float4 r=viewRect(v,R);float w=r.z-r.x,h=r.w-r.y;return v==0?min(w/40,h/26):min(w/40,h/40);}
float2 toView(uint v,float3 p,float2 R){float4 r=viewRect(v,R);float s=viewScale(v,R);float cx=(r.x+r.z)*.5;
 return v==0?float2(cx+p.x*s,r.w-10-p.y*s):float2(cx+p.x*s,(r.y+r.w)*.5+p.z*s);}
