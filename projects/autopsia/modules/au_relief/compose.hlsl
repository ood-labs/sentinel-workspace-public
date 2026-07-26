// AUTOPSIA — instrument face over the 3D relief.
//
// Multiple viewpoints WITHOUT rival cameras: the main image is the module's
// internal camera; PLAN / ELEVATION / SECTION are fixed orthographic technical
// projections of the same world, each plotting the live internal-camera
// position (and, in plan, its view cone) so the operator can read where the one
// real camera is standing. The observation histogram from the analysis lens is
// carried through as a designed readout, not an afterthought.
//
// _Tex0 = shaded relief   _Tex1 = Field   _Tex2 = gbuffer (depth)
// Markers(t3) = projected agents   _Data0 = Agents   _Data1 = Histogram
#include "scene.hlsli"
#include "hud_text.hlsli"

struct AgentRec {
    float2 position; float2 velocity;
    float scale; float confidence; float angle; float age;
    uint stable_id; uint kind; uint source_index; uint flags;
    float4 aux;
};

struct Marker {
    float2 baseUV; float2 topUV;
    float baseDist; float conf; float visible; float established;
};

RWTexture2D<float4> Out : register(u0);
StructuredBuffer<Marker> Markers : register(t3);

float rectIn(float2 uv, float4 r) {
    return step(r.x, uv.x) * step(uv.x, r.z) * step(r.y, uv.y) * step(uv.y, r.w);
}

float rectFrame(float2 uv, float4 r, float2 t) {
    return rectIn(uv, r) - rectIn(uv, float4(r.x + t.x, r.y + t.y, r.z - t.x, r.w - t.y));
}

float seg2(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float h = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-7));
    return length(p - (a + ab * h));
}

float fieldH(float2 xz) {
    return auHeightClamped(_Tex1, LinearSampler, xz, height_scale);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);

    float3 col = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float sceneT = _Tex2.Load(int3(tid.xy, 0)).a;
    if (sceneT <= 0.0) sceneT = 1e9;

    // ================= agent pins (depth tested against the relief) =========
    [loop] for (uint i = 0u; i < 64u; ++i) {
        Marker m = Markers[i];
        if (m.visible < 0.5) continue;
        if (m.baseDist > sceneT + 0.035) continue;      // occluded by the block

        float2 q = float2((uv.x - m.baseUV.x) * aspect, uv.y - m.baseUV.y);
        if (abs(q.x) > 0.05 && abs(uv.y - m.topUV.y) > 0.05) continue;   // cheap reject

        float2 b = float2(m.baseUV.x * aspect, m.baseUV.y);
        float2 tp = float2(m.topUV.x * aspect, m.topUV.y);
        float2 pp = float2(uv.x * aspect, uv.y);

        float pin = 1.0 - smoothstep(px.y * 0.5, px.y * 1.6, seg2(pp, b, tp));
        float head = 1.0 - smoothstep(px.y * 1.6, px.y * 3.0, length(pp - tp));
        float ring = 1.0 - smoothstep(px.y * 0.5, px.y * 1.5,
                                      abs(length(pp - tp) - px.y * 3.4));

        float3 ink = float3(0.78, 0.785, 0.76) * (0.35 + 0.65 * m.conf);
        col += ink * (pin * 0.55 + head * 0.5 + ring * 0.7) * pin_gain;

        if (m.established > 0.5) {
            col += accent_color * ring * 0.9 * pin_gain;
        }
    }

    // ================= orthographic technical views =========================
    // camera forward, reconstructed from the SAME injected matrices
    float4 cf0 = mul(_InvViewProjMatrix, float4(0.0, 0.0, 0.0, 1.0));
    float4 cf1 = mul(_InvViewProjMatrix, float4(0.0, 0.0, 1.0, 1.0));
    cf0 /= cf0.w; cf1 /= cf1.w;
    float3 camFwd = normalize(cf1.xyz - cf0.xyz);

    float4 panels[3] = {
        float4(0.7620, 0.0480, 0.9820, 0.2920),   // PLAN
        float4(0.7620, 0.3160, 0.9820, 0.5600),   // ELEVATION
        float4(0.7620, 0.5840, 0.9820, 0.8280)    // SECTION
    };

    [unroll] for (int pi = 0; pi < 3; ++pi) {
        float4 r = panels[pi];
        if (rectIn(uv, r) < 0.5) continue;

        float2 l = float2((uv.x - r.x) / (r.z - r.x), (uv.y - r.y) / (r.w - r.y));
        float3 pc = float3(0.012, 0.013, 0.014);

        if (pi == 0) {
            // ---------- PLAN: looking straight down at the plate -------------
            // Zoomed out past the plate footprint so the live camera station
            // stays inside the diagram instead of falling off its edge.
            float z = max(plan_zoom, 1.0);
            float2 wxz = float2((l.x - 0.5) * AU_DOMAIN.x * z, (l.y - 0.5) * AU_DOMAIN.y * z);
            bool inPlate = all(abs(wxz) <= AU_DOMAIN * 0.5);

            if (inPlate) {
                float d = _Tex1.SampleLevel(LinearSampler, saturate(auWorldToUV(wxz)), 0).r;
                pc += float3(0.055, 0.057, 0.055) * smoothstep(0.03, 0.55, d);
                float band = abs(frac(d * 9.0) - 0.5);
                pc += float3(0.30, 0.305, 0.29) * smoothstep(0.46, 0.5, band) * step(0.03, d);
            }

            // plate boundary
            float2 pb = abs(wxz) - AU_DOMAIN * 0.5;
            float bd = length(max(pb, 0.0)) + min(max(pb.x, pb.y), 0.0);
            pc += float3(0.40, 0.405, 0.39) * (1.0 - smoothstep(0.0, 0.012 * z, abs(bd)));

            // agents in plan (same zoom mapping)
            [loop] for (uint a = 0u; a < _Data0_Count; ++a) {
                if ((_Data0[a].flags & 1u) == 0u) continue;
                float2 ap = (_Data0[a].position - 0.5) / z + 0.5;
                float dd = length((l - ap) * float2((r.z - r.x) / (r.w - r.y), 1.0));
                pc += float3(0.85, 0.855, 0.83) * (1.0 - smoothstep(0.008, 0.016, dd))
                    * (0.35 + 0.65 * _Data0[a].confidence);
            }

            // the one real camera, plotted in plan with its view cone
            float2 camL = (auWorldToUV(_CameraPos.xz) - 0.5) / z + 0.5;
            float2 fwdL = normalize(camFwd.xz + 1e-5);
            float2 perp = float2(-fwdL.y, fwdL.x) * 0.16;
            float2 tip = fwdL * 0.34 / z * 2.0;
            float coneL = 1.0 - smoothstep(0.0, 0.005, min(
                seg2(l, camL, camL + tip + perp),
                seg2(l, camL, camL + tip - perp)));
            pc += accent_color * coneL * 0.60;
            float camM = 1.0 - smoothstep(0.006, 0.013, length(l - camL));
            pc += accent_color * camM * 1.0;

        } else if (pi == 1) {
            // ---------- ELEVATION: silhouette looking along +Z ---------------
            float wx = (l.x - 0.5) * AU_DOMAIN.x;
            float yTop = height_scale * 1.25;
            float wy = lerp(yTop, -slab_depth, l.y);

            float hMax = 0.0;
            [loop] for (int k = 0; k < 28; ++k) {
                float wz = ((float)k / 27.0 - 0.5) * AU_DOMAIN.y;
                hMax = max(hMax, fieldH(float2(wx, wz)));
            }
            pc += float3(0.048, 0.050, 0.048) * step(wy, hMax) * step(0.0, wy);
            pc += float3(0.030, 0.031, 0.030) * step(wy, 0.0) * step(-slab_depth, wy);
            float edge = 1.0 - smoothstep(0.0, 0.012, abs(wy - hMax));
            pc += float3(0.70, 0.705, 0.68) * edge;
            // ground line
            pc += float3(0.24, 0.245, 0.235) * (1.0 - smoothstep(0.0, 0.006, abs(wy)));
            // camera altitude marker
            float camY = 1.0 - smoothstep(0.0, 0.005,
                abs(l.y - saturate((yTop - _CameraPos.y) / (yTop + slab_depth))));
            pc += accent_color * camY * 0.40;

        } else {
            // ---------- SECTION: single cut at the section plane -------------
            float wx = (l.x - 0.5) * AU_DOMAIN.x;
            float wz = (section_z - 0.5) * AU_DOMAIN.y;
            float yTop = height_scale * 1.25;
            float wy = lerp(yTop, -slab_depth, l.y);
            float h = fieldH(float2(wx, wz));

            pc += float3(0.052, 0.054, 0.052) * step(wy, h) * step(0.0, wy);
            // stratified base material
            float strata = 1.0 - smoothstep(0.0, 0.35, abs(frac(wy * strata_bands * 0.5) - 0.5));
            pc += float3(0.10, 0.103, 0.098) * strata * step(wy, 0.0) * step(-slab_depth, wy);
            float edge = 1.0 - smoothstep(0.0, 0.010, abs(wy - h));
            pc += float3(0.82, 0.825, 0.80) * edge;
            pc += float3(0.24, 0.245, 0.235) * (1.0 - smoothstep(0.0, 0.006, abs(wy)));
        }

        // panel graticule
        float2 gl = abs(frac(l * float2(6.0, 5.0)) - 0.5);
        pc += float3(0.030, 0.031, 0.030) * step(0.47, max(gl.x, gl.y));

        col = pc;
    }

    // panel frames + corner ticks
    [unroll] for (int pf = 0; pf < 3; ++pf) {
        float4 r = panels[pf];
        col += float3(0.34, 0.345, 0.33) * rectFrame(uv, r, px);
    }

    // ================= observation distribution (from the analysis lens) ====
    // Plotted as a real instrument trace with axes and a marked threshold,
    // not a bar chart: this is the same histogram the analysis lens uses to
    // decide what counts as specimen, carried through to the instrument face.
    float4 hr = float4(0.0300, 0.8480, 0.4180, 0.9420);
    float peak = max((float)_Data1[64].count, 1.0);
    if (rectIn(uv, hr) > 0.5) {
        float3 hc = float3(0.010, 0.011, 0.012);
        float l = (uv.x - hr.x) / (hr.z - hr.x);
        float up = (hr.w - uv.y) / (hr.w - hr.y);

        uint bin = min((uint)(l * 64.0), 63u);
        float hgt = saturate(log(1.0 + (float)_Data1[bin].count) / log(1.0 + peak));

        // filled body under the trace, plus a bright trace line on top
        hc += float3(0.055, 0.057, 0.054) * step(up, hgt);
        float traceW = 2.2 * px.y / (hr.w - hr.y);
        hc += float3(0.86, 0.865, 0.84) * (1.0 - smoothstep(0.0, traceW, abs(up - hgt)));

        // decade graticule
        hc += float3(0.055, 0.056, 0.053) * step(0.965, frac(l * 8.0));
        hc += float3(0.055, 0.056, 0.053) * step(0.965, frac(up * 4.0));

        // the live blob threshold, marked on the distribution it governs
        float mk = 1.0 - smoothstep(0.0, 1.4 * px.x / (hr.z - hr.x), abs(l - hist_mark));
        hc = lerp(hc, accent_color, mk * 0.9);
        col = hc;
    }
    col += float3(0.30, 0.305, 0.29) * rectFrame(uv, hr, px);

    // ================= typography ===========================================
    float2 tp = uv * _Resolution.xy;
    float3 ink = float3(0.90, 0.905, 0.88);
    float3 dim = float3(0.44, 0.445, 0.43);
    float s1 = 2.0, s0 = 1.0;

    // title block
    col += ink * auText(tp, float2(20.0, 22.0), s1,
        G_A,G_U,G_T,G_O,G_P,G_S,G_I,G_A, 0,0,0,0);
    col += dim * auText(tp, float2(20.0, 44.0), s0,
        G_S,G_P,G_E,G_C,G_I,G_M,G_E,G_N,0,0,0,0);
    col += dim * auText(tp, float2(20.0, 56.0), s0,
        G_R,G_E,G_L,G_I,G_E,G_F,G_SP,G_L,G_I,G_V,G_E,0);

    // panel titles
    col += ink * auText(tp, float2(0.7620 * _Resolution.x + 4.0, 0.0480 * _Resolution.y - 13.0), s0,
        G_P,G_L,G_A,G_N, 0,0,0,0,0,0,0,0);
    col += ink * auText(tp, float2(0.7620 * _Resolution.x + 4.0, 0.3160 * _Resolution.y - 13.0), s0,
        G_E,G_L,G_E,G_V,G_A,G_T,G_I,G_O,G_N, 0,0,0);
    col += ink * auText(tp, float2(0.7620 * _Resolution.x + 4.0, 0.5840 * _Resolution.y - 13.0), s0,
        G_S,G_E,G_C,G_T,G_I,G_O,G_N, 0,0,0,0,0);

    // distribution label + axis extents
    col += ink * auText(tp, float2(hr.x * _Resolution.x, hr.y * _Resolution.y - 13.0), s0,
        G_O,G_B,G_S,G_SP,G_D,G_I,G_S,G_T,G_R,G_I,G_B, 0);
    col += dim * auNum(tp, float2(hr.x * _Resolution.x, hr.w * _Resolution.y + 4.0), s0, 0, 1);
    col += dim * auText(tp, float2(hr.z * _Resolution.x - 12.0, hr.w * _Resolution.y + 4.0), s0,
        G_0 + 1, G_DT, G_0, 0,0,0,0,0,0,0,0,0);

    // ---- live readouts: every number derived from real state ---------------
    float readX = 0.460 * _Resolution.x;
    float readY = 0.862 * _Resolution.y;
    uint nActive = 0u;
    uint nEstab = 0u;
    [loop] for (uint ra = 0u; ra < _Data0_Count; ++ra) {
        if ((_Data0[ra].flags & 1u) == 0u) continue;
        nActive++;
        if (_Data0[ra].confidence >= 0.88 && _Data0[ra].age >= 4.0) nEstab++;
    }

    col += dim * auText(tp, float2(readX, readY), s0,
        G_A,G_G,G_E,G_N,G_T,G_S, 0,0,0,0,0,0);
    col += ink * auNum(tp, float2(readX + 52.0, readY), s0, (int)nActive, 2);

    col += dim * auText(tp, float2(readX, readY + 14.0), s0,
        G_E,G_S,G_T,G_A,G_B, 0,0,0,0,0,0,0);
    col += accent_color * auNum(tp, float2(readX + 52.0, readY + 14.0), s0, (int)nEstab, 2);

    col += dim * auText(tp, float2(readX, readY + 28.0), s0,
        G_S,G_A,G_M,G_P,G_L,G_E,G_S, 0,0,0,0,0);
    col += ink * auNum(tp, float2(readX + 52.0, readY + 28.0), s0, (int)_Data1[65].count, 6);

    // camera station, read off the one real camera
    float camX2 = 0.610 * _Resolution.x;
    col += dim * auText(tp, float2(camX2, readY), s0,
        G_C,G_A,G_M,G_SP,G_X, 0,0,0,0,0,0,0);
    col += ink * auFixed(tp, float2(camX2 + 46.0, readY), s0, _CameraPos.x);
    col += dim * auText(tp, float2(camX2, readY + 14.0), s0,
        G_C,G_A,G_M,G_SP,G_Y, 0,0,0,0,0,0,0);
    col += ink * auFixed(tp, float2(camX2 + 46.0, readY + 14.0), s0, _CameraPos.y);
    col += dim * auText(tp, float2(camX2, readY + 28.0), s0,
        G_C,G_A,G_M,G_SP,G_Z, 0,0,0,0,0,0,0);
    col += ink * auFixed(tp, float2(camX2 + 46.0, readY + 28.0), s0, _CameraPos.z);

    // relief scale readout next to the elevation panel
    col += dim * auText(tp, float2(0.7620 * _Resolution.x + 78.0, 0.3160 * _Resolution.y - 13.0), s0,
        G_H, G_CO, 0,0,0,0,0,0,0,0,0,0);
    col += ink * auFixed(tp, float2(0.7620 * _Resolution.x + 92.0, 0.3160 * _Resolution.y - 13.0), s0, height_scale);

    // ================= outer frame + registration ===========================
    float4 fr = float4(0.010, 0.014, 0.990, 0.986);
    col += float3(0.26, 0.265, 0.25) * rectFrame(uv, fr, px);

    // gutter divider between the viewport and the instrument column
    col += float3(0.16, 0.165, 0.155)
         * step(0.7480, uv.x) * step(uv.x, 0.7480 + px.x)
         * step(0.030, uv.y) * step(uv.y, 0.845);

    float2 cc = min(uv, 1.0 - uv);
    float corner = step(cc.x, 0.030) * step(cc.y, 0.0035) + step(cc.y, 0.030) * step(cc.x, 0.0035);
    col += float3(0.70, 0.705, 0.68) * saturate(corner);

    // edge ruler with decade emphasis
    float rulerBase = step(uv.y, 0.9985) * step(0.9930, uv.y);
    col += float3(0.16, 0.165, 0.155) * rulerBase * step(0.80, frac(uv.x * 64.0));
    col += float3(0.40, 0.405, 0.39) * step(uv.y, 0.9985) * step(0.9895, uv.y)
                                     * step(0.90, frac(uv.x * 8.0));

    Out[tid.xy] = float4(saturate(col), 1.0);
}
