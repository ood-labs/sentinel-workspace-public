
#include "../_shared/rig.hlsli"
float rowCount(uint w){float counts[12]={wing_01_count,wing_02_count,wing_03_count,wing_04_count,wing_05_count,wing_06_count,wing_07_count,wing_08_count,wing_09_count,wing_10_count,wing_11_count,wing_12_count};return counts[w];}
float3 wingPoint(uint w,uint k){
 uint bay=w/4,arm=w%4;float side=arm%2==0?-1:1,level=arm<2?1:-1;
 float z=(1-(float)bay)*bay_spacing;
 bool inner=k==0||k==3;
 float x=inner?inner_width:wing_width;
 float y=spine_height+wing_height_offset+level*(tier_separation*.5+(inner?0:wing_rise));
 return float3(side*x,y,z+(k==0?wing_length*.48:k==1?wing_length*.27:k==2?-wing_length*.27:-wing_length*.48));
}
float3 handle(uint h){return h==0?float3(0,spine_height,0):wingPoint(h-1,1);}
uint viewAt(float2 p){return p.y<_Resolution.y*.5?0:p.x<_Resolution.x*.65?1:2;}
float scaleAt(uint v){return v==0?min(_Resolution.x*.88/(spine_length+4),_Resolution.y*.36/(wing_width*2+3)):v==1?min(_Resolution.x*.56/(spine_length+4),_Resolution.y*.35/14):min(_Resolution.x*.28/(wing_width*2+3),_Resolution.y*.35/14);}
float2 originAt(uint v){return v==0?float2(_Resolution.x*.5,_Resolution.y*.28):v==1?float2(_Resolution.x*.325,_Resolution.y*.93):float2(_Resolution.x*.825,_Resolution.y*.93);}
float2 project(float3 p,uint v){return originAt(v)+scaleAt(v)*(v==0?float2(-p.z,p.x):v==1?float2(-p.z,-p.y):float2(p.x,-p.y));}
float lineDist(float2 p,float2 a,float2 b){float2 d=b-a;return length(p-a-d*saturate(dot(p-a,d)/max(dot(d,d),.00001)));}
