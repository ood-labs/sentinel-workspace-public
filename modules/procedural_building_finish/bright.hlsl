RWTexture2D<float4> OutputUAV : register(u0);
[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID){if(id.x>=(uint)_Resolution.x||id.y>=(uint)_Resolution.y)return;float3 c=_Tex0.Load(int3(id.xy,0)).rgb;float l=max(c.r,max(c.g,c.b));float soft=saturate((l-bloom_threshold+bloom_knee)/max(2*bloom_knee,.001));float contribution=max(l-bloom_threshold,0)+soft*soft*bloom_knee;OutputUAV[id.xy]=float4(c*(contribution/max(l,.001)),1);}
