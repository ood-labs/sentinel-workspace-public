// One working mapping, always bank 0 of the points buffer (the buffer keeps its three-bank size
// so saved projects and presets stay valid; see update.hlsl for the one-time migration).
#ifndef BANK
#define BANK 0
#endif
StructuredBuffer<float4> Points:register(t1);
RWStructuredBuffer<float4> C:register(u0);
StructuredBuffer<float4> M:register(t2);
#include "canvas_view.hlsli"
#include "masks.hlsli"
// Masks: C[34] = (edit mode 0 mapping / 1 masks, tool 0 rect / 1 ellipse / 2 polygon, selected+1,
//                 polygon being built+1)
//        C[35] = one-cook mask op for mask_update.hlsl (op, index, arg, 0), C[36] = its vector
//        C[37] = (gesture anchor in scanner units, vertex, mask index), C[38] = gesture memory
// Gestures in C[2].x: 4 draw a new rect/ellipse, 5 move a mask, 6 resize from a corner,
// 7 drag a polygon point, 8 rotate. The tool only decides what a drag on EMPTY space creates:
// pressing on any mask selects it and grabs it, whatever the tool.
void maskOp(int op,uint j,float arg,float4 v){
 // Several events can land in one cook but only one op reaches mask_update, so a create,
 // append or insert still pending absorbs the drag that follows it, and moves accumulate.
 int p=(int)C[35].x;bool same=p>0&&(uint)C[35].y==j;
 if(same&&(p==1||p==6||p==7)&&op==2){C[36]=v;return;}
 if(same&&(p==1||p==6||p==7)&&op==9){C[36].xy=v.xy;return;}
 if(same&&p==8&&op==8){C[36].xy+=v.xy;return;}
 C[35]=float4(op,j,arg,0);C[36]=v;
}
// Ends polygon drawing. Fewer than three points is not a zone, so it is removed.
void finishPolygon(){
 int b=(int)C[34].w-1;if(b<0)return;C[34].w=0;
 uint np=((int)maskCount()>b?polyCount(b):0)+((C[35].x==6&&(int)C[35].y==b)?1:0)+((C[35].x==1&&(int)C[35].y==b)?1:0);
 if(np<3){if(C[35].x==1&&(int)C[35].y==b)C[35]=0;else maskOp(5,b,0,0);C[34].z=0;}
}
float scanPixels(){return C[0].z*canvasScale()/(2.5*extent_a);}
float2 world(float2 uv,float4 view){return canvasWorld(uv,view);}
bool corner(int k){return k==0||k==4||k==20||k==24;}
void fit(){
 float2 lo=Points[BANK+0].xy,hi=lo;
 [unroll]for(int k=1;k<25;k++){lo=min(lo,Points[BANK+k].xy);hi=max(hi,Points[BANK+k].xy);}
 float2 span=max(hi-lo,.0001);
 float z=.8*min(_Resolution.x/span.x,_Resolution.y/span.y)/canvasScale();
 C[0]=float4((lo+hi)*.5,clamp(z,.05,4096),7301);
}
[numthreads(1,1,1)]
void main(uint3 id:SV_DispatchThreadID){
 if(C[0].w!=7301){[unroll]for(int k=0;k<40;k++)C[k]=0;C[0]=float4(.5,.5,1,7301);}
 if(C[7].z!=0){C[2]=0;[unroll]for(int k=0;k<25;k++)C[8+k]=0;fit();}
 C[3]=0; // start, update, cancel, completed operation mode
 // The event queue may lose a release boundary when a panel loses capture.
 // Never keep a GPU gesture alive after the host says its button is up.

 C[33]=0;  // one-cook arrow-key nudge for update.hlsl, in world units
 C[35]=0;C[36]=0;
 if((int)C[34].z>(int)maskCount())C[34].z=0;
 if((int)C[34].w>(int)maskCount())C[34].w=0;
 if(fit_view>.5&&C[7].x<.5)fit();
 if(select_all>.5&&C[7].y<.5){[unroll]for(int k=0;k<25;k++)C[8+k].x=1;}
 C[7]=float4(fit_view,select_all,0,0);
 [loop]for(uint e=0;e<min(_ViewportEventCount,64u);e++){
  ViewportEvent ev=_ViewportEvents[e];
  // The uploaded batch can survive multiple cooks. Consume each sequence once.
  if(C[6].y>0&&(int)(ev.sequence-asuint(C[6].x))<=0)continue;
  C[6].x=asfloat(ev.sequence);C[6].y=1;
  // Esc or Enter finishes a polygon being drawn (so do double-click, right-click and its first point).
  if(ev.type==4&&ev.phase==1&&(ev.code==48||ev.code==50))finishPolygon();
  if(ev.phase==8||(ev.type==4&&ev.phase==1&&ev.code==48)){
   if(C[2].x==1){C[3].z=1;C[3].w=1;}C[2].x=0;continue;
  }
  if(ev.type==4&&ev.phase==1){
   if(ev.code==1&&(ev.modifiers&2)!=0&&C[34].x<.5){[unroll]for(int k=0;k<25;k++)C[8+k].x=1;}
   if(ev.code==6)fit();
  }
  // Arrow keys nudge the selection one screen pixel at the current zoom (Shift: 10, Alt: 0.1), and
  // auto-repeat while held. Zoom in for finer steps. Screen up is world -y.
  if(ev.type==4&&(ev.phase==1||ev.phase==2)&&ev.code>=53&&ev.code<=56&&C[2].x==0&&C[34].x<.5){
   float px=((ev.modifiers&VIEWPORT_MODIFIER_SHIFT)!=0?10:(ev.modifiers&VIEWPORT_MODIFIER_ALT)!=0?.1:1)/(canvasScale()*C[0].z);
   C[33].xy+=px*(ev.code==53?float2(-1,0):ev.code==54?float2(1,0):ev.code==55?float2(0,-1):float2(0,1));
  }
  if(ev.type==3&&_ViewportButtons==0)C[2].x=0;
  if(ev.type==3&&C[2].x==0&&(ev.flags&VIEWPORT_EVENT_FLAG_HOST_CONSUMED)==0){
   float4 v=C[0];float2 anchor=world(ev.position,v);
   v.z=clamp(v.z*exp2(ev.value*.25),.05,4096);v.xy=anchor-canvasOffset(ev.position)/v.z;C[0]=v;
  }
  // A press always starts a fresh gesture. Rapid clicks arrive as double-click (phase 4), not
  // press (1): accept both or every other click in a quick series is dropped. And if a release
  // was lost (focus left mid-drag), the stale gesture must not swallow this press: end it here.
  bool press=ev.type==2&&(ev.phase==1||ev.phase==4)&&(ev.flags&VIEWPORT_EVENT_FLAG_HOST_CONSUMED)==0;
  if(press&&C[2].x>0){if(C[2].x==1)C[3].w=1;C[2].x=0;}
  if(press){
   C[1]=float4(world(ev.position,C[0]),world(ev.position,C[0]));
   C[39]=float4(world(ev.position,C[0]),0,0); // the real pointer, for Alt fine-drag
   C[5]=float4(ev.position,C[0].xy);
   float2 ppx=ev.position*_Resolution;uint n=maskCount(),row=0;
   uint hit=ev.code==0?panelHit(ppx,n,row):0;
   if(ev.code==1&&C[34].w>0){finishPolygon();C[2].x=0;}
   else if(ev.code==1||ev.code==2){C[2]=float4(3,ev.code,0,0);}
   else if(hit>0){
    // The panel never starts a canvas gesture.
    C[2].x=0;
    if(hit>=10&&hit<=22)finishPolygon();
    if(hit==10)C[34].x=0;
    if(hit==11)C[34].x=1;
    if(hit>=20&&hit<=22){C[34].x=1;C[34].y=hit-20;}
    if(hit>=30&&hit<=32){C[34].x=1;C[34].z=row+1;}
    if(hit==31)maskOp(3,row,0,0);
    if(hit==32)maskOp(4,row,0,0);
    if(hit==33){if((int)C[34].w-1==(int)row)C[34].w=0;maskOp(5,row,0,0);int s=(int)C[34].z-1;C[34].z=s==(int)row?0:(s>(int)row?s:s+1);}
   }
   else if(ev.code==0&&C[34].x>.5){
    float2 q=worldToScan(world(ev.position,C[0]));int sel=(int)C[34].z-1,build=(int)C[34].w-1;bool handled=false;
    // Drawing a polygon: every click adds a point (drag to place it), clicking the first point closes it.
    if(build>=0&&build<(int)n){
     uint np=polyCount(build);handled=true;
     if(ev.phase==4)finishPolygon();
     else if(np>=3&&length(canvasPixel(scanToWorld(polyPoint(build,0)),C[0])-ppx)<14)C[34].w=0;
     else if(np<POLY_MAX){maskOp(6,build,0,float4(q,0,0));C[37]=float4(q,np,build);C[2]=float4(7,0,0,0);}
     else C[34].w=0;
    }
    // The selected mask's own handles come first.
    if(!handled&&sel>=0&&sel<(int)n){
     float4 info=maskInfo(sel),r=maskRect(sel);
     if(info.x>1.5){
      uint np=polyCount(sel);
      [loop]for(uint i=0;i<np;i++)if(!handled&&length(canvasPixel(scanToWorld(polyPoint(sel,i)),C[0])-ppx)<9){C[37]=float4(q,i,sel);C[2]=float4(7,0,0,0);handled=true;}
      // Pressing on an edge adds a point there and drags it.
      [loop]for(uint e=0;e<np;e++){uint e1=(e+1)%np;
       if(!handled&&np>=3&&segDist(ppx,canvasPixel(scanToWorld(polyPoint(sel,e)),C[0]),canvasPixel(scanToWorld(polyPoint(sel,e1)),C[0]))<6&&np<POLY_MAX){
        maskOp(7,sel,e,float4(q,0,0));C[37]=float4(q,e+1,sel);C[2]=float4(7,0,0,0);handled=true;}}
     }else{
      if(length(canvasPixel(scanToWorld(knobOf(info,r,scanPixels())),C[0])-ppx)<9){C[37]=float4(r.xy,0,sel);C[2]=float4(8,0,0,0);handled=true;}
      // Resize from a corner; the opposite corner stays put.
      [unroll]for(uint c=0;c<4;c++){float2 k=cornerOf(info,r,c);
       if(!handled&&length(canvasPixel(scanToWorld(k),C[0])-ppx)<9){C[37]=float4(2*r.xy-k,0,sel);C[2]=float4(6,0,0,0);handled=true;}}
     }
    }
    // Any mask under the pointer: select it and move it.
    if(!handled){
     int found=-1;
     [loop]for(int j=(int)n-1;j>=0;j--)if(found<0&&maskDistance(j,q)*scanPixels()<4)found=j;
     if(found>=0){C[34].z=found+1;C[37]=float4(q,0,found);C[38]=float4(maskRect(found).xy,0,0);C[2]=float4(5,0,0,0);handled=true;}
    }
    // Empty space: deselect, and start a new shape with the current tool (a bare click leaves none).
    if(!handled){
     C[34].z=0;
     if(n<MASK_MAX){
      uint tool=(uint)C[34].y;maskOp(1,n,tool,float4(q,0,0));C[34].z=n+1;C[37]=float4(q,0,n);
      if(tool==2){C[34].w=n+1;C[2]=float4(7,0,0,0);}else C[2]=float4(4,0,0,0);
     }
    }
   }
   else if(ev.code==0){
   float best=1e9;int chosen=-1;
   [unroll]for(int k=0;k<25;k++){
    float dist=length(canvasPixel(Points[BANK+k].xy,C[0])-ev.position*_Resolution);
    if(dist<(corner(k)?16:11)&&dist<best){best=dist;chosen=k;}
   }
   bool additive=(ev.modifiers&1)!=0;
   if(chosen>=0){
    if(!additive&&C[8+chosen].x<.5){[unroll]for(int k=0;k<25;k++)C[8+k].x=0;}
    C[8+chosen].x=1;
    C[2]=float4(1,0,chosen,0);C[3].x=1;C[3].w=1;
   }else{
    if(!additive){[unroll]for(int k=0;k<25;k++)C[8+k].x=0;}
    [unroll]for(int k=0;k<25;k++)C[8+k].y=C[8+k].x;
    C[2]=float4(2,0,0,0);
   }
   }
  }
  bool release=ev.type==2&&ev.phase==3&&ev.code==(uint)C[2].y;
  bool move=(ev.type==1||(ev.type==5&&ev.code==3&&ev.device==(uint)C[2].y&&(ev.phase==5||ev.phase==6||ev.phase==7)))&&(_ViewportButtons&(1u<<(uint)C[2].y))!=0&&(ev.flags&VIEWPORT_EVENT_FLAG_HOST_CONSUMED)==0;
  if(C[2].x>0&&(move||release)){
   int mode=(int)C[2].x;
   if(mode==3)C[0].xy=C[5].zw-(ev.position-C[5].xy)*_Resolution/(canvasScale()*C[0].z);
   else{
    // C[1].zw is a virtual cursor: it follows the pointer's MOVEMENT, at a tenth of the speed while
    // Alt is held, so a handle, mask or polygon point can be placed finely. Pressing or releasing
    // Alt mid-drag never jumps it. Box select still follows the pointer itself.
    float2 pw=world(ev.position,C[0]);
    if(mode==2)C[1].zw=pw;
    else C[1].zw+=(pw-C[39].xy)*((ev.modifiers&VIEWPORT_MODIFIER_ALT)!=0?.1:1);
    C[39].xy=pw;
    if(mode==1){C[3].y=1;C[3].w=1;}
    if(mode==2){
     float2 lo=min(C[1].xy,C[1].zw),hi=max(C[1].xy,C[1].zw);
     [unroll]for(int k=0;k<25;k++)C[8+k].x=max(C[8+k].y,(all(Points[BANK+k].xy>=lo)&&all(Points[BANK+k].xy<=hi))?1:0);
    }
    if(mode>=4){
     float2 q=worldToScan(C[1].zw);uint j=(uint)C[37].w;bool shift=(ev.modifiers&VIEWPORT_MODIFIER_SHIFT)!=0;
     if(mode==5){
      float2 moved=q-C[37].xy;
      if(maskInfo(j).x>1.5){maskOp(8,j,0,float4(moved-C[38].zw,0,0));C[38].zw=moved;}
      else maskOp(2,j,0,float4(C[38].xy+moved,maskRect(j).zw));
     }
     if(mode==7)maskOp(9,j,C[37].z,float4(q,0,0));
     if(mode==8){
      // The knob points along the shape's local -y; Shift snaps to 15 degrees.
      float2 v=q-C[37].xy;float a=atan2(v.x,-v.y);if(shift)a=round(a/0.2617994)*0.2617994;
      maskOp(10,j,0,float4(a,0,0,0));
     }
     if(mode==4||mode==6){
      // Corner to corner from the anchor, in the shape's own rotated frame; Shift: square/circle.
      float ang=mode==6?maskInfo(j).w:0;float2 d=rot(q-C[37].xy,-ang);
      if(shift){float s=max(abs(d.x),abs(d.y));d=float2(d.x<0?-s:s,d.y<0?-s:s);}
      maskOp(2,j,0,float4(C[37].xy+rot(d*.5,ang),abs(d)*.5));
      // A click without a drag leaves no sliver of a mask behind.
      if(release&&mode==4&&any(abs(d)*scanPixels()<3)){
       if(C[35].x==1&&(uint)C[35].y==j)C[35]=0;else maskOp(5,j,0,0);
       C[34].z=0;
      }
     }
    }
   }
   if(release||(ev.type==5&&ev.phase==7&&ev.device==(uint)C[2].y))C[2].x=0;
  }
 }
 if(C[2].x>0&&(_ViewportButtons&(1u<<(uint)C[2].y))==0)C[2].x=0;
 float count=0;[unroll]for(int k=0;k<25;k++)count+=C[8+k].x;C[4].x=count;
}
