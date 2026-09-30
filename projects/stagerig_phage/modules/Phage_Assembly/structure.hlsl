// Structure buffer: 13248 truss tubes (4 chords, zig-zag lacing, end frames; 96 slots per member)
// followed by 64 oriented solids. Both records are four float4, so one 64-byte stride carries both.
// Solid: c=(centre or base, kind + 10*material) with kind 1 box, 2 cone, 3 figure; material 0 truss
// metal, 1 blackened steel, 2 stage black, 3 cloth. x/y/z=(unit axis, half extent); a cone's y axis
// runs base->tip with y.w = height and x.w = base radius; a figure stands at c with y.w = height.
#include "assembly_types.hlsli"
StructuredBuffer<PhMember> Mem:register(t0);
#include "assembly.hlsli"
RWStructuredBuffer<Tube> O:register(u0);
PhSolid solidAt(uint i){
 PhSolid s=(PhSolid)0;uint mi=TRUSS_MEMBERS+i;
 if(mi<_Data0_Count&&mi<189){PhMember m=Mem[mi];float kind=m.b.w;float prof=m.up.w;
  if(kind>.5&&prof>1.5&&prof<2.5){float3 c=(m.a.xyz+m.b.xyz)*.5,h=abs(m.b.xyz-m.a.xyz)*.5;
   float3 Z=float3(m.up.x,0,m.up.z);Z=dot(Z,Z)>.01?normalize(Z):float3(0,0,1);float3 Y=float3(0,1,0),X=cross(Y,Z);
   float mat=kind==16||kind==17?2:0;s.c=float4(c,1+10*mat);s.x=float4(X,h.x);s.y=float4(Y,h.y);s.z=float4(Z,h.z);}
  else if(kind>.5&&prof>2.5&&prof<3.5){float3 d=m.b.xyz-m.a.xyz;float L=length(d);float3 Y=d/max(L,1e-4);
   float3 X=normalize(cross(abs(Y.y)<.9?float3(0,1,0):float3(1,0,0),Y)),Z=cross(X,Y);
   s.c=float4(m.a.xyz,2+10);s.x=float4(X,m.a.w);s.y=float4(Y,L);s.z=float4(Z,m.a.w);}
  else if(kind>.5&&prof>4.5){float3 Z=normalize(m.up.xyz),Y=float3(0,1,0),X=cross(Y,Z);
   s.c=float4(m.a.xyz,3+30);s.x=float4(X,.26);s.y=float4(Y,length(m.b.xyz-m.a.xyz));s.z=float4(Z,.16);}}
 return s;}

[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=TUBE_COUNT+SOLID_COUNT)return;Tube t=(Tube)0;
 if(i<TUBE_COUNT){uint m=i/TUBES_PER;if(m<_Data0_Count)t=trussTube(Mem[m],i%TUBES_PER);}
 else{PhSolid s=solidAt(i-TUBE_COUNT);t.a=s.c;t.b=s.x;t.cutA=s.y;t.cutB=s.z;}
 O[i]=t;}
