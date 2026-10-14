// The axis under the pointer, shared by the marks pass (which lights that axis's members in both
// views) and the layout (which lights its meter row): a meter row, a leg pointed at in either view,
// the capsid above the collar or the body below it. -1 when the pointer is elsewhere. The pointer is
// read live and never stored. Include after phage_anatomy, kin_common and kin_view.
float kvSeg(float2 p,float2 a,float2 b){float2 pa=p-a,ba=b-a;return length(pa-ba*saturate(dot(pa,ba)/max(dot(ba,ba),1e-6)));}

int kvHoverAxis(float2 R,PhDesign D,PhPose P){
 float2 uv=_ViewportPointerPosition,p=uv*R;
 if(any(uv<0)||any(uv>1))return -1;
 float top=kvRowTop(R),rh=kvRowH(R);
 if(p.y>=top&&p.y<top+8*rh&&p.x>12&&p.x<R.x-12)return (int)floor((p.y-top)/rh);
 bool plan=ilIn(p,kvPlanRect(R)),elev=ilIn(p,kvElevRect(R));
 if(!plan&&!elev)return -1;
 int hit=-1;float best=10*kvS(R);
 [loop]for(uint leg=0;leg<6;leg++){
  float3 h=phHip(D,P,leg),k=phKnee(D,P,leg),a=phAnkle(D,P,leg);
  float2 h2=plan?kvPlan(h,R):kvElev(h,R),k2=plan?kvPlan(k,R):kvElev(k,R),a2=plan?kvPlan(a,R):kvElev(a,R);
  float d=min(kvSeg(p,h2,k2),kvSeg(p,k2,a2));
  if(d<best){best=d;hit=2+(int)leg;}}
 if(hit>=0)return hit;
 if(plan)return length(p-kvPlan(float3(0,0,0),R))<(D.plateR+.5)*kvPlanScale(R)?0:-1;
 float es=kvElevScale(R);float2 o=kvElevOrigin(R);float2 w=float2(p.x-o.x,o.y-p.y)/es;   // metres
 float3 cc=phCapCenter(D,P);float ch=2*D.capS*D.capK;
 if(abs(w.x)<2.4*D.capS&&w.y>phCollarY(D,P)-.3&&w.y<cc.y+ch+.3)return 1;
 if(abs(w.x)<D.plateR+.3&&w.y>D.plateY+P.bodyH-D.plateDepth&&w.y<=phCollarY(D,P)-.3)return 0;
 return -1;
}

// Whether a truss member belongs to axis k: BODY is the plate and the hips, CAPSID the sheath, the
// collar and the capsid (spin and contraction), LEG n everything on that leg. meta=(id,part,kind,leg).
bool kvMemberOf(float4 meta,int k){
 if(k<0)return false;
 bool sheath=meta.x>=18&&meta.x<54;
 if(k==0)return meta.y==1&&!sheath;
 if(k==1)return meta.y==2||meta.y==3||sheath;
 return meta.w==(float)(k-2);
}
