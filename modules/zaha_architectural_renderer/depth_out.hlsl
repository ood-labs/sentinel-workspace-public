RWTexture2D<float4> OutputUAV:register(u0);
[numthreads(8,8,1)]void main(uint3 tid:SV_DispatchThreadID){if(tid.x>=(uint)_Resolution.x||tid.y>=(uint)_Resolution.y)return;float d=_Tex0.Load(int3(tid.xy,0)).a;float v=1-saturate(d);OutputUAV[tid.xy]=float4(v.xxx,1);}
