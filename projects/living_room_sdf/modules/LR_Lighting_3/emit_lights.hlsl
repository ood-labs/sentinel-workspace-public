struct LightRecord {
    float3 position; float type_id;
    float3 direction; float range;
    float3 color; float intensity;
    float2 size; float softness; float enabled;
};
RWStructuredBuffer<LightRecord> OutputBuffer : register(u0);

float3 archPos(uint i){ return float3(_Data0[i].position[0],_Data0[i].position[1],_Data0[i].position[2]); }
float3 furnPos(uint i){ return float3(_Data1[i].position[0],_Data1[i].position[1],_Data1[i].position[2]); }

LightRecord makeLight(float3 p,float typeId,float3 direction,float rangeValue,float3 colorValue,
                      float intensityValue,float2 sizeValue,float softnessValue)
{
    LightRecord l; l.position=p; l.type_id=typeId; l.direction=normalize(direction);
    l.range=rangeValue; l.color=colorValue; l.intensity=intensityValue;
    l.size=sizeValue; l.softness=softnessValue; l.enabled=1.0; return l;
}

[numthreads(8,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=id.x; if(i>=6)return;
    float3 warm=float3(1.0,.61,.30); float3 sky=float3(.58,.76,1.0);
    LightRecord l=makeLight(float3(0,3,0),3,float3(-.25,-1,.18),20,sky,ambient_fill,float2(0,0),1);
    if(i==0){ float3 p=archPos(min(5u,_Data0_Count-1)); l=makeLight(p+float3(0,.55,.16),0,float3(0,0,1),8,sky,daylight_intensity,float2(2.6,1.7),shadow_softness); }
    if(i==1){ float3 p=archPos(min(8u,_Data0_Count-1)); l=makeLight(p+float3(0,-.22,0),1,float3(0,-1,0),4.8,warm,practical_intensity,float2(.36,.36),shadow_softness); }
    if(i==2){ float3 p=archPos(min(9u,_Data0_Count-1)); l=makeLight(p+float3(0,-.22,0),1,float3(0,-1,0),4.8,warm,practical_intensity,float2(.36,.36),shadow_softness); }
    if(i==3){ float3 p=furnPos(min(12u,_Data1_Count-1)); l=makeLight(p+float3(0,1.52,0),1,float3(0,-.45,0),3.4,warm,practical_intensity*.78,float2(.28,.28),shadow_softness); }
    if(i==4){ float3 p=furnPos(min(13u,_Data1_Count-1)); l=makeLight(p+float3(0,.48,0),1,float3(0,-1,0),2.8,warm,practical_intensity*.62,float2(.20,.20),shadow_softness); }
    if(i==5) l=makeLight(float3(-1.5,2.8,1.6),3,float3(.25,-1,-.12),20,float3(.32,.43,.58),ambient_fill,float2(0,0),1);
    OutputBuffer[i]=l;
}
