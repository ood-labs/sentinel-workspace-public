// BLINK_Previs / raw10.hlsli: the RAW 10 FB4 housing SDF and materials from laser_lab LS_Air
// fixture.hlsl (1563058e), unchanged.
float sdBox(float3 p,float3 b){float3 q=abs(p)-b;return length(max(q,0))+min(max(q.x,max(q.y,q.z)),0);}
float rawPart(float3 p,uint i,float yoke){
 uint partKind=(uint)RAW_CENTRES[i].w;
 if(partKind==1||partKind==2){float2 q=p.yz-float2(-.049,-.175);p.yz=float2(cos(yoke)*q.x+sin(yoke)*q.y,-sin(yoke)*q.x+cos(yoke)*q.y)+float2(-.049,-.175);}
 float3 q=p-RAW_CENTRES[i].xyz,b=RAW_SIZES[i];uint kind=(uint)RAW_CENTRES[i].w;
 float bevel=kind==0?.002:.0006;
 float d=sdBox(q,b-bevel)-bevel;
 if(kind==0){
  // Recessed aperture through the front wall, stopping at the scanner cavity.
  d=max(d,-sdBox(p-float3(0,0,-.012),float3(.032,.023,.020)));
 }
 if(kind==6)d=max(d,-sdBox(p-float3(0,0,-.002),float3(.032,.023,.020)));
 if(kind==3){float2 c=float2(length(q.yz)-b.y,abs(q.x)-b.x);d=min(max(c.x,c.y),0)+length(max(c,0));}
 if(kind==2){
  float x=p.x-round(p.x/.095)*.095;
  d=max(d,-(length(float2(x,p.z+.175))-.005));
 }
 return d;
}
float2 rawSDF(float3 p,float yoke){
 float2 hit=float2(1000,0);
 [loop]for(uint i=0;i<RAW_PART_COUNT;i++){float d=rawPart(p,i,yoke);if(d<hit.x)hit=float2(d,i);}
 return hit;
}
float2 boundsHit(float3 ro,float3 rd){
 float3 a=(float3(-.176,-.272,-.400)-ro)/(rd+1e-15),b=(float3(.176,.174,.050)-ro)/(rd+1e-15);
 float3 lo=min(a,b),hi=max(a,b);return float2(max(lo.x,max(lo.y,lo.z)),min(hi.x,min(hi.y,hi.z)));
}
float3 finishMaterial(float3 p,float3 n,float3 worldN,float3 view,uint part,float power){
 uint kind=(uint)RAW_CENTRES[part].w;
 float3 base=kind==4?.008:((kind==1||kind==2||kind==3)?.04:.022);
 float metal=(kind==1||kind==2||kind==3)?.65:.12;
 // Lower side cooling slots, powder-coated body and panel seams.
 if(kind==0&&abs(n.x)>.75&&p.y<-.045&&p.z<-.025&&p.z>-.305){
  float slot=step(abs(frac((p.z+.30)/.006)-.5),.20);base*=lerp(1,.12,slot);
 }
 if(kind==0&&abs(n.x)>.75&&abs(p.y+.047)<.0007)base*=.25;
 if(kind==0&&n.z>.8){
  // Small emission indicator follows optical power.
  if(length(p.xy-float2(0,.032))<.0023)return power>0?float3(.35,.008,.002):float3(.025,0,0);
  float2 labelP=p.xy-float2(.084,-.021);
  bool label=abs(labelP.x)<.021&&abs(labelP.y)<.011;
  if(label){base=float3(.42,.33,.025);if(abs(labelP.x)>.019||abs(labelP.y)>.009)base=.008;
   if(abs(labelP.x)<.016&&abs(labelP.y)<.006&&frac((labelP.y+.006)*1300)<.4)base=.015;}
  // Four front-panel screw heads.
  if(length(float2(abs(p.x)-.11,p.y+.055))<.0024){base=.32;metal=.9;}
 }
 if(kind==5&&abs(p.x)<.021&&abs(p.y+.058)<.01){base=float3(.42,.33,.025);if(abs(p.x)>.019||abs(p.y+.058)>.008)base=.008;
  if(abs(p.x)<.016&&abs(p.y+.058)<.006&&frac((p.y+.064)*1300)<.4)base=.015;}
 if(kind==6&&length(float2(abs(p.x)-.043,p.y+.021))<.003){base=.35;metal=.9;}
 if(kind==7){
  float2 q=p.xy;
  float sockets=length(float2((frac((q.x+.095)/.03)-.5)*.03,q.y+.050));
  if(abs(q.x)<.102&&sockets<.010){base=sockets>.007?.23:.006;metal=.8;}
  if(abs(q.x)<.016&&abs(q.y-.005)<.013)base=float3(.015,.07,.095);
 }
 float3 l=normalize(float3(-.6,.9,.8));float diffuse=max(dot(worldN,l),0);
 float sky=.35+.25*worldN.y;
 float spec=pow(max(dot(worldN,normalize(l+view)),0),32)*metal;
 return fixture_light*(base*(sky+diffuse*1.8)+spec*.2);
}
