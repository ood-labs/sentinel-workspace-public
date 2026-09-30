#include "f_marker.hlsli"
#include "sweep.hlsli"
struct Scan { float4 endpoints,color0,color1,timing,meta; };
RWStructuredBuffer<Scan> OutputBuffer:register(u0);
float2 endAt(int row,int endpoint) {
 float q=-extent+2*extent*(row%5)/4;
 float z=((row%2)==0?endpoint:1-endpoint)*2*extent-extent;
 return row<5?float2(z,q):float2(q,z);
}
// 0..9 grid lines, then the F orientation mark.
void litAt(int k,out float2 a,out float2 b){
 if(k<10){a=endAt(k,0);b=endAt(k,1);}
 else fStroke(k-10,extent,a,b);
 // The grid is drawn +y down (as the projector image is); a Scan Signal is ILDA +y up.
 a.y=-a.y;b.y=-b.y;
}
// Sync Sweep: the vertical line as one closed lit loop, up then back down, two records.
void sweepSignal(){
 float cycle=1.0/max(cycle_fps,1);
 float x=sweepX(_Time,extent,sweep_hz);
 Scan h=(Scan)0;h.endpoints=float4(2,cycle,30000,0);h.meta.w=1;OutputBuffer[0]=h;
 Scan r=(Scan)0;r.color0=r.color1=float4(line_color,1);r.meta=float4(0,1,cycle,1);
 r.endpoints=float4(x,-extent,x,extent);r.timing=float4(0,cycle*.5,0,0);OutputBuffer[1]=r;
 r.endpoints=float4(x,extent,x,-extent);r.timing=float4(cycle*.5,cycle*.5,0,0);OutputBuffer[2]=r;
 for(int j=3;j<1024;j++)OutputBuffer[j]=(Scan)0;
}
[numthreads(1,1,1)]
void main(uint3 id:SV_DispatchThreadID) {
 if(pattern>.5){sweepSignal();return;}
 const int N=10+F_STROKE_COUNT;
 float cycle=1.0/max(cycle_fps,1),blank=.0001;
 // Time each stroke by its length so scan velocity stays constant: the short
 // F strokes must not slow the galvos down, and adding them must not speed
 // the long grid lines up.
 float total=0;float2 a,b;
 for(int k=0;k<N;k++){litAt(k,a,b);total+=length(b-a);}
 float perUnit=max(cycle-N*blank,cycle*.5)/max(total,1e-6);
 Scan h=(Scan)0;h.endpoints=float4(2*N,cycle,30000,0);h.meta.w=1;OutputBuffer[0]=h;
 float t=0;
 for(int i=0;i<N;i++){
  float2 p0,p1,n0,n1;litAt(i,p0,p1);litAt((i+1)%N,n0,n1);
  float dt=length(p1-p0)*perUnit;
  Scan r=(Scan)0;r.endpoints=float4(p0,p1);
  r.color0=r.color1=float4(line_color,1);
  r.timing=float4(t,dt,0,0);r.meta=float4(0,1,cycle,1);OutputBuffer[1+i*2]=r;
  r.endpoints=float4(p1,n0);r.color0=r.color1=0;
  r.timing=float4(t+dt,blank,0,1);OutputBuffer[2+i*2]=r;
  t+=dt+blank;
 }
 for(int j=1+2*N;j<1024;j++)OutputBuffer[j]=(Scan)0;
}
