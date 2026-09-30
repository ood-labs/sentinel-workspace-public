#include "../_shared/plan_theme.hlsli"
struct Beam { float4 origin; float4 direction0; float4 direction1; float4 color0; float4 color1; float4 timing; float4 meta; };
StructuredBuffer<Beam> Beams:register(t0);
RWTexture2D<float4> OutputUAV:register(u0);
// Room frame: drywall face at z = 0 on the left, the laser ~5 m out on the right.
// Top half: plan (x across), bottom half: elevation (y up). 10 m spans the width.
float2 plot(float3 pos,bool side){return float2(pos.z/10+0.05,(side?pos.y-1.5:pos.x)/10);}
float distSeg(float2 p,float2 a,float2 b){float h=saturate(dot(p-a,b-a)/max(dot(b-a,b-a),1e-9));return length(p-lerp(a,b,h));}
[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID){
 if(any(id.xy>=(uint2)_Resolution))return;
 float2 uv=(id.xy+0.5)/_Resolution;bool side=uv.y>0.5;
 float2 p=float2(uv.x,(side?0.75:0.25)-uv.y);float px=1/_Resolution.x;
 float3 col=PT_FIELD;
 if(abs(uv.y-0.5)<px)col=PT_RULE;
 for(uint i=1;i<=(uint)Beams[0].origin.x;i++){
  Beam b=Beams[i];if(b.timing.w>0.5||b.timing.y<=0)continue;
  float2 a=plot(b.origin.xyz,side),v=plot(b.origin.xyz+b.direction0.xyz*b.direction1.w,side);
  float d=distSeg(p,a,v);
  float strength=length(b.direction1.xyz-b.direction0.xyz)<1e-5?0.4:((i%16==0)?0.28:0.028);
  col+=ptSampleColour(b.color0.rgb/max(power,0.001))*(1-smoothstep(px,px*2,d))*strength;
  col=lerp(col,PT_INK,1-smoothstep(px*2,px*4,length(p-a)));
 }
 OutputUAV[id.xy]=float4(min(col,1),1);
}
