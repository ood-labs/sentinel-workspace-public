// botany_render — the bouquet SDF plate. Marches a BouquetPart buffer (data:0) as a union of
// botanical forms (blade/petal/cone/berry/wire/stamen), toon-shaded: flat pop albedo, quantized
// light bands, black depth-edge OUTLINES, per-form surface patterns (veins/reticulation/dots),
// and a global hue-cycle. Domain-warp toolkit (twist/bend/swirl/wave/melt x2) is wired for live
// manipulation. Premultiplied-alpha coverage matte (transparent bg) so it composites in 2D.
// Orbit camera only (deterministic, MCP-drivable, no camera-feature reload crash).
#include "../_shared/sdf/sdf_ops.hlsli"
#include "../_shared/sdf/sdf_extras.hlsli"
#include "../_shared/sdf/sdf_botany.hlsli"
#include "../_shared/sdf/sdf_shading.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct Part {
    float2 pos_xy; float2 sc_xy;
    float pos_z; float sc_z; float yaw; float tilt; float roll;
    float kind; float mat; float group; float colA; float colB; float grad; float active;
};
// _Data0 / _Data0_Count injected by the engine from the data:0 binding.

float3 sd_rotZ(float3 p, float a){ p.xy = sd_rot2(p.xy, a); return p; }

// ---- domain-warp toolkit (ported from blob_render / dada_render) ----
float3 warpFieldMode(float3 p, int mode, float f, float t)
{
    if (mode == 1){ float r = length(p.xz)+1e-3; float w = sin(r*f*2.0 - t*2.0);
        return float3(p.x/r*w, sin(p.y*f+t), p.z/r*w)*0.6; }
    if (mode == 2) return float3(sin(p.y*f+t), cos(p.x*f-t), sin(p.z*f+t*1.3));
    if (mode == 3){ float3 w = float3(sin(p.y*f+t), sin(p.z*f*1.3+t), sin(p.x*f*0.7-t));
        w += 0.5*float3(sin(p.y*f*2.1+t*1.7), sin(p.z*f*2.3-t), sin(p.x*f*1.9+t)); return w; }
    if (mode == 4){ float3 s = float3(sin(p.y*f+t), sin(p.z*f*1.2-t), sin(p.x*f*0.8+t));
        return lerp(s, round(s*3.0)/3.0, 0.85); }
    if (mode == 5){ float3 s = float3(sin(p.y*f+t), sin(p.x*f-t), sin(p.z*f*1.3+t));
        return clamp(s*4.0,-1.0,1.0)*0.7; }
    if (mode == 6){ float3 cell = floor(p*f*0.6 + t*0.1);
        float3 h = float3(frac(sin(dot(cell,float3(12.9,78.2,37.7)))*43758.5),
                          frac(sin(dot(cell,float3(39.3,11.1,83.2)))*24634.6),
                          frac(sin(dot(cell,float3(73.1,52.7,9.7)))*13451.2)) - 0.5; return h*1.4; }
    return float3(sin(p.y*f+t)+0.5*sin(p.z*f*1.7-t*1.3),
                  sin(p.z*f*0.9+t)+0.5*sin(p.x*f*1.5+t*1.1),
                  sin(p.x*f*1.1-t)+0.5*sin(p.y*f*1.3+t*0.7));
}
float3 warpLayer(float3 p, float amt, int mode, float f, float spd, float3 off, float yaw, float pitch)
{
    if (amt < 0.001) return float3(0,0,0);
    float3 q = p - off; q = sd_rotY(q, yaw); q = sd_rotX(q, pitch);
    float3 d = warpFieldMode(q, mode, f, _Time*spd);
    d = sd_rotX(d, -pitch); d = sd_rotY(d, -yaw);
    return amt*d;
}
float3 domainDistort(float3 p)
{
    float3 c = float3(dist_cx, dist_cy, dist_cz);
    float3 q = p; float h = q.y - c.y;
    if (abs(twist_amt) > 0.001) q.xz = sd_rot2(q.xz - c.xz, twist_amt*h*0.35) + c.xz;
    if (abs(bend_amt)  > 0.001) q.x += bend_amt*h*h*0.06;
    if (abs(swirl_amt) > 0.001){ float2 d = q.xz - c.xz; q.xz = sd_rot2(d, swirl_amt*exp(-length(d)*0.4)) + c.xz; }
    if (wave_amt > 0.001) q += wave_amt*sin(q.yzx*wave_freq + _Time*warp_speed)*0.3;
    if (melt_amt > 0.001){
        float3 disp = warpLayer(q, w1_amt, w1_mode, w1_freq, w1_speed, float3(w1_ox,w1_oy,w1_oz), w1_yaw, w1_pitch)
                    + warpLayer(q, w2_amt, w2_mode, w2_freq, w2_speed, float3(w2_ox,w2_oy,w2_oz), w2_yaw, w2_pitch);
        q += melt_amt*disp;
    }
    return q;
}
float distortLip(){
    float warpF = melt_amt*(w1_amt*w1_freq + w2_amt*w2_freq)*0.5;
    return 1.0/(1.0 + warpF + wave_amt*wave_freq*0.25 + abs(twist_amt)*0.4 + abs(swirl_amt)*0.3 + abs(bend_amt)*0.3);
}

float3 partLocal(Part d, float3 p, out float minsc)
{
    float3 q = p - float3(d.pos_xy.x, d.pos_xy.y, d.pos_z);
    q = sd_rotY(q, -d.yaw); q = sd_rotX(q, -d.tilt); q = sd_rotZ(q, -d.roll);
    float3 sc = float3(d.sc_xy.x, d.sc_xy.y, d.sc_z);
    minsc = min(sc.x, min(sc.y, sc.z));
    return q / sc;
}

float2 sceneMap(float3 p)
{
    float3 pw = domainDistort(p);
    float d = 1e9;
    uint c0 = min((uint)_Data0_Count, 128u);
    [loop] for (uint i=0u; i<128u; i++){
        if (i >= c0) break;
        Part b = _Data0[i];
        if (b.active < 0.5) continue;
        float3 cen = float3(b.pos_xy.x, b.pos_xy.y, b.pos_z);
        float maxsc = max(b.sc_xy.x, max(b.sc_xy.y, b.sc_z));
        float approx = length(pw - cen) - BOT_BOUND_R*maxsc;
        if (approx > blend_k + 0.06){ d = min(d, approx); continue; }
        float minsc; float3 q = partLocal(b, pw, minsc);
        float real = bot_obj_sdf(q, (int)b.kind) * minsc;
        d = op_smin(d, real, blend_k);
    }
    return float2(d * distortLip(), 0.0);
}

// nearest part -> kind + tint + local q, at a hit point
void nearestPart(float3 pos, out int kind, out float tint, out float3 q)
{
    float3 pw = domainDistort(pos);
    float best = 1e9; kind = 0; tint = 0.5; q = float3(0,0,0);
    uint c0 = min((uint)_Data0_Count, 128u);
    [loop] for (uint i=0u; i<128u; i++){
        if (i >= c0) break;
        Part b = _Data0[i];
        if (b.active < 0.5) continue;
        float3 cen = float3(b.pos_xy.x, b.pos_xy.y, b.pos_z);
        float maxsc = max(b.sc_xy.x, max(b.sc_xy.y, b.sc_z));
        if (length(pw - cen) - BOT_BOUND_R*maxsc > best) continue;
        float minsc; float3 ql = partLocal(b, pw, minsc);
        float real = bot_obj_sdf(ql, (int)b.kind) * minsc;
        if (real < best){ best = real; kind = (int)b.kind; tint = b.colA; q = ql; }
    }
}

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float aspect = _Resolution.x / _Resolution.y;
    float az = cam_orbit + rotate_speed * _Time * 30.0;
    float hueA = hue_offset + hue_cycle * frac(_Time / max(loop_period,0.001)) * 6.2831853;

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 ndc = (uv*2.0 - 1.0) * float2(aspect, -1.0);
    float3 ro, rd; sdf_orbitRay(az, cam_elevation, cam_distance, float3(0.0, cam_target_y, 0.0), ndc, cam_focal, ro, rd);

    float mat;
    float t = sdf_march(ro, rd, march_dist, 150, mat);

    // neighbour depths for the toon outline (silhouette + interior)
    float2 texel = 1.4 / _Resolution.xy;
    float nb[4]; int hitCount = 0;
    [unroll] for (int e=0;e<4;e++){
        float2 off = (e==0)?float2(texel.x,0):(e==1)?float2(-texel.x,0):(e==2)?float2(0,texel.y):float2(0,-texel.y);
        float2 nn = ((uv+off)*2.0 - 1.0) * float2(aspect,-1.0);
        float3 ro2, rd2; sdf_orbitRay(az, cam_elevation, cam_distance, float3(0.0,cam_target_y,0.0), nn, cam_focal, ro2, rd2);
        float m2; nb[e] = sdf_march(ro2, rd2, march_dist, 96, m2);
        if (nb[e] > 0.0) hitCount++;
    }

    float3 col; float cov;
    if (t < 0.0){
        // outside geometry: draw a black silhouette ring where neighbours hit
        float ring = (hitCount >= 2) ? 1.0 : 0.0;
        col = float3(0.05,0.03,0.12); cov = ring * outline_amt;
    } else {
        float3 pos = ro + rd*t;
        float3 n = sdf_calcNormal(pos);
        int kind; float tint; float3 q; nearestPart(pos, kind, tint, q);
        float3 alb = bot_albedo(kind, tint, q, n, hueA);
        float3 key = sdf_sunDir(sun_azimuth, sun_elevation);
        float dif = dot(n, key)*0.5 + 0.5;
        float band = dif > 0.66 ? 1.0 : (dif > 0.36 ? 0.80 : 0.62);
        float ao = lerp(1.0, sdf_calcAO(pos, n), 0.5);
        col = alb * band * ao;
        float edge = 0.0;
        [unroll] for (int e=0;e<4;e++){
            if (nb[e] < 0.0) edge = max(edge, 0.9);
            else edge = max(edge, smoothstep(0.05, 0.14, abs(nb[e]-t)));
        }
        col = lerp(col, float3(0.05,0.03,0.12), edge*outline_amt);
        cov = 1.0;
    }
    OutputUAV[px] = float4(col*cov, cov);   // premultiplied
}
