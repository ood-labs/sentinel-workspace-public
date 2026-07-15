#include "types.hlsli"
#include "../_shared/ui/sui_v2.hlsli"
#include "_ui.generated.hlsli"
#include "../_shared/ui/sui_generated_text.hlsli"

StructuredBuffer<SceneObject> _Tex0 : register(t0);
StructuredBuffer<GizmoState> _Tex1 : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float sdSphereLab(float3 p, float r) { return length(p) - r; }
float sdBoxLab(float3 p, float3 b) { float3 q = abs(p) - b; return min(max(q.x, max(q.y, q.z)), 0.0) + length(max(q, 0.0)); }
float sdTorusLab(float3 p, float2 t) { float2 q = float2(length(p.xz) - t.x, p.y); return length(q) - t.y; }
float sdCapsuleLab(float3 p, float h, float r) { p.y -= clamp(p.y, -h, h); return length(p) - r; }

float objectSdf(SceneObject object, float3 p) {
    float3 q = mul(transpose(labRotation(object.rotation)), p - object.position) / max(object.scale, 0.05);
    float d = object.kind == 0u ? sdSphereLab(q, 0.48) : (object.kind == 1u ? sdBoxLab(q, 0.42.xxx) : (object.kind == 2u ? sdTorusLab(q, float2(0.34, 0.14)) : sdCapsuleLab(q, 0.30, 0.25)));
    return d * min(object.scale.x, min(object.scale.y, object.scale.z));
}

float sceneSdf(float3 p, out uint objectId) {
    float distance = 1e9;
    objectId = 0u;
    [loop] for (uint i = 0u; i < 16u; ++i) {
        SceneObject object = _Tex0[i];
        if (object.object_id == 0u) continue;
        float objectDistance = objectSdf(object, p);
        if (objectDistance < distance) { distance = objectDistance; objectId = object.object_id; }
    }
    float floorDistance = p.y + 2.15;
    if (floorDistance < distance) { distance = floorDistance; objectId = 0u; }
    return distance;
}

float3 normalAt(float3 p) {
    uint objectId;
    float e = 0.002;
    float d = sceneSdf(p, objectId);
    return normalize(float3(sceneSdf(p + float3(e,0,0), objectId) - d, sceneSdf(p + float3(0,e,0), objectId) - d, sceneSdf(p + float3(0,0,e), objectId) - d));
}

float4 toolbarRect(uint index) {
    if (index == 0u) return UI_RECT_TRANSLATE;
    if (index == 1u) return UI_RECT_ROTATE;
    if (index == 2u) return UI_RECT_SCALE;
    return UI_RECT_LOCAL;
}

uint toolbarIndex(uint index) {
    if (index == 0u) return UI_INDEX_TRANSLATE;
    if (index == 1u) return UI_INDEX_ROTATE;
    if (index == 2u) return UI_INDEX_SCALE;
    return UI_INDEX_LOCAL;
}

uint toolbarLabel(uint index) {
    if (index == 0u) return UI_LABEL_MOVE;
    if (index == 1u) return UI_LABEL_ROTATE;
    if (index == 2u) return UI_LABEL_SCALE;
    return UI_LABEL_LOCAL;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    SuiContext c = suiContext(tid.xy, _Resolution.xy);
    SuiTheme theme = suiMonochromeTheme();
    float2 ndc = float2(c.uv.x * 2.0 - 1.0, 1.0 - c.uv.y * 2.0);
    float4 farWorld = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    farWorld /= farWorld.w;
    float3 rayOrigin = _CameraPos;
    float3 rayDirection = normalize(farWorld.xyz - rayOrigin);
    float travel = 0.0;
    uint objectId = 0u;
    float distance = 0.0;
    [loop] for (int stepIndex = 0; stepIndex < 80; ++stepIndex) {
        distance = sceneSdf(rayOrigin + rayDirection * travel, objectId);
        if (abs(distance) < 0.0015 || travel > 40.0) break;
        travel += max(distance, 0.004);
    }

    float3 color = theme.background;
    if (travel < 40.0) {
        float3 p = rayOrigin + rayDirection * travel;
        float3 normal = normalAt(p);
        float3 light = normalize(float3(-0.4, 0.8, -0.5));
        float diffuse = saturate(dot(normal, light)) * 0.75 + 0.18;
        if (objectId == 0u) {
            float checker = frac((floor(p.x) + floor(p.z)) * 0.5) * 2.0;
            float floorLevel = lerp(0.055, 0.105, checker);
            color = floorLevel.xxx * (0.68 + diffuse * 0.32);
        } else {
            float level = 0.40 + 0.035 * fmod((float)objectId, 5.0);
            float3 base = level.xxx;
            if (labSelected(objectId)) base = lerp(base, theme.text, 0.72);
            color = base * diffuse + pow(saturate(dot(reflect(-light, normal), -rayDirection)), 32.0) * 0.25;
        }
    }
    GizmoState state = _Tex1[0];
    if (_ViewportSelectionMeta.x > 0u) {
        float2 center = labProject(state.pivot);
        float3 activeRotation = 0.0;
        [loop] for (uint i = 0u; i < 16u; ++i) if (_Tex0[i].object_id == (uint)round(state.active_id)) activeRotation = _Tex0[i].rotation;
        if ((uint)round(state.mode) == 1u) {
            float radius[3] = { 42.0, 54.0, 66.0 };
            [unroll] for (uint axis = 0u; axis < 3u; ++axis) {
                float3 axisColor = axis == 0u ? theme.axisX : (axis == 1u ? theme.axisY : theme.axisZ);
                float width = (uint)round(state.active_handle) == axis + 1u ? 5.0 : 2.5;
                float ringDistance = labRotationRingDistancePx(c.uv, state.pivot, axis, state.local_space > 0.5, activeRotation, radius[axis]);
                suiComposite(color, axisColor, suiCoverage(ringDistance - width * 0.5));
            }
        } else {
            float2 ends[3];
            [unroll] for (uint axis = 0u; axis < 3u; ++axis) ends[axis] = labGizmoAxisEnd(state.pivot, axis, state.local_space > 0.5, activeRotation);
            if ((uint)round(state.mode) == 0u) {
                [unroll] for (uint planeIndex = 0u; planeIndex < 3u; ++planeIndex) {
                    uint a = planeIndex == 0u ? 0u : (planeIndex == 1u ? 1u : 2u);
                    uint b = planeIndex == 0u ? 1u : (planeIndex == 1u ? 2u : 0u);
                    float2 plane = center + (ends[a] + ends[b] - center * 2.0) * 0.28;
                    float size = (uint)round(state.active_handle) == planeIndex + 4u ? 11.0 : 8.0;
                    float mask = suiCoverage(max(abs(c.pixel.x - plane.x * c.resolution.x), abs(c.pixel.y - plane.y * c.resolution.y)) - size);
                    float3 planeColor = planeIndex == 0u ? (theme.axisX + theme.axisY) * 0.5 : (planeIndex == 1u ? (theme.axisY + theme.axisZ) * 0.5 : (theme.axisZ + theme.axisX) * 0.5);
                    suiComposite(color, planeColor, mask * 0.75);
                }
            }
            [unroll] for (uint axis = 0u; axis < 3u; ++axis) {
                float3 axisColor = axis == 0u ? theme.axisX : (axis == 1u ? theme.axisY : theme.axisZ);
                float width = (uint)round(state.active_handle) == axis + 1u ? 6.0 : 4.0;
                suiComposite(color, axisColor, suiLinePx(c, center, ends[axis], width));
                suiComposite(color, axisColor, suiDiscPx(c, ends[axis], 7.0));
            }
            if ((uint)round(state.mode) == 2u) suiComposite(color, theme.text, suiDiscPx(c, center, 9.0));
        }
    }

    suiComposite(color, theme.panelRaised, suiFillRect(c, float4(0.0, 0.0, 1.0, 0.119)));
    suiComposite(color, theme.text, suiFillRect(c, float4(0.0, 0.0, 0.0042, 0.119)));
    suiComposite(color, theme.text, suiLabelText(c, float2(0.023, 0.041), suiTitleStyle(), UI_LABEL_TITLE));
    [unroll] for (uint button = 0u; button < 4u; ++button) {
        float4 rect = toolbarRect(button);
        bool selected = (button < 3u && (uint)round(state.mode) == button) || (button == 3u && state.local_space > 0.5);
        suiButton(color, c, theme, rect, suiInteraction(toolbarIndex(button)), selected);
        if (button == 3u) {
            float4 toggleThumb = suiToggleThumb(c, theme, rect, saturate(state.local_space));
            suiComposite(color, toggleThumb.rgb, toggleThumb.a);
        }
        suiComposite(color, selected ? theme.background : theme.text,
            suiLabelText(c, rect.xy + float2(12.0, 11.0) * c.invResolution, suiBodyStyle(), toolbarLabel(button)));
    }
    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
