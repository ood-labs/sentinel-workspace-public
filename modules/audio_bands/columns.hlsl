// Reduce the newest spectrum hop to one value per display column, once.
//
// Doing this in the renderer would repeat each column's bin scan for every row
// of the panel. Above ~1 kHz a single column covers many bins, so the reduction
// is a MAX rather than an average: a transient that lands in one bin of thirty
// must still be visible, and averaging is exactly what would hide it.
//
// The column COUNT is the live panel width, not a fixed 1280. The buffer is
// sized for the widest panel worth serving and only its first _Resolution.x
// entries are filled, so a docked panel gets one reduced column per real pixel
// at every size rather than a 1280-wide picture stretched across it.

#include "bands.hlsli"

RWStructuredBuffer<float4> Cols : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint x = tid.x;
    if (x > AB_COL_HDR) return;

    uint capacity = max(_Data0_HopCapacity, 1u);
    uint latest   = _Data0_Generation;
    uint vcount   = max(_Data0_ValueCount, 1u);
    uint total    = (uint)_Data0_Count;
    uint sbase    = (latest % capacity) * vcount;

    bool haveHop = (sbase + vcount <= total)
                && (_Data0[sbase].sample_rate != 0u)
                && (_Data0[sbase].fft_size != 0u);

    float binHz = haveHop
        ? (float)_Data0[sbase].sample_rate / (float)_Data0[sbase].fft_size : 0.0;
    float hzMax = binHz * (float)(AB_BINS - 1u);

    if (x == AB_COL_HDR) {
        float hopDt = (haveHop && _Data0[sbase].sample_rate != 0u)
            ? (float)_Data0[sbase].hop_size / (float)_Data0[sbase].sample_rate : 0.0;
        Cols[AB_COL_HDR] = float4(binHz, hzMax, hopDt, 0.0);
        return;
    }

    // Beyond the panel's real width there is nothing to draw. Cleared rather
    // than left stale so a shrink cannot leave a band of frozen spectrum that a
    // later widen would suddenly reveal.
    float w = clamp(_Resolution.x, 1.0, (float)AB_COLS_MAX);
    if ((float)x >= w) {
        Cols[x] = float4(0.0, 0.0, 0.0, 0.0);
        return;
    }

    float4 prev = Cols[x];
    float  peak = prev.y;

    if (!haveHop || binHz <= 0.0) {
        Cols[x] = float4(0.0, peak, 0.0, 0.0);
        return;
    }

    float hzLo = abXToHz((float)x / w,        hzMax);
    float hzHi = abXToHz((float)(x + 1u) / w, hzMax);

    int b0 = (int)floor(hzLo / binHz);
    int b1 = (int)floor(hzHi / binHz);
    b0 = clamp(b0, 0, (int)vcount - 1);
    b1 = clamp(max(b1, b0), 0, (int)vcount - 1);

    float mag = 0.0;
    [loop] for (int b = b0; b <= b1; ++b) {
        mag = max(mag, _Data0[sbase + (uint)b].magnitude);
    }

    // Normalize dB into 0..1 against the display floor so the renderer stays a
    // pure drawing pass.
    // Same gain the detector applies, so the picture and the decision can never
    // be looking at different levels.
    float floorDb = min(db_floor, -6.0);
    float lvl = saturate((abSafeDb(mag) + input_gain_db - floorDb) / (0.0 - floorDb));

    // Peak hold falls in wall clock, not per cook, so the decay a human sees is
    // the same at 20 Hz and at 60 Hz.
    peak = max(lvl, peak - max(_DeltaTime, 0.0) * 0.55);

    Cols[x] = float4(lvl, saturate(peak), 0.0, 0.0);
}
