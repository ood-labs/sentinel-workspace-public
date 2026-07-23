#include "types.hlsli"
RWTexture2D<float4> OutputUAV:register(u0);

LoftSection sectionAt(uint i){LoftSection s=(LoftSection)0;if(i>=_Data0_Count)return s;s.center=float3(_Data0[i].center[0],_Data0[i].center[1],_Data0[i].center[2]);s.radius_x=_Data0[i].radius_x;s.radius_z=_Data0[i].radius_z;s.rotation=_Data0[i].rotation;s.curvature=_Data0[i].curvature;s.u=_Data0[i].u;s.floor_band=_Data0[i].floor_band;s.skin_bias=_Data0[i].skin_bias;s.void_bias=_Data0[i].void_bias;s.active=_Data0[i].active;s.tangent=float3(_Data0[i].tangent[0],_Data0[i].tangent[1],_Data0[i].tangent[2]);s.seed=_Data0[i].seed;return s;}
MaterialRecord materialAt(uint i){MaterialRecord m=(MaterialRecord)0;if(_Data2_Count==0u)return m;i=min(i,_Data2_Count-1u);m.base_color=float3(_Data2[i].base_color[0],_Data2[i].base_color[1],_Data2[i].base_color[2]);m.roughness=_Data2[i].roughness;m.secondary_color=float3(_Data2[i].secondary_color[0],_Data2[i].secondary_color[1],_Data2[i].secondary_color[2]);m.metallic=_Data2[i].metallic;m.texture_scale=_Data2[i].texture_scale;m.texture_strength=_Data2[i].texture_strength;m.pattern_id=_Data2[i].pattern_id;m.emissive=_Data2[i].emissive;m.specular=_Data2[i].specular;m.normal_strength=_Data2[i].normal_strength;m.seed=_Data2[i].seed;m.reserved=_Data2[i].reserved;return m;}
float sdRoundBoxLocal(float3 p,float3 b,float r){float3 q=abs(p)-b+r;return length(max(q,0))+min(max(q.x,max(q.y,q.z)),0)-r;}
float rot2x(float2 p,float a){return p.x*cos(a)-p.y*sin(a);}
float2 rotate2(float2 p,float a){float c=cos(a),s=sin(a);return float2(c*p.x-s*p.y,s*p.x+c*p.y);}

float shellDistance(float3 p,out float shellU,out float2 shellQ,out LoftSection sec){
 shellU=0;shellQ=0;sec=(LoftSection)0;if(_Data0_Count<2u)return 1000;
 LoftSection first=sectionAt(0),last=sectionAt(min(_Data0_Count,96u)-1u);float bottom=min(first.center.y,last.center.y),top=max(first.center.y,last.center.y);shellU=saturate((p.y-bottom)/max(top-bottom,.001));float fi=shellU*(float)(min(_Data0_Count,96u)-1u);uint ia=(uint)floor(fi),ib=min(ia+1u,min(_Data0_Count,96u)-1u);float f=frac(fi);LoftSection a=sectionAt(ia),b=sectionAt(ib);
 sec.center=lerp(a.center,b.center,f);sec.radius_x=lerp(a.radius_x,b.radius_x,f);sec.radius_z=lerp(a.radius_z,b.radius_z,f);sec.rotation=lerp(a.rotation,b.rotation,f);sec.curvature=lerp(a.curvature,b.curvature,f);sec.u=shellU;sec.floor_band=lerp(a.floor_band,b.floor_band,f);sec.skin_bias=lerp(a.skin_bias,b.skin_bias,f);sec.void_bias=lerp(a.void_bias,b.void_bias,f);sec.active=1;sec.tangent=normalize(lerp(a.tangent,b.tangent,f)+1e-5);sec.seed=lerp(a.seed,b.seed,f);
 shellQ=rotate2(p.xz-sec.center.xz,-sec.rotation);float exponent=lerp(2.0,4.8,shell_roundness);float radial=pow(pow(abs(shellQ.x)/max(sec.radius_x,.1),exponent)+pow(abs(shellQ.y)/max(sec.radius_z,.1),exponent),1.0/exponent)-1.0;float d=radial*min(sec.radius_x,sec.radius_z);
 float cap=max(bottom-p.y,p.y-top);d=max(d,cap);
 float canyonCenter=sin(shellU*6.283+sec.seed*.001)*sec.radius_x*.20;float2 cq=float2((shellQ.x-canyonCenter)/max(sec.radius_x*.24,.1),shellQ.y/max(sec.radius_z*1.1,.1));float voidD=(length(cq)-1.0)*min(sec.radius_x*.24,sec.radius_z);d=max(d,-voidD*canyon_strength);
 return d;
}

float sceneDistance(float3 p,out float objectId){
 float u;float2 q;LoftSection s;float shell=shellDistance(p,u,q,s);objectId=1;
 LoftSection first=sectionAt(0);float podium=sdRoundBoxLocal(p-float3(first.center.x,first.center.y-.68,first.center.z),float3(first.radius_x*1.22,.72,first.radius_z*1.20),.42);if(podium<shell){shell=podium;objectId=2;}
 float groundY=first.center.y-1.40;float ground=p.y-groundY;if(ground<shell){shell=ground;objectId=0;}
 float ring=abs(length((p.xz-first.center.xz)*float2(1.0,.78))-first.radius_x*1.65)-.10;ring=max(ring,abs(p.y-(groundY+.035))-.035);if(ring<shell){shell=ring;objectId=3;}
 return shell;
}

float3 calcNormal(float3 p){float e=.015;float id;float dx=sceneDistance(p+float3(e,0,0),id)-sceneDistance(p-float3(e,0,0),id);float dy=sceneDistance(p+float3(0,e,0),id)-sceneDistance(p-float3(0,e,0),id);float dz=sceneDistance(p+float3(0,0,e),id)-sceneDistance(p-float3(0,0,e),id);return normalize(float3(dx,dy,dz));}

void nearestClone(float3 p,out float best,out uint bestIndex){best=1000;bestIndex=0;[loop]for(uint i=0u;i<_Data1_Count;i+=2u){if(_Data1[i].active<.5)continue;float3 c=float3(_Data1[i].position[0],_Data1[i].position[1],_Data1[i].position[2]);float d=length(p-c);if(d<best){best=d;bestIndex=i;}}}

float3 shade(float3 p,float3 n,float3 rd,float objectId){
 if(objectId<.5){float g=fbm3D(p*float3(.8,2.0,.8),4)*0.5+0.5;return lerp(float3(.018,.022,.027),float3(.055,.060,.064),g)+float3(.025,.020,.016);}
 float u;float2 q;LoftSection sec;shellDistance(p,u,q,sec);float angle=atan2(q.y/max(sec.radius_z,.1),q.x/max(sec.radius_x,.1))/6.2831853+.5;float rib=pow(1.0-smoothstep(.02,.11,abs(frac(angle*16.0+u*helix_detail)-.5)),rib_sharpness);float floorLine=pow(1.0-smoothstep(.015,.09,abs(frac(u*floor_detail)-.5)),3.0);float cell=step(.5,frac(floor(angle*16.0)+floor(u*floor_detail)));
 uint matId=objectId>2.5?4u:(objectId>1.5?2u:(cell>.5?3u:1u));float nearest;uint cloneIndex;nearestClone(p,nearest,cloneIndex);float emissive=0;
 if(nearest<clone_influence&&cloneIndex<_Data1_Count){matId=(uint)clamp(_Data1[cloneIndex].material_id,0.0,(float)max((int)_Data2_Count-1,0));emissive=_Data1[cloneIndex].emissive;rib=max(rib,smoothstep(clone_influence,0.0,nearest));}
 MaterialRecord m=materialAt(matId);float grain=fbm3D(p*m.texture_scale*.9+float3(m.seed*.01,0,0),4)*.5+.5;float3 base=lerp(m.base_color,m.secondary_color,grain*m.texture_strength);base=lerp(base,materialAt(5u).base_color,rib*.72);base=lerp(base,materialAt(3u).base_color,(1-rib)*glass_mix*.62);
 float3 sun=normalize(float3(cos(sun_orbit.x*6.283)*cos((sun_orbit.y-.5)*2.2),sin((sun_orbit.y-.5)*2.2),sin(sun_orbit.x*6.283)*cos((sun_orbit.y-.5)*2.2)));float ndl=saturate(dot(n,sun));float3 sky=float3(.17,.26,.38)*(n.y*.5+.5)*sky_energy;float3 warm=float3(1.0,.54,.28)*pow(ndl,1.4)*sun_energy;float3 fill=float3(.08,.18,.25)*(0.32+0.68*saturate(dot(n,normalize(float3(-.6,.35,-.7)))));
 float3 h=normalize(sun-rd);float spec=pow(saturate(dot(n,h)),lerp(8,180,1-m.roughness))*m.specular;float edge=pow(1-saturate(dot(n,-rd)),3);float3 col=base*(.12+sky+warm+fill)+spec*float3(1,.72,.45)+edge*materialAt(3u).secondary_color*.22;
 col+=materialAt(9u).base_color*emissive*interior_gain*(.45+.55*floorLine);return col;
}

[numthreads(8,8,1)]
void main(uint3 tid:SV_DispatchThreadID){
 if(tid.x>=(uint)_Resolution.x||tid.y>=(uint)_Resolution.y)return;float2 suv=((float2)tid.xy+.5)/_Resolution.xy;float2 ndc=float2(suv.x*2-1,1-suv.y*2);float4 nearW=mul(_InvViewProjMatrix,float4(ndc,0,1));float4 farW=mul(_InvViewProjMatrix,float4(ndc,1,1));nearW/=nearW.w;farW/=farW.w;float3 ro=_CameraPos,rd=normalize(farW.xyz-nearW.xyz);
 float t=0;float objectId=0;bool hit=false;[loop]for(int step=0;step<max_steps;step++){float3 p=ro+rd*t;float d=sceneDistance(p,objectId);if(d<.012){hit=true;break;}t+=max(d*.72,.012);if(t>120)break;}
 float3 sky=lerp(float3(.004,.006,.013),float3(.055,.105,.16),saturate(rd.y*.5+.5));sky+=pow(saturate(dot(rd,normalize(float3(.22,.42,.88)))),48)*float3(.16,.32,.48);float3 col=sky;float depth=1;
 if(hit){float3 p=ro+rd*t,n=calcNormal(p);col=shade(p,n,rd,objectId);float fog=1-exp(-t*fog_density);col=lerp(col,sky,fog);depth=saturate(t/80.0);}OutputUAV[tid.xy]=float4(max(col,0),depth);
}
