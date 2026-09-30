// Kinetics shared: Design reader, pose from the axis state, member records.
// Axis state A: per axis k three records: [3k]=(pos a, pos b, vel a, vel b), [3k+1]=(target a,
// target b, previous raw a, unwrapped a), [3k+2]=(raw a, raw b, -, -); [24]=(magic, drive, time, -).
// Axis 0 BODY (height m, yaw deg), 1 CAPSID (spin deg, sheath contraction m), 2-7 LEG 0-5 (swing m, lift m).
#define AX_MAGIC 260930
#define AX_RECORDS 26
PhPose phPoseFrom(float4 a0,float4 a1,float4 l0,float4 l1,float4 l2,float4 l3,float4 l4,float4 l5){
 PhPose p;p.bodyH=a0.x;p.bodyYaw=a0.y;p.spin=a1.x;p.contract=a1.y;
 p.swing[0]=l0.x;p.lift[0]=l0.y;p.swing[1]=l1.x;p.lift[1]=l1.y;p.swing[2]=l2.x;p.lift[2]=l2.y;
 p.swing[3]=l3.x;p.lift[3]=l3.y;p.swing[4]=l4.x;p.lift[4]=l4.y;p.swing[5]=l5.x;p.lift[5]=l5.y;return p;}
#define PH_POSE_FROM(A) phPoseFrom(A[0],A[3],A[6],A[9],A[12],A[15],A[18],A[21])

// Truss member: a=(xyz, width) b=(xyz, kind) up=(orientation reference, profile) meta=(id, part, index, leg)
// Profiles: 0 box truss, 2 solid box, 3 cone (a=base, b=tip, width=base radius), 4 node, 5 figure.
struct PhMember{float4 a;float4 b;float4 up;float4 meta;};
PhMember phMem(float3 a,float3 b,float w,float kind,float3 up,float profile,float id,float part,float leg){
 PhMember m;m.a=float4(a,w);m.b=float4(b,kind);m.up=float4(up,profile);m.meta=float4(id,part,kind,leg);return m;}
PhMember phMember(PhDesign D,PhPose P,uint i){
 PhMember m=(PhMember)0;m.meta=float4(i,0,0,-1);float3 up=float3(0,1,0);
 if(i<18){uint e=i%6;float y=D.plateY;
  if(i<6)return phMem(phPlateVertex(D,P,e,D.plateR,y),phPlateVertex(D,P,e+1,D.plateR,y),D.legTruss,1,up,0,i,1,-1);
  if(i<12)return phMem(phPlateVertex(D,P,e,D.plateInner,y),phPlateVertex(D,P,e+1,D.plateInner,y),D.ringTruss,2,up,0,i,1,-1);
  return phMem(phPlateVertex(D,P,e,D.plateInner+D.ringTruss*.5,y),phPlateVertex(D,P,e,D.plateR-D.legTruss*.5,y),D.ringTruss,3,up,0,i,1,-1);}
 if(i<24){uint j=i-18;float y0=D.plateY+D.plateDepth*.5,y1=phSheathTop(D,P)-P.bodyH;
  return phMem(phPlateVertex(D,P,j,D.sheathR,y0),phPlateVertex(D,P,j,D.sheathR,y1),D.ringTruss*.55,4,phBodyDir(P,phDir(phLegAz(j))),0,i,1,-1);}
 if(i<54){uint k=(i-24)/6,e=(i-24)%6;float y=phSheathRingY(D,P,k)-P.bodyH;
  return phMem(phPlateVertex(D,P,e,D.sheathR,y),phPlateVertex(D,P,e+1,D.sheathR,y),D.ringTruss*.8,5,up,0,i,1,-1);}
 if(i<78){uint r=(i-54)/12,k=(i-54)%12;float y=phCollarY(D,P)-P.bodyH+(r==0?.24:-.24);
  float3 a=phBodyPoint(P,phDir(PH_TAU*k/12)*D.collarR+float3(0,y,0)),b=phBodyPoint(P,phDir(PH_TAU*(k+1)/12)*D.collarR+float3(0,y,0));
  return phMem(a,b,D.ringTruss*.8,6,up,0,i,2,-1);}
 if(i<114){uint e=i-78;uint2 v=phCapEdge(e);float3 a=phCapVertex(D,P,v.x),b=phCapVertex(D,P,v.y);
  return phMem(a,b,D.capTruss,7,normalize((a+b)*.5-phCapCenter(D,P)),0,i,3,-1);}
 if(i<126){uint j=i-114,leg=j/2,seg=j%2;float3 h=phHip(D,P,leg),k=phKnee(D,P,leg),a=phAnkle(D,P,leg);
  return phMem(seg==0?h:k,seg==0?k:a,D.legTruss,8+seg,phTan(phLegAz(leg)),0,i,4+leg,leg);}
 if(i<134){uint k=i-126;return phMem(phBoothVertex(D,k),phBoothVertex(D,k+1),D.ringTruss,10,up,0,i,0,-1);}
 if(i<138){uint k=1+2*(i-134);float3 v=phBoothVertex(D,k);return phMem(float3(v.x,0,v.z),v,D.ringTruss*.8,11,phDir(radians(22.5+45.0*k)),0,i,0,-1);}
 if(i<144){uint leg=i-138;float3 k=phKnee(D,P,leg);float s=D.legTruss*.85;return phMem(k-s,k+s,s,12,phTan(phLegAz(leg)),2,i,4+leg,leg);}
 if(i<150){uint leg=i-144;float3 h=phHip(D,P,leg);float s=D.legTruss*.8;return phMem(h-s,h+s,s,13,up,2,i,1,leg);}
 if(i<156){uint leg=i-150;return phMem(phAnkle(D,P,leg),phFootTip(D,P,leg),D.spikeR,14,up,3,i,10+leg,leg);}
 if(i<162){uint leg=i-156;float3 a=phAnkle(D,P,leg);float s=D.spikeR*1.15;return phMem(a-float3(s,.12,s),a+float3(s,.28,s),s,19,up,2,i,10+leg,leg);}
 if(i<186){uint v=i-162;float3 c=phCapVertex(D,P,v);float s=D.capTruss*.62;return phMem(c-s,c+s,s,15,up,2,i,3,-1);}
 if(i==186)return phMem(float3(-D.riserW*.5,0,-D.riserD*.5),float3(D.riserW*.5,D.riserH,D.riserD*.5),1,16,up,2,i,0,-1);
 if(i==187)return phMem(float3(-1.25,D.riserH,.35),float3(1.25,D.riserH+.95,1.15),1,17,up,2,i,0,-1);
 if(i==188)return phMem(float3(0,D.riserH,-.25),float3(0,D.riserH+1.82,-.25),.5,18,float3(0,0,1),5,i,0,-1);
 return m;
}
