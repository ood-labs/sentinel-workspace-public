// PHAGE anatomy: the one construction model for the rig.
// Phage_Plan draws it at rest, Phage_Kinetics poses it every frame, and
// tools/phage_rig.py mirrors it line for line to aim fixtures for the look banks.
// Units are metres. y is up, +z faces the audience, azimuth runs from +z toward +x.
//
// The includer defines `float4 phD(uint i)` (the Design record reader) first.
#ifndef PHAGE_ANATOMY_HLSLI
#define PHAGE_ANATOMY_HLSLI

#include "../_shared/phage_slots.hlsli"

// Truncated octahedron in unit coordinates: 6 squares (+x,-x,+y,-y,+z,-z), 4 cyclic vertices each.
static const float3 PH_CAP_V[24]={float3(2,1,0),float3(2,0,1),float3(2,-1,0),float3(2,0,-1),float3(-2,1,0),float3(-2,0,-1),float3(-2,-1,0),float3(-2,0,1),float3(1,2,0),float3(0,2,-1),float3(-1,2,0),float3(0,2,1),float3(1,-2,0),float3(0,-2,1),float3(-1,-2,0),float3(0,-2,-1),float3(1,0,2),float3(0,-1,2),float3(-1,0,2),float3(0,1,2),float3(1,0,-2),float3(0,1,-2),float3(-1,0,-2),float3(0,-1,-2)};
// Hexagon-to-hexagon links: 4 top (touching +y), 4 middle, 4 bottom (touching -y).
static const uint2 PH_CAP_LINK[12]={uint2(0,8),uint2(4,10),uint2(9,21),uint2(11,19),uint2(1,16),uint2(3,20),uint2(5,22),uint2(7,18),uint2(2,12),uint2(6,14),uint2(13,17),uint2(15,23)};

struct PhDesign{
 float plateY,plateR,plateInner,plateDepth;
 float sheathR,collarY,collarR,capS;
 float capK,kneeR,kneeY,footR;
 float ankleY,boothR,boothY,riserH;
 float riserW,riserD,legTruss,capTruss;
 float ringTruss,moverScale,strobeLen,spikeR;
 float4 movers0;   // plate outer per edge, plate inner per edge, capsid vertices on, movers per knee
 float4 movers1;   // collar, booth, feet on, -
 float4 strobes0;  // collar, plate per edge, knees on, feet on
 float4 strobes1;  // capsid faces on, booth, -, -
 float4 leg[6];    // foot radial, foot tangential, knee radial, knee height (hand edits, metres)
};
PhDesign phLoad(){
 PhDesign d;float4 a=phD(0);d.plateY=a.x;d.plateR=a.y;d.plateInner=a.z;d.plateDepth=a.w;
 a=phD(1);d.sheathR=a.x;d.collarY=a.y;d.collarR=a.z;d.capS=a.w;
 a=phD(2);d.capK=a.x;d.kneeR=a.y;d.kneeY=a.z;d.footR=a.w;
 a=phD(3);d.ankleY=a.x;d.boothR=a.y;d.boothY=a.z;d.riserH=a.w;
 a=phD(4);d.riserW=a.x;d.riserD=a.y;d.legTruss=a.z;d.capTruss=a.w;
 a=phD(5);d.ringTruss=a.x;d.moverScale=a.y;d.strobeLen=a.z;d.spikeR=a.w;
 d.movers0=phD(6);d.movers1=phD(7);d.strobes0=phD(8);d.strobes1=phD(9);
 [unroll]for(uint i=0;i<6;i++)d.leg[i]=phD(10+i);
 return d;
}

// Live pose. Kinetics owns it; the plan draws the rest pose (all zero).
struct PhPose{float bodyH,bodyYaw,spin,contract;float lift[6];float swing[6];};
PhPose phRest(){PhPose p=(PhPose)0;return p;}

float3 phRotY(float3 p,float a){float s=sin(a),c=cos(a);return float3(c*p.x+s*p.z,p.y,-s*p.x+c*p.z);}
float3 phDir(float az){return float3(sin(az),0,cos(az));}
float3 phTan(float az){return float3(cos(az),0,-sin(az));}
float phLegAz(uint i){return radians(30.0+60.0*(float)i);}
float3 phBodyPoint(PhPose P,float3 p){return phRotY(p,radians(P.bodyYaw))+float3(0,P.bodyH,0);}
float3 phBodyDir(PhPose P,float3 v){return phRotY(v,radians(P.bodyYaw));}

// ---- legs: hip on the plate, foot planted in the world, knee solved by two-bone IK ----
float3 phHipRest(PhDesign D,uint i){return phDir(phLegAz(i))*D.plateR+float3(0,D.plateY,0);}
float3 phKneeRest(PhDesign D,uint i){return phDir(phLegAz(i))*(D.kneeR+D.leg[i].z)+float3(0,D.kneeY+D.leg[i].w,0);}
float3 phAnkleRest(PhDesign D,uint i){float az=phLegAz(i);return phDir(az)*(D.footR+D.leg[i].x)+phTan(az)*D.leg[i].y+float3(0,D.ankleY,0);}
float3 phHip(PhDesign D,PhPose P,uint i){return phBodyPoint(P,phHipRest(D,i));}
float3 phAnkle(PhDesign D,PhPose P,uint i){
 float az=phLegAz(i);float lift=max(0,P.lift[i]);
 return phAnkleRest(D,i)+float3(0,lift,0)-phDir(az)*lift*.3+phTan(az)*P.swing[i];
}
float phUpperLen(PhDesign D,uint i){return length(phKneeRest(D,i)-phHipRest(D,i));}
float phLowerLen(PhDesign D,uint i){return length(phAnkleRest(D,i)-phKneeRest(D,i));}
// Knees fold up and out, like the reference's raised elbows.
float3 phKnee(PhDesign D,PhPose P,uint i){
 float3 h=phHip(D,P,i),a=phAnkle(D,P,i);float L1=phUpperLen(D,i),L2=phLowerLen(D,i);
 float3 v=a-h;float d=max(length(v),1e-4);float3 u=v/d;
 d=clamp(d,abs(L1-L2)+.02,L1+L2-.02);
 float x=(L1*L1-L2*L2+d*d)/(2*d),y=sqrt(max(L1*L1-x*x,0));
 float3 pole=normalize(phDir(phLegAz(i))*.35+float3(0,1,0));
 float3 p=pole-u*dot(pole,u);p=p/max(length(p),1e-4);
 return h+u*x+p*y;
}
// How far the posed foot asks the leg to stretch (1 = fully straight). Above ~.98 the plan draws red.
float phReach(PhDesign D,PhPose P,uint i){return length(phAnkle(D,P,i)-phHip(D,P,i))/(phUpperLen(D,i)+phLowerLen(D,i));}
float3 phFootTip(PhDesign D,PhPose P,uint i){return phAnkle(D,P,i)-float3(0,D.ankleY,0);}

// ---- body column: plate, tail sheath, collar, capsid ----
float phPlateTop(PhDesign D,PhPose P){return D.plateY+D.plateDepth*.5+P.bodyH;}
float phCollarY(PhDesign D,PhPose P){return D.collarY+P.bodyH-P.contract;}
float phSheathTop(PhDesign D,PhPose P){return phCollarY(D,P)-.34;}
float phSheathRingY(PhDesign D,PhPose P,uint k){return lerp(phPlateTop(D,P)+.22,phSheathTop(D,P)-.08,(float)k/4.0);}
float3 phCapCenter(PhDesign D,PhPose P){return float3(0,phCollarY(D,P)+.45+2*D.capS*D.capK,0);}
float phCapYaw(PhPose P){return radians(P.bodyYaw+P.spin);}
float3 phCapLocal(PhDesign D,uint v){float3 c=PH_CAP_V[v];return float3(c.x,c.y*D.capK,c.z)*D.capS;}
float3 phCapVertex(PhDesign D,PhPose P,uint v){return phCapCenter(D,P)+phRotY(phCapLocal(D,v),phCapYaw(P));}
float3 phCapNormal(PhDesign D,PhPose P,uint v){float3 c=PH_CAP_V[v];return phRotY(normalize(float3(c.x,c.y/D.capK,c.z)),phCapYaw(P));}
float3 phCapFaceAxis(uint f){return f==0?float3(1,0,0):f==1?float3(-1,0,0):f==2?float3(0,1,0):f==3?float3(0,-1,0):f==4?float3(0,0,1):float3(0,0,-1);}
// Edges 0-23 walk the six squares, 24-35 are the hexagon links.
uint2 phCapEdge(uint e){uint j=min(e>=24?e-24:0,11u);uint2 l=PH_CAP_LINK[j];return e<24?uint2(e,(e/4)*4+(e%4+1)%4):l;}

// Outer hexagon vertex e (0-5) sits under leg e; inner hexagon shares the azimuths.
float3 phPlateVertex(PhDesign D,PhPose P,uint e,float r,float y){return phBodyPoint(P,phDir(phLegAz(e%6))*r+float3(0,y,0));}
// Booth ring: an octagon with a flat front edge.
float3 phBoothVertex(PhDesign D,uint k){float az=radians(22.5+45.0*(float)(k%8));return phDir(az)*D.boothR/cos(radians(22.5))+float3(0,D.boothY,0);}
float3 phBoothPerimeter(PhDesign D,float t){float s=frac(t)*8;uint k=(uint)floor(s);return lerp(phBoothVertex(D,k),phBoothVertex(D,k+1),frac(s));}

// ---- fixture mounts (PhMount and the family codes are documented in phage_slots.hlsli) ----

// A mover frame whose neutral beam points along `beam` (made perpendicular to `up`).
void phFrame(inout PhMount m,float3 up,float3 beam){
 float3 b=beam-up*dot(beam,up);if(dot(b,b)<1e-6)b=abs(up.y)<.9?float3(0,1,0):float3(0,0,1);
 m.up=normalize(up);m.fwd=-normalize(b);
}
float phHash1(float x){return frac(sin(x*12.9898+4.1414)*43758.5453);}

PhMount phMoverMount(PhDesign D,PhPose P,uint s){
 PhMount m=(PhMount)0;m.fixture_id=s;m.kind=0;m.extra=float4(-1,0,-1,0);float3 down=float3(0,-1,0),up=float3(0,1,0);
 if(s<24){uint e=s/4,j=s%4,n=(uint)D.movers0.x;m.active=j<n?1:0;
  float t=((float)j+.5)/max(1.0,(float)n);float3 a=phDir(phLegAz(e))*D.plateR,b=phDir(phLegAz(e+1))*D.plateR;
  m.position=phBodyPoint(P,lerp(a,b,t)+float3(0,D.plateY-D.plateDepth*.5-.1,0));
  phFrame(m,down,phBodyDir(P,phDir(radians(60.0+60.0*e))));m.extra=float4(0,s,-1,1);}
 else if(s<36){uint k=s-24,e=k/2,j=k%2,n=(uint)D.movers0.y;m.active=j<n?1:0;
  float t=((float)j+.5)/max(1.0,(float)n);float3 a=phDir(phLegAz(e))*D.plateInner,b=phDir(phLegAz(e+1))*D.plateInner;
  m.position=phBodyPoint(P,lerp(a,b,t)+float3(0,D.plateY-D.plateDepth*.5-.1,0));
  phFrame(m,down,phBodyDir(P,phDir(radians(60.0+60.0*e))));m.extra=float4(1,k,-1,1);}
 else if(s<60){uint v=s-36;m.active=D.movers0.z>.5?1:0;float3 n=phCapNormal(D,P,v);
  m.position=phCapVertex(D,P,v)+n*(D.capTruss*.5+.06);phFrame(m,n,down);m.extra=float4(2,v,-1,3);}
 else if(s<72){uint k=s-60,i=k/2,j=k%2;m.active=j<(uint)D.movers0.w?1:0;float3 kn=phKnee(D,P,i),ov=phDir(phLegAz(i));
  m.position=kn+phTan(phLegAz(i))*(j==0?-.62:.62)+float3(0,D.legTruss*.5+.12,0);phFrame(m,up,ov);m.extra=float4(3,k,i,4+i);}
 else if(s<84){uint k=s-72,n=(uint)D.movers1.x;m.active=k<n?1:0;float az=PH_TAU*(float)k/max(1.0,(float)n);
  m.position=phBodyPoint(P,phDir(az)*D.collarR+float3(0,phCollarY(D,P)-P.bodyH-.46,0));phFrame(m,down,phBodyDir(P,phDir(az)));m.extra=float4(4,k,-1,2);}
 else if(s<100){uint k=s-84,n=(uint)D.movers1.y;m.active=k<n?1:0;float t=((float)k+.5)/max(1.0,(float)n);
  float3 p=phBoothPerimeter(D,t);m.position=p+float3(0,-.34,0);float3 o=p;o.y=0;phFrame(m,down,normalize(o));m.extra=float4(5,k,-1,0);}
 else if(s<106){uint i=s-100;m.active=D.movers1.z>.5?1:0;float3 ov=phDir(phLegAz(i));
  m.position=phAnkle(D,P,i)+ov*.62+float3(0,.3,0);phFrame(m,up,ov);m.extra=float4(6,i,i,10+i);}
 else m.active=0;
 return m;
}

// Strobes: a 1 m linear tube between two RGB plates. fwd = emission, up = tube axis.
PhMount phStrobeMount(PhDesign D,PhPose P,uint s){
 PhMount m=(PhMount)0;m.fixture_id=PH_STROBE0+s;m.kind=1;m.extra=float4(-1,0,-1,0);
 if(s<6){uint n=(uint)D.strobes0.x;m.active=s<n?1:0;float az=PH_TAU*((float)s+.5)/max(1.0,(float)n);
  float3 o=phBodyDir(P,phDir(az));m.position=phBodyPoint(P,phDir(az)*(D.collarR+D.ringTruss*.5+.14)+float3(0,phCollarY(D,P)-P.bodyH,0));
  m.fwd=o;m.up=phBodyDir(P,phTan(az));m.extra=float4(10,s,-1,2);}
 else if(s<24){uint k=s-6,e=k/3,j=k%3,n=(uint)D.strobes0.y;m.active=j<n?1:0;
  float t=((float)j+.5)/max(1.0,(float)n);float3 a=phDir(phLegAz(e))*D.plateR,b=phDir(phLegAz(e+1))*D.plateR;
  float3 o=phDir(radians(60.0+60.0*e));m.position=phBodyPoint(P,lerp(a,b,t)+o*(D.legTruss*.5+.18)+float3(0,D.plateY+D.plateDepth*.2,0));
  m.fwd=phBodyDir(P,normalize(o*.94-float3(0,.34,0)));m.up=phBodyDir(P,normalize(b-a));m.extra=float4(11,k,-1,1);}
 else if(s<30){uint i=s-24;m.active=D.strobes0.z>.5?1:0;float3 o=phDir(phLegAz(i));
  m.position=phKnee(D,P,i)+o*(D.legTruss*.5+.24)-float3(0,.1,0);m.fwd=normalize(o-float3(0,.45,0));m.up=phTan(phLegAz(i));m.extra=float4(12,i,i,4+i);}
 else if(s<36){uint i=s-30;m.active=D.strobes0.w>.5?1:0;float3 o=phDir(phLegAz(i));
  m.position=phAnkle(D,P,i)+o*(D.spikeR+.12)-float3(0,.55,0);m.fwd=o;m.up=phTan(phLegAz(i));m.extra=float4(13,i,i,10+i);}
 else if(s<41){uint k=s-36,f=k<2?k:k+1;m.active=D.strobes1.x>.5?1:0;float3 ax=phCapFaceAxis(f);
  float dist=f==2?2*D.capS*D.capK:2*D.capS;float3 n=phRotY(ax,phCapYaw(P));
  m.position=phCapCenter(D,P)+n*(dist+D.capTruss*.5+.1);m.fwd=n;m.up=phRotY(f==2?float3(1,0,0):float3(0,1,0),phCapYaw(P));m.extra=float4(14,k,-1,3);}
 else if(s<47){uint k=s-41,n=(uint)D.strobes1.y;m.active=k<n?1:0;
  // Four across the riser front, then one on each flank.
  if(k<4){m.position=float3(lerp(-D.riserW*.36,D.riserW*.36,(float)k/3.0),D.riserH*.55,D.riserD*.5+.14);m.fwd=float3(0,0,1);m.up=float3(1,0,0);}
  else{float side=k==4?-1:1;m.position=float3(side*(D.riserW*.5+.14),D.riserH*.55,0);m.fwd=float3(side,0,0);m.up=float3(0,0,1);}
  m.extra=float4(15,k,-1,0);}
 else m.active=0;
 return m;
}

// ---- pixel bars: each bar is a run of up to 12 straight pieces, facing `n`, u runs 0..1 along it ----
// Legs: bar = leg*4 + segment*2 + side; segment 0 hip->knee, 1 knee->ankle; side 0 faces the front.
uint phBarSegCount(uint b){
 if(b<24)return 1;if(b<30)return 1;if(b<35)return 6;if(b<37)return 12;if(b<43)return 4;if(b<46)return 4;if(b<47)return 8;return 0;}
float phBarFamily(uint b){return b<24?(((b%4)/2)==0?20:21):b<30?22:b<35?23:b<37?24:b<43?25:b<46?26:b<47?27:-1;}
void phBarPiece(PhDesign D,PhPose P,uint b,uint k,out float3 a,out float3 c,out float3 n){
 a=0;c=0;n=float3(0,0,1);
 if(b<24){uint i=b/4,seg=(b%4)/2,side=b%2;float3 h=phHip(D,P,i),kn=phKnee(D,P,i),an=phAnkle(D,P,i);
  float3 p0=seg==0?h:kn,p1=seg==0?kn:an;float3 t=phTan(phLegAz(i));float face=t.z>0?1:-1;if(side==1)face=-face;
  float3 off=t*face*(D.legTruss*.5+.035);a=p0+off+normalize(p1-p0)*(seg==0?.55:.35);c=p1+off-normalize(p1-p0)*(seg==0?.35:.5);n=t*face;}
 else if(b<30){uint e=b-24;float3 o=phBodyDir(P,phDir(radians(60.0+60.0*e)));float y=D.plateY+D.plateDepth*.05;
  a=phPlateVertex(D,P,e,D.plateR,y)+o*(D.legTruss*.5+.04);c=phPlateVertex(D,P,e+1,D.plateR,y)+o*(D.legTruss*.5+.04);
  float3 d=normalize(c-a);a+=d*.45;c-=d*.45;n=o;}
 else if(b<35){uint ring=b-30;float y=phSheathRingY(D,P,ring)-P.bodyH;float r=D.sheathR+D.ringTruss*.5+.035;
  a=phPlateVertex(D,P,k,r,y);c=phPlateVertex(D,P,k+1,r,y);n=phBodyDir(P,phDir(radians(60.0+60.0*k)));}
 else if(b<37){float y=phCollarY(D,P)-P.bodyH+(b==35?.24:-.24);float r=D.collarR+D.ringTruss*.5+.035;
  float a0=PH_TAU*(float)k/12,a1=PH_TAU*(float)(k+1)/12;a=phBodyPoint(P,phDir(a0)*r+float3(0,y,0));c=phBodyPoint(P,phDir(a1)*r+float3(0,y,0));
  n=phBodyDir(P,phDir(PH_TAU*((float)k+.5)/12));}
 else if(b<43){uint f=b-37;uint2 e=uint2(f*4+k,f*4+(k+1)%4);float3 va=phCapLocal(D,e.x),vc=phCapLocal(D,e.y);
  float3 o=normalize((va+vc)*.5);float3 off=o*(D.capTruss*.5+.035);float3 d=normalize(vc-va)*.3;
  a=phCapCenter(D,P)+phRotY(va+off+d,phCapYaw(P));c=phCapCenter(D,P)+phRotY(vc+off-d,phCapYaw(P));n=phRotY(o,phCapYaw(P));}
 else if(b<46){uint g=b-43;uint2 e=PH_CAP_LINK[g*4+k];float3 va=phCapLocal(D,e.x),vc=phCapLocal(D,e.y);
  float3 o=normalize((va+vc)*.5);float3 off=o*(D.capTruss*.5+.035);float3 d=normalize(vc-va)*.3;
  a=phCapCenter(D,P)+phRotY(va+off+d,phCapYaw(P));c=phCapCenter(D,P)+phRotY(vc+off-d,phCapYaw(P));n=phRotY(o,phCapYaw(P));}
 else if(b<47){float3 lift=float3(0,.16,0);float3 v0=phBoothVertex(D,k),v1=phBoothVertex(D,k+1);float3 o=(v0+v1)*.5;o.y=0;o=normalize(o);
  a=v0+o*(D.ringTruss*.5+.035)+lift;c=v1+o*(D.ringTruss*.5+.035)+lift;n=o;}
}
float phBarLeg(uint b){return b<24?(float)(b/4):-1;}
float phBarPart(uint b){return b<24?4+b/4:b<37?(b<35&&b>=30?1:(b<30?1:2)):b<46?3:0;}

// Kinetic axes: 0 BODY, 1 CAPSID, 2-7 LEG 0-5. Position is what the axis visibly moves.
PhMount phAxisMount(PhDesign D,PhPose P,uint k){
 PhMount m=(PhMount)0;m.fixture_id=PH_AXIS0+k;m.kind=3;m.active=1;m.up=float3(0,1,0);m.fwd=float3(0,0,1);
 if(k==0){m.position=float3(0,D.plateY+P.bodyH,0);m.extra=float4(30,0,-1,1);}
 else if(k==1){m.position=phCapCenter(D,P);m.extra=float4(31,0,-1,3);}
 else{uint i=k-2;m.position=phKnee(D,P,i);m.extra=float4(32,i,i,4+i);}
 return m;
}

PhMount phMountAt(PhDesign D,PhPose P,uint slot){
 if(slot<PH_STROBE0)return phMoverMount(D,P,slot);
 if(slot<PH_BAR0)return phStrobeMount(D,P,slot-PH_STROBE0);
 if(slot<PH_AXIS0){uint b=slot-PH_BAR0;PhMount m=(PhMount)0;m.fixture_id=slot;m.kind=2;uint n=phBarSegCount(b);m.active=n>0?1:0;
  float3 mid=0;for(uint k=0;k<n;k++){float3 a,c,nn;phBarPiece(D,P,b,k,a,c,nn);mid+=(a+c)*.5/max(1.0,(float)n);m.fwd+=nn;}
  m.position=mid;m.fwd=length(m.fwd)>1e-4?normalize(m.fwd):float3(0,0,1);m.up=float3(0,1,0);m.extra=float4(phBarFamily(b),b,phBarLeg(b),phBarPart(b));return m;}
 return phAxisMount(D,P,slot-PH_AXIS0);
}
PhMount phMountFull(PhDesign D,PhPose P,uint slot){
 PhMount m=phMountAt(D,P,slot);PhMount r=phMountAt(D,phRest(),slot);
 m.rest=float4(r.position,phHash1((float)slot*1.618+.37));return m;
}
#endif
