RWStructuredBuffer<float4> OutputBuffer:register(u0);
[numthreads(1,1,1)]
void main(uint3 id:SV_DispatchThreadID){
 float4 state=OutputBuffer[0];
 if(state.w!=173.0)state=float4(0,0,0,173);
 state.x+=min(_DeltaTime,.1)*fog_speed;
 OutputBuffer[0]=state;
}
