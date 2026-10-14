// One-lane path draw: every lit record as a thin quad, in the record's colour, landed in the
// canvas's scanner field (am_view.hlsli: the same mapping the layout's hover inspector uses).
#include "../_shared/scan.hlsli"
#include "am_view.hlsli"
StructuredBuffer<Scan> A:register(t0);
struct VS_OUTPUT{float4 Position:SV_POSITION;float3 Color:COLOR0;};
VS_OUTPUT VSMain(uint vid:SV_VertexID){VS_OUTPUT o=(VS_OUTPUT)0;o.Position=float4(0,0,-999,1);
uint i=vid/6+1,v=vid%6;Scan h=A[0];
if(i>min((uint)h.endpoints.x,1023u))return o;Scan q=A[i];if(q.timing.w>.5)return o;
AMLayout L=amLayout(_Resolution.xy);
float2 a=amFieldPx(L,q.endpoints.xy),b=amFieldPx(L,q.endpoints.zw); // scanner +y up, screen +y down
float2 dv=b-a,n=float2(-dv.y,dv.x)/max(length(dv),.001)*.8;
bool atEnd=v==1||v==2||v==4;float side=v==0||v==1||v==3?-1:1;float2 uv=((atEnd?b:a)+n*side)/_Resolution;
o.Position=float4(uv*float2(2,-2)+float2(-1,1),0,1);o.Color=atEnd?q.color1.rgb:q.color0.rgb;return o;}
float4 PSMain(VS_OUTPUT i):SV_TARGET{return float4(i.Color,1);}
