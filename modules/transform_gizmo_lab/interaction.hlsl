#include "types.hlsli"
#include "../_shared/ui/sui_interaction.hlsli"
#include "_ui.generated.hlsli"
StructuredBuffer<SceneObject> _Tex0 : register(t0);
RWStructuredBuffer<GizmoState> OutputBuffer : register(u0);

void selectionPivot(out float3 pivot,out uint activeId,out uint selectedCount){pivot=0;selectedCount=0u;activeId=_ViewportSelectionMeta.y;[loop]for(uint i=0u;i<16u;i++)if(_Tex0[i].object_id>0u&&labSelected(_Tex0[i].object_id)){pivot+=_Tex0[i].position;selectedCount++;}if(selectedCount>0u)pivot/=selectedCount;}
uint selectionMask(){uint mask=0u;[loop]for(uint i=0u;i<16u;i++){uint id=_Tex0[i].object_id;if(id>0u&&id<=24u&&labSelected(id))mask|=1u<<(id-1u);}return mask;}
float3 activeRotation(uint activeId){[loop]for(uint i=0u;i<16u;i++)if(_Tex0[i].object_id==activeId)return _Tex0[i].rotation;return 0;}

uint hitHandle(float2 p,GizmoState st,uint activeId){
    return labGizmoHit(p,st,activeRotation(activeId));
}

[numthreads(1,1,1)]
void main(uint3 tid:SV_DispatchThreadID){
    GizmoState st=OutputBuffer[0];uint modeParam=(uint)clamp(transform_mode,0,2);uint localParam=local_space?1u:0u;
    if(st.mode<0||st.mode>2||isnan(st.mode)){st.mode=(float)modeParam;st.local_space=(float)localParam;st.last_local_param=100.0+(float)localParam+2.0*(float)modeParam;st.active_handle=0;st.dragging=0;}
    // Keep capture alive across cooks with no pointer events. Only clear the
    // handle on the cook after an explicit commit/cancel boundary.
    if(st.dragging<0.5&&(st.command==3.0||st.command==4.0||st.command==5.0))st.active_handle=0.0;
    st.command=0;
    uint packedSync=st.last_local_param>=99.0?(uint)round(st.last_local_param-100.0):99u;
    uint previousLocal=packedSync&1u,previousMode=(packedSync>>1u)&3u;
    if(packedSync==99u||modeParam!=previousMode)st.mode=(float)modeParam;
    if(packedSync==99u||localParam!=previousLocal)st.local_space=(float)localParam;
    st.last_local_param=100.0+(float)localParam+2.0*(float)modeParam;
    if(suiInteraction(UI_INDEX_TRANSLATE).down)st.mode=0;
    if(suiInteraction(UI_INDEX_ROTATE).down)st.mode=1;
    if(suiInteraction(UI_INDEX_SCALE).down)st.mode=2;
    float3 pivot;uint activeId,count;selectionPivot(pivot,activeId,count);uint currentMask=selectionMask();
    // Pointer events describe the gizmo rendered on the previous frame. Keep
    // that rendered pivot/selection as the transaction source even if a host
    // release-pick has already changed the live selection in this same cook.
    float3 renderedPivot=st.active_id>0.5?st.pivot:pivot;uint renderedActive=st.active_id>0.5?(uint)round(st.active_id):activeId;uint renderedMask=st.selection_mask>0.5?(uint)round(st.selection_mask):currentMask;bool ownsTransaction=st.drag_pad.z>0.5;
    bool beganThisCook=false;uint events=min(_ViewportEventCount,64u);[loop]for(uint i=0u;i<events;i++){ViewportEvent e=_ViewportEvents[i];
        if(e.type==4u&&e.phase==1u){if(e.code==33u)st.mode=0;if(e.code==34u)st.mode=1;if(e.code==35u)st.mode=2;if(e.code==36u)st.local_space=1.0-st.local_space;if(e.code==48u&&st.dragging>0.5){st.command=4;st.dragging=0;}}
        // A drag Begin is reported at the first point beyond the host drag
        // threshold, which can already be far past a narrow handle. Arm the
        // handle at the actual mouse-down position and reuse that hit when the
        // gesture begins, so fast pointer motion cannot outrun acquisition.
        if(e.type==2u&&e.code==0u&&e.phase==1u&&renderedMask>0u&&st.dragging<0.5){
            st.pivot=renderedPivot;st.active_id=(float)renderedActive;uint armed=hitHandle(e.position,st,renderedActive);st.drag_pad=float3(e.position,(float)armed);if(armed>0u){st.selection_mask=(float)renderedMask;ownsTransaction=true;}
        }
        if(e.type==2u&&e.code==0u&&e.phase==3u&&st.dragging<0.5){st.drag_pad.z=0.0;ownsTransaction=false;}
        if(e.type!=5u||e.code!=3u||e.device!=0u)continue;
        if(e.phase==5u&&renderedMask>0u){uint handle=st.drag_pad.z>0.5?(uint)round(st.drag_pad.z):hitHandle(e.position,st,renderedActive);float2 press=st.drag_pad.z>0.5?st.drag_pad.xy:e.position;if(handle>0u){st.pivot=renderedPivot;st.active_id=(float)renderedActive;st.selection_mask=(float)renderedMask;st.active_handle=(float)handle;st.dragging=1;st.command=1;beganThisCook=true;ownsTransaction=true;st.drag_start=press;st.pointer=e.position;float2 cp=labProject(renderedPivot);uint axis=min(handle-1u,2u);float ringRadius=42.0+12.0*(float)axis;st.start_angle=(uint)round(st.mode)==1u&&handle<=3u?labRotationPointerAngle(press,renderedPivot,axis,st.local_space>0.5,activeRotation(renderedActive),ringRadius):atan2(press.y-cp.y,press.x-cp.x);st.start_radius=length((press-cp)*labViewportSize());}}
        else if(st.dragging>0.5&&st.active_handle>0u&&(e.phase==6u||e.phase==7u||e.phase==8u)){ownsTransaction=true;st.pointer=e.position;if(e.phase==8u){st.command=4;st.dragging=0;st.drag_pad.z=0;}else if(e.phase==7u){st.command=beganThisCook?5.0:3.0;st.dragging=0;st.drag_pad.z=0;}else st.command=beganThisCook?6.0:2.0;}
    }
    if(!ownsTransaction&&st.dragging<0.5){st.pivot=pivot;st.active_id=(float)activeId;st.selection_mask=(float)currentMask;}
    OutputBuffer[0]=st;
}
