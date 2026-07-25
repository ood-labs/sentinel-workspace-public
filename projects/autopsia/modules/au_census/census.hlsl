// AUTOPSIA — the measurement rack's reduction.
//
// One 64-lane group aggregates the live agent population into statistics, and
// lane 0 appends a timed sample to a persistent ring so the instrument keeps a
// real chart-recorder history rather than only an instantaneous reading.
//
// Buffer layout (float4 each):
//   [0]        active, established, meanConfidence, meanAge
//   [1]        colony1, colony2, colony3, colonyUnassigned
//   [2]        meanSpeed, maxAge, totalPath, peakConfidence
//   [3]        writeIndex, sampleAccumulator, samplesWritten, spare
//   [8..23]    age distribution, 16 bins (.x = count)
//   [24..39]   heading rose, 16 bins (.x = count)
//   [64..319]  history ring: active, established, meanConfidence, meanAge
#define AU_HIST_BASE 64u
#define AU_HIST_LEN  256u

RWStructuredBuffer<float4> Census : register(u0);

groupshared float gConf[64];
groupshared float gAge[64];
groupshared float gSpeed[64];
groupshared float gActive[64];
groupshared float gEstab[64];
groupshared uint gColony[64];
groupshared uint gAgeBin[64];
groupshared uint gRoseBin[64];

[numthreads(64, 1, 1)]
void main(uint3 gtid : SV_GroupThreadID) {
    uint i = gtid.x;

    float conf = 0.0, age = 0.0, speed = 0.0, act = 0.0, est = 0.0;
    uint colony = 0u, ageBin = 99u, roseBin = 99u;

    if (i < _Data0_Count) {
        if ((_Data0[i].flags & 1u) != 0u) {
            act = 1.0;
            conf = saturate(_Data0[i].confidence);
            age = max(_Data0[i].age, 0.0);
            speed = length(_Data0[i].velocity);
            est = (conf >= establish_conf && age >= establish_time) ? 1.0 : 0.0;
            colony = (uint)clamp(_Data0[i].aux.w, 0.0, 3.0);
            ageBin = min((uint)(age / max(age_span, 0.5) * 16.0), 15u);
            float ang = _Data0[i].angle;                       // -PI..PI
            roseBin = min((uint)(frac(ang / 6.2831853 + 0.5) * 16.0), 15u);
        }
    }

    gConf[i] = conf; gAge[i] = age; gSpeed[i] = speed;
    gActive[i] = act; gEstab[i] = est;
    gColony[i] = colony; gAgeBin[i] = ageBin; gRoseBin[i] = roseBin;
    GroupMemoryBarrierWithGroupSync();

    if (i != 0u) return;

    float nAct = 0.0, nEst = 0.0, sConf = 0.0, sAge = 0.0, sSpeed = 0.0;
    float maxAge = 0.0, peakConf = 0.0;
    float4 colonies = float4(0, 0, 0, 0);
    float ageBins[16];
    float roseBins[16];
    [unroll] for (int z = 0; z < 16; ++z) { ageBins[z] = 0.0; roseBins[z] = 0.0; }

    [loop] for (uint k = 0u; k < 64u; ++k) {
        if (gActive[k] < 0.5) continue;
        nAct += 1.0;
        nEst += gEstab[k];
        sConf += gConf[k];
        sAge += gAge[k];
        sSpeed += gSpeed[k];
        maxAge = max(maxAge, gAge[k]);
        peakConf = max(peakConf, gConf[k]);

        uint c = gColony[k];
        if (c == 1u) colonies.x += 1.0;
        else if (c == 2u) colonies.y += 1.0;
        else if (c == 3u) colonies.z += 1.0;
        else colonies.w += 1.0;

        if (gAgeBin[k] < 16u) ageBins[gAgeBin[k]] += 1.0;
        if (gRoseBin[k] < 16u) roseBins[gRoseBin[k]] += 1.0;
    }

    float inv = 1.0 / max(nAct, 1.0);
    Census[0] = float4(nAct, nEst, sConf * inv, sAge * inv);
    Census[1] = colonies;
    Census[2] = float4(sSpeed * inv, maxAge, 0.0, peakConf);

    [unroll] for (int a = 0; a < 16; ++a) Census[8 + a] = float4(ageBins[a], 0, 0, 0);
    [unroll] for (int b = 0; b < 16; ++b) Census[24 + b] = float4(roseBins[b], 0, 0, 0);

    // ---- ledger: the eight longest-surviving agents ------------------------
    // Selection sort over 64 slots, done once on lane 0 — cheap here, and it
    // keeps the renderer free of any sorting work.
    float taken[64];
    [unroll] for (int q = 0; q < 64; ++q) taken[q] = 0.0;
    [loop] for (uint slot = 0u; slot < 8u; ++slot) {
        float bestAge = -1.0;
        uint bestK = 64u;
        [loop] for (uint k2 = 0u; k2 < 64u; ++k2) {
            if (gActive[k2] < 0.5 || taken[k2] > 0.5) continue;
            if (gAge[k2] > bestAge) { bestAge = gAge[k2]; bestK = k2; }
        }
        if (bestK >= 64u) { Census[40 + slot] = float4(0, 0, 0, -1); continue; }
        taken[bestK] = 1.0;
        Census[40 + slot] = float4((float)_Data0[bestK].stable_id,
                                   gAge[bestK], gConf[bestK], (float)gColony[bestK]);
    }

    // ---- timed history append ---------------------------------------------
    float4 ctl = Census[3];
    if (isnan(ctl.x) || ctl.x < 0.0 || ctl.x >= (float)AU_HIST_LEN) ctl = float4(0, 0, 0, 0);
    ctl.y += min(_DeltaTime, 0.1);
    float interval = max(sample_interval, 0.01);
    if (ctl.y >= interval) {
        ctl.y -= interval;
        uint w = (uint)ctl.x;
        Census[AU_HIST_BASE + w] = float4(nAct, nEst, sConf * inv, sAge * inv);
        ctl.x = (float)((w + 1u) % AU_HIST_LEN);
        ctl.z += 1.0;
    }
    Census[3] = ctl;
}
