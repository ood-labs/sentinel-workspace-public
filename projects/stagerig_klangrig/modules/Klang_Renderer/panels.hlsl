#include "../_shared/rig.hlsli"
StructuredBuffer<RigRecord> R:register(t0);
Texture2D<float4> LED:register(t1);
struct V{float4 pos:SV_POSITION;float3 world:TEXCOORD0;float2 uv:TEXCOORD1;float face:TEXCOORD2;};
V VSMain(uint id:SV_VertexID){
 V o=(V)0;uint segment=id/36+1,v=id%36,wing=(segment-1)/4,edge=(segment-1)%4;
 RigRecord r=R[segment];uint corner[6]={0,1,2,2,1,3};uint k=corner[v%6],face=v/6;
 float3 points[4],dirs[4],inward[4];float lengths[4];float3 center=0;float total=0,prior=0;
 for(uint j=0;j<4;j++){RigRecord q=R[1+wing*4+j];points[j]=q.a.xyz;dirs[j]=normalize(q.b.xyz-q.a.xyz);lengths[j]=length(q.b.xyz-q.a.xyz);center+=points[j]*.25;total+=lengths[j];if(j<edge)prior+=lengths[j];}
 for(uint j=0;j<4;j++){float3 d=center-points[j];inward[j]=normalize(d-dirs[j]*dot(d,dirs[j]));}
 float3 D=dirs[edge],U=inward[edge],N=normalize(cross(D,U));
 // Shared offset-line intersections make adjacent panel ends meet at a miter.
 uint prev=(edge+3)%4,next=(edge+1)%4;
 float3 mA=(inward[prev]+U)/max(.001,1+dot(inward[prev],U));
 float3 mB=(U+inward[next])/max(.001,1+dot(U,inward[next]));
 float3 normal=face<2?N:face<4?U:D;float sign=face%2==0?-1:1;
 float3 Y=face<4?D:U,Z=face<2?U:N;
 float3 local=normal*sign+Y*(k%2==0?-1:1)+Z*(k<2?-1:1);
 float along=dot(local,D)*.5+.5,across=dot(local,U)*.5+.5,height=dot(local,N);
 // LED occupies the inward wall of the truss, width across the loop plane.
 // Only the aperture-facing side emits; underside and outer casing stay dark.
 float offset=r.shape.x*.5+.015+across*.06;
 float3 a=points[edge]+mA*offset,b=points[next]+mB*offset;
 float3 p=lerp(a,b,along)+N*height*r.shape.y*.5;
 o.world=p;o.pos=mul(_ViewProjMatrix,float4(p,1));
 o.uv=float2((prior+along*lengths[edge])/total,(wing+(height*.5+.5)*.94+.03)/12);
 o.face=face==3?1:0;return o;
}
float4 PSMain(V i):SV_TARGET0{float3 c=LED.SampleLevel(LinearSampler,i.uv,0).rgb*led_gain*i.face+.008*worklight;return float4(c,length(i.world-_CameraPos));}
