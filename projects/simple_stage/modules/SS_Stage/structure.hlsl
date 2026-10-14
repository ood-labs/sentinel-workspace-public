// SS_Stage / structure - the Structure buffer the renderer draws: SS_TUBE_COUNT truss tubes (SS_TUBES_PER slots per
// member: 4 chords, zig-zag lacing, end frames; a corner block's 12 cube edges) followed by SS_SOLID_COUNT oriented
// solids. Both records are four float4, so one 64-byte stride carries both. Solid: c=(centre, kind + 10*material),
// kind 1 box; material 0 truss metal, 1 blackened steel, 2 stage black. x/y/z=(unit axis, half extent).
#include "assembly.hlsli"
#include "../_shared/ss_stage.hlsli"
StructuredBuffer<SsMember> Mem:register(t0);
RWStructuredBuffer<Tube> O:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=TUBE_COUNT+SOLID_COUNT)return;Tube t=(Tube)0;
 if(i<TUBE_COUNT)t=trussTube(Mem[i/TUBES_PER],i%TUBES_PER);
 else{uint j=i-TUBE_COUNT;t.a=SS_SOLID_DATA[j*4];t.b=SS_SOLID_DATA[j*4+1];t.cutA=SS_SOLID_DATA[j*4+2];t.cutB=SS_SOLID_DATA[j*4+3];}
 O[i]=t;}
