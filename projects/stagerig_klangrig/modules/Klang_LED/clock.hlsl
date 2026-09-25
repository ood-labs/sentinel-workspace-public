RWStructuredBuffer<float4>S:register(u0);
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){float t=S[0].x;if(!isfinite(t)||t<0)t=0;if(pattern==5&&animate)t=fmod(t+max(0,_DeltaTime)/max(.1,chase_seconds),48);else t=0;uint face=((uint)floor(t)+(uint)test_face-1)%48;S[0]=float4(t,face+1,face/4+1,face%4+1);}
