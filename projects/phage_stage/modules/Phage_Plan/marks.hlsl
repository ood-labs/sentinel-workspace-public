// Canvas marks for the construction plan: every anatomy-derived stroke of the plan (clip 1) and of the
// section through the selected leg (clip 2), computed once per frame here instead of once per pixel,
// plus the records behind the readouts. Projections come from layout.hlsli, the same as picking.
StructuredBuffer<float4> E:register(t0);
#include "plan_design.hlsli"
#include "../_shared/phage_anatomy.hlsli"
StructuredBuffer<PhMount> RM:register(t1);
StructuredBuffer<float4> RQ:register(t2);
#include "../_shared/plan_theme.hlsli"
#include "layout.hlsli"
#include "../_shared/ph_marks.hlsli"
#include "plan_marks.hlsli"
RWStructuredBuffer<PhMark> Marks:register(u0);
PhMark mkLine(float2 a,float2 b,float w,float3 col,float alpha,uint clip){PhMark m=(PhMark)0;m.geo=float4(a,b);m.shape=float4(PHM_LINE,0,w,clip);m.stroke=float4(col,alpha);return m;}
PhMark mkDot(float2 p,float r,float3 col,uint clip){PhMark m=(PhMark)0;m.geo=p.xyxy;m.shape=float4(PHM_DOT,r,0,clip);m.fill=float4(col,1);return m;}
PhMark mkRing(float2 p,float r,float w,float3 col,float alpha,uint clip){PhMark m=(PhMark)0;m.geo=p.xyxy;m.shape=float4(PHM_RING,r,w,clip);m.stroke=float4(col,alpha);return m;}
PhMark mkDashRing(float2 p,float r,float period,float3 col,uint clip){PhMark m=mkRing(p,r,1,col,1,clip);m.shape.x=PHM_DASHRING;m.fill.x=period;return m;}
PhMark mkFrame(float4 r,float3 col,float alpha,uint clip){PhMark m=(PhMark)0;m.geo=r;m.shape=float4(PHM_FRAME,0,1,clip);m.stroke=float4(col,alpha);return m;}
[numthreads(64,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint i=tid.x;if(i>=PM_TOTAL)return;
 PhDesign D=phLoad();PhPose R=phRest();int sel=(int)E[0].x-1;bool sym=E[3].x>.5,dragging=E[0].z>.5;
 uint li=sel>=0?(uint)sel:0,op=(li+3)%6;PhMark m=phmHidden();
 // One call site per anatomy routine (FXC inlines every call): pick the leg and capsid edge this
 // thread needs, evaluate them once, then every branch below only projects.
 uint leg=9;
 if(i>=PM_LEGS&&i<PM_REACH)leg=(i-PM_LEGS)/5;else if(i==PM_REACH||i==PM_REC+1||(i>=PS_SEL&&i<PM_MARKS))leg=li;
 else if(i>=PS_LEGS&&i<PS_SEL)leg=(i-PS_LEGS)/4==0?li:op;
 float3 h=0,kn=0,an=0,tip=0;float upper=1,lower=1,reach=0;bool bad=false;
 if(leg<6){h=phHip(D,R,leg);kn=phKnee(D,R,leg);an=phAnkle(D,R,leg);tip=phFootTip(D,R,leg);upper=phUpperLen(D,leg);lower=phLowerLen(D,leg);
  reach=length(an-h)/(upper+lower);bad=reach>.985||kn.y<h.y+.5||length(an-phAnkle(D,R,(leg+1)%6))<3.0;}
 uint ce=99;if(i>=PM_CAP&&i<PM_BARS)ce=i-PM_CAP;else if(i>=PS_CAP&&i<PS_LEGS)ce=i-PS_CAP;
 float3 va=0,vb=0;if(ce<36){uint2 ve=phCapEdge(ce);va=phCapVertex(D,R,ve.x);vb=phCapVertex(D,R,ve.y);}
 if(i>=PM_REC){uint k=i-PM_REC;
  if(k==0){uint n0=0,n1=0,n2=0;[loop]for(uint f=0;f<PH_AXIS0;f++){PhMount mt=RM[f];if(mt.active<.5)continue;uint kind=min(2u,(uint)mt.kind);if(kind==0)n0++;else if(kind==1)n1++;else n2++;}
   m.fill=float4(n0,n1,n2,1);}
  else if(k==1)m.fill=float4(upper,lower,round(reach*100),bad?1:0);
  else m.fill=float4(D.riserD*.5+.9,li,0,0);
  Marks[i]=m;return;}
 float s=planScale();
 if(i==PM_RISER)m=mkFrame(float4(planPx(float3(-D.riserW*.5,0,-D.riserD*.5)),planPx(float3(D.riserW*.5,0,D.riserD*.5))),PT_RULE,.9,1);
 else if(i<PM_PLATE){uint k=i-PM_BOOTH;m=mkLine(planPx(phBoothVertex(D,k)),planPx(phBoothVertex(D,k+1)),1.4,PT_DIM,1,1);}
 else if(i<PM_COLLAR){uint e=(i-PM_PLATE)/4,part=(i-PM_PLATE)%4;
  float ra=part==3?D.sheathR:part==1?D.plateInner:D.plateR,rb=part==0?D.plateR:part==2?D.plateR:ra;
  float3 a=phPlateVertex(D,R,e,part==2?D.plateInner:ra,D.plateY),b=phPlateVertex(D,R,part==2?e:e+1,rb,D.plateY);
  m=mkLine(planPx(a),planPx(b),part==0?2.2:part==1?1.5:1.2,part==0?PT_MID:PT_DIM,1,1);}
 else if(i==PM_COLLAR)m=mkRing(planPx(0),D.collarR*s,1.2,PT_DIM,.9,1);
 else if(i<PM_BARS)m=mkLine(planPx(va),planPx(vb),1,PT_RULE,.7,1);
 else if(i<PM_MOUNTS){uint bi=i-PM_BARS;float4 a=RQ[bi*2];if(a.w>.5)m=mkLine(planPx(a.xyz),planPx(RQ[bi*2+1].xyz),1.6,ptId(2),.85,1);}
 else if(i<PM_LEGS){PhMount mt=RM[i-PM_MOUNTS];if(mt.active>.5){float2 mp=planPx(mt.position);
   if(mt.kind<.5)m=mkDot(mp,3.2,ptId(0),1);
   else{float2 ax=float2(mt.up.x,mt.up.z);ax=dot(ax,ax)>1e-4?normalize(ax)*4.5:float2(4.5,0);m=mkLine(mp-ax,mp+ax,2.2,ptId(1),1,1);}}}
 else if(i<PM_REACH){uint part=(i-PM_LEGS)%5;
  bool on=sel==(int)leg,mir=sym&&sel>=0&&mirrorLeg((uint)sel)==leg;
  float3 col=bad?PT_ALARM:on?PT_ACCENT:mir?lerp(PT_INK,PT_ACCENT,.45):PT_INK;
  if(part<2)m=mkLine(planPx(part==0?h:kn),planPx(part==0?kn:an),on?3.0:2.2,col,1,1);
  else if(part==2)m=mkDot(planPx(an),D.spikeR*s+.5,col*.8,1);
  else if(part==3)m=mkRing(planPx(an),9,1.2,on&&dragging?PT_ACCENT:PT_MID,1,1);
  else if(any(abs(E[4+leg])>.01))m=mkDot(planPx(an)+float2(12,-12),2.6,PT_MID,1);}
 else if(i==PM_REACH){if(sel>=0){float L=upper+lower,dy=h.y-an.y;m=mkDashRing(planPx(h),sqrt(max(L*L-dy*dy,0))*s,7,PT_DIM,1);}}
 else{
  // ---- section through the selected leg
  float az=phLegAz(li),ss=sectScale();float2 o=sectOrigin();float3 d3=phDir(az);
  if(i==PS_RISER){float ext=abs(d3.x)*D.riserW*.5+abs(d3.z)*D.riserD*.5;m=mkFrame(float4(o.x-ext*ss,o.y-D.riserH*ss,o.x+ext*ss,o.y),PT_RULE,1,2);}
  else if(i<PS_BOOTH){float2 dj=o+float2(0,-D.riserH*ss);if(i==PS_DJ)m=mkLine(dj,dj-float2(0,1.45*ss),2,PT_MID,1,2);else m=mkRing(dj-float2(0,1.62*ss),.17*ss,1.4,PT_MID,1,2);}
  else if(i<PS_PLATE){float sd=i==PS_BOOTH?-1:1;m=mkDot(sectPx(float3(0,D.boothY,0)+d3*sd*D.boothR,az),3,PT_DIM,2);}
  else if(i==PS_PLATE)m=mkFrame(float4(o.x-D.plateR*ss,o.y-(D.plateY+D.plateDepth*.5)*ss,o.x+D.plateR*ss,o.y-(D.plateY-D.plateDepth*.5)*ss),PT_MID,1,2);
  else if(i<PS_RINGS){float x=o.x+(i==PS_SHEATH?-1:1)*D.sheathR*ss;m=mkLine(float2(x,o.y-phPlateTop(D,R)*ss),float2(x,o.y-phSheathTop(D,R)*ss),1.4,PT_DIM,1,2);}
  else if(i<PS_COLLAR){float y=o.y-phSheathRingY(D,R,i-PS_RINGS)*ss;m=mkLine(float2(o.x-D.sheathR*ss,y),float2(o.x+D.sheathR*ss,y),1,PT_DIM,1,2);}
  else if(i==PS_COLLAR){float cy=phCollarY(D,R);m=mkFrame(float4(o.x-D.collarR*ss,o.y-(cy+.3)*ss,o.x+D.collarR*ss,o.y-(cy-.3)*ss),PT_MID,1,2);}
  else if(i<PS_LEGS)m=mkLine(sectPx(va,az),sectPx(vb,az),1.2,PT_MID,.8,2);
  else if(i<PS_SEL){uint t=(i-PS_LEGS)/4,part=(i-PS_LEGS)%4;
   float3 col=bad?PT_ALARM:(t==0&&sel>=0)?PT_ACCENT:t==0?PT_INK:PT_MID;
   float2 H2=sectPx(h,az),K2=sectPx(kn,az),A2=sectPx(an,az),T2=sectPx(tip,az);float2 sp=float2(D.spikeR*ss,0);
   if(part<2)m=mkLine(part==0?H2:K2,part==0?K2:A2,t==0?3:2,col,1,2);
   else m=mkLine(part==2?A2-sp:A2+sp,T2,1.5,col*.75,1,2);}
  else{uint part=i-PS_SEL;float2 H2=sectPx(h,az);
   if(part==0)m=mkDashRing(H2,upper*ss,6,PT_DIM,2);
   else if(part==1)m=mkRing(sectPx(kn,az),10,1.4,sel>=0&&dragging&&E[0].y>1.5?PT_ACCENT:PT_MID,1,2);
   else m=mkDot(H2,3,PT_INK,2);}
 }
 Marks[i]=m;}
