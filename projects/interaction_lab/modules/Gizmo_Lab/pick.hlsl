#include "types.hlsli"
struct ViewportPickResult{uint object_id;uint hit;float3 world_position;float3 world_normal;float distance;uint sub_element_id;};
StructuredBuffer<SceneObject> _Tex0:register(t0);
StructuredBuffer<GizmoState> _Tex1:register(t1);
RWStructuredBuffer<ViewportPickResult> OutputBuffer:register(u0);

float pickRadius(SceneObject o){
    float base=o.kind==0u?0.52:(o.kind==1u?0.73:(o.kind==2u?0.54:0.62));
    return base*max(o.scale.x,max(o.scale.y,o.scale.z));
}

[numthreads(1,1,1)]
void main(uint3 tid:SV_DispatchThreadID){
    if(_ViewportPickQuery.w==0u)return;
    float2 query=float2(_ViewportPickRayOrigin.w,_ViewportPickRayDirection.w);
    float2 queryPx=query*labViewportSize();
    float bestScore=1e9;uint bestId=0u;float3 bestPos=0;
    GizmoState st=_Tex1[0];uint activeId=(uint)round(st.active_id);float3 activeRot=0;
    [loop]for(uint activeScan=0u;activeScan<16u;activeScan++)if(_Tex0[activeScan].object_id==activeId){activeRot=_Tex0[activeScan].rotation;bestPos=_Tex0[activeScan].position;}
    bool gizmoTransaction=st.drag_pad.z>0.5||st.dragging>0.5||st.command==2.0||st.command==3.0||st.command==5.0||st.command==6.0;
    if(activeId>0u&&(gizmoTransaction||labGizmoHit(query,st,activeRot)>0u)){ViewportPickResult selected=(ViewportPickResult)0;selected.object_id=activeId;selected.hit=1u;selected.world_position=bestPos;selected.world_normal=normalize(_CameraPos-bestPos);selected.distance=length(_CameraPos-bestPos);selected.sub_element_id=0xffffffffu;OutputBuffer[0]=selected;return;}
    [loop]for(uint i=0u;i<16u;i++){
        SceneObject o=_Tex0[i];if(o.object_id==0u)continue;
        float radius=pickRadius(o);float2 center=labProject(o.position);
        float2 centerPx=center*labViewportSize();
        float rx=length((labProject(o.position+float3(radius,0,0))-center)*labViewportSize());
        float ry=length((labProject(o.position+float3(0,radius,0))-center)*labViewportSize());
        float rz=length((labProject(o.position+float3(0,0,radius))-center)*labViewportSize());
        float hitRadius=max(18.0,max(rx,max(ry,rz)))+6.0;
        float screenDistance=length(queryPx-centerPx);
        if(screenDistance>hitRadius)continue;
        float depth=length(_CameraPos-o.position);
        float score=screenDistance/max(hitRadius,1.0)+depth*0.0005;
        if(score<bestScore){bestScore=score;bestId=o.object_id;bestPos=o.position;}
    }
    ViewportPickResult r=(ViewportPickResult)0;r.object_id=bestId;r.hit=bestId>0u?1u:0u;r.world_position=bestPos;r.world_normal=normalize(_CameraPos-bestPos);r.distance=r.hit?length(_CameraPos-bestPos):-1.0;r.sub_element_id=0xffffffffu;OutputBuffer[0]=r;
}
