#ifndef TRANSFORM_GIZMO_TYPES_HLSLI
#define TRANSFORM_GIZMO_TYPES_HLSLI

struct SceneObject {
    float3 position; float pad0;
    float3 rotation; float pad1;
    float3 scale; uint object_id;
    uint kind; uint flags; float marker; float pad2;
};

// Reseed sentinel. NOT a range check on `mode`: mode 0 is legal, so a zeroed
// buffer looks like a valid Move-mode state and the seed never runs. Same defect
// and same cure as SD_MAGIC in modules/spline_desk/interaction.hlsl.
#define GD_MAGIC 7321.0

struct GizmoState {
    float mode; float local_space; float active_handle; float command;
    float2 pointer; float2 drag_start;
    float3 pivot; float last_local_param;
    float active_id; float start_angle; float start_radius; float selection_mask;
    float dragging; float3 drag_pad;
    // Rising-edge latch for the numeric-transform doors, then the deferred
    // transform command and the reseed sentinel. GizmoState moves from 80 to 96
    // bytes; the published Gizmo State schema keeps its original field order and
    // appends these so a consumer deriving stride from the schema gets 96.
    float auto_latch; float pending; float magic; float pad3;
};

float2 labViewportSize() { return max(_Resolution.xy, float2(1.0, 1.0)); }

float3x3 labRotation(float3 degreesValue) {
    float3 a=radians(degreesValue); float cx=cos(a.x),sx=sin(a.x),cy=cos(a.y),sy=sin(a.y),cz=cos(a.z),sz=sin(a.z);
    float3x3 rx=float3x3(1,0,0,0,cx,-sx,0,sx,cx);
    float3x3 ry=float3x3(cy,0,sy,0,1,0,-sy,0,cy);
    float3x3 rz=float3x3(cz,-sz,0,sz,cz,0,0,0,1);
    return mul(rz,mul(ry,rx));
}

bool labSelected(uint objectId) {
    for(uint i=0u;i<min(_ViewportSelectionMeta.x,64u);i++) if(_ViewportSelectionIds[i/4u][i%4u]==objectId)return true;
    return false;
}

float2 labProject(float3 p) {
    float4 clip=mul(_ViewProjMatrix,float4(p,1)); if(abs(clip.w)<1e-5)return float2(-1000,-1000);
    float2 ndc=clip.xy/clip.w; return float2(ndc.x*0.5+0.5,0.5-ndc.y*0.5);
}

float labSegmentDistance(float2 p,float2 a,float2 b){float2 ba=b-a;float h=saturate(dot(p-a,ba)/max(dot(ba,ba),1e-7));return length(p-(a+ba*h));}

float3 labAxisWorld(uint axis, bool localMode, float3 rotation) {
    float3 a = axis == 0u ? float3(1,0,0) : (axis == 1u ? float3(0,1,0) : float3(0,0,1));
    return normalize(localMode ? mul(labRotation(rotation), a) : a);
}

float2 labAxisScreenVector(float3 pivot, uint axis, bool localMode, float3 rotation) {
    float2 viewport = labViewportSize();
    float2 centerPx = labProject(pivot) * viewport;
    float2 unitPx = labProject(pivot + labAxisWorld(axis, localMode, rotation)) * viewport;
    float2 v = unitPx - centerPx;
    if (dot(v,v) < 1e-4) v = axis == 0u ? float2(1,0) : (axis == 1u ? float2(0,-1) : normalize(float2(1,-1)));
    return v;
}

float2 labGizmoAxisEnd(float3 pivot, uint axis, bool localMode, float3 rotation) {
    float2 center = labProject(pivot);
    float2 dirPx = normalize(labAxisScreenVector(pivot, axis, localMode, rotation));
    return center + dirPx * 72.0 / labViewportSize();
}

void labRotationPlane(uint axis, bool localMode, float3 rotation, out float3 u, out float3 v) {
    uint uAxis = axis == 0u ? 1u : (axis == 1u ? 2u : 0u);
    uint vAxis = axis == 0u ? 2u : (axis == 1u ? 0u : 1u);
    u = labAxisWorld(uAxis, localMode, rotation);
    v = labAxisWorld(vAxis, localMode, rotation);
}

void labRotationScreenBasis(float3 pivot, uint axis, bool localMode, float3 rotation, float radiusPx,
                            out float2 centerPx, out float2 uPx, out float2 vPx) {
    float2 viewport = labViewportSize();
    centerPx = labProject(pivot) * viewport;
    float3 uWorld, vWorld;
    labRotationPlane(axis, localMode, rotation, uWorld, vWorld);
    uPx = labProject(pivot + uWorld) * viewport - centerPx;
    vPx = labProject(pivot + vWorld) * viewport - centerPx;
    float scale = radiusPx / max(max(length(uPx), length(vPx)), 1e-4);
    uPx *= scale;
    vPx *= scale;
}

float labRotationRingDistancePx(float2 p, float3 pivot, uint axis, bool localMode, float3 rotation, float radiusPx) {
    float2 centerPx, uPx, vPx;
    labRotationScreenBasis(pivot, axis, localMode, rotation, radiusPx, centerPx, uPx, vPx);
    float2 d = p * labViewportSize() - centerPx;
    float determinant = uPx.x * vPx.y - uPx.y * vPx.x;
    if (abs(determinant) < max(radiusPx * radiusPx * 0.012, 1.0)) {
        float2 major = dot(uPx, uPx) > dot(vPx, vPx) ? uPx : vPx;
        return labSegmentDistance(p * labViewportSize(), centerPx - major, centerPx + major);
    }
    float2 q = float2((d.x * vPx.y - d.y * vPx.x) / determinant,
                      (uPx.x * d.y - uPx.y * d.x) / determinant);
    return abs(length(q) - 1.0) * max(min(length(uPx), length(vPx)), 2.0);
}

float labRotationPointerAngle(float2 p, float3 pivot, uint axis, bool localMode, float3 rotation, float radiusPx) {
    float2 centerPx, uPx, vPx;
    labRotationScreenBasis(pivot, axis, localMode, rotation, radiusPx, centerPx, uPx, vPx);
    float2 d = p * labViewportSize() - centerPx;
    float determinant = uPx.x * vPx.y - uPx.y * vPx.x;
    if (abs(determinant) < max(radiusPx * radiusPx * 0.012, 1.0)) return atan2(d.y, d.x);
    float2 q = float2((d.x * vPx.y - d.y * vPx.x) / determinant,
                      (uPx.x * d.y - uPx.y * d.x) / determinant);
    return atan2(q.y, q.x);
}

uint labGizmoHit(float2 p, GizmoState st, float3 activeRot) {
    float2 viewport=labViewportSize(),center=labProject(st.pivot),pPx=p*viewport,centerPx=center*viewport;
    float best=18.0;uint hit=0u;
    if((uint)round(st.mode)==1u){float radius[3]={42,54,66};[unroll]for(uint i=0u;i<3u;i++){float d=labRotationRingDistancePx(p,st.pivot,i,st.local_space>0.5,activeRot,radius[i]);if(d<best){best=d;hit=i+1u;}}return hit;}
    float2 ends[3];
    [unroll]for(uint axis=0u;axis<3u;axis++){ends[axis]=labGizmoAxisEnd(st.pivot,axis,st.local_space>0.5,activeRot);float2 a=centerPx,b=ends[axis]*viewport,ba=b-a;float along=saturate(dot(pPx-a,ba)/max(dot(ba,ba),1e-7));float d=length(pPx-(a+ba*along));if(along>0.20&&d<best){best=d;hit=axis+1u;}}
    // Plane handles exist only in Move mode and never steal a click from a
    // visible axis line where their projected regions overlap.
    if((uint)round(st.mode)==0u&&hit==0u){
        if(length(pPx-(centerPx+(ends[0]+ends[1]-center*2.0)*viewport*0.28))<11.0)hit=4u;
        if(length(pPx-(centerPx+(ends[1]+ends[2]-center*2.0)*viewport*0.28))<11.0)hit=5u;
        if(length(pPx-(centerPx+(ends[2]+ends[0]-center*2.0)*viewport*0.28))<11.0)hit=6u;
    }
    if((uint)round(st.mode)==2u&&length(pPx-centerPx)<13.0)hit=7u;
    return hit;
}

#endif
