// What the three lanes can drive, shown three different ways on purpose.
//
//   KICK  count  -> spawns a ring that expands and dies on its own.
//                   A discrete trigger seeding an object with its own lifetime.
//   SNARE count  -> throws the scan line to a new height, which springs into
//                   place. A trigger changing persistent STATE.
//   HAT   count  -> steps one segment along the top rail, mod 32.
//                   A counter read directly as an index, no state at all.
//
// The envelopes are used only for weight and glow, which is the easy half. The
// bottom strip shows all six numbers raw so the picture above can be checked
// against the data that produced it.
//
// Monochrome instrument: white and grey geometry on black, thin strokes. The
// warm accent means ONE thing — a live event — so it appears on the kick core,
// the current hat segment, and the leading edge of each envelope bar, and
// nowhere else.

#include "demo.hlsli"
#include "../_shared/anim/anim.hlsli"
#include "../_shared/au_hud/au_text.hlsli"

StructuredBuffer<float4> Pool : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float3 BG     = float3(0.021, 0.022, 0.024);
static const float3 INK    = float3(0.93, 0.94, 0.95);
static const float3 DIM    = float3(0.33, 0.35, 0.37);
static const float3 GRID   = float3(0.12, 0.13, 0.14);
static const float3 ACCENT = float3(1.00, 0.62, 0.24);

float dmLaneLabel(float2 p, float2 a, float s, uint lane) {
    if (lane == 0u) return auText(p, a, s, G_K, G_I, G_C, G_K, 0,0,0,0,0,0,0,0);
    if (lane == 1u) return auText(p, a, s, G_S, G_N, G_A, G_R, G_E, 0,0,0,0,0,0,0);
    return auText(p, a, s, G_H, G_A, G_T, 0,0,0,0,0,0,0,0,0);
}

int dmDigits(float v) {
    float av = max(v, 0.0);
    return (av < 10.0) ? 1 : (av < 100.0) ? 2 : (av < 1000.0) ? 3
         : (av < 10000.0) ? 4 : (av < 100000.0) ? 5 : 6;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 p = float2(px) + 0.5;
    float  W = _Resolution.x;
    float  H = _Resolution.y;
    float  t = _Time;

    float u  = dmUI(H);
    float gw = 7.0 * u;
    float lw = max(1.0, u * 0.5);

    float3 col = BG;

    float M     = 14.0 * u;
    float railY = M;                        // hat step rail
    float railH = 5.0 * u;
    float fx0 = M, fx1 = W - M;
    float fy0 = railY + railH + 8.0 * u;    // event field
    float fy1 = H - 58.0 * u;
    float hy0 = fy1 + 6.0 * u;              // readout strip

    float2 ctr  = float2((fx0 + fx1) * 0.5, (fy0 + fy1) * 0.5);
    bool inField = (p.x > fx0 && p.x < fx1 && p.y > fy0 && p.y < fy1);
    float d2c    = length(p - ctr);

    // ---------------- hat: counter read straight as an index ---------------
    if (p.y >= railY && p.y <= railY + railH && p.x >= fx0 && p.x <= fx1) {
        float segW = (fx1 - fx0) / 32.0;
        int   si   = (int)floor((p.x - fx0) / segW);
        float within = frac((p.x - fx0) / segW);
        int   cur  = (int)fmod(max(hat_hits, 0.0), 32.0);
        if (si >= 0 && si < 32 && within > 0.10 && within < 0.90) {
            if (si == cur)      col = max(col, ACCENT * (0.35 + 0.65 * hat_env));
            else if (si < cur)  col = max(col, INK * 0.26);
            else                col = max(col, INK * 0.075);
        }
    }

    if (inField) {
        // Field furniture: guide rings and a crosshair, so an expanding ring is
        // read against something instead of floating in a void.
        [loop] for (int g = 1; g <= 4; ++g) {
            float gr = (fy1 - fy0) * 0.11 * (float)g;
            if (abs(d2c - gr) < lw * 0.5) col = max(col, GRID);
        }
        if (abs(p.x - ctr.x) < lw * 0.5 || abs(p.y - ctr.y) < lw * 0.5) {
            col = max(col, GRID * 0.8);
        }

        // ---------------- kick: one ring per hit, living its own life ------
        [loop] for (uint i = 0u; i < DM_RINGS; ++i) {
            float4 r = Pool[i];
            if (r.z < 0.5) continue;
            float age = t - r.x;
            if (age < 0.0 || age > ring_life) continue;

            float rad  = age * ring_speed;
            float fade = pow(saturate(1.0 - age / ring_life), 1.6);
            // Slight per-ring radius jitter from the stored seed, so a run of
            // kicks reads as separate events rather than one thick band.
            rad *= 0.94 + 0.12 * r.y;

            if (abs(d2c - rad) < lw * 0.9) col = max(col, INK * fade * 0.92);
        }

        // Kick core, on the envelope rather than the counter: the one place the
        // continuous value says something the trigger cannot.
        float coreR = (2.0 + 7.0 * kick_env) * u;
        if (d2c < coreR) col = max(col, ACCENT * (0.22 + 0.78 * kick_env));

        // ---------------- snare: trigger changing persistent state ---------
        float4 snr = Pool[DM_SNR];
        float  e   = an_spring(t - snr.z, AN_SNAPPY.x, AN_SNAPPY.y, AN_SNAPPY.z);
        float  sy  = fy0 + lerp(snr.y, snr.x, e) * (fy1 - fy0);

        if (abs(p.y - sy) < lw * 0.7) col = max(col, INK * 0.70);
        if ((p.x < fx0 + 7.0 * u || p.x > fx1 - 7.0 * u)
            && abs(p.y - sy) < 2.5 * u) {
            col = max(col, INK * (0.55 + 0.45 * snare_env));
        }
    }

    // Registration marks, drawn outside the field test so they sit on its edge.
    float ml = 7.0 * u;
    bool nearL = abs(p.x - fx0) < lw, nearR = abs(p.x - fx1) < lw;
    bool nearT = abs(p.y - fy0) < lw, nearB = abs(p.y - fy1) < lw;
    bool spanX = (p.x > fx0 - lw && p.x < fx0 + ml)
              || (p.x > fx1 - ml && p.x < fx1 + lw);
    bool spanY = (p.y > fy0 - lw && p.y < fy0 + ml)
              || (p.y > fy1 - ml && p.y < fy1 + lw);
    if (((nearL || nearR) && spanY) || ((nearT || nearB) && spanX)) {
        col = max(col, DIM * 0.9);
    }

    // ---------------- readout strip: the numbers behind the picture --------
    float rowH = (H - hy0 - 4.0 * u) / 3.0;
    if (p.y >= hy0 && p.y < H - 4.0 * u) {
        uint  lane = (uint)clamp(floor((p.y - hy0) / rowH), 0.0, 2.0);
        float ry   = hy0 + (float)lane * rowH;

        float env = (lane == 0u) ? kick_env  : (lane == 1u) ? snare_env : hat_env;
        float cnt = (lane == 0u) ? kick_hits : (lane == 1u) ? snare_hits : hat_hits;

        if (dmLaneLabel(p, float2(M, ry + 3.0 * u), u * 0.9, lane) > 0.0) {
            col = max(col, DIM * 1.5);
        }

        float bx0 = M + 6.0 * gw;
        float bx1 = W - M - 7.0 * gw;
        float by0 = ry + 3.0 * u, by1 = by0 + 4.0 * u;
        float fillX = bx0 + saturate(env) * (bx1 - bx0);

        if (p.y >= by0 && p.y <= by1 && p.x >= bx0 && p.x <= bx1) {
            if (p.x <= fillX) col = max(col, INK * 0.55);
            else              col = max(col, GRID * 1.2);
        }
        // Leading edge in the accent: it is the live value, and it is the only
        // part of the bar that is an event rather than a reading.
        if (p.y >= by0 - u && p.y <= by1 + u && abs(p.x - fillX) < lw
            && env > 0.01) {
            col = max(col, ACCENT);
        }

        if (auNum(p, float2(bx1 + 2.0 * u, ry + 3.0 * u), u * 0.9,
                  (int)round(max(cnt, 0.0)), dmDigits(cnt)) > 0.0) {
            col = max(col, DIM * 1.6);
        }
    }

    OutputUAV[px] = float4(col, 1.0);
}
