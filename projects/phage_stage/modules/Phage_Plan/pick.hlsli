// The handle under a canvas pixel, shared by the editor (state.hlsl picks on a press) and the layout
// (which lifts the handle the pointer is over before anything is pressed), so what lights is what a
// press would take. Returns (leg, kind): kind 1 a foot in plan, 0 a leg's line in plan (selects it),
// 2 the selected leg's knee in section; leg -1 when nothing is in reach. Include after phage_anatomy
// and layout.hlsli.
int2 planPick(float2 px,int sel,PhDesign D,PhPose R){
 int pick=-1,kind=0;float best=12;
 if(inRect(px,planRect())){
  for(uint i=0;i<6;i++){float d=length(px-planPx(phAnkle(D,R,i)));if(d<best){best=d;pick=(int)i;kind=1;}}
  if(pick<0){best=7;for(uint i=0;i<6;i++){float3 h=phHip(D,R,i),kn=phKnee(D,R,i),a=phAnkle(D,R,i);
   float d=min(segDist(px,planPx(h),planPx(kn)),segDist(px,planPx(kn),planPx(a)));if(d<best){best=d;pick=(int)i;kind=0;}}}
 }else if(inRect(px,sectRect())&&sel>=0){
  float az=phLegAz((uint)sel);if(length(px-sectPx(phKnee(D,R,(uint)sel),az))<14){pick=sel;kind=2;}
 }
 return int2(pick,kind);
}
