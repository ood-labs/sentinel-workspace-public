// Gizmo Desk - pre-edit snapshot, the base every transform is computed from and
// the buffer cancel restores.
//
// CAPTURES ON COMMAND 1 ONLY. Command 1 is the drag BEGIN, and `update`
// early-returns on it, so scene_state still holds the pre-edit objects no matter
// which order the scheduler picked for the snapshot/update cycle.
//
// It used to also capture on 5 and 6 -- begin and move landing in one cook --
// which is precisely the cook where `update` DOES transform. The scheduler runs
// `update` first, so those captures recorded post-transform objects. Those
// commands no longer reach this buffer: interaction.hlsl defers them by a cook
// and reports the begin instead, so the capture below is always clean.
#include "types.hlsli"
StructuredBuffer<GizmoState> _Tex0:register(t0);StructuredBuffer<SceneObject> _Tex1:register(t1);RWStructuredBuffer<SceneObject> OutputBuffer:register(u0);
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){if((uint)round(_Tex0[0].command)!=1u)return;[loop]for(uint i=0u;i<16u;i++)OutputBuffer[i]=_Tex1[i];}
