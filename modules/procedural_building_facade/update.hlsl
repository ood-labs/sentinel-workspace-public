#include "types.hlsli"
StructuredBuffer<FacadeEditorState> _Tex1:register(t1);StructuredBuffer<FacadeControlState> _Tex2:register(t2);RWStructuredBuffer<FacadeControlState> OutputBuffer:register(u0);
void init(){FacadeControlState a=(FacadeControlState)0;a.position=float2(.62,.42);a.object_id=1;a.marker=7319;OutputBuffer[0]=a;FacadeControlState b=(FacadeControlState)0;b.position=float2(.47,.68);b.object_id=2;OutputBuffer[1]=b;}
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 if(abs(OutputBuffer[0].marker-7319)>.5){
  if(abs(OutputBuffer[0].marker-6227)<.5){[unroll]for(uint i=0u;i<FC_OBJECT_COUNT;++i){FacadeControlState migrated=OutputBuffer[i];migrated.position=fcLocalFromCanvas(migrated.position);OutputBuffer[i]=migrated;}OutputBuffer[0].marker=7319;}
  else init();
 }
 FacadeEditorState e=_Tex1[0];uint c=(uint)round(e.command);if(c==5u)c=3u;if(c==6u)c=2u;if(c==8u){init();return;}uint active=(uint)round(e.active_id);if(active<1u||active>FC_OBJECT_COUNT)return;uint ix=active-1u;
 if(c==7u){FacadeControlState r=OutputBuffer[ix];r.position=ix==0u?float2(.62,.42):float2(.47,.68);OutputBuffer[ix]=r;return;}if(c==4u){OutputBuffer[ix]=_Tex2[ix];return;}if(c!=2u&&c!=3u)return;
 FacadeControlState s=_Tex2[ix];if(ix==1u&&_Data0_Count>=3){float3 base=float3(_Data0[2].position[0],_Data0[2].position[1],_Data0[2].position[2]);s.position=fcFeatureSemanticAtCanvas(e.pointer,base,_Data0[2].width,_Data0[2].height);}else{float2 localDelta=(e.pointer-e.drag_start)/max(FC_EDIT_RECT.zw-FC_EDIT_RECT.xy,1e-5);s.position=clamp(s.position+localDelta,FC_LOCAL_MIN,FC_LOCAL_MAX);}OutputBuffer[ix]=s;OutputBuffer[0].marker=7319;
}
