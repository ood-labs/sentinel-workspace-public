// Screen-space marks for the PHAGE instrument canvases. A marks pass writes one record per drawable
// primitive, already projected to canvas pixels; a bins pass files the marks into square tiles; the
// preview then visits only its own tile's marks, in mark order, so draw order survives. A tile that
// would hold more than PHM_PER_TILE-1 marks is flagged, and its pixels loop the whole list instead.
#ifndef PH_MARKS_HLSLI
#define PH_MARKS_HLSLI
struct PhMark{float4 geo;float4 shape;float4 fill;float4 stroke;};
// geo: a.xy, b.xy (b = a for point marks; the two corners for rects). shape: x kind, y size, z stroke
// width, w clip id (0 = none). fill / stroke: rgb + opacity (a dashed ring keeps its dash period in fill.x).
#define PHM_LINE 0      // stroke along a-b
#define PHM_DISC 1      // disc of radius size, ring just outside it
#define PHM_TUBE 2      // capsule a-b of width size, outline just inside its edge
#define PHM_DIAMOND 3   // diamond outline of radius size
#define PHM_DOT 4       // filled disc of radius size, no outline
#define PHM_RING 5      // ring of radius size
#define PHM_RECT 6      // filled rectangle between the corners a and b
#define PHM_FRAME 7     // hairline rectangle outline (snapped) between a and b
#define PHM_DASHRING 8  // ring of radius size, dashed with period fill.x px
#define PHM_HIDDEN 99
#define PHM_BLOCKS 128
#define PHM_TILE_CAP 8192    // PHM_BLOCKS blocks of 8 x 8 tiles
#define PHM_PER_TILE 96
PhMark phmHidden(){PhMark m=(PhMark)0;m.shape.x=PHM_HIDDEN;m.geo=-1e6;return m;}
float4 phmBox(PhMark m){float r=m.shape.y+m.shape.z+2;return float4(min(m.geo.xy,m.geo.zw)-r,max(m.geo.xy,m.geo.zw)+r);}
// Tiles are 16 px unless the canvas would need more than PHM_BLOCKS blocks of 8 x 8 tiles.
uint phmTileSize(float2 R){uint t=16;[loop]for(uint k=0;k<6&&ceil(ceil(R.x/t)/8)*ceil(ceil(R.y/t)/8)>PHM_BLOCKS;k++)t*=2;return t;}
uint phmTileOf(float2 P,float2 R){uint t=phmTileSize(R);uint2 n=(uint2)ceil(R/t);return min((uint)(P.y/t),n.y-1)*n.x+min((uint)(P.x/t),n.x-1);}
float phmSeg(float2 p,float2 a,float2 b){float2 pa=p-a,ba=b-a;return length(pa-ba*saturate(dot(pa,ba)/max(dot(ba,ba),1e-6)));}
float phmInk(float d,float w){return saturate(w*.5+.5-d);}
void phmOver(inout float3 c,float4 k,float a){c=lerp(c,k.rgb,saturate(a*k.a));}
void phmDraw(inout float3 c,float2 P,PhMark m){
 uint kind=(uint)m.shape.x;float size=m.shape.y,w=m.shape.z;
 if(kind==PHM_LINE)phmOver(c,m.stroke,phmInk(phmSeg(P,m.geo.xy,m.geo.zw),w));
 else if(kind==PHM_DISC){float d=length(P-m.geo.xy);phmOver(c,m.fill,saturate(size-d));phmOver(c,m.stroke,phmInk(abs(d-size-1),w));}
 else if(kind==PHM_TUBE){float d=phmSeg(P,m.geo.xy,m.geo.zw);phmOver(c,m.fill,phmInk(d,size));phmOver(c,m.stroke,phmInk(abs(d-size*.5-1),w));}
 else if(kind==PHM_DIAMOND){float d=abs(P.x-m.geo.x)+abs(P.y-m.geo.y);phmOver(c,m.fill,saturate(size-d+.5));phmOver(c,m.stroke,phmInk(abs(d-size),w));}
 else if(kind==PHM_DOT)phmOver(c,m.fill,saturate(size-length(P-m.geo.xy)));
 else if(kind==PHM_RING)phmOver(c,m.stroke,phmInk(abs(length(P-m.geo.xy)-size),w));
 else if(kind==PHM_RECT){if(all(P>=min(m.geo.xy,m.geo.zw))&&all(P<max(m.geo.xy,m.geo.zw)))phmOver(c,m.fill,1);}
 else if(kind==PHM_FRAME){float4 r=floor(float4(min(m.geo.xy,m.geo.zw),max(m.geo.xy,m.geo.zw)))+.5;float2 q=abs(P-(r.xy+r.zw)*.5)-(r.zw-r.xy)*.5;
  phmOver(c,m.stroke,phmInk(abs(length(max(q,0))+min(max(q.x,q.y),0)),w));}
 else if(kind==PHM_DASHRING){float2 v=P-m.geo.xy;float d=length(v);
  phmOver(c,m.stroke,phmInk(abs(d-size),w)*step(frac((d>1e-3?atan2(v.y,v.x):0)*size/(6.2831853*max(m.fill.x,1))),.5));}
}
// Bins kernel: define PHM_BINS_KERNEL and PHM_MARKS (mark count) before including; dispatch PHM_BLOCKS groups.
// A group owns an 8 x 8 block of tiles: marks are staged 64 at a time in groupshared memory and culled
// against the block into a survivor bitmask; each thread then walks only the survivors (lowest bit
// first, so in mark order) and keeps those that touch its own tile.
#ifdef PHM_BINS_KERNEL
StructuredBuffer<PhMark> Marks:register(t0);
RWStructuredBuffer<uint> Bins:register(u0);
groupshared float4 gBox[64];
groupshared uint gLive[2];   // survivors of the current chunk, bit k = mark c0+k
[numthreads(64,1,1)]void main(uint3 gid:SV_GroupID,uint gi:SV_GroupIndex){
 float2 R=_Resolution.xy;uint t=phmTileSize(R);uint2 n=(uint2)ceil(R/t);uint bx=(n.x+7)/8;
 uint2 block=uint2(gid.x%bx,gid.x/bx),tc=block*8+uint2(gi%8,gi/8);
 if(block.y*8>=n.y)return;   // whole group exits together
 bool mine=tc.x<n.x&&tc.y<n.y;uint base=(tc.y*n.x+tc.x)*PHM_PER_TILE;
 float4 tr=float4(tc,tc+1)*t,br=float4(block*8,min(block*8+8,n))*t;uint count=0;bool over=false;
 [loop]for(uint c0=0;c0<PHM_MARKS;c0+=64){
  if(gi<2)gLive[gi]=0;
  GroupMemoryBarrierWithGroupSync();
  uint i=c0+gi;
  if(i<PHM_MARKS){PhMark m;m.geo=Marks[i].geo;m.shape=Marks[i].shape;
   if(m.shape.x!=PHM_HIDDEN){float4 b=phmBox(m);if(!(b.z<br.x||b.x>br.z||b.w<br.y||b.y>br.w)){gBox[gi]=b;InterlockedOr(gLive[gi>>5],1u<<(gi&31));}}}
  GroupMemoryBarrierWithGroupSync();
  if(mine){[unroll]for(uint w=0;w<2;w++){uint live=gLive[w];
    [loop]while(live!=0){uint k=w*32+firstbitlow(live);live&=live-1;float4 q=gBox[k];
     if(q.z<tr.x||q.x>tr.z||q.w<tr.y||q.y>tr.w)continue;
     if(count<PHM_PER_TILE-1){Bins[base+1+count]=c0+k;count++;}else over=true;}}}
  GroupMemoryBarrierWithGroupSync();}
 if(mine)Bins[base]=count|(over?0x80000000u:0u);}
#endif
#endif
// Tile draw for previews: include this header once for PhMark, declare the marks and bins buffers,
// define PHM_MARKS_BUF / PHM_BINS_BUF (their names) and PHM_MARKS, then include it again.
// Only marks whose clip id equals `clip` are drawn (pass 0 to draw unclipped marks only).
#if defined(PHM_MARKS_BUF)&&!defined(PH_MARKS_DRAW_HLSLI)
#define PH_MARKS_DRAW_HLSLI
void phmDrawTile(inout float3 c,float2 P,float2 R,uint clip){
 uint base=phmTileOf(P,R)*PHM_PER_TILE,h=PHM_BINS_BUF[base];
 if(h>>31){[loop]for(uint i=0;i<PHM_MARKS;i++){PhMark m=PHM_MARKS_BUF[i];if((uint)m.shape.w==clip&&m.shape.x!=PHM_HIDDEN)phmDraw(c,P,m);}}
 else{uint count=h&0x7fffffffu;[loop]for(uint k=0;k<count;k++){PhMark m=PHM_MARKS_BUF[PHM_BINS_BUF[base+1+k]];if((uint)m.shape.w==clip)phmDraw(c,P,m);}}}
#endif
