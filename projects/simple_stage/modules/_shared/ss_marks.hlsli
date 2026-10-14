// Screen-space marks for the PHAGE instrument canvases. A marks pass writes one record per drawable
// primitive, already projected to canvas pixels; a bins pass files the marks into square tiles; the
// preview then visits only its own tile's marks, in mark order, so draw order survives. A tile that
// would hold more than SSM_PER_TILE-1 marks is flagged, and its pixels loop the whole list instead.
#ifndef SS_MARKS_HLSLI
#define SS_MARKS_HLSLI
struct SsMark{float4 geo;float4 shape;float4 fill;float4 stroke;};
// geo: a.xy, b.xy (b = a for point marks; the two corners for rects). shape: x kind, y size, z stroke
// width, w clip id (0 = none). fill / stroke: rgb + opacity (a dashed ring keeps its dash period in fill.x).
#define SSM_LINE 0      // stroke along a-b
#define SSM_DISC 1      // disc of radius size, ring just outside it
#define SSM_TUBE 2      // capsule a-b of width size, outline just inside its edge
#define SSM_DIAMOND 3   // diamond outline of radius size
#define SSM_DOT 4       // filled disc of radius size, no outline
#define SSM_RING 5      // ring of radius size
#define SSM_RECT 6      // filled rectangle between the corners a and b
#define SSM_FRAME 7     // hairline rectangle outline (snapped) between a and b
#define SSM_DASHRING 8  // ring of radius size, dashed with period fill.x px
#define SSM_HIDDEN 99
#define SSM_BLOCKS 128
#define SSM_TILE_CAP 8192    // SSM_BLOCKS blocks of 8 x 8 tiles
#define SSM_PER_TILE 96
SsMark ssmHidden(){SsMark m=(SsMark)0;m.shape.x=SSM_HIDDEN;m.geo=-1e6;return m;}
float4 ssmBox(SsMark m){float r=m.shape.y+m.shape.z+2;return float4(min(m.geo.xy,m.geo.zw)-r,max(m.geo.xy,m.geo.zw)+r);}
// Tiles are 16 px unless the canvas would need more than SSM_BLOCKS blocks of 8 x 8 tiles.
uint ssmTileSize(float2 R){uint t=16;[loop]for(uint k=0;k<6&&ceil(ceil(R.x/t)/8)*ceil(ceil(R.y/t)/8)>SSM_BLOCKS;k++)t*=2;return t;}
uint ssmTileOf(float2 P,float2 R){uint t=ssmTileSize(R);uint2 n=(uint2)ceil(R/t);return min((uint)(P.y/t),n.y-1)*n.x+min((uint)(P.x/t),n.x-1);}
float ssmSeg(float2 p,float2 a,float2 b){float2 pa=p-a,ba=b-a;return length(pa-ba*saturate(dot(pa,ba)/max(dot(ba,ba),1e-6)));}
float ssmInk(float d,float w){return saturate(w*.5+.5-d);}
void ssmOver(inout float3 c,float4 k,float a){c=lerp(c,k.rgb,saturate(a*k.a));}
void ssmDraw(inout float3 c,float2 P,SsMark m){
 uint kind=(uint)m.shape.x;float size=m.shape.y,w=m.shape.z;
 if(kind==SSM_LINE)ssmOver(c,m.stroke,ssmInk(ssmSeg(P,m.geo.xy,m.geo.zw),w));
 else if(kind==SSM_DISC){float d=length(P-m.geo.xy);ssmOver(c,m.fill,saturate(size-d));ssmOver(c,m.stroke,ssmInk(abs(d-size-1),w));}
 else if(kind==SSM_TUBE){float d=ssmSeg(P,m.geo.xy,m.geo.zw);ssmOver(c,m.fill,ssmInk(d,size));ssmOver(c,m.stroke,ssmInk(abs(d-size*.5-1),w));}
 else if(kind==SSM_DIAMOND){float d=abs(P.x-m.geo.x)+abs(P.y-m.geo.y);ssmOver(c,m.fill,saturate(size-d+.5));ssmOver(c,m.stroke,ssmInk(abs(d-size),w));}
 else if(kind==SSM_DOT)ssmOver(c,m.fill,saturate(size-length(P-m.geo.xy)));
 else if(kind==SSM_RING)ssmOver(c,m.stroke,ssmInk(abs(length(P-m.geo.xy)-size),w));
 else if(kind==SSM_RECT){if(all(P>=min(m.geo.xy,m.geo.zw))&&all(P<max(m.geo.xy,m.geo.zw)))ssmOver(c,m.fill,1);}
 else if(kind==SSM_FRAME){float4 r=floor(float4(min(m.geo.xy,m.geo.zw),max(m.geo.xy,m.geo.zw)))+.5;float2 q=abs(P-(r.xy+r.zw)*.5)-(r.zw-r.xy)*.5;
  ssmOver(c,m.stroke,ssmInk(abs(length(max(q,0))+min(max(q.x,q.y),0)),w));}
 else if(kind==SSM_DASHRING){float2 v=P-m.geo.xy;float d=length(v);
  ssmOver(c,m.stroke,ssmInk(abs(d-size),w)*step(frac((d>1e-3?atan2(v.y,v.x):0)*size/(6.2831853*max(m.fill.x,1))),.5));}
}
// Bins kernel: define SSM_BINS_KERNEL and SSM_MARKS (mark count) before including; dispatch SSM_BLOCKS groups.
// A group owns an 8 x 8 block of tiles: marks are staged 64 at a time in groupshared memory and culled
// against the block into a survivor bitmask; each thread then walks only the survivors (lowest bit
// first, so in mark order) and keeps those that touch its own tile.
#ifdef SSM_BINS_KERNEL
StructuredBuffer<SsMark> Marks:register(t0);
RWStructuredBuffer<uint> Bins:register(u0);
groupshared float4 gBox[64];
groupshared uint gLive[2];   // survivors of the current chunk, bit k = mark c0+k
[numthreads(64,1,1)]void main(uint3 gid:SV_GroupID,uint gi:SV_GroupIndex){
 float2 R=_Resolution.xy;uint t=ssmTileSize(R);uint2 n=(uint2)ceil(R/t);uint bx=(n.x+7)/8;
 uint2 block=uint2(gid.x%bx,gid.x/bx),tc=block*8+uint2(gi%8,gi/8);
 if(block.y*8>=n.y)return;   // whole group exits together
 bool mine=tc.x<n.x&&tc.y<n.y;uint base=(tc.y*n.x+tc.x)*SSM_PER_TILE;
 float4 tr=float4(tc,tc+1)*t,br=float4(block*8,min(block*8+8,n))*t;uint count=0;bool over=false;
 [loop]for(uint c0=0;c0<SSM_MARKS;c0+=64){
  if(gi<2)gLive[gi]=0;
  GroupMemoryBarrierWithGroupSync();
  uint i=c0+gi;
  if(i<SSM_MARKS){SsMark m;m.geo=Marks[i].geo;m.shape=Marks[i].shape;
   if(m.shape.x!=SSM_HIDDEN){float4 b=ssmBox(m);if(!(b.z<br.x||b.x>br.z||b.w<br.y||b.y>br.w)){gBox[gi]=b;InterlockedOr(gLive[gi>>5],1u<<(gi&31));}}}
  GroupMemoryBarrierWithGroupSync();
  if(mine){[unroll]for(uint w=0;w<2;w++){uint live=gLive[w];
    [loop]while(live!=0){uint k=w*32+firstbitlow(live);live&=live-1;float4 q=gBox[k];
     if(q.z<tr.x||q.x>tr.z||q.w<tr.y||q.y>tr.w)continue;
     if(count<SSM_PER_TILE-1){Bins[base+1+count]=c0+k;count++;}else over=true;}}}
  GroupMemoryBarrierWithGroupSync();}
 if(mine)Bins[base]=count|(over?0x80000000u:0u);}
#endif
#endif
// Tile draw for previews: include this header once for SsMark, declare the marks and bins buffers,
// define SSM_MARKS_BUF / SSM_BINS_BUF (their names) and SSM_MARKS, then include it again.
// Only marks whose clip id equals `clip` are drawn (pass 0 to draw unclipped marks only).
#if defined(SSM_MARKS_BUF)&&!defined(SS_MARKS_DRAW_HLSLI)
#define SS_MARKS_DRAW_HLSLI
void ssmDrawTile(inout float3 c,float2 P,float2 R,uint clip){
 uint base=ssmTileOf(P,R)*SSM_PER_TILE,h=SSM_BINS_BUF[base];
 if(h>>31){[loop]for(uint i=0;i<SSM_MARKS;i++){SsMark m=SSM_MARKS_BUF[i];if((uint)m.shape.w==clip&&m.shape.x!=SSM_HIDDEN)ssmDraw(c,P,m);}}
 else{uint count=h&0x7fffffffu;[loop]for(uint k=0;k<count;k++){SsMark m=SSM_MARKS_BUF[SSM_BINS_BUF[base+1+k]];if((uint)m.shape.w==clip)ssmDraw(c,P,m);}}}
#endif
