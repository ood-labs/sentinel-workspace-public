#include "mapping.hlsli"
RWStructuredBuffer<float4> OutputBuffer:register(u0);
// The editor's warped lattice, evaluated ONCE per cook instead of once per
// pixel. 2 axes x 5 rows x 33 steps = 330 points, stored in canvas WORLD space
// so this pass never touches _Resolution (meaningless in a buffer pass).
[numthreads(64,1,1)]
void main(uint3 id:SV_DispatchThreadID){
 uint i=id.x;
 if(i<330){
  uint axis=i/165,rem=i%165,row=rem/33,j=rem%33;
  float2 p=axis==0?float2(j/32.0,row/4.0):float2(row/4.0,j/32.0);
  OutputBuffer[i]=float4(.1+.8*correctedUV(p),0,0);
 }
}
