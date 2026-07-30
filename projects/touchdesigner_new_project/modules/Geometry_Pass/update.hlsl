#include "types.hlsli"
StructuredBuffer<GizmoState> _Tex0 : register(t0);
StructuredBuffer<SceneObject> _Tex1 : register(t1);
RWStructuredBuffer<SceneObject> OutputBuffer : register(u0);

void initialize() {
    for (uint index = 0u; index < 16u; ++index) {
        SceneObject o = (SceneObject)0;
        if (index == 0u) {
            o.object_id = 1u;
            o.kind = 1u;
            o.position = float3(0.0, 0.0, 0.0);
            o.rotation = float3(0.0, 0.0, 0.0);
            o.scale = 1.0.xxx;
            o.flags = 7u;
            o.marker = 8932.0;
        }
        OutputBuffer[index] = o;
    }
}

float3 rotateAround(float3 v, float3 axis, float angle) {
    return v * cos(angle) + cross(axis, v) * sin(angle) +
           axis * dot(axis, v) * (1.0 - cos(angle));
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (abs(OutputBuffer[0].marker - 8932.0) > 0.5) initialize();
    GizmoState st = _Tex0[0];
    uint cmd = (uint)round(st.command);
    // Numeric orbit about the SHARED pivot of the selection, which is the same
    // pivot the gizmo drag uses -- two objects orbit together and each keeps
    // its own orientation updated, rather than each spinning in place.
    if (cmd == 20u) {
        uint mask = (uint)round(st.selection_mask);
        float3 pivot = 0.0; uint n = 0u;
        [loop] for (uint pi = 0u; pi < 16u; ++pi) {
            uint id = OutputBuffer[pi].object_id;
            if (id == 0u || id > 24u || (mask & (1u << (id - 1u))) == 0u) continue;
            pivot += OutputBuffer[pi].position; n++;
        }
        if (n == 0u) return;
        pivot /= (float)n;
        uint ax = (uint)clamp(orbit_axis, 0, 2);
        float3 axis = ax == 0u ? float3(1,0,0) : (ax == 1u ? float3(0,1,0) : float3(0,0,1));
        float ang = radians(orbit_degrees);
        [loop] for (uint oi = 0u; oi < 16u; ++oi) {
            uint id = OutputBuffer[oi].object_id;
            if (id == 0u || id > 24u || (mask & (1u << (id - 1u))) == 0u) continue;
            SceneObject base = OutputBuffer[oi];
            SceneObject o = base;
            o.position = pivot + rotateAround(base.position - pivot, axis, ang);
            if (ax == 0u) o.rotation.x = base.rotation.x + orbit_degrees;
            if (ax == 1u) o.rotation.y = base.rotation.y + orbit_degrees;
            if (ax == 2u) o.rotation.z = base.rotation.z + orbit_degrees;
            OutputBuffer[oi] = o;
        }
        return;
    }
    // 5 and 6 deliberately have NO mapping here any more. They mean "begin and
    // transform landed in the same cook", and interaction.hlsl now rewrites them
    // into a begin plus a deferred 3 or 2 so the transform runs against a clean
    // snapshot. Mapping them through would restore the exact bug that deferral
    // exists to fix: a transform applied against the PREVIOUS transaction's
    // snapshot. If one ever reaches this pass it falls through the range check
    // below and does nothing, which is a visibly dropped gesture rather than
    // silently corrupted transforms.
    if (cmd < 2u || cmd > 4u) return;
    uint handle = (uint)round(st.active_handle);
    float2 deltaPx = (st.pointer - st.drag_start) * labViewportSize();

    float3 activeRot = 0.0;
    for (uint scan = 0u; scan < 16u; ++scan)
        if (_Tex1[scan].object_id == (uint)round(st.active_id)) activeRot = _Tex1[scan].rotation;
    uint rotationAxis = handle > 0u ? min(handle - 1u, 2u) : 0u;
    float ringRadius = 42.0 + 12.0 * (float)rotationAxis;
    float pointerAngle = labRotationPointerAngle(st.pointer, st.pivot, rotationAxis, st.local_space > 0.5, activeRot, ringRadius);
    float angle = atan2(sin(pointerAngle - st.start_angle), cos(pointerAngle - st.start_angle));
    float uniformScale = max(0.05, 1.0 + (deltaPx.x - deltaPx.y) / 120.0);

    for (uint objectIndex = 0u; objectIndex < 16u; ++objectIndex) {
        uint objectId=_Tex1[objectIndex].object_id;uint mask=(uint)round(st.selection_mask);
        if (objectId == 0u || objectId>24u || (mask&(1u<<(objectId-1u)))==0u) continue;
        SceneObject base = _Tex1[objectIndex];
        SceneObject o = base;
        if (cmd == 4u) { OutputBuffer[objectIndex] = base; continue; }

        if ((uint)round(st.mode) == 0u) {
            float3 move = 0.0;
            if (handle <= 3u) {
                float3 axis = labAxisWorld(handle-1u, st.local_space>0.5, activeRot);
                float2 screen = labAxisScreenVector(st.pivot, handle-1u, st.local_space>0.5, activeRot);
                // The rendered handle has a fixed screen length, so use a
                // fixed pixel-to-world sensitivity as well. Dividing by the
                // projection of one world unit becomes singular for an axis
                // aimed toward the camera and causes enormous jumps.
                move = axis * dot(deltaPx, normalize(screen)) / 90.0;
            } else {
                uint axisA = handle == 4u ? 0u : (handle == 5u ? 1u : 2u);
                uint axisB = handle == 4u ? 1u : (handle == 5u ? 2u : 0u);
                float3 worldA=labAxisWorld(axisA,st.local_space>0.5,activeRot),worldB=labAxisWorld(axisB,st.local_space>0.5,activeRot);
                float2 screenA=labAxisScreenVector(st.pivot,axisA,st.local_space>0.5,activeRot),screenB=labAxisScreenVector(st.pivot,axisB,st.local_space>0.5,activeRot);
                float2 dirA=normalize(screenA),dirB=normalize(screenB);float det=dirA.x*dirB.y-dirA.y*dirB.x;
                if(abs(det)>0.08){float a=(deltaPx.x*dirB.y-deltaPx.y*dirB.x)/det/90.0;float b=(dirA.x*deltaPx.y-dirA.y*deltaPx.x)/det/90.0;move=worldA*a+worldB*b;}
            }
            o.position = base.position + move;
        } else if ((uint)round(st.mode) == 1u && handle <= 3u) {
            float3 axis = labAxisWorld(handle-1u, st.local_space>0.5, activeRot);
            o.position = st.pivot + rotateAround(base.position - st.pivot, axis, angle);
            if (handle == 1u) o.rotation.x = base.rotation.x + degrees(angle);
            if (handle == 2u) o.rotation.y = base.rotation.y + degrees(angle);
            if (handle == 3u) o.rotation.z = base.rotation.z + degrees(angle);
        } else if ((uint)round(st.mode) == 2u) {
            if (handle == 7u) {
                o.scale = base.scale * uniformScale;
                o.position = st.pivot + (base.position - st.pivot) * uniformScale;
            } else if (handle <= 3u) {
                float3 axis = labAxisWorld(handle-1u, st.local_space>0.5, activeRot);
                float2 screen=labAxisScreenVector(st.pivot,handle-1u,st.local_space>0.5,activeRot);
                float scaleFactor=max(0.05,1.0+dot(deltaPx,normalize(screen))/90.0);
                float3 rel = base.position - st.pivot;
                o.position = st.pivot + rel + axis * dot(rel, axis) * (scaleFactor - 1.0);
                if (handle == 1u) o.scale.x = base.scale.x * scaleFactor;
                if (handle == 2u) o.scale.y = base.scale.y * scaleFactor;
                if (handle == 3u) o.scale.z = base.scale.z * scaleFactor;
            }
        }
        OutputBuffer[objectIndex] = o;
    }
}
