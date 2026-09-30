// BLINK_Previs / bounds.hlsli: laser_lab LS_Air screen_bounds.hlsl (1563058e), unchanged apart
// from the SCAN / SCAN_COUNT macros so one file serves both lasers. World-space triangle
// support, expanded by the finite Gaussian beam footprint.
struct ScreenRec {float4 ab;float4 cd;float4 bounds;float4 meta;};
RWStructuredBuffer<ScreenRec> OutputBuffer:register(u0);
[numthreads(64,1,1)]
void main(uint3 id:SV_DispatchThreadID){
 uint i=id.x;if(i>=4096)return;ScreenRec s=(ScreenRec)0;
 if(SCAN_COUNT==0){OutputBuffer[i]=s;return;}
 if(i==0){s.meta.x=min(SCAN[0].origin.x,SCAN_COUNT-1);OutputBuffer[i]=s;return;}
 if(i>(uint)SCAN[0].origin.x||i>=SCAN_COUNT||SCAN[i].timing.w>.5||SCAN[i].timing.y<=0){OutputBuffer[i]=s;return;}
 float3 o=SCAN[i].origin.xyz;float range=SCAN[i].direction1.w;
 float radius=SCAN[i].origin.w+SCAN[i].direction0.w*range;
 s.ab=float4(o,6*radius);
 s.cd=float4(o+SCAN[i].direction0.xyz*range,0);
 s.bounds=float4(o+SCAN[i].direction1.xyz*range,0);
 s.meta.x=1;
 OutputBuffer[i]=s;
}
