#include "f_marker.hlsli"
#include "sweep.hlsli"
RWTexture2D<float4> OutputUAV:register(u0);
float segDist(float2 p,float2 a,float2 b){
 float2 d=b-a;float t=saturate(dot(p-a,d)/max(dot(d,d),1e-12));
 return length(p-(a+d*t));
}
// Sync Sweep on the projector: the line full height, and the latency ruler (see sweep.hlsli).
float3 sweepPixel(float2 p){
 float2 s=_Resolution*.5;                         // [-1,1] to pixels
 float hw=line_width*.5;
 float x=sweepX(_Time,extent,sweep_hz);
 float c=0;
 if(abs(p.y)<=extent)c=1-smoothstep(hw,hw+1,abs(p.x-x)*s.x);
 float band=.1*extent,tick=0;
 for(int k=1;k<=SWEEP_TICKS;k++){
  float len=(k%5==0?2:1)*band;
  float xl=sweepX(_Time-k*SWEEP_TICK_S,extent,sweep_hz);   // where the line was: laser late
  float xe=sweepX(_Time+k*SWEEP_TICK_S,extent,sweep_hz);   // where it will be: laser early
  float w=1-smoothstep(hw,hw+1,abs(p.x-xl)*s.x);
  if(p.y>=-extent&&p.y<=-extent+len)tick=max(tick,w);
  w=1-smoothstep(hw,hw+1,abs(p.x-xe)*s.x);
  if(p.y<=extent&&p.y>=extent-len)tick=max(tick,w);
 }
 return line_color*max(c,.55*tick);
}
[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID){
 if(any(id.xy>=(uint2)_Resolution))return;
 float2 p=(id.xy+.5)/_Resolution*2-1;
 if(pattern>.5){OutputUAV[id.xy]=float4(sweepPixel(p),1);return;}
 float2 grid=abs(p/extent*2-round(p/extent*2))*extent*.5;
 float2 px=2/_Resolution;
 float coverage=max(1-smoothstep(line_width*px.x*.5,(line_width*.5+1)*px.x,grid.x),
                    1-smoothstep(line_width*px.y*.5,(line_width*.5+1)*px.y,grid.y));
 if(any(abs(p)>extent+px*line_width*.5))coverage=0;
 // Same F, same coordinates as the scan signal. Measured in pixels so the
 // stroke lands at line_width on both axes, exactly like the grid lines.
 float2 s=_Resolution*.5;float fd=1e9;
 [unroll]for(int k=0;k<F_STROKE_COUNT;k++){
  float2 a,b;fStroke(k,extent,a,b);
  fd=min(fd,segDist(p*s,a*s,b*s));
 }
 coverage=max(coverage,1-smoothstep(line_width*.5,line_width*.5+1,fd));
 OutputUAV[id.xy]=float4(line_color*coverage,1);
}
