#include "types.hlsli"
#include "../_shared/ui/sui_interaction.hlsli"
#include "_ui.generated.hlsli"
StructuredBuffer<FacadeControlState> _Tex1:register(t1);
RWStructuredBuffer<FacadeEditorState> OutputBuffer:register(u0);
float2 fcHandleCanvas(uint i){if(i==1u&&_Data0_Count>=3){float3 base=float3(_Data0[2].position[0],_Data0[2].position[1],_Data0[2].position[2]);return fcFeatureCanvas(_Tex1[i].position,base,_Data0[2].width,_Data0[2].height);}return fcCanvasFromLocal(_Tex1[i].position);}
uint fcHandleAt(float2 pointer){uint hit=0u;float best=FC_PICK_RADIUS_PX;[unroll]for(uint i=0u;i<FC_OBJECT_COUNT;++i){float d=fcCanvasDistancePx(pointer,fcHandleCanvas(i));if(d<best){best=d;hit=i+1u;}}return hit;}
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){FacadeEditorState st=OutputBuffer[0];if(abs(st.marker-6113)>.5){st=(FacadeEditorState)0;st.marker=6113;}st.command=0;
 uint down=(suiInteraction(UI_INDEX_RESET).down?1u:0u)|(suiInteraction(UI_INDEX_RESET_ALL).down?2u:0u);uint pressed=down&~(uint)round(st.control_latch);st.control_latch=(float)down;if((pressed&1u)!=0u&&_ViewportSelectionMeta.y>0u){st.active_id=(float)_ViewportSelectionMeta.y;st.command=7;}if((pressed&2u)!=0u)st.command=8;
 bool began=false;uint count=min(_ViewportEventCount,64u);[loop]for(uint i=0u;i<count;++i){ViewportEvent e=_ViewportEvents[i];if(e.type==4u&&e.phase==1u&&e.code==52u){bool shift=(e.modifiers&VIEWPORT_MODIFIER_SHIFT)!=0u;if(shift)st.command=8;else if(_ViewportSelectionMeta.y>0u){st.active_id=(float)_ViewportSelectionMeta.y;st.command=7;}}if(e.type==4u&&e.phase==1u&&e.code==48u&&st.dragging>.5){st.command=4;st.dragging=0;}
  bool drag=e.type==5u&&e.code==3u&&e.device==0u;if(!drag)continue;if(e.phase==5u){uint hit=fcHandleAt(e.position);if(hit>0u){st.active_id=(float)hit;st.drag_start=e.position;st.pointer=e.position;st.dragging=1;st.command=1;began=true;}}else if(st.dragging>.5&&(e.phase==6u||e.phase==7u||e.phase==8u)){st.pointer=e.position;if(e.phase==8u){st.command=4;st.dragging=0;}else if(e.phase==7u){st.command=began?5:3;st.dragging=0;}else st.command=began?6:2;}}
 OutputBuffer[0]=st;}
