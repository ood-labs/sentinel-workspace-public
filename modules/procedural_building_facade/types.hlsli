#ifndef PROCEDURAL_BUILDING_FACADE_TYPES_HLSLI
#define PROCEDURAL_BUILDING_FACADE_TYPES_HLSLI
static const uint FC_OBJECT_COUNT=2u;
static const float4 FC_EDIT_RECT=float4(.025,.112,.975,.955);
static const float4 FC_GRID_RECT_LOCAL=float4(.06,.14,.94,.86);
static const float FC_PICK_RADIUS_PX=26.0;
static const float2 FC_LOCAL_MIN=float2(.045,.045);
static const float2 FC_LOCAL_MAX=float2(.955,.955);
struct FacadeElement{float3 position;float type_id;float3 size;float yaw;float material_id;float seed;float emissive;float active;float2 uv;float floor_index;float bay_index;};
struct FacadeControlState{float2 position;float rotation;uint object_id;float marker;float3 pad;};
struct FacadeEditorState{float command;float active_id;float dragging;float control_latch;float2 pointer;float2 drag_start;float marker;float pad0;float4 pad1;};
float2 fcCanvasFromLocal(float2 localPosition){return lerp(FC_EDIT_RECT.xy,FC_EDIT_RECT.zw,clamp(localPosition,FC_LOCAL_MIN,FC_LOCAL_MAX));}
float2 fcLocalFromCanvas(float2 canvasPosition){return clamp((canvasPosition-FC_EDIT_RECT.xy)/max(FC_EDIT_RECT.zw-FC_EDIT_RECT.xy,1e-5),FC_LOCAL_MIN,FC_LOCAL_MAX);}
float fcCanvasDistancePx(float2 a,float2 b){return length((a-b)*_Resolution.xy);}
float2 fcSemantic01(float2 statePosition){return saturate((statePosition-FC_LOCAL_MIN)/max(FC_LOCAL_MAX-FC_LOCAL_MIN,1e-5));}
float2 fcFeatureCanvas(float2 statePosition,float3 buildingBase,float buildingWidth,float buildingHeight){
 float2 n=fcSemantic01(statePosition);uint bays=(uint)max(front_bays,1),floorCount=(uint)max(floors,1);
 uint bay=min((uint)(n.x*(float)bays),bays-1u),floorIndex=min((uint)((1.0-n.y)*(float)floorCount),floorCount-1u);
 float2 elevationLocal=float2(lerp(FC_GRID_RECT_LOCAL.x,FC_GRID_RECT_LOCAL.z,((float)bay+.5)/(float)bays),lerp(FC_GRID_RECT_LOCAL.w,FC_GRID_RECT_LOCAL.y,((float)floorIndex+.5)/(float)floorCount));
 return lerp(FC_EDIT_RECT.xy,FC_EDIT_RECT.zw,elevationLocal);
}
float2 fcFeatureSemanticAtCanvas(float2 canvasPosition,float3 buildingBase,float buildingWidth,float buildingHeight){
 float2 elevationLocal=(canvasPosition-FC_EDIT_RECT.xy)/max(FC_EDIT_RECT.zw-FC_EDIT_RECT.xy,1e-5);
 float bayN=saturate((elevationLocal.x-FC_GRID_RECT_LOCAL.x)/max(FC_GRID_RECT_LOCAL.z-FC_GRID_RECT_LOCAL.x,1e-5));
 float downN=saturate((elevationLocal.y-FC_GRID_RECT_LOCAL.y)/max(FC_GRID_RECT_LOCAL.w-FC_GRID_RECT_LOCAL.y,1e-5));
 return lerp(FC_LOCAL_MIN,FC_LOCAL_MAX,float2(bayN,downN));
}
bool fcSelected(uint objectId){for(uint i=0u;i<min(_ViewportSelectionMeta.x,64u);++i)if(_ViewportSelectionIds[i/4u][i%4u]==objectId)return true;return false;}
#endif
