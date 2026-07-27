// Gizmo Desk - renderer.
//
// PALETTE CONTRACT, and it is narrow on purpose. The only chromatic elements in
// this image are:
//   * the X / Y / Z handles in red / green / blue, because those colours carry
//     directional meaning and are the one agreed exception to the monochrome
//     rule (operator decision, recorded in the phase doc);
//   * amber, for the uniform-scale centre and for established live values.
// Everything else -- objects, ground grid, chrome, type, readouts -- is
// greyscale. 3E's criterion 4 asserts exactly this, so nothing else may
// introduce a hue.
#include "types.hlsli"
#include "layout.hlsli"
#include "../_shared/ui/sui3_theme.hlsli"
#include "../_shared/ui/sui3_controls.hlsli"

StructuredBuffer<SceneObject> _Tex0 : register(t0);
StructuredBuffer<GizmoState>  _Tex1 : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

static const float3 AXIS_R = float3(0.92, 0.22, 0.20);
static const float3 AXIS_G = float3(0.28, 0.82, 0.32);
static const float3 AXIS_B = float3(0.30, 0.50, 0.95);
float3 axisColor(uint a) { return a == 0u ? AXIS_R : (a == 1u ? AXIS_G : AXIS_B); }

// ---------------------------------------------------------------------------
// Raymarched scene. The objects are LIT SOLIDS, not screen-space outlines: a
// transform gizmo is only judgeable against real shaded geometry, because
// rotation and non-uniform scale are invisible on a flat silhouette. Shading
// stays strictly greyscale so the palette contract above still holds.
// ---------------------------------------------------------------------------
static const float GD_FLOOR_Y = -2.15;

float sdSphereLab(float3 p, float r) { return length(p) - r; }
float sdBoxLab(float3 p, float3 b) { float3 q = abs(p) - b; return min(max(q.x, max(q.y, q.z)), 0.0) + length(max(q, 0.0)); }
float sdTorusLab(float3 p, float2 t) { float2 q = float2(length(p.xz) - t.x, p.y); return length(q) - t.y; }
float sdCapsuleLab(float3 p, float h, float r) { p.y -= clamp(p.y, -h, h); return length(p) - r; }

float objectSdf(SceneObject o, float3 p) {
    float3 q = mul(transpose(labRotation(o.rotation)), p - o.position) / max(o.scale, 0.05);
    float d = o.kind == 0u ? sdSphereLab(q, 0.48)
            : o.kind == 1u ? sdBoxLab(q, 0.42.xxx)
            : o.kind == 2u ? sdTorusLab(q, float2(0.34, 0.14))
                           : sdCapsuleLab(q, 0.30, 0.25);
    return d * min(o.scale.x, min(o.scale.y, o.scale.z));
}

float objectsSdf(float3 p, out uint objectId) {
    float best = 1e9; objectId = 0u;
    [loop] for (uint i = 0u; i < 16u; ++i) {
        SceneObject o = _Tex0[i];
        if (o.object_id == 0u) continue;
        float d = objectSdf(o, p);
        if (d < best) { best = d; objectId = o.object_id; }
    }
    return best;
}

// Floor is a separate analytic plane rather than part of the SDF, so the
// marcher never wastes steps creeping along it at grazing angles.
float sceneSdf(float3 p, out uint objectId) {
    float d = objectsSdf(p, objectId);
    float floorDistance = p.y - GD_FLOOR_Y;
    if (floorDistance < d) { d = floorDistance; objectId = 0u; }
    return d;
}

float3 normalAt(float3 p) {
    uint ignored; float e = 0.0025;
    float d = sceneSdf(p, ignored);
    float3 g = float3(sceneSdf(p + float3(e,0,0), ignored) - d,
                      sceneSdf(p + float3(0,e,0), ignored) - d,
                      sceneSdf(p + float3(0,0,e), ignored) - d);
    // A gradient of exactly zero normalizes to NaN, which propagates through the
    // lighting into a black or garbage pixel. Rare, but it costs one compare.
    float len2 = dot(g, g);
    return len2 > 1e-20 ? g * rsqrt(len2) : float3(0, 1, 0);
}

// Soft shadow against the OBJECTS only. Without it the twelve solids float,
// and the contact point is what tells you where a translate actually landed.
float softShadow(float3 origin, float3 lightDir) {
    // The ray must clear its own surface before the penumbra term switches on.
    // Starting at t=0.05 made `10*d/t` sample the originating object at
    // near-zero distance, which printed concentric rings around the lit pole of
    // every sphere -- self-shadow banding, not geometry.
    float shade = 1.0, t = 0.30; uint ignored;
    [loop] for (int i = 0; i < 18; ++i) {
        float d = objectsSdf(origin + lightDir * t, ignored);
        if (d < 0.0015) return 0.05;
        shade = min(shade, 7.0 * d / t);
        t += clamp(d, 0.06, 0.40);
        if (t > 7.0) break;
    }
    return saturate(shade);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 R = _Resolution.xy;
    float2 P = ((float2)tid.xy) + 0.5;

    Sui3Theme T = sui3Theme(accent_color.rgb);
    float sB  = gdTextScale(R);
    float pad = 0.016 * R.x;

    GizmoState st = _Tex1[0];
    uint mode = (uint)round(clamp(st.mode, 0.0, 2.0));
    bool local = st.local_space > 0.5;
    uint mask = (uint)round(st.selection_mask);

    int selCount = 0, objCount = 0;
    [loop] for (uint n = 0u; n < 16u; n++) {
        uint id = _Tex0[n].object_id;
        if (id == 0u) continue;
        objCount++;
        if (id <= 24u && (mask & (1u << (id - 1u))) != 0u) selCount++;
    }

    // ---- raymarched scene ----------------------------------------------------
    float2 uv  = P / R;
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 farWorld = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    // Sign-preserving guard. `max(w, 1e-6)` on a SIGNED w turns any negative w
    // into +1e-6, flipping the unprojected point through the origin and sending
    // the ray backwards; clamp the magnitude and keep the sign instead.
    farWorld /= (farWorld.w < 0.0 ? min(farWorld.w, -1e-6) : max(farWorld.w, 1e-6));
    float3 ro = _CameraPos;
    float3 rd = normalize(farWorld.xyz - ro);

    // Hit epsilon scales with distance and the step floor is tied to it. With a
    // FIXED floor (0.004) and an `abs(d) < eps` test, a ray that overshoots the
    // surface lands inside at d = -0.004, keeps adding the floor, and marches
    // deeper forever -- which printed a scatter of single black pixels at each
    // object's centre where the surface faces the camera dead-on. Testing
    // `d < eps` makes going negative a hit rather than a miss.
    float travel = 0.0; uint hitId = 0u; bool hitAnything = false;
    [loop] for (int step = 0; step < 84; ++step) {
        uint stepId;
        float d = sceneSdf(ro + rd * travel, stepId);
        float eps = 0.0012 * max(travel, 1.0);
        if (d < eps) { hitId = stepId; hitAnything = true; break; }
        travel += max(d, eps);
        if (travel > 42.0) break;
    }

    float3 col = T.field;
    float3 keyDir = normalize(float3(-0.42, 0.80, -0.48));

    if (hitAnything) {
        float3 p = ro + rd * travel;
        float3 nrm = normalAt(p);
        float diffuse = saturate(dot(nrm, keyDir));
        // One key, one dim opposing fill, one rim. Enough to read curvature and
        // orientation; not enough to become atmosphere.
        float fill = saturate(dot(nrm, normalize(float3(0.55, 0.15, 0.70)))) * 0.22;
        float rim  = pow(1.0 - saturate(dot(nrm, -rd)), 5.0);

        if (hitId == 0u) {
            // Floor: a real lit plane carrying the measurement grid in WORLD
            // space, so the grid recedes with perspective and the objects sit
            // on it rather than in front of it.
            // Distant floor is already near the grid fade, so the shadow there
            // costs 18 SDF sweeps to move a value nobody can see.
            float shadow = travel < 20.0 ? softShadow(p + nrm * 0.02, keyDir) : 1.0;
            float3 base = T.field + 0.055;
            float lit = 0.35 + diffuse * 0.55 * (0.25 + 0.75 * shadow);

            float2 gridCell = abs(frac(p.xz + 0.5) - 0.5);
            // No ddx/ddy in a compute shader, so the footprint is analytic:
            // world units per pixel at this depth, widened by the grazing
            // angle so distant floor lines stay one hairline instead of moire.
            float grazing = max(abs(dot(nrm, rd)), 0.12);
            float worldPerPx = travel * 1.9 / max(R.y, 1.0) / grazing;
            float gridLine = 1.0 - smoothstep(0.0, max(worldPerPx * 1.5, 1e-4), min(gridCell.x, gridCell.y));
            float fade = saturate(1.0 - travel / 34.0);

            col = base * lit;
            col += T.rule * 0.34 * gridLine * fade;
        } else {
            bool sel = (hitId <= 24u) && ((mask & (1u << (hitId - 1u))) != 0u);
            float shadow = softShadow(p + nrm * 0.02, keyDir);
            // Objects differ in VALUE as well as silhouette, so neighbouring
            // solids stay separable where they overlap on screen.
            float level = 0.34 + 0.030 * fmod((float)hitId, 5.0);
            float3 base = level.xxx;
            if (sel) base = lerp(base, T.ink, 0.55);

            col = base * (0.13 + diffuse * 0.92 * (0.28 + 0.72 * shadow) + fill);
            col += pow(saturate(dot(reflect(-keyDir, nrm), -rd)), 34.0) * (sel ? 0.30 : 0.20);
            // Selection reads as an AMBER EDGE on the lit body -- the 3D
            // equivalent of the spline desk's bracket, and it survives the
            // object being partly occluded. Kept to the silhouette: a broad
            // falloff washes whole faces amber and stops reading as an edge.
            // BLEND toward amber, never add. An additive rim on an already-lit
            // body clips the red channel first, which drifts the hue to yellow
            // and quietly breaks the palette contract at the top of this file.
            if (sel) col = lerp(col, T.accent, saturate(smoothstep(0.30, 0.95, rim) * 1.25));
            else     col += T.mid * rim * 0.14;
        }
    }

    // ---- gizmo ---------------------------------------------------------------
    if (mask != 0u) {
        float3 activeRot = 0.0;
        [loop] for (uint s = 0u; s < 16u; s++)
            if (_Tex0[s].object_id == (uint)round(st.active_id)) activeRot = _Tex0[s].rotation;

        float2 cPx = labProject(st.pivot) * R;
        uint held = (uint)round(st.active_handle);

        if (mode == 1u) {
            // Rotation rings, drawn from the same projected basis the hit test
            // uses -- render and hit-test share one transform, per ui-authoring.
            [loop] for (uint a = 0u; a < 3u; a++) {
                float radius = 42.0 + 12.0 * (float)a;
                float d = labRotationRingDistancePx(P / R, st.pivot, a, local, activeRot, radius);
                float w = (held == a + 1u) ? 2.2 : 1.4;
                col += axisColor(a) * (held == a + 1u ? 1.0 : 0.78) * sui3Aa(d, w);
            }
        } else {
            [loop] for (uint a = 0u; a < 3u; a++) {
                float2 endPx = labGizmoAxisEnd(st.pivot, a, local, activeRot) * R;
                float w = (held == a + 1u) ? 2.4 : 1.5;
                col += axisColor(a) * (held == a + 1u ? 1.0 : 0.8) * sui3Line(P, cPx, endPx, w);
                // Translate gets an arrow head, scale gets a box: the handle
                // shape says which transform you are about to perform even in a
                // still frame.
                if (mode == 0u) col += axisColor(a) * sui3Disc(P, endPx, (held == a + 1u) ? 4.6 : 3.4);
                else            col += axisColor(a) * sui3Frame(P, float4(endPx - 4.0, endPx + 4.0));
            }
            if (mode == 2u) {
                // Uniform-scale centre: the one amber handle.
                col += T.accent * (held == 7u ? sui3Disc(P, cPx, 6.0)
                                              : sui3Ring(P, cPx, 6.0, 1.6));
            }
        }
        col += T.mid * sui3Ring(P, cPx, 2.4, 1.2);
    }

    // ---- toolbar -------------------------------------------------------------
    float4 rMode  = gdPx(UI_RECT_MODE, R);
    float4 rLocal = gdPx(UI_RECT_LOCAL, R);
    float4 bar = float4(0.0, 0.0, R.x, rMode.w + 0.014 * R.y);
    col = lerp(col, T.field, sui3RectIn(P, bar) * 0.92);
    col += T.rule * sui3HairAt(P.y, bar.w);

    if (gdCapFits(rMode.y, sB))
        col += T.ink * sui3Text(P, float2(pad, rMode.y - 14.0 * sB), sB,
            S_G,S_I,S_Z,S_M,S_O,S_SP,S_D,S_E,S_S,S_K,0,0);

    {
        float cw = (rMode.z - rMode.x) / 3.0;
        [loop] for (int c = 0; c < 3; c++) {
            float4 rc = float4(rMode.x + (float)c * cw, rMode.y,
                               rMode.x + (float)(c + 1) * cw - 3.0, rMode.w);
            bool on = ((int)mode == c);
            if (sui3RectIn(P, rc) > 0.5 || sui3Frame(P, rc) > 0.0) {
                col = lerp(col, float3(0,0,0), sui3RectIn(P, rc));
                col += sui3BankCell(P, rc, on, T);
            }
            float2 ta = float2(rc.x + 5.0 * sB, rc.y + (rc.w - rc.y) * 0.5 - 5.0 * sB);
            col += (on ? T.accent : T.dim) * (c == 0
                ? sui3Text(P, ta, sB, S_M,S_O,S_V,S_E,0,0,0,0,0,0,0,0)
                : c == 1 ? sui3Text(P, ta, sB, S_R,S_O,S_T,0,0,0,0,0,0,0,0,0)
                         : sui3Text(P, ta, sB, S_S,S_C,S_L,0,0,0,0,0,0,0,0,0));
        }
    }

    if (sui3RectIn(P, rLocal) > 0.5 || sui3Frame(P, rLocal) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rLocal));
        col += sui3Toggle(P, rLocal, local, T);
    }
    col += (local ? T.accent : T.dim)
         * sui3Text(P, float2(rLocal.x + 7.0 * sB, rLocal.y + (rLocal.w - rLocal.y) * 0.5 - 5.0 * sB), sB,
                    local ? S_L : S_W, local ? S_C : S_R, local ? S_L : S_L, 0,0,0,0,0,0,0,0,0);

    // ---- telemetry -----------------------------------------------------------
    float ty = R.y - pad - 11.0 * sB;
    float tx = pad;
    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_S,S_E,S_L,0,0,0,0,0,0,0,0,0);
    tx += sui3TextWidth(4, sB);
    col += T.accent * sui3Digits(P, float2(tx, ty), sB, selCount, 2);
    tx += sui3TextWidth(3, sB);
    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_SL,0,0,0,0,0,0,0,0,0,0,0);
    tx += sui3TextWidth(2, sB);
    col += T.dim * sui3Digits(P, float2(tx, ty), sB, objCount, 2);
    tx += sui3TextWidth(4, sB);

    col += T.dim * sui3Text(P, float2(tx, ty), sB, S_H,S_N,S_D,0,0,0,0,0,0,0,0,0);
    tx += sui3TextWidth(4, sB);
    col += T.ink * sui3Digits(P, float2(tx, ty), sB, (int)round(st.active_handle), 1);

    col += T.rule * 0.7 * sui3Registration(P, R, 14.0 * sB);
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
