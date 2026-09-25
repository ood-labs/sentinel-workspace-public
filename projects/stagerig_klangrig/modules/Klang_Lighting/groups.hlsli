#include "group_layout.hlsli"
float3 groupButtons(float2 p,float3 color){

 uint labels[32]={group_label_1_0,group_label_1_1,group_label_1_2,group_label_1_3,group_label_2_0,group_label_2_1,group_label_2_2,group_label_2_3,group_label_3_0,group_label_3_1,group_label_3_2,group_label_3_3,group_label_4_0,group_label_4_1,group_label_4_2,group_label_4_3,group_label_5_0,group_label_5_1,group_label_5_2,group_label_5_3,group_label_6_0,group_label_6_1,group_label_6_2,group_label_6_3,group_label_7_0,group_label_7_1,group_label_7_2,group_label_7_3,group_label_8_0,group_label_8_1,group_label_8_2,group_label_8_3};
 [loop]for(uint i=0;i<16;i++){
  float4 r=groupRect(i)*_Resolution.xyxy;if(any(p<r.xy)||any(p>r.zw))continue;
  bool active=((uint)group_selected&(1u<<i))!=0;
  color=active?float3(.18,.40,.39):float3(.07,.11,.15);
  float edge=min(min(p.x-r.x,r.z-p.x),min(p.y-r.y,r.w-p.y));
  if(edge<1)color=active?float3(.45,.83,.75):float3(.19,.28,.32);
  float scale=(_Resolution.x>=1500)?1.5:1;
  float2 origin=float2(r.x+8,(r.y+r.w-11*scale)*.5);
  int ch=(int)floor((p.x-origin.x)/(7*scale));int code=32;
  if(ch>=0&&ch<12){code=i<12?uiLabelCode(i,ch):(labels[(i-12)*4+ch/3]>>(8*(ch%3)))&255;
    float ink=sui3Glyph(p,origin+float2(ch*7*scale,0),scale,code);
    color=lerp(color,float3(.87,.93,.94),ink);}
  break;
 }
 return color;
}
