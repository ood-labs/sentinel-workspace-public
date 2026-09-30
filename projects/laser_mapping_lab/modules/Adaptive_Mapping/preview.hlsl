// Screen preview gain only; scan data and physical intensity are untouched.
#include "../_shared/laser_text.hlsli"
StructuredBuffer<float4> S:register(t1);
float4 main(VS_OUTPUT i):SV_TARGET0{float2 q=i.Uv*_Resolution;
 float4 h=S[0],t=S[1];float3 c=saturate(_Tex0.SampleLevel(LinearSampler,i.Uv,0).rgb * 8.0);
 float text=lsText(q,float2(12,10),1,24);
 text=max(text,lsText(q,float2(12,28),1,3));text=max(text,lsNum(q,float2(155,28),1,h.x,4));text=max(text,lsNum(q,float2(195,28),1,h.y,4));
 text=max(text,lsText(q,float2(12,46),1,4));text=max(text,lsNum(q,float2(180,46),1,t.x*1e6,5));text=max(text,lsNum(q,float2(230,46),1,t.y*1e6,7));
 text=max(text,lsText(q,float2(12,_Resolution.y-25),1,h.z==0?5:(h.z==1?6:(h.z==2?7:8))));
 c=lerp(c,h.z>=2?PT_ALARM:PT_INK,text);return float4(c,1);}
