// 96 line emitters that let the pixel bars light the truss, floor and crowd. Each takes one bar
// piece (rings and long runs are subsampled) and averages the live LED texture over its u range.
struct PhPiece{float4 a;float4 b;float4 n;float4 w;};
StructuredBuffer<PhPiece> Q:register(t0);
Texture2D<float4> LED:register(t1);
struct Emitter{float4 a,b,radiance;};RWStructuredBuffer<Emitter> O:register(u0);
// (bar, piece, weight) for every emitter slot.
uint3 pick(uint e){
 if(e<24)return uint3(e,0,1);
 if(e<30)return uint3(e,0,1);
 if(e<45){uint k=e-30;return uint3(30+k/3,(k%3)*2,2);}
 if(e<53){uint k=e-45;return uint3(35+k/4,(k%4)*3,3);}
 if(e<77){uint k=e-53;return uint3(37+k/4,k%4,1);}
 if(e<89){uint k=e-77;return uint3(43+k/4,k%4,1);}
 if(e<93){uint k=e-89;return uint3(46,k*2,2);}
 return uint3(99,0,0);
}
[numthreads(96,1,1)]void main(uint3 id:SV_DispatchThreadID){uint e=id.x;if(e>=96)return;Emitter o=(Emitter)0;uint3 p=pick(e);
 if(p.x<64&&_Data0_Count>=768){PhPiece q=Q[p.x*12+p.y];if(q.w.z>.5){float3 r=0;
  uint lw,lh;LED.GetDimensions(lw,lh);[unroll]for(uint s=0;s<8;s++){float u=lerp(q.a.w,q.b.w,(s+.5)/8);r+=LED.SampleLevel(LinearSampler,float2(u,(p.x+.5)/max(1,lh)),0).rgb/8;}
  o.a=float4(q.a.xyz+q.n.xyz*.05,.08);o.b=float4(q.b.xyz+q.n.xyz*.05,1);o.radiance=float4(r*p.z,1);}}
 O[e]=o;}
