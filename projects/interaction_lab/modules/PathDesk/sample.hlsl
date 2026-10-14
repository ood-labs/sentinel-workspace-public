// Path Desk / sample - what the desk publishes: every path measured and sampled evenly along its
// length (the "Path" buffer, laid out in _shared/plot.hlsli).
//
// One group of 1024 threads:
//   1. one thread per segment walks it as 32 chords and keeps the running length;
//   2. one thread per path adds its segments up;
//   3. thread 0 shares the 1024 samples out by length (every path with a segment gets two or more)
//      and writes the header and the path records;
//   4. one thread per anchor writes where it sits along its path and how far its tangent breaks;
//   5. one thread per sample finds its segment and chord by length, then evaluates the bezier there:
//      position, heading and curvature.
#include "../_shared/ui/il_core.hlsli"
#include "path.hlsli"

RWStructuredBuffer<float4> P : register(u0);

#define SUB 32u
#define NSEG (PD_PATHS * PD_AMAX)

groupshared float gsCum[NSEG][SUB + 1u];   // length along each segment at each chord end
groupshared float gsStart[NSEG];           // where each segment starts along its path
groupshared float gsLen[PD_PATHS];
groupshared uint  gsFirst[PD_PATHS];
groupshared uint  gsCount[PD_PATHS];

float2 dirOf(float2 v) { return dot(v, v) > 1e-8 ? normalize(v) : float2(1.0, 0.0); }

[numthreads(1024, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    uint pk = S[PD_P0].e;

    // 1. segment lengths
    if (gi < NSEG)
    {
        uint p = gi / PD_AMAX, k = gi % PD_AMAX;
        gsCum[gi][0] = 0.0;
        if (k < pdSegs(pk, p))
        {
            float2 p0, p1, p2, p3;
            pdSeg(pk, p, k, p0, p1, p2, p3);
            float2 prev = p0;
            float acc = 0.0;
            [loop] for (uint i = 1u; i <= SUB; i++)
            {
                float2 cur = pdBez(p0, p1, p2, p3, (float)i / (float)SUB);
                acc += length(cur - prev);
                gsCum[gi][i] = acc;
                prev = cur;
            }
        }
        else
        {
            [loop] for (uint i = 1u; i <= SUB; i++) gsCum[gi][i] = 0.0;
        }
    }
    GroupMemoryBarrierWithGroupSync();

    // 2. path lengths
    if (gi < PD_PATHS)
    {
        uint segs = pdSegs(pk, gi);
        float acc = 0.0;
        [loop] for (uint k = 0u; k < PD_AMAX; k++)
        {
            gsStart[gi * PD_AMAX + k] = acc;
            if (k < segs) acc += gsCum[gi * PD_AMAX + k][SUB];
        }
        gsLen[gi] = acc;
    }
    GroupMemoryBarrierWithGroupSync();

    // 3. the samples shared out by length
    if (gi == 0u)
    {
        uint paths = pdPaths(pk), drawn = 0u, anchors = 0u;
        float total = 0.0;
        [loop] for (uint p = 0u; p < PD_PATHS; p++)
        {
            anchors += pdCount(pk, p);
            if (pdSegs(pk, p) == 0u) continue;
            drawn++;
            total += gsLen[p];
        }
        uint spare = PLOT_SAMPLES - 2u * drawn;
        uint first = 0u;
        [loop] for (uint p2 = 0u; p2 < PD_PATHS; p2++)
        {
            uint n = 0u;
            if (pdSegs(pk, p2) > 0u) n = 2u + (uint)floor((float)spare * gsLen[p2] / max(total, 1e-3));
            gsFirst[p2] = first;
            gsCount[p2] = n;
            first += n;
            float flags = (pdClosed(p2) ? 1.0 : 0.0) + 2.0 * (float)pdPen(p2);
            P[PLOT_PATH0 + p2] = float4((float)gsFirst[p2], (float)n, gsLen[p2], p2 < paths ? flags : 0.0);
        }
        P[PLOT_HEAD] = float4((float)paths, total, (float)first, (float)anchors);
    }
    GroupMemoryBarrierWithGroupSync();

    // 4. the anchors: where along the path, and how far the tangent breaks there
    if (gi < NSEG)
    {
        uint p = gi / PD_AMAX, j = gi % PD_AMAX;
        uint n = pdCount(pk, p), segs = pdSegs(pk, p);
        float4 rec = float4(0.0, 0.0, 0.0, 0.0);
        if (j < n)
        {
            PdRec r = pdAnchor(p, j);
            float sAt = (j < segs) ? gsStart[gi] : gsLen[p];
            float turn = 0.0;
            bool hasIn = segs > 0u && (j > 0u || pdClosed(p));
            bool hasOut = j < segs;
            if (hasIn && hasOut)
            {
                float2 a0, a1, a2, a3, b0, b1, b2, b3;
                pdSeg(pk, p, (j + n - 1u) % n, a0, a1, a2, a3);
                pdSeg(pk, p, j, b0, b1, b2, b3);
                float2 tin = dirOf(pdTangent(a0, a1, a2, a3, 1.0));
                float2 tout = dirOf(pdTangent(b0, b1, b2, b3, 0.0));
                turn = atan2(tin.x * tout.y - tin.y * tout.x, dot(tin, tout));
            }
            rec = float4(sAt, turn, r.a);
        }
        P[PLOT_ANCHOR0 + gi] = rec;
    }

    // 5. one sample each
    {
        uint k = gi;
        uint p = PD_PATHS;
        [unroll] for (uint q = 0u; q < PD_PATHS; q++)
            if (gsCount[q] > 0u && k >= gsFirst[q] && k < gsFirst[q] + gsCount[q]) p = q;
        float4 rec = float4(0.0, 0.0, 0.0, 0.0);
        if (p < PD_PATHS)
        {
            float sAt = gsLen[p] * (float)(k - gsFirst[p]) / (float)(gsCount[p] - 1u);
            uint segs = pdSegs(pk, p);
            uint seg = 0u;
            [loop] for (uint m = 1u; m < segs; m++)
                if (gsStart[p * PD_AMAX + m] <= sAt) seg = m;
            uint id = p * PD_AMAX + seg;
            float local = sAt - gsStart[id];
            uint lo = 0u, hi = SUB;
            [loop] while (hi - lo > 1u)
            {
                uint mid = (lo + hi) >> 1;
                if (gsCum[id][mid] <= local) lo = mid; else hi = mid;
            }
            float span = gsCum[id][hi] - gsCum[id][lo];
            float t = ((float)lo + (span > 1e-6 ? saturate((local - gsCum[id][lo]) / span) : 0.0)) / (float)SUB;
            float2 p0, p1, p2, p3;
            pdSeg(pk, p, seg, p0, p1, p2, p3);
            float2 pos = pdBez(p0, p1, p2, p3, t);
            float2 tan = pdTangent(p0, p1, p2, p3, t);
            rec = float4(pos, atan2(tan.y, tan.x), pdCurvature(p0, p1, p2, p3, t));
        }
        P[PLOT_SAMPLE0 + k] = rec;
    }
}
