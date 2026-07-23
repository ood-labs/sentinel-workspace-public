#include "types.hlsli"
struct ViewportPickResult { uint object_id; uint hit; float3 world_position; float3 world_normal; float distance; uint sub_element_id; };
StructuredBuffer<PNode> _Tex0 : register(t0); StructuredBuffer<EditorState> _Tex1 : register(t1); RWStructuredBuffer<ViewportPickResult> OutputBuffer : register(u0);

void boundsFor(uint objectId,out float2 low,out float2 high){low=1e6;high=-1e6;[loop]for(uint i=0u;i<LR_RECORD_COUNT;++i)if(lrObjectForRecord(i)==objectId){PNode n=_Tex0[i];float2 half=float2(n.width,n.depth)*0.5;low=min(low,n.position.xz-half);high=max(high,n.position.xz+half);}}

[numthreads(1,1,1)]
void main(uint3 tid:SV_DispatchThreadID){if(_ViewportPickQuery.w==0u)return;float2 query=float2(_ViewportPickRayOrigin.w,_ViewportPickRayDirection.w);ViewportPickResult result=(ViewportPickResult)0;result.distance=-1.0;result.sub_element_id=0xffffffffu;if(query.y<LR_PLAN_TOP){OutputBuffer[0]=result;return;}EditorState editor=_Tex1[0];float2 world=lrPlanWorld(query,editor.view_pan,editor.view_zoom);float best=1e9;[loop]for(uint id=1u;id<=LR_OBJECT_COUNT;++id){float2 low,high;boundsFor(id,low,high);float2 center=(low+high)*0.5;float2 half=max((high-low)*0.5,0.08)+0.14;float2 q=abs(world-center)/half;if(max(q.x,q.y)>1.0)continue;float score=dot(q,q);if(score<best){best=score;result.object_id=id;result.hit=1u;result.world_position=float3(center.x,0,center.y);result.world_normal=float3(0,1,0);result.distance=0.0;}}OutputBuffer[0]=result;}
