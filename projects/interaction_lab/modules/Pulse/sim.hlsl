// Pulse / sim - one group of 64 threads: thread 0 turns this cook's viewport events into drops,
// then every thread runs one ball through PB_SUB substeps against the twelve bars.
//
// A contact faster than `strike_floor` is a STRIKE: it is appended to EventOut0 ("Impacts") with
// its substep, so the host can place it inside the frame, and it lights a spark - the only thing
// the GPU shows on its own. Whether the bar rings is the Script's decision, and comes back later
// through EventIn0 ("Echo").
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "pulse.hlsli"

RWStructuredBuffer<PbRec> W : register(u0);

groupshared uint gsHits;
groupshared uint gsHistBase;

float pbHash(float n) { return frac(sin(n * 12.9898) * 43758.5453); }

void spawnBall(float2 p, float2 v)
{
    // first free slot, else the oldest ball
    uint slot = 0u;
    float oldest = -1.0;
    [loop] for (uint i = 0u; i < PB_BALLS; i++)
    {
        PbRec b = W[W_BALL0 + i];
        if (b.c <= 0.0) { slot = i; oldest = 1e9; break; }
        if (b.d > oldest) { oldest = b.d; slot = i; }
    }
    PbRec h = W[W_HEAD];
    PbRec b = (PbRec)0;
    b.a = p;
    b.b = v;
    b.c = PB_BALL_R;
    b.e = (uint)h.c;
    W[W_BALL0 + slot] = b;
    h.c += 1.0;
    W[W_HEAD] = h;
}

void controlThread(float dt)
{
    PbRec h = W[W_HEAD];
    uint lastSeq = ilEvWatermark(h.e);
    uint newest = lastSeq;
    bool autoOn = (h.f & 1u) != 0u;
    bool spaceHeld = (h.f & 2u) != 0u;
    bool clearAll = false;
    float2 pours[4];
    uint nPour = 0u;

    uint n = ilEvCount();
    [loop] for (uint i = 0u; i < n; i++)
    {
        ViewportEvent e = _ViewportEvents[i];
        if (!ilEvFresh(e.sequence, lastSeq)) continue;
        newest = ilEvAdvance(newest, lastSeq, e.sequence);
        float2 p = pbFromUv(e.position);
        if (ilIsClick(e) && nPour < 4u) { pours[nPour] = p; nPour++; }
        else if (ilIsDrag(e) && e.phase != IL_PH_CANCEL)
        {
            // pour: one ball every 70 ms along the drag
            if (_Time - h.a.y > 0.07 && nPour < 4u) { pours[nPour] = p; nPour++; h.a.y = _Time; }
        }
        else if (ilLatch(e, IL_KEY_SPACE, spaceHeld)) autoOn = !autoOn;
        else if (ilIsKeyDown(e, IL_KEY_C)) clearAll = true;
        if (e.type != IL_EV_KEY) h.b = p;
    }
    h.e = newest;
    h.f = (autoOn ? 1u : 0u) | (spaceHeld ? 2u : 0u);
    h.d = _Time;                                    // the clock every strike stamp is in

    // the dropper: alternate staircases, a little jitter so no two runs repeat
    bool autoDrop = false;
    float2 autoP = float2(0.0, 0.0);
    if (autoOn)
    {
        h.a.x += dt * max(auto_rate, 0.05);
        if (h.a.x >= 1.0)
        {
            h.a.x = frac(h.a.x);
            float k = h.c;
            bool right = frac(k * 0.5) > 0.25;
            float jitter = (pbHash(k) - 0.5) * 60.0;
            autoP = float2(right ? PB_W - 170.0 + jitter : 170.0 + jitter, 40.0);
            autoDrop = true;
        }
    }
    W[W_HEAD] = h;

    if (clearAll)
        [loop] for (uint i2 = 0u; i2 < PB_BALLS; i2++) { PbRec b = W[W_BALL0 + i2]; b.c = 0.0; W[W_BALL0 + i2] = b; }
    [loop] for (uint k2 = 0u; k2 < nPour; k2++) spawnBall(pours[k2], float2(0.0, 0.0));
    if (autoDrop) spawnBall(autoP, float2(0.0, 30.0));
}

[numthreads(64, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    float dt = clamp(_DeltaTime, 0.0, 1.0 / 30.0);
    if (gi == 0u)
    {
        controlThread(dt);
        gsHits = 0u;
        gsHistBase = W[W_STATS].e;
    }
    AllMemoryBarrierWithGroupSync();

    PbRec b = W[W_BALL0 + gi];
    if (b.c > 0.0)
    {
        float sdt = dt / (float)PB_SUB;
        [loop] for (uint s = 0u; s < PB_SUB; s++)
        {
            b.b.y += gravity * sdt;
            b.a += b.b * sdt;
            [loop] for (uint i = 0u; i < PB_BARS; i++)
            {
                float2 c, dir;
                float hl;
                pbBar(i, c, dir, hl);
                float2 rel = b.a - c;
                float along = clamp(dot(rel, dir), -hl, hl);
                float2 d = rel - dir * along;
                float dist = length(d);
                float pen = b.c + PB_BAR_T - dist;
                if (pen <= 0.0 || dist < 1e-4) continue;
                float2 nrm = d / dist;
                float vn = dot(b.b, nrm);
                if (vn < 0.0)
                {
                    float2 vt = b.b - nrm * vn;
                    b.b = vt * 0.992 - nrm * vn * bounce;          // rolling loses a little each contact
                    float speed = -vn;
                    if (speed > strike_floor)
                    {
                        float stamp = _Time + ((float)s + 0.5) * sdt;
                        float u = 0.5 + 0.5 * along / hl;
                        GPUEventRecord ev;
                        ev.event_type = PB_EV_IMPACT;
                        ev.payload = float4((float)i, speed, u, stamp);
                        ev.sub_step = s;
                        ev.sub_step_fraction = 0.5;
                        ev.sub_step_count = PB_SUB;
                        EventOut0.Append(ev);

                        PbRec sp = (PbRec)0;
                        sp.a = float2(stamp, u);
                        sp.b = float2(speed, (float)b.e);
                        W[W_SPARK0 + i] = sp;

                        uint k;
                        InterlockedAdd(gsHits, 1u, k);
                        PbRec hr = (PbRec)0;
                        hr.a = float2(stamp, (float)i);
                        hr.b = float2(speed, u);
                        W[W_HIST0 + (gsHistBase + k) % PB_HIST] = hr;
                    }
                }
                b.a += nrm * pen;
            }
        }
        b.d += dt;
        if (b.a.y > PB_H + 40.0 || b.a.x < -40.0 || b.a.x > PB_W + 40.0 || b.d > 40.0) b.c = 0.0;
        W[W_BALL0 + gi] = b;
    }
    AllMemoryBarrierWithGroupSync();
    if (gi == 0u)
    {
        PbRec st = W[W_STATS];
        st.c += (float)gsHits;
        st.e = gsHistBase + gsHits;
        W[W_STATS] = st;
    }
}
