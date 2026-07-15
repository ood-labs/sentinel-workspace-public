RWTexture2D<float4> OutputUAV : register(u0);
float3 at(int2 p){p=clamp(p,int2(0,0),int2(_Resolution.xy)-1);return _Tex0.Load(int3(p,0)).rgb;}
[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID){if(id.x>=(uint)_Resolution.x||id.y>=(uint)_Resolution.y)return;int2 p=int2(id.xy);int r=max(1,(int)(bloom_radius*_Resolution.x*.22));float3 c=at(p)*.227027;c+=(at(p+int2(r,0))+at(p-int2(r,0)))*.1945946;c+=(at(p+int2(r*2,0))+at(p-int2(r*2,0)))*.1216216;c+=(at(p+int2(r*3,0))+at(p-int2(r*3,0)))*.054054;c+=(at(p+int2(r*4,0))+at(p-int2(r*4,0)))*.016216;OutputUAV[id.xy]=float4(c,1);}
