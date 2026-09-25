
float2 mapPoint(float3 p,float4 bounds){float scale=min((_Resolution.x-100)/max(1,bounds.y-bounds.x),(_Resolution.y*.75-100)/max(1,bounds.w-bounds.z));return float2(_Resolution.x*.5,_Resolution.y*.60)+float2(-p.z+(bounds.x+bounds.y)*.5,p.x-(bounds.z+bounds.w)*.5)*scale;}
float2 marker(float3 pos,uint f,float4 bounds){float2 p=mapPoint(pos,bounds);if(f>=64&&f<256){uint w=(f-64)/16;p.y+=(w%4<2?-1:1)*10;}return p;}
bool visible(uint f){return f<64||f>=256||tier==0||(tier==1&&((f-64)/16)%4<2)||(tier==2&&((f-64)/16)%4>=2);}
