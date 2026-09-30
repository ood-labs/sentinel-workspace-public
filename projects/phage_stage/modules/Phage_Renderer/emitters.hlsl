// Strobes (dark housing, white-hot tube, two RGB plates) and pixel bars (extrusion + a strip of
// 5 cm pixels sampled from the LED texture at each pixel's own centre).
#include "../_shared/phage_fixture.hlsli"
StructuredBuffer<PhStrobe> Strobes:register(t0); // Optics buffer, strobe records from PH_OPT_STROBE0
struct PhPiece{float4 a;float4 b;float4 n;float4 w;};StructuredBuffer<PhPiece> Q:register(t1);
Texture2D<float4> LED:register(t2);
struct V{float4 pos:SV_POSITION;float3 world:TEXCOORD0;float3 normal:TEXCOORD1;float4 emit:TEXCOORD2;float4 info:TEXCOORD3;};
#define STROBE_VERTS 84
#define STROBE_COUNT 48
#define BAR_VERTS 42
float3 boxCorner(uint v,out float3 n){uint f=v/6,k=v%6;float2 uv=float2(k==1||k==4||k==5?1:-1,k==2||k==3||k==5?1:-1);float s=f%2==0?-1:1;
 if(f<2){n=float3(s,0,0);return float3(s,uv);}if(f<4){n=float3(0,s,0);return float3(uv.x,s,uv.y);}n=float3(0,0,s);return float3(uv,s);}
float3 quadCorner(uint k){return float3(k==1||k==4||k==5?1:-1,k==2||k==3||k==5?1:-1,0);}
V VSMain(uint id:SV_VertexID){V o=(V)0;o.pos=float4(0,0,-1,1);float3 p,n;
 if(id<STROBE_COUNT*STROBE_VERTS){uint si=id/STROBE_VERTS,v=id%STROBE_VERTS;if(PH_OPT_STROBE0+si>=_Data1_Count)return o;PhStrobe s=Strobes[PH_OPT_STROBE0+si];if(s.active<.5)return o;
  float3 L=s.up,F=s.fwd,W=normalize(cross(F,L));float hl=s.length*.5;
  if(v<36){float3 q=boxCorner(v,n);p=s.position-F*.07+L*q.x*hl+W*q.y*.13+F*q.z*.065;n=L*n.x+W*n.y+F*n.z;o.info=float4(0,0,0,0);}
  else if(v<72){float3 q=boxCorner(v-36,n);p=s.position+F*.012+L*q.x*hl*.93+W*q.y*.02+F*q.z*.02;n=L*n.x+W*n.y+F*n.z;o.emit=float4(s.tube_colour*s.tube,1);o.info=float4(1,0,0,0);}
  else{uint k=(v-72)%6,side=(v-72)/6;float3 q=quadCorner(k);p=s.position+F*.004+L*q.x*hl*.93+W*((side==0?-.075:.075)+q.y*.045);n=F;o.emit=float4(s.plate_colour*s.plate,1);o.info=float4(2,0,0,0);}}
 else{uint j=id-STROBE_COUNT*STROBE_VERTS,pi=j/BAR_VERTS,v=j%BAR_VERTS;if(pi>=768||pi>=_Data2_Count)return o;PhPiece q=Q[pi];if(q.w.z<.5)return o;
  float3 A=q.a.xyz,B=q.b.xyz,D=normalize(B-A),N=q.n.xyz;N=normalize(N-D*dot(N,D));float3 S=normalize(cross(D,N));float hl=length(B-A)*.5;float3 C=(A+B)*.5;
  if(v<36){float3 c=boxCorner(v,n);p=C-N*.03+D*c.x*hl+S*c.y*.045+N*c.z*.03;n=D*n.x+S*n.y+N*n.z;o.info=float4(3,0,0,0);}
  else{float3 c=quadCorner(v-36);p=C+N*.002+D*c.x*hl+S*c.y*.022;n=N;o.info=float4(4,lerp(q.a.w,q.b.w,c.x*.5+.5),q.n.w,q.w.x/max(1e-3,q.b.w-q.a.w));}}
 o.world=p;o.normal=n;o.pos=mul(_ViewProjMatrix,float4(p,1));return o;}
float4 PSMain(V i):SV_TARGET0{
 float3 n=normalize(i.normal),v=normalize(_CameraPos-i.world);float kind=i.info.x;float3 c;
 float key=.02+.08*saturate(dot(n,normalize(float3(-.4,.8,.5))));
 if(kind<.5||(kind>2.5&&kind<3.5))c=float3(.025,.026,.03)*key*worklight;
 else if(kind<1.5){c=i.emit.rgb*emitter_gain*1.6+i.emit.rgb*emitter_gain*saturate(1-abs(dot(n,v)))*.5;}
 else if(kind<2.5){c=i.emit.rgb*emitter_gain*.9+.004*worklight;}
 else{float pitch=.05;float barLen=i.info.w;float cells=max(1,barLen/pitch);float x=i.info.y*cells;float uc=(floor(x)+.5)/cells;
  uint lw,lh;LED.GetDimensions(lw,lh);float3 led=LED.SampleLevel(PointSampler,float2(uc,(i.info.z+.5)/max(1,lh)),0).rgb;float dot_=smoothstep(.5,.22,abs(frac(x)-.5));
  c=led*led_gain*(.35+.65*dot_)+.003*worklight;}
 return float4(c,length(i.world-_CameraPos));}
