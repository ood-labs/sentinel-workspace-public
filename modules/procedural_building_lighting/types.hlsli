#ifndef PROCEDURAL_BUILDING_LIGHTING_TYPES_HLSLI
#define PROCEDURAL_BUILDING_LIGHTING_TYPES_HLSLI
static const uint LC_OBJECT_COUNT=4u;static const float4 LC_EDIT_RECT=float4(.025,.112,.975,.955);
struct LightRecord{float3 position;float type_id;float3 direction;float range;float3 color;float intensity;float2 size;float softness;float enabled;};
struct LightControlState{float2 position;float rotation;uint object_id;float marker;float3 pad;};
struct LightEditorState{float command;float active_id;float dragging;float control_latch;float2 pointer;float2 drag_start;float marker;float pad0;float4 pad1;};
float2 lcCanvasToWorld(float2 p){float2 n=(p-LC_EDIT_RECT.xy)/max(LC_EDIT_RECT.zw-LC_EDIT_RECT.xy,1e-5);return float2((n.x-.5)*18.0,(.5-n.y)*18.0);}
float2 lcWorldToCanvas(float2 p){float2 n=float2(.5+p.x/18.0,.5-p.y/18.0);return lerp(LC_EDIT_RECT.xy,LC_EDIT_RECT.zw,n);}
bool lcSelected(uint objectId){for(uint i=0u;i<min(_ViewportSelectionMeta.x,64u);++i)if(_ViewportSelectionIds[i/4u][i%4u]==objectId)return true;return false;}
#endif
