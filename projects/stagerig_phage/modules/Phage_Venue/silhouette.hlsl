// The phage at rest as world-space line segments for the arena preview, computed on one thread so
// the per-pixel preview never runs the leg IK. V[0]=(capsid top at rest, capsid top at kinetic max,
// segments, magic) V[1]=(capsid centre y, capsid half width, -, -). Segment k: V[2+2k]=(a, style)
// V[3+2k]=(b, view). view 0 plan, 1 section; style 0 ink, 1 mid, 2 dim, 3 ring (a centre, b.x radius).
StructuredBuffer<float4> DesignIn:register(t0);
float4 phD(uint i){return DesignIn[i];}
#include "../_shared/phage_anatomy.hlsli"
RWStructuredBuffer<float4> V:register(u0);
#define SEGS 128
static uint gN;
void seg(float3 a,float3 b,float style,float view){if(gN>=SEGS)return;V[2+2*gN]=float4(a,style);V[3+2*gN]=float4(b,view);gN++;}
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){
 gN=0;
 if(_Data0_Count<PH_DESIGN_COUNT||DesignIn[16].w!=260929){V[0]=0;V[1]=0;return;}
 PhDesign D=phLoad();PhPose R=phRest();
 [loop]for(uint l=0;l<6;l++){float3 h=phHip(D,R,l),k=phKnee(D,R,l),a=phAnkle(D,R,l),f=phFootTip(D,R,l);
  seg(h,k,0,0);seg(k,a,0,0);seg(a,float3(3.4,0,0),3,0);
  seg(h,k,0,1);seg(k,a,0,1);seg(a,f,1,1);}
 float zlo=1e5,zhi=-1e5;
 [loop]for(uint e=0;e<6;e++){float3 p0=phPlateVertex(D,R,e,D.plateR,D.plateY),p1=phPlateVertex(D,R,e+1,D.plateR,D.plateY);
  seg(p0,p1,1,0);seg(phPlateVertex(D,R,e,D.plateInner,D.plateY),phPlateVertex(D,R,e+1,D.plateInner,D.plateY),2,0);zlo=min(zlo,p0.z);zhi=max(zhi,p0.z);}
 [loop]for(uint b=0;b<8;b++)seg(phBoothVertex(D,b),phBoothVertex(D,b+1),2,0);
 // section: plate block, sheath, collar, capsid, riser, booth ring
 float yt=phPlateTop(D,R),yb=yt-D.plateDepth,yc=phCollarY(D,R),ys=phSheathTop(D,R);
 seg(float3(0,yt,zlo),float3(0,yt,zhi),1,1);seg(float3(0,yb,zlo),float3(0,yb,zhi),1,1);seg(float3(0,yb,zlo),float3(0,yt,zlo),1,1);seg(float3(0,yb,zhi),float3(0,yt,zhi),1,1);
 seg(float3(0,yt,-D.sheathR),float3(0,ys,-D.sheathR),1,1);seg(float3(0,yt,D.sheathR),float3(0,ys,D.sheathR),1,1);
 seg(float3(0,yc,-D.collarR),float3(0,yc,D.collarR),1,1);
 [loop]for(uint c=0;c<36;c++){uint2 v=phCapEdge(c);seg(phCapVertex(D,R,v.x),phCapVertex(D,R,v.y),0,1);}
 float rz=D.riserD*.5;seg(float3(0,D.riserH,-rz),float3(0,D.riserH,rz),2,1);seg(float3(0,0,-rz),float3(0,D.riserH,-rz),2,1);seg(float3(0,0,rz),float3(0,D.riserH,rz),2,1);
 seg(float3(0,D.boothY,-D.boothR),float3(0,D.boothY,D.boothR),2,1);
 float3 cc=phCapCenter(D,R);float top=cc.y+2*D.capS*D.capK;
 // Kinetic envelope: body height +2.0 m and sheath extension 1.2 m (Phage_Kinetics limits) plus a mover head.
 V[0]=float4(top,top+2.0+1.2+.36*D.moverScale,gN,260932);V[1]=float4(cc.y,2*D.capS,2*D.capS*D.capK,0);
}
