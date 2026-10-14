// Still Life / pick - answers the HOST's selection queries (viewport.selection provider ray_query).
//
// The host asks only on a click (press and release without a drag). A click on the gizmo answers
// with the active object and the handle as sub_element_id. Otherwise the internal camera's ray
// through the clicked position is marched through the same field the program renders: the first
// object surface is the answer, the room is a miss (and a miss clears the selection).
#include "../_shared/ui/il_core.hlsli"

#define SL_RECORD_ONLY
#include "still.hlsli"
#undef SL_RECORD_ONLY
StructuredBuffer<SlObject> Objs : register(t0);
#define SL_OBJECTS Objs
#include "still.hlsli"

struct ViewportPickResult { uint object_id; uint hit; float3 world_position; float3 world_normal; float distance; uint sub_element_id; };
RWStructuredBuffer<ViewportPickResult> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (_ViewportPickQuery.w == 0u) return;              // nothing pending
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    // The query's normalized image position is in the .w components. Its xyz "ray" is a generic
    // screen ray (origin (u, v, -1), direction +z on 0.6.3) - the host does not know this
    // module's camera - so the real ray comes from the internal camera, exactly as the march
    // builds it.
    float2 uv = float2(_ViewportPickRayOrigin.w, _ViewportPickRayDirection.w);
    float3 ro, rd;
    slRay(uv, ro, rd);
    ViewportPickResult r = (ViewportPickResult)0;
    r.distance = -1.0;
    r.sub_element_id = 0xFFFFFFFFu;

    uint act = slActive();
    if (act != 0u)
    {
        SlGizmo g = slGizmoOf(Objs[act], res, s);
        uint h = slGizmoHit(uv * res, g, res, s);
        if (h != G_NONE)
        {
            // The host has no "leave the selection alone" answer (an id no descriptor carries
            // clears it; sub_element_id does not change what a click selects), so a plain click
            // on a handle narrows a multi-selection to the active object. A drag never asks.
            r.object_id = Objs[act].id;
            r.hit = 1u;
            r.world_position = g.pivot;
            r.world_normal = normalize(ro - g.pivot);
            r.distance = length(g.pivot - ro);
            r.sub_element_id = h;
            OutputBuffer[0] = r;
            return;
        }
    }

    float t; uint rec;
    if (slMarch(ro, rd, 128u, t, rec) && rec != 0u)
    {
        float3 p = ro + rd * t;
        const float e = 0.0008;
        float3 n = normalize(float3(slField(p + float3(e, 0, 0)) - slField(p - float3(e, 0, 0)),
                                    slField(p + float3(0, e, 0)) - slField(p - float3(0, e, 0)),
                                    slField(p + float3(0, 0, e)) - slField(p - float3(0, 0, e))));
        r.object_id = Objs[rec].id;
        r.hit = 1u;
        r.world_position = p;
        r.world_normal = n;
        r.distance = t;
        r.sub_element_id = 0u;
    }
    OutputBuffer[0] = r;
}
