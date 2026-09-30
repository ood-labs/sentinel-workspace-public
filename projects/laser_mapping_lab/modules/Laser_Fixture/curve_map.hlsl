#include "curve.hlsli"
RWStructuredBuffer<uint4> OutputBuffer:register(u0);
[numthreads(1,1,1)]
void main(uint3 id:SV_DispatchThreadID){
 uint n=StreamCount()>0?min((uint)Stream[0].endpoints.x,min(StreamCount()-1,1023u)):0;
 uint bank=clamp(projector_count,1,4);
 uint limit=min((uint)clamp(curve_steps,1,8),max(1u,4095u/max(n*bank,1u)));
 uint index=1;
 if(input_is_sent_stream){
  // A Sent Stream is a sample path (see project.hlsl). A smooth stroke arrives as hundreds of
  // tiny, nearly collinear sample steps, and Laser Previs pays ~15 us per beam at 1080p. So each
  // run of lit records whose sample points stay within Beam Merge Tolerance of one straight chord
  // becomes ONE beam, x = first record, w = last record (at most 32). Blank records emit nothing.
  uint j=1;
  [loop]for(uint guard=0;guard<1024&&j<=n&&index<4095;guard++){
   if(Stream[j].timing.w>.5){j++;}
   else{
    uint k=j;float2 a=Stream[j].endpoints.xy;
    [loop]for(uint g=0;g<32;g++){
     uint kn=k+1;if(kn>n||Stream[kn].timing.w>.5)break;
     float2 b=Stream[kn<n?kn+1:1].endpoints.xy;bool ok=true;
     [loop]for(uint q=j+1;q<=kn;q++){float2 p=Stream[q].endpoints.xy,d=b-a;ok=ok&&length(p-a-d*saturate(dot(p-a,d)/max(dot(d,d),1e-12)))<=beam_merge_tolerance;}
     if(!ok)break;
     k=kn;
    }
    OutputBuffer[index++]=uint4(j,0,1,k);
    j=k+1;
   }
  }
 }else{
 for(uint j=1;j<=n;j++){
  uint steps=curve_smoothing<=0?1:limit;
  if(adaptive_curves){
   float2 a=Stream[j].endpoints.xy,b=Stream[j].endpoints.zw;
   float deviation=0;
   [unroll]for(int k=1;k<4;k++){
    float t=k*.25;
    deviation=max(deviation,length(curvePoint(j,n,t)-lerp(a,b,t)));
   }
   steps=clamp((uint)ceil(sqrt(deviation/max(curve_tolerance,1e-7))),1u,limit);
  }
  for(uint sub=0;sub<steps;sub++)OutputBuffer[index++]=uint4(j,sub,steps,j);
 }
 }
 OutputBuffer[0]=uint4(index-1,n,limit,0);
}
