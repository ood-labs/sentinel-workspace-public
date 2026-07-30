// Procedural SDF reconstruction of TouchDesigner's Geometry viewer.
//
// The cube begins at world origin with zero rotation. The elevated three-quarter
// view belongs to Sentinel's internal camera, not to a baked object transform.
// The RGB coordinate axes are thin world-space SDF cylinders, so perspective,
// intersection, and occlusion are genuinely three-dimensional.
#include "types.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "../_shared/ui/sui3_theme.hlsli"

StructuredBuffer<SceneObject> Scene : register(t1);
StructuredBuffer<GizmoState> Gizmo  : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);

static const float3 AXIS_R = float3(0.92, 0.22, 0.20);
static const float3 AXIS_G = float3(0.28, 0.82, 0.32);
static const float3 AXIS_B = float3(0.30, 0.50, 0.95);
static const float AXIS_RADIUS = 0.0045;

float3 axisColor(uint a) { return a == 0u ? AXIS_R : (a == 1u ? AXIS_G : AXIS_B); }

struct SdfSample
{
    float distance;
    uint material;
};

float sdBox(float3 p, float3 halfExtent)
{
    float3 q = abs(p) - halfExtent;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

SdfSample sceneSdf(float3 p, SceneObject cube)
{
    SdfSample s;
    float3 local = mul(transpose(labRotation(cube.rotation)), p - cube.position);
    s.distance = sdBox(local, max(cube.scale, 0.05));
    s.material = 1u;

    // Infinite world axes. Their union with the box naturally disappears
    // inside the cube and re-emerges on the far side.
    float dx = length(p.yz) - AXIS_RADIUS;
    float dy = length(p.xz) - AXIS_RADIUS;
    float dz = length(p.xy) - AXIS_RADIUS;
    if (dx < s.distance) { s.distance = dx; s.material = 2u; }
    if (dy < s.distance) { s.distance = dy; s.material = 3u; }
    if (dz < s.distance) { s.distance = dz; s.material = 4u; }
    return s;
}

float3 normalAt(float3 p, SceneObject cube)
{
    float e = 0.0025;
    float d = sceneSdf(p, cube).distance;
    float3 g = float3(
        sceneSdf(p + float3(e,0,0), cube).distance - d,
        sceneSdf(p + float3(0,e,0), cube).distance - d,
        sceneSdf(p + float3(0,0,e), cube).distance - d);
    return dot(g,g) > 1e-18 ? normalize(g) : float3(0,1,0);
}

float3 boxLocalNormal(float3 local, float3 halfExtent)
{
    float3 q = abs(local / max(halfExtent, 0.0001));
    if (q.x > q.y && q.x > q.z) return float3(sign(local.x),0,0);
    if (q.y > q.z) return float3(0,sign(local.y),0);
    return float3(0,0,sign(local.z));
}

float2 cubeUv(float3 local, float3 n, float3 halfExtent)
{
    float3 q = local / max(halfExtent, 0.0001);
    float2 outUv;
    if (abs(n.x) > 0.5)      outUv = float2(n.x > 0.0 ? -q.z : q.z, -q.y);
    else if (abs(n.y) > 0.5) outUv = float2(q.x, n.y > 0.0 ? q.z : -q.z);
    else                     outUv = float2(n.z > 0.0 ? q.x : -q.x, -q.y);
    return outUv * 0.5 + 0.5;
}

float axisLabel(float2 P, float2 anchor, float s, int signCode, int axisCode)
{
    float c = sui3Glyph(P, anchor, s, signCode);
    c = max(c, sui3Glyph(P, anchor + float2(7.0*s,0), s, S_0 + 1));
    c = max(c, sui3Glyph(P, anchor + float2(14.0*s,0), s, axisCode));
    return c;
}

[numthreads(8,8,1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 R = _Resolution.xy;
    if (tid.x >= (uint)R.x || tid.y >= (uint)R.y) return;
    float2 P = float2(tid.xy) + 0.5;
    float2 uv = P / R;

    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 farW = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    farW /= farW.w < 0.0 ? min(farW.w, -0.000001) : max(farW.w, 0.000001);
    float3 ro = _CameraPos;
    float3 rd = normalize(farW.xyz - ro);

    SceneObject cube = Scene[0];
    float travel = 0.0;
    SdfSample hit = sceneSdf(ro, cube);
    bool found = false;
    [loop] for (int stepIndex = 0; stepIndex < 128; ++stepIndex)
    {
        float3 p = ro + rd * travel;
        hit = sceneSdf(p, cube);
        float eps = 0.00075 * max(travel, 1.0);
        if (hit.distance < eps) { found = true; break; }
        travel += max(hit.distance * 0.88, eps * 0.45);
        if (travel > 100.0) break;
    }

    Sui3Theme T = sui3Theme(float3(1.0,0.42,0.09));
    float3 col = float3(0.075,0.077,0.079);
    if (found)
    {
        float3 p = ro + rd * travel;
        float3 n = normalAt(p, cube);
        if (hit.material == 1u)
        {
            float3x3 rotation = labRotation(cube.rotation);
            float3 local = mul(transpose(rotation), p - cube.position);
            float3 localN = boxLocalNormal(local, max(cube.scale,0.05));
            float2 texUv = cubeUv(local, localN, max(cube.scale,0.05));
            float3 albedo = _Tex0.SampleLevel(LinearSampler, texUv, 0).rgb;
            float3 lightDir = normalize(float3(-0.36,0.78,-0.51));
            float diffuse = 0.28 + 0.72 * saturate(dot(n,lightDir));
            col = albedo * diffuse * exposure;

            if (labSelected(cube.object_id))
            {
                float3 face = abs(local / max(cube.scale,0.05));
                float edge = max(min(face.x,face.y),
                                 max(min(face.y,face.z),min(face.z,face.x)));
                col = lerp(col,T.accent,smoothstep(0.92,0.995,edge)*0.88);
            }
        }
        else
        {
            uint axis = hit.material - 2u;
            // Slight view-normal response makes the cylinders read as geometry
            // rather than screen strokes without changing their semantic color.
            float facing = 0.72 + 0.28 * saturate(dot(n,-rd));
            col = axisColor(axis) * facing;
        }
    }

    // Unit markers are screen text anchored to exact world points, just like a
    // DCC viewer annotation. The axis lines themselves remain SDF geometry.
    float s = min(R.x/1280.0,R.y/720.0) >= 1.7 ? 2.0 : 1.0;
    float2 pxNegX = labProject(float3(-1.48,0,0)) * R;
    float2 pxPosY = labProject(float3(0,1.30,0)) * R;
    float2 pxPosZ = labProject(float3(0,0,1.48)) * R;
    col += AXIS_R * axisLabel(P,pxNegX+float2(5,-5)*s,s,S_MI,S_X);
    col += AXIS_G * axisLabel(P,pxPosY+float2(5,-5)*s,s,43,S_Y);
    col += AXIS_B * axisLabel(P,pxPosZ+float2(5,-5)*s,s,43,S_Z);
    col += AXIS_R * sui3Frame(P,float4(pxNegX-2,pxNegX+2));
    col += AXIS_G * sui3Frame(P,float4(pxPosY-2,pxPosY+2));
    col += AXIS_B * sui3Frame(P,float4(pxPosZ-2,pxPosZ+2));

    // Selection-only transform gizmo, using the same projected basis and hit
    // functions as Interaction Lab.
    GizmoState st = Gizmo[0];
    if ((uint)round(st.selection_mask) != 0u)
    {
        uint mode = (uint)round(clamp(st.mode,0.0,2.0));
        bool local = st.local_space > 0.5;
        uint held = (uint)round(st.active_handle);
        float2 centerPx = labProject(st.pivot) * R;
        if (mode == 1u)
        {
            [loop] for (uint axisIndex=0u;axisIndex<3u;++axisIndex)
            {
                float radius = 42.0 + 12.0*(float)axisIndex;
                float d = labRotationRingDistancePx(P/R,st.pivot,axisIndex,
                                                     local,cube.rotation,radius);
                col += axisColor(axisIndex)
                     * (held==axisIndex+1u?1.0:0.82)
                     * sui3Aa(d,held==axisIndex+1u?2.3:1.45);
            }
        }
        else
        {
            [loop] for (uint axisIndex=0u;axisIndex<3u;++axisIndex)
            {
                float2 endPx=labGizmoAxisEnd(st.pivot,axisIndex,local,cube.rotation)*R;
                col += axisColor(axisIndex)*sui3Line(P,centerPx,endPx,
                                                     held==axisIndex+1u?2.4:1.55);
                if(mode==0u) col+=axisColor(axisIndex)*sui3Disc(P,endPx,3.8);
                else col+=axisColor(axisIndex)*sui3Frame(P,float4(endPx-4.0,endPx+4.0));
            }
            if(mode==2u) col+=T.accent*(held==7u?sui3Disc(P,centerPx,6.0)
                                                   :sui3Ring(P,centerPx,6.0,1.6));
        }
        col += T.mid*sui3Ring(P,centerPx,2.4,1.2);
    }

    OutputUAV[tid.xy] = float4(saturate(col),1.0);
}
