#include "../_shared/rm_types.hlsli"
#include "yoke.hlsli"
#define PER_FIXTURE 11004
struct VOut{float4 Position:SV_POSITION;float3 world:TEXCOORD0;float3 normal:TEXCOORD1;float3 radiance:TEXCOORD2;float material:TEXCOORD3;float2 detail:TEXCOORD4;};
float edge(uint k,float e,float b){return k==0?-e:k==1?-e+b:k==2?e-b:e;}
static const float2 Profile[8]={float2(.080,.075),float2(.094,.060),float2(.098,-.062),float2(.098,-.076),float2(.096,-.077),float2(.076,-.077),float2(.071,-.073),float2(.067,-.070)};
VOut VSMain(uint vid:SV_VertexID){
 VOut o=(VOut)0;uint fi=vid/PER_FIXTURE,v=vid%PER_FIXTURE;
 if(fi>=min(288u,_Data0_Count)||_Data0[fi].active<.5){o.Position=float4(0,0,-1,1);return o;}
 RmPose r=_Data0[fi];float3 p=0,n=0;float2 detail=0;uint space=0,lamp=0;float mat=0;
 if(v<1944){
  uint b=v/324,local=v%324;float3 center=float3(0,.037,0),extent=float3(.125,.028,.094);
  if(b>=1&&b<=4){center=float3(b%2==0?.094:-.094,.008,b<3?-.065:.065);extent=float3(.016,.008,.019);}
  if(b==5){center=float3(0,.04,-.0945);extent=float3(.027,.010,.001);mat=5;}
  uint face=local/54,quad=(local%54)/6,c=local%6;
  uint ai=quad%3+((c==1||c==4||c==5)?1:0),bi=quad/3+((c==2||c==3||c==5)?1:0);
  float bevel=min(.006,min(extent.x,min(extent.y,extent.z))*.4);float3 cube;
  if(face<2)cube=float3(edge(ai,extent.x,bevel),edge(bi,extent.y,bevel),face==0?-extent.z:extent.z);
  else if(face<4)cube=float3(edge(ai,extent.x,bevel),face==2?-extent.y:extent.y,edge(bi,extent.z,bevel));
  else cube=float3(face==4?-extent.x:extent.x,edge(ai,extent.y,bevel),edge(bi,extent.z,bevel));
  float3 core=clamp(cube,-extent+bevel,extent-bevel);n=normalize(cube-core);p=center+core+n*bevel;detail=p.xy;
 }else if(v<1944+YOKE_VERTS){
  uint k=v-1944;space=1;mat=1;
  if(k<YOKE_FACE_VERTS*2){uint side=k/YOKE_FACE_VERTS;float2 q=YokePoints[YokeTriangles[k%YOKE_FACE_VERTS]];p=float3(q,side==0?-.04:.04);n=float3(0,0,side==0?-1:1);}
  else{uint local=k-YOKE_FACE_VERTS*2,seg=local/6,c=local%6;float u=(c==1||c==4||c==5)?1:0,w=(c==2||c==3||c==5)?1:0;
   float2 a=YokePoints[seg],b=YokePoints[(seg+1)%YOKE_POINTS],d=b-a;p=float3(lerp(a,b,u),lerp(-.04,.04,w));n=normalize(float3(d.y,-d.x,0));}
  detail=p.xy;
 }else if(v<1944+YOKE_VERTS+1728){
  uint k=v-1944-YOKE_VERTS,b=k/576,local=k%576,seg=local/12,c=local%12;
  float a=(seg+((c==1||c==4||c==5||c==8||c==11)?1:0))*6.2831853/48;
  float radius=b==0?.061:.014,halfLength=b==0?.013:.014;
  float2 radial=float2(cos(a),sin(a));float z=c<6?((c==0||c==1||c==4)?-halfLength:halfLength):(c<9?-halfLength:halfLength);
  n=c<6?float3(radial,0):float3(0,0,c<9?-1:1);if(c==6||c==9)radius=0;p=float3(radial*radius,z);
  if(b==0){p=rmX(p,1.5707963)+float3(0,.075,0);n=rmX(n,1.5707963);space=0;}
  else{p=rmY(p,1.5707963)+float3(b==1?-.104:.104,.152,0);n=rmY(n,1.5707963);space=1;}
  mat=1;
 }else if(v<1944+YOKE_VERTS+1728+4032){
  uint k=v-1944-YOKE_VERTS-1728,band=k/576,local=k%576,seg=local/6,c=local%6;
  float u=(c==1||c==4||c==5)?1:0,w=(c==2||c==3||c==5)?1:0;
  float a=(seg+u-2)*6.2831853/96;float2 radial=float2(sin(a),cos(a)),q=lerp(Profile[band],Profile[band+1],w),d=Profile[band+1]-Profile[band];
  p=float3(radial*q.x,q.y);n=normalize(float3(radial*(-d.y),d.x));space=2;mat=band==4?3:(band>=5?4:2);
  lamp=band==4?1+seg/4:0;detail=band==4?float2((seg+u)/4,q.x):float2(a,q.y);
 }else if(v<1944+YOKE_VERTS+1728+4032+2304){
  uint k=v-1944-YOKE_VERTS-1728-4032,band=k/576,local=k%576,seg=local/6,c=local%6;
  float u=(c==1||c==4||c==5)?1:0,w=(c==2||c==3||c==5)?1:0;
  float a=(seg+u)*6.2831853/96,rad=(band+w)*.067/4;
  float2 xy=float2(sin(a),cos(a))*rad;float z=-.045-.025*pow(rad/.067,2);
  p=float3(xy,z);n=normalize(float3(-xy*11.1383,-1));space=2;mat=6;detail=xy/.067;
 }else if(v<10668){
  uint k=v-10380,seg=k/3,c=k%3;float a=(seg+(c==2?1:0))*6.2831853/96;
  float2 xy=c==0?float2(0,0):float2(sin(a),cos(a))*.080;
  p=float3(xy,.075);n=float3(0,0,1);space=2;mat=7;detail=xy;
 }else{o.Position=float4(0,0,-1,1);return o;}
 if(space==2){o.world=rmHeadPoint(p,r);o.normal=rmHeadNormal(n,r);}
 else if(space==1){o.world=r.position+rmMount(float3(0,.075,0)+rmY(p,r.pan),r);o.normal=rmMount(rmY(n,r.pan),r);}
 else{o.world=r.position+rmMount(p,r);o.normal=rmMount(n,r);}
 RmOptical light=_Data1[fi*25+lamp];o.radiance=light.colour*light.intensity;o.material=mat;o.detail=detail;
 o.Position=mul(_ViewProjMatrix,float4(o.world,1));return o;
}
float4 PSMain(VOut i):SV_TARGET0{
 float3 n=normalize(i.normal),v=normalize(_CameraPos-i.world),key=normalize(float3(-.5,.8,-.6));
 float diffuse=.22+.78*saturate(dot(n,key)),spec=pow(saturate(dot(reflect(-key,n),v)),48);
 float3 col=(.025*diffuse+.10*spec)*worklight;
 if(i.material>.5&&i.material<1.5)col=(.038*diffuse+.13*spec)*worklight;
 if(i.material>1.5&&i.material<2.5){col=(.025*diffuse+.18*spec)*worklight;
  float vents=step(-.015,i.detail.y)*step(i.detail.y,.052)*(1-smoothstep(.24,.32,abs(frac(i.detail.y/.012)-.5)));
  col*=1-.8*vents;
 }
 if(i.material>2.5&&i.material<3.5){float cell=exp(-pow((frac(i.detail.x)-.5)*2,2)*2);col=(.018*diffuse+.30*spec)*worklight+i.radiance*(1.2+cell);}
 if(i.material>3.5&&i.material<4.5)col=(.045*diffuse+.45*spec)*worklight;
 if(i.material>4.5&&i.material<5.5)col=float3(.008,.014,.018)*worklight;
 if(i.material>5.5&&i.material<6.5){float rad=length(i.detail),center=exp(-rad*rad*32),rings=.97+.03*cos(rad*160);col=(.10*diffuse+.7*spec)*worklight+i.radiance*(.35*rings+center*2.5);}
 if(i.material>6.5){float radial=length(i.detail);float grille=smoothstep(.18,.3,abs(frac(radial/.008)-.5));col=(.02*diffuse+.06*spec)*worklight*lerp(.12,1,grille);}
 return float4(col,length(i.world-_CameraPos));
}
