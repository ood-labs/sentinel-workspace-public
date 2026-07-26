// CRYOGRAM / INTERPRETATION — SEM read of the extruded specimen.
//
// The crystal, measured, is now a landscape. Surface shading and every 3D
// overlay derive from the same injected internal camera and the same g-buffer
// depth, so the lattice actually stands ON the terrain rather than floating in
// screen space.
//
//   contours  -> constant-elevation strata, screen-space corrected
//   scarps    -> grain boundaries read as fault lines
//   hatching  -> crystallographic orientation, carried up from the specimen
//   wires     -> measured bonds, occluded portions drawn faint (x-ray)
//   amber     -> confirmed identities, standing on their own surface point

#include "common.hlsli"
#include "../_shared/ui/sui_core.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

static const float3 CRYO_AMBER = float3(1.00, 0.66, 0.22);
static const float TAU = 6.28318530718;

// _Tex1 is the combined height field: .g is already world height (base relief
// plus kick swells), so wires and markers land on the swollen surface too.
float cryoH(float2 uv) { return cryoFieldBilinear(_Tex1, uv).g; }

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;
    int2 px = int2(id.xy);
    float2 P = (float2)px + 0.5;
    SuiContext c = suiContext(id.xy, _Resolution.xy);

    float4 g = _Tex0.Load(int3(px, 0));
    float tHit = g.r;

    float2 screenUV = P / _Resolution.xy;
    float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);
    float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nearW /= nearW.w; farW /= farW.w;
    float3 ro = _CameraPos;
    float3 rd = normalize(farW.xyz - nearW.xyz);

    float3 col = float3(0.004, 0.004, 0.005);
    float depth = (tHit > 0.0) ? tHit : 1e9;

    if (tHit > 0.0) {
        float3 hp = ro + rd * tHit;
        float2 uv = cryoUvFromWorld(hp);
        float hgt = g.g;
        float gid = g.b;
        float th = g.a * TAU;

        // ---- normal from the height field --------------------------------
        float ex = normal_eps / 1280.0;
        float hL = cryoH(uv - float2(ex, 0.0));
        float hR = cryoH(uv + float2(ex, 0.0));
        float hD = cryoH(uv - float2(0.0, ex));
        float hU = cryoH(uv + float2(0.0, ex));
        float dhdx = (hR - hL) / (2.0 * ex * 2.0 * CRYO_ASPECT);
        float dhdz = (hU - hD) / (2.0 * ex * 2.0);
        float3 n = normalize(float3(-dhdx, 1.0, -dhdz));

        // ---- monochrome instrument lighting -------------------------------
        float3 L = normalize(float3(-0.42, 0.66, -0.62));
        float lam = saturate(dot(n, L));
        float graze = pow(1.0 - saturate(dot(n, -rd)), 3.0);
        float amb = 0.10 + 0.20 * saturate(n.y);

        float lum = amb + lam * key_gain + graze * rim_gain;

        // ---- crystallographic hatching carried up from the specimen -------
        if (hgt > 0.001) {
            float2 sp = uv * float2(1280.0, 720.0);
            float hv = dot(sp, float2(cos(th), sin(th)));
            float dl = abs(frac(hv / max(hatch_pitch, 2.0) + 0.5) - 0.5) * hatch_pitch;
            float stroke = 1.0 - smoothstep(0.9, 2.1, dl);
            lum += stroke * hatch_gain * saturate(lam + 0.25);
        }

        // ---- strata: constant-elevation contours, screen-space corrected --
        float hC = g.g;
        float hXp = _Tex0.Load(int3(clamp(px + int2(1, 0), int2(0, 0), int2(res) - 1), 0)).g;
        float hXm = _Tex0.Load(int3(clamp(px - int2(1, 0), int2(0, 0), int2(res) - 1), 0)).g;
        float hYp = _Tex0.Load(int3(clamp(px + int2(0, 1), int2(0, 0), int2(res) - 1), 0)).g;
        float hYm = _Tex0.Load(int3(clamp(px - int2(0, 1), int2(0, 0), int2(res) - 1), 0)).g;

        float step_ = max(contour_step, 0.002);
        float gx = (hXp - hXm) * 0.5 / step_;
        float gy = (hYp - hYm) * 0.5 / step_;
        float grad = max(length(float2(gx, gy)), 1e-5);
        float dC = abs(frac(hC / step_ + 0.5) - 0.5) / grad;
        float contour = 1.0 - smoothstep(contour_width, contour_width + 1.1, dC);

        // Contours are an elevation reading, so they belong on surfaces you can
        // read elevation from. On a near-vertical face the screen gradient
        // collapses and every pixel qualifies, which is what produced the sheet
        // of vertical stripes. Gate by how horizontal the surface is.
        float steep = 1.0 - saturate(n.y * 2.2);
        lum = lerp(lum, 1.0, contour * contour_gain * (1.0 - steep));

        // Steep faces instead read as a cut section: bands at constant WORLD
        // height, darkened, like a stratigraphic wall.
        if (steep > 0.30) {
            float bw = max(contour_step, 0.004);
            float band = abs(frac(hp.y / bw + 0.5) - 0.5) * bw;
            float pw = max(tHit * 0.0016 * fwidth_approx_scale, 0.0009);
            float bl = 1.0 - smoothstep(pw, pw * 2.3, band);
            lum *= lerp(1.0, 0.48, steep);
            lum = lerp(lum, 0.88, bl * contour_gain * steep * 0.75);
        }

        // ---- grain boundaries read as fault scarps ------------------------
        float scarp = 0.0;
        float gXp = _Tex0.Load(int3(clamp(px + int2(1, 0), int2(0, 0), int2(res) - 1), 0)).b;
        float gXm = _Tex0.Load(int3(clamp(px - int2(1, 0), int2(0, 0), int2(res) - 1), 0)).b;
        float gYp = _Tex0.Load(int3(clamp(px + int2(0, 1), int2(0, 0), int2(res) - 1), 0)).b;
        float gYm = _Tex0.Load(int3(clamp(px - int2(0, 1), int2(0, 0), int2(res) - 1), 0)).b;
        // 0.004 is one 8-bit step, so quantization alone tripped this and
        // speckled the surfaces. Require a real grain change.
        if (abs(gXp - gid) > 0.014 || abs(gXm - gid) > 0.014 ||
            abs(gYp - gid) > 0.014 || abs(gYm - gid) > 0.014) scarp = 1.0;
        lum = lerp(lum, 0.02, scarp * scarp_gain);

        // ---- the stage: dark plate with a registration grid ----------------
        // The bare plate must read as the instrument's stage, not as a lit
        // ground plane. Shading it normally floods the frame with mid gray and
        // buries the specimen.
        if (hgt <= 0.0015) {
            float2 w2 = hp.xz;
            float2 d2 = abs(frac(w2 / max(stage_grid, 0.02) + 0.5) - 0.5) * max(stage_grid, 0.02);
            float gl = min(d2.x, d2.y);
            float pxw = max(fwidth_approx_scale * tHit * 0.0016, 0.0012);
            float gline = 1.0 - smoothstep(pxw, pxw * 2.4, gl);

            // fade the infinite plane out beyond the specimen footprint
            float outside = max(max(-uv.x, uv.x - 1.0), max(-uv.y, uv.y - 1.0));
            float plate = 1.0 - smoothstep(0.0, 0.45, outside);

            lum = 0.010 + gline * stage_gain * (0.25 + 0.75 * plate);
        }

        // ---- snare: volumetric noise burst ---------------------------------
        // A sphere placed in 3D near the impact, tested against the pixel's real
        // WORLD hit position — so the corruption wraps over the terrain and sits
        // in the scene rather than floating as a flat screen disc. Inside it,
        // world-space voxel cells are re-randomised at burst_rate, which is what
        // makes it read as a snappy block of noise instead of a ripple.
        float burst = 0.0;
        uint sN = min(_Data2_Count, 8u);
        [loop] for (uint bi = 0u; bi < sN; ++bi) {
            if (_Data2[bi].active < 0.5) continue;

            float bage = _Time - _Data2[bi].birth;
            if (bage < 0.0 || bage > burst_life) continue;

            float2 cuv = _Data2[bi].center;
            float3 wc = cryoWorldFromUv(cuv, cryoH(cuv) + burst_lift);

            // drift so successive snares wander through the volume
            float da = _Data2[bi].seed * 6.28318530718;
            wc += float3(cos(da), 0.42, sin(da)) * bage * burst_drift;

            // Radius is NOT scaled by strength. It used to be, and combined
            // with lifting the sphere centre above the surface it shrank the
            // ground intersection to a ~0.1-unit speck on a 3.55-unit plate —
            // the burst was effectively invisible. Strength drives intensity
            // only; the radius is what the user authored.
            float r = max(burst_radius * (1.0 + bage * burst_grow), 1e-3);
            float d = distance(hp, wc);
            float m = 1.0 - smoothstep(r * saturate(burst_soft), r, d);

            float env = (bage < burst_attack)
                      ? (bage / max(burst_attack, 1e-3))
                      : exp(-(bage - burst_attack) / max(burst_decay, 0.02));

            burst = max(burst, m * saturate(env) * max(_Data2[bi].strength, 0.25));
        }

        if (burst > 0.002) {
            float cs = max(burst_cell, 0.002);
            int3 cell = (int3)floor(hp / cs) + 8192;
            uint tstep = (uint)max(floor(_Time * burst_rate), 0.0);

            uint3 uc = (uint3)cell;
            uint hh = uc.x * 73856093u ^ uc.y * 19349663u ^ uc.z * 83492791u;
            hh ^= tstep * 2654435761u;
            hh ^= hh >> 13u; hh *= 1274126177u; hh ^= hh >> 16u;

            float n1 = (float)(hh & 0xFFFFu) / 65535.0;
            float n2 = (float)((hh >> 16u) & 0xFFFFu) / 65535.0;

            float amt = saturate(burst * burst_amount);
            lum = lerp(lum, n1 * burst_level, amt);
            lum = lerp(lum, step(0.5, n2) * burst_level, amt * saturate(burst_hard));
        }

        // ---- distance fade -------------------------------------------------
        float fog = exp(-tHit * fog_density);
        lum *= fog;
        col = float3(lum, lum, lum);
    }

    // ---- measured bonds, standing in the same 3D space ---------------------
    uint fCount = min(_Data0_Count, 160u);
    [loop] for (uint i = 0u; i < fCount; ++i) {
        if (_Data0[i].weight <= 0.0) continue;

        float2 ua = _Data0[i].a;
        float2 ub = _Data0[i].b;
        float3 wa = cryoWorldFromUv(ua, cryoH(ua) + wire_lift);
        float3 wb = cryoWorldFromUv(ub, cryoH(ub) + wire_lift);

        float2 pa, pb; float da, db;
        if (!cryoProject(wa, _Resolution.xy, pa, da)) continue;
        if (!cryoProject(wb, _Resolution.xy, pb, db)) continue;

        float2 lo = min(pa, pb) - 6.0, hi = max(pa, pb) + 6.0;
        if (P.x < lo.x || P.x > hi.x || P.y < lo.y || P.y > hi.y) continue;

        float tt;
        float d = cryoSegDist(P, pa, pb, tt);
        float w = lerp(wire_weight_max, wire_weight_min, saturate(_Data0[i].strain * 0.5 + 0.5));
        float cov = 1.0 - smoothstep(w, w + 1.1, d);
        if (cov <= 0.001) continue;

        float segDepth = lerp(da, db, tt);
        bool occluded = segDepth > depth + 0.02;
        float a = cov * wire_gain * (0.35 + 0.65 * saturate(_Data0[i].weight));
        col = lerp(col, float3(0.95, 0.95, 0.96), a * (occluded ? xray_gain : 1.0));
    }

    // ---- confirmed identities, planted on their own surface point ---------
    uint tCount = min(_Data1_Count, 97u);
    [loop] for (uint k = 0u; k < tCount; ++k) {
        if (_Data1[k].active < 0.5) continue;
        if (_Data1[k].confidence < marker_confidence) continue;

        float2 up = _Data1[k].position;
        float baseH = cryoH(up);
        float3 wbase = cryoWorldFromUv(up, baseH);
        float3 wtop = cryoWorldFromUv(up, baseH + marker_height);

        float2 pb0, pt0; float d0, d1;
        if (!cryoProject(wbase, _Resolution.xy, pb0, d0)) continue;
        if (!cryoProject(wtop, _Resolution.xy, pt0, d1)) continue;

        float2 lo = min(pb0, pt0) - 8.0, hi = max(pb0, pt0) + 8.0;
        if (P.x < lo.x || P.x > hi.x || P.y < lo.y || P.y > hi.y) continue;

        float tt;
        float d = cryoSegDist(P, pb0, pt0, tt);
        float stem = 1.0 - smoothstep(0.8, 1.9, d);
        float head = 1.0 - smoothstep(0.0, 1.3, abs(length(P - pt0) - 3.2 * marker_scale));

        float segDepth = lerp(d0, d1, tt);
        bool occ = segDepth > depth + 0.02;
        float a = max(stem * 0.75, head) * marker_gain * (occ ? xray_gain : 1.0);
        col = lerp(col, CRYO_AMBER, saturate(a));
    }

    // ---- snare strikes: a burst thrown up from the impact point ------------
    // The shock records come from the specimen itself, so the burst stands
    // exactly where the plate was struck rather than at an invented coordinate.
    uint sCount = min(_Data2_Count, 8u);
    [loop] for (uint si = 0u; si < sCount; ++si) {
        if (_Data2[si].active < 0.5) continue;

        float age = _Time - _Data2[si].birth;
        if (age < 0.0 || age > strike_life) continue;

        float2 suv = _Data2[si].center;
        float fade = exp(-age / max(strike_decay, 0.02));
        float grow = saturate(age / max(strike_rise, 0.01));

        float baseH = cryoH(suv);
        float3 wbase = cryoWorldFromUv(suv, baseH);

        float2 pbase; float dbase;
        if (!cryoProject(wbase, _Resolution.xy, pbase, dbase)) continue;

        uint rays = (uint)clamp(strike_rays, 1, 12);
        [loop] for (uint r = 0u; r < rays; ++r) {
            float a = (float)r / (float)rays * 6.28318530718
                    + _Data2[si].seed * 6.28318530718;
            float spread = strike_spread * grow;
            float len = strike_height * grow * _Data2[si].strength;

            float3 wtip = cryoWorldFromUv(
                suv + float2(cos(a), sin(a)) * spread,
                baseH + len);

            float2 ptip; float dtip;
            if (!cryoProject(wtip, _Resolution.xy, ptip, dtip)) continue;

            float2 lo = min(pbase, ptip) - 4.0, hi = max(pbase, ptip) + 4.0;
            if (P.x < lo.x || P.x > hi.x || P.y < lo.y || P.y > hi.y) continue;

            float tt;
            float d = cryoSegDist(P, pbase, ptip, tt);
            // taper: heavy at the root, fine at the tip
            float w = lerp(strike_weight, strike_weight * 0.25, tt);
            float cov = 1.0 - smoothstep(w, w + 1.2, d);
            if (cov <= 0.002) continue;

            float segDepth = lerp(dbase, dtip, tt);
            bool occ = segDepth > depth + 0.02;

            float3 sc = lerp(float3(0.96, 0.96, 0.97), CRYO_AMBER, tt * strike_tint);
            float a2 = cov * fade * strike_gain * (occ ? xray_gain : 1.0) * (1.0 - tt * 0.35);
            col = lerp(col, sc, saturate(a2));
        }
    }

    // ---- frame vignette -----------------------------------------------------
    float2 q = (screenUV - 0.5) * 2.0;
    col *= 1.0 - vignette * saturate(dot(q, q) * 0.42);

    OutputUAV[id.xy] = float4(saturate(col * exposure), 1.0);
}
