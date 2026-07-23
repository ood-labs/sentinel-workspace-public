#include "types.hlsli"
StructuredBuffer<LightControlState> _Tex1:register(t1);
RWStructuredBuffer<LightRecord> OutputBuffer:register(u0);
LightRecord makeLight(float3 p,float kind,float3 dir,float radius,float3 colorValue,float power,float2 area,float soft){LightRecord l;l.position=p;l.type_id=kind;l.direction=normalize(dir);l.range=radius;l.color=colorValue;l.intensity=power;l.size=area;l.softness=soft;l.enabled=1;return l;}
float2 uiToWorld(float2 p){return lcCanvasToWorld(p);}

[numthreads(8,1,1)]
void main(uint3 id:SV_DispatchThreadID){
 uint i=id.x;if(i>=8)return;float2 sunXZ=uiToWorld(_Tex1[0].position);float sunRadius=max(length(sunXZ),.1);float az=atan2(sunXZ.x,sunXZ.y),el=radians(lerp(10.0,68.0,saturate(sunRadius/10.0)));float3 sunDir=normalize(float3(cos(el)*sin(az),sin(el),cos(el)*cos(az)));
 float3 warm=time_of_day==0?float3(1,.56,.27):float3(1,.43,.18);float3 sky=time_of_day==0?float3(.48,.64,.86):(time_of_day==1?float3(.24,.40,.72):float3(.10,.18,.34));float dayScale=time_of_day==0?1.0:(time_of_day==1?.40:.06);
 float2 keyXZ=uiToWorld(_Tex1[1].position),fillXZ=uiToWorld(_Tex1[2].position),canopyXZ=uiToWorld(_Tex1[3].position);
 LightRecord l=makeLight(float3(0,10,0),3,float3(0,-1,0),30,sky,sky_intensity,float2(0,0),1);
 if(i==0)l=makeLight(float3(0,18,0),0,sunDir,40,warm,sun_intensity*dayScale,float2(8,8),shadow_softness);
 if(i==1)l=makeLight(float3(-6,9,7),3,float3(.35,-1,-.35),30,sky,sky_intensity,float2(0,0),1);
 if(i==2)l=makeLight(float3(canopyXZ.x,3.05,canopyXZ.y),2,float3(0,-1,-.12),canopy_range,warm,interior_intensity,float2(4.5,1.2),shadow_softness);
 if(i==3)l=makeLight(float3(keyXZ.x,.55,keyXZ.y),1,float3(.12,1,-.10),practical_range,warm,interior_intensity*.55,float2(.18,.18),shadow_softness);
 if(i==4)l=makeLight(float3(fillXZ.x,.55,fillXZ.y),1,float3(-.12,1,-.10),practical_range,warm,interior_intensity*.55,float2(.18,.18),shadow_softness);
 if(i==5){float3 p=float3(-3.55,2.9,6.1);if(_Data0_Count>8)p=float3(_Data0[8].position[0],_Data0[8].position[1]+2.65,_Data0[8].position[2]);l=makeLight(p,1,float3(0,-1,0),6,warm,lamp_intensity,float2(.14,.14),shadow_softness);}
 if(i==6){float3 p=float3(3.55,2.9,6.1);if(_Data0_Count>9)p=float3(_Data0[9].position[0],_Data0[9].position[1]+2.65,_Data0[9].position[2]);l=makeLight(p,1,float3(0,-1,0),6,warm,lamp_intensity,float2(.14,.14),shadow_softness);}
 if(i==7)l=makeLight(float3(.7,10.75,-.7),2,float3(0,-1,.15),9,float3(.42,.68,1),interior_intensity*.75,float2(5.5,3),shadow_softness);
 OutputBuffer[i]=l;
}
