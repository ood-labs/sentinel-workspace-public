// 2E1 Step 0 — preview of the proof's own state.
//
// Not decoration and not a data-contract stand-in: this is the node's evidence
// made inspectable, as the workspace manual requires of plan and data-transform
// nodes. The capture_data_port readback is the numeric proof; this is what makes
// a failure visible at a glance instead of only in a JSON dump.
//
// TOP STRIP  - ring AGE, one column per slot: how many cooks ago each slot was
//              written. A working ring reads as a smooth sawtooth sweeping with
//              the cursor. If persistence failed, every slot except the cursor
//              collapses to "never written" and the strip is flat black.
// BOTTOM     - the (tau, theta) comb grid, tinted by each cell's own recorded
//              coordinates. A correct 2D dispatch fills the whole rectangle; a
//              broken guard or a wrong flatten leaves bands or gaps.

struct R4 { float a, b, c, d; };

StructuredBuffer<R4> Ring : register(t0);
StructuredBuffer<R4> Comb : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

static const uint NSLOTS = 800u;
static const uint HDR    = 800u;
static const uint NTAU   = 100u;
static const uint NTHETA = 160u;

static const float3 INK   = float3(0.035, 0.037, 0.040);
static const float3 GRID  = float3(0.16, 0.17, 0.18);
static const float3 TRACE = float3(0.92, 0.94, 0.95);
static const float3 WARN  = float3(0.98, 0.62, 0.23);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    uint W = (uint)_Resolution.x, H = (uint)_Resolution.y;
    if (px.x >= W || px.y >= H) return;

    float2 uv = float2(((float)px.x + 0.5) / (float)W,
                       ((float)px.y + 0.5) / (float)H);
    float3 col = INK;

    float now = max(Ring[HDR].a, 1.0);   // newest 1-based stamp
    float split = 0.34;

    if (uv.y < split) {
        // ---- ring age strip ------------------------------------------------
        uint slot = (uint)clamp(uv.x * (float)NSLOTS, 0.0, (float)(NSLOTS - 1u));
        float stamp = Ring[slot].a;
        if (stamp < 0.5) {
            // Never written. Flagged in the accent colour rather than left dark,
            // because "no data" and "old data" must not look the same -- telling
            // them apart is the entire point of the experiment.
            col = WARN * 0.55;
        } else {
            float age = saturate((now - stamp) / (float)NSLOTS);
            col = lerp(TRACE, GRID * 0.6, age);
        }
        if (uv.y > split - 2.0 / (float)H) col = GRID;
    } else {
        // ---- comb (tau, theta) grid ----------------------------------------
        float gy = (uv.y - split) / (1.0 - split);
        uint tau = (uint)clamp(gy * (float)NTAU, 0.0, (float)(NTAU - 1u));
        uint th  = (uint)clamp(uv.x * (float)NTHETA, 0.0, (float)(NTHETA - 1u));
        R4 c = Comb[tau * NTHETA + th];

        // A cell is VALID only if it recorded the coordinates this pixel asked
        // for. That catches a wrong flatten, which a mere "is it non-zero" test
        // would pass while the whole matrix was transposed.
        bool ok = (abs(c.a - (float)tau) < 0.5) && (abs(c.b - (float)th) < 0.5);
        if (!ok) {
            col = WARN;
        } else {
            col = lerp(GRID * 0.8, TRACE,
                       0.5 * (float)tau / (float)NTAU + 0.5 * (float)th / (float)NTHETA);
        }
    }

    OutputUAV[px] = float4(col, 1.0);
}
