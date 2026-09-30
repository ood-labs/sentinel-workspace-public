// Zoning masks: rectangles, ellipses and polygons drawn on the laser's own field. They live in
// scanner units (the output field, -1..1, screen +y down), so re-mapping the surface or changing
// the scanner correction never moves a zone off the object it covers.
//
// The including pass declares M (the zones buffer, StructuredBuffer or RW) before including this.
//   M[0]              = (count, MASK_COOKIE, 0, 0)
//   M[1+2j]           = (kind 0 rect / 1 ellipse / 2 polygon, mode 0 block / 1 only-in, on, angle)
//   M[2+2j]           = rect/ellipse: (centre x, centre y, half width, half height), unrotated
//                       polygon: (point count, 0, 0, 0)
//   M[MASK_PT0+32j+i] = polygon point i, (x, y, 0, 0)
// Rule: a point is lit only if it is outside every enabled Block, and, when any enabled Only-In
// exists, inside at least one of them. Order never matters, and inverting a mask is Block <-> Only-In.
#ifndef MASKS_HLSLI
#define MASKS_HLSLI
#include "mask_labels.hlsli"
#include "../_shared/fonts/scientifica_ascii.hlsli"
#define MASK_MAX 16
#define POLY_MAX 32
#define MASK_PT0 33
#define MASK_COOKIE 6173
#define CAL_MASK_BASE 32
#define CAL_POLY_BASE 65
#define CAL_MASK_COOKIE 5151

uint maskCount(){return M[0].y==MASK_COOKIE?(uint)clamp(M[0].x,0,MASK_MAX):0;}
float4 maskInfo(uint j){return M[1+2*j];}
float4 maskRect(uint j){return M[2+2*j];}
uint polyCount(uint j){return (uint)clamp(M[2+2*j].x,0,POLY_MAX);}
float2 polyPoint(uint j,uint i){return M[MASK_PT0+POLY_MAX*j+i].xy;}

// Editor world (the canvas, .1..0.9 = the mapped extent) <-> scanner units.
float2 worldToScan(float2 w){return (w-.5)*2.5*extent_a;}
float2 scanToWorld(float2 q){return .5+q/(2.5*extent_a);}
float2 rot(float2 v,float a){float c=cos(a),s=sin(a);return float2(c*v.x-s*v.y,s*v.x+c*v.y);}
// A rectangle's or ellipse's frame: local = rot(q - centre, -angle).
float2 toLocal(float4 info,float4 r,float2 q){return rot(q-r.xy,-info.w);}
float2 cornerOf(float4 info,float4 r,uint c){return r.xy+rot(r.zw*float2((c&1)?1:-1,(c&2)?1:-1),info.w);}
// The rotate knob sits beyond the top edge, a fixed number of pixels out.
float2 knobOf(float4 info,float4 r,float pxs){return r.xy+rot(float2(0,-(r.w+22/pxs)),info.w);}

// Margin: a Block zone grows by the margin and an Only-In zone shrinks by it, conservatively.
// A rectangle offsets exactly. An ellipse is scaled about its centre by margin / its smaller
// radius, which always contains the true offset curve (and, shrinking, always sits inside it).
// Polygons are offset in compile_map with mitred corners.
float4 effectiveRect(float4 info,float4 r,float margin){
 float g=info.y<.5?margin:-margin;
 if(info.x<.5)return float4(r.xy,r.zw+g);
 float m=max(min(r.z,r.w),1e-6);return float4(r.xy,r.zw*max(1+g/m,0));
}
float segDist(float2 p,float2 a,float2 b){float2 d=b-a;return length((p-a)-d*saturate(dot(p-a,d)/max(dot(d,d),1e-20)));}
bool polyInside(uint j,float2 q){
 uint n=polyCount(j);bool in_=false;if(n<3)return false;
 float2 a=polyPoint(j,n-1);
 [loop]for(uint i=0;i<n;i++){float2 b=polyPoint(j,i);if((a.y>q.y)!=(b.y>q.y)&&q.x<a.x+(q.y-a.y)*(b.x-a.x)/(b.y-a.y))in_=!in_;a=b;}
 return in_;
}
// Signed distance in scanner units (negative inside). Exact for rectangles and polygons, close
// for ellipses. An unclosed polygon (fewer than three points) is just its open line.
float maskDistance(uint j,float2 q){
 float4 info=maskInfo(j),r=maskRect(j);
 if(info.x>1.5){
  uint n=polyCount(j);float d=1e9;if(n==0)return d;if(n==1)return length(q-polyPoint(j,0));
  [loop]for(uint i=0;i+1<n;i++)d=min(d,segDist(q,polyPoint(j,i),polyPoint(j,i+1)));
  if(n>=3)d=min(d,segDist(q,polyPoint(j,n-1),polyPoint(j,0)));
  return polyInside(j,q)?-d:d;
 }
 float2 l=toLocal(info,r,q);
 if(info.x<.5){float2 e=abs(l)-r.zw;return length(max(e,0))+min(max(e.x,e.y),0);}
 float2 h=max(r.zw,1e-6);return (length(l/h)-1)*min(h.x,h.y);
}

// ---- The side panel, in panel pixels (origin top-left, +y down). Shared by the canvas pass
// (hit testing) and the editor pass (drawing), so the two can never disagree.
#define PANEL_W 196
#define ROW_Y0 76
#define ROW_H 24
float panelX0(){return _Resolution.x-PANEL_W-8;}
float panelBottom(uint count){return ROW_Y0+ROW_H*max(count,1)+6;}
bool inBox(float2 p,float4 b){return all(p>=b.xy)&&all(p<b.xy+b.zw);}
float4 tabBox(uint i){return float4(panelX0()+i*100,8,94,22);}
float4 toolBox(uint i){return float4(panelX0()+i*66,40,62,22);}
float4 rowBox(uint j){return float4(panelX0(),ROW_Y0+ROW_H*j,PANEL_W,ROW_H-2);}
float4 rowModeBox(uint j){float4 b=rowBox(j);return float4(b.x+72,b.y,56,b.w);}
float4 rowOnBox(uint j){float4 b=rowBox(j);return float4(b.x+132,b.y,36,b.w);}
float4 rowDeleteBox(uint j){float4 b=rowBox(j);return float4(b.x+172,b.y,24,b.w);}
// 0 = not the panel, 1 = panel background, 10+i tab, 20+i tool, 30 row, 31 mode, 32 on, 33 delete.
uint panelHit(float2 p,uint count,out uint row){
 row=0;
 if(p.x<panelX0()-8||p.y>panelBottom(count))return 0;
 [unroll]for(uint i=0;i<2;i++)if(inBox(p,tabBox(i)))return 10+i;
 [unroll]for(uint t=0;t<3;t++)if(inBox(p,toolBox(t)))return 20+t;
 [loop]for(uint j=0;j<count;j++){
  row=j;
  if(inBox(p,rowModeBox(j)))return 31;
  if(inBox(p,rowOnBox(j)))return 32;
  if(inBox(p,rowDeleteBox(j)))return 33;
  if(inBox(p,rowBox(j)))return 30;
 }
 return 1;
}

// 8x11 glyphs on a 7 px advance.
float glyph(float2 p,float2 a,uint code){int2 v=(int2)floor(p-a);if(any(v<0)||v.x>=8||v.y>=11||code<33||code>126)return 0;return (scientificaRowForFace(0,code,v.y)>>(7-v.x))&1;}
float label(float2 p,float2 a,uint id){float2 v=p-a;if(any(v<0)||v.y>=11||v.x>=56)return 0;uint col=(uint)v.x/7;return glyph(p,a+float2(col*7,0),ML[id*8+col]);}
float hint(float2 p,float2 a,uint id){float2 v=p-a;if(any(v<0)||v.y>=11||v.x>=196)return 0;uint col=(uint)v.x/7;return glyph(p,a+float2(col*7,0),MH[id*28+col]);}
float digits2(float2 p,float2 a,uint n){float2 v=p-a;if(any(v<0)||v.y>=11||v.x>=14)return 0;uint col=(uint)v.x/7;uint d=col==0?n/10:n%10;if(col==0&&d==0)return 0;return glyph(p,a+float2(col*7,0),48+d);}
#endif
