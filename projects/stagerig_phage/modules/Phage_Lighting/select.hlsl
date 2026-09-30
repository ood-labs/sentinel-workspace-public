// Canvas selection over all 248 slots. Click picks the nearest fixture in the view it lands in, drag
// box-selects in the view it started in (Shift adds, Ctrl toggles), A selects all, Escape clears, and
// the 16 buttons select groups. The Surface mirrors the result through selection_word0-15 and can push
// its own selection back through remote_selection0-15 + selection_apply.
// S[0]=(dragging, modifiers, drag view, magic) S[1]=drag rect px S[2]=(last event, -, apply seen, changes)
// S[3]=(selected count) S[4+slot]=(selected, before gesture) S[252+w]=16-bit words.
#include "lighting.hlsli"
StructuredBuffer<PhMount> Mounts:register(t0);
RWStructuredBuffer<float4>S:register(u0);
uint viewAt(float2 px,float2 R){[unroll]for(uint v=0;v<2;v++){float4 r=viewRect(v,R);if(all(px>=r.xy)&&all(px<=r.zw))return v;}return 9;}
float combine(uint mods,bool hit,float prev){return (mods&2)?(hit?1-prev:prev):(mods&1)?max(prev,hit?1:0):(hit?1:0);}
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){
 float2 R=_Resolution.xy;
 if(S[0].w!=SEL_MAGIC){[loop]for(uint i=0;i<SEL_ROWS;i++)S[i]=0;S[0].w=SEL_MAGIC;}
 if(_Data0_Count<PH_SLOTS)return;
 bool change=false;
 float words[16]={remote_selection0,remote_selection1,remote_selection2,remote_selection3,remote_selection4,remote_selection5,remote_selection6,remote_selection7,
  remote_selection8,remote_selection9,remote_selection10,remote_selection11,remote_selection12,remote_selection13,remote_selection14,remote_selection15};
 if(S[2].z!=selection_apply){[loop]for(uint f=0;f<PH_SLOTS;f++)S[SEL_SLOT0+f].x=((uint)words[f/16]>>(f%16))&1;S[2].z=selection_apply;}
 uint count=min((uint)_ViewportEventCount,64u);
 if(count>0&&_ViewportEvents[count-1].sequence<S[2].x)S[2].x=0;
 [loop]for(uint k=0;k<count;k++){ViewportEvent e=_ViewportEvents[k];
  if(e.sequence<=S[2].x)continue;S[2].x=e.sequence;float2 px=e.position*R;uint mods=(uint)e.modifiers;
  if(e.type==2&&e.phase==1&&e.code==0&&px.y<.16*R.y){
   [loop]for(uint b=0;b<GROUPS;b++){float4 r=buttonRect(b,R);if(all(px>=r.xy)&&all(px<=r.zw)){
    [loop]for(uint f=0;f<PH_SLOTS;f++)S[SEL_SLOT0+f].x=combine(mods,inGroup(b,Mounts[f]),S[SEL_SLOT0+f].x);change=true;}}
   S[0].x=0;continue;}
  if(e.type==4&&e.phase==1&&(e.code==1||e.code==48)){[loop]for(uint f=0;f<PH_SLOTS;f++)S[SEL_SLOT0+f].x=e.code==1?Mounts[f].active:0;S[0].x=0;change=true;continue;}
  if(e.type==2&&e.phase==1&&e.code==0){uint v=viewAt(px,R);if(v>1)continue;
   S[0].x=1;S[0].y=mods;S[0].z=v;S[1]=float4(px,px);uint pick=999;float best=14;
   [loop]for(uint f=0;f<PH_SLOTS;f++){S[SEL_SLOT0+f].y=S[SEL_SLOT0+f].x;PhMount m=Mounts[f];if(m.active<.5)continue;
    float d=length(px-toView(v,m.position,R));if(d<best){best=d;pick=f;}}
   [loop]for(uint f=0;f<PH_SLOTS;f++)S[SEL_SLOT0+f].x=combine(mods,f==pick,S[SEL_SLOT0+f].y);change=true;}
  if(e.type==5&&e.code==3&&S[0].x>0){uint v=(uint)S[0].z;uint dm=(uint)S[0].y;
   if(e.phase==8){[loop]for(uint f=0;f<PH_SLOTS;f++)S[SEL_SLOT0+f].x=S[SEL_SLOT0+f].y;S[0].x=0;}
   else if(e.phase==6||e.phase==7){S[1].zw=px;float2 lo=min(S[1].xy,px),hi=max(S[1].xy,px);
    [loop]for(uint f=0;f<PH_SLOTS;f++){PhMount m=Mounts[f];float2 p=toView(v,m.position,R);bool hit=all(p>=lo)&&all(p<=hi)&&m.active>.5;
     S[SEL_SLOT0+f].x=combine(dm,hit,S[SEL_SLOT0+f].y);}
    if(e.phase==7)S[0].x=0;}
   change=true;}
  if(e.type==2&&e.phase==2)S[0].x=0;
 }
 if(change)S[2].w+=1;
 uint n=0;[loop]for(uint w=0;w<16;w++){uint bits=0;[loop]for(uint b=0;b<16;b++){uint f=w*16+b;if(f<PH_SLOTS&&S[SEL_SLOT0+f].x>.5&&Mounts[f].active>.5){bits|=1u<<b;n++;}}S[SEL_WORD0+w]=float4(bits,0,0,0);}
 S[3]=float4(n,0,0,0);
}
