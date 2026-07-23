#include "types.hlsli"
StructuredBuffer<EditorState> _Tex0 : register(t0);
StructuredBuffer<FurnishingState> _Tex1 : register(t1);
RWStructuredBuffer<FurnishingState> OutputBuffer : register(u0);

void initialize() {
    [loop] for (uint i=0u;i<LR_OBJECT_COUNT;++i) {
        FurnishingState state=(FurnishingState)0; state.object_id=i+1u; state.marker=i==0u?7319.0:0.0; OutputBuffer[i]=state;
    }
}

[numthreads(1,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (abs(OutputBuffer[0].marker-7319.0)>0.5) initialize();
    EditorState editor=_Tex0[0]; uint command=(uint)round(editor.command);
    if(command==5u)command=3u;if(command==6u)command=2u;
    if(command==8u){initialize();return;}
    uint active=(uint)round(editor.active_id);if(active<1u||active>LR_OBJECT_COUNT)return;uint index=active-1u;
    if(command==7u){FurnishingState reset=OutputBuffer[index];reset.offset=0.0;reset.yaw_offset=0.0;OutputBuffer[index]=reset;return;}
    if(command==4u){OutputBuffer[index]=_Tex1[index];return;}
    if(command!=2u&&command!=3u)return;
    FurnishingState base=_Tex1[index];FurnishingState state=base;float2 delta=editor.pointer-editor.drag_start;
    if(editor.mode<0.5){
        float2 worldDelta=lrPlanWorld(editor.pointer,editor.view_pan,editor.view_zoom)-lrPlanWorld(editor.drag_start,editor.view_pan,editor.view_zoom);
        state.offset=base.offset+worldDelta;
        if(editor.snap_enabled>0.5){float step=max(editor.snap_step,0.01);state.offset=round(state.offset/step)*step;}
    }else{
        state.yaw_offset=base.yaw_offset+delta.x*6.2831853;
        if(editor.snap_enabled>0.5){float step=radians(15.0);state.yaw_offset=round(state.yaw_offset/step)*step;}
    }
    OutputBuffer[index]=state;OutputBuffer[0].marker=7319.0;
}
