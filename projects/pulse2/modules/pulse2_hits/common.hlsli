#ifndef PULSE2_HITS_COMMON_HLSLI
#define PULSE2_HITS_COMMON_HLSLI

// Shared geometry so the scatter and render passes cannot disagree about which
// column is which sample. They are separate dispatches over the same mapping;
// duplicating the arithmetic in both is how a timeline ends up drawing marks
// one column away from where it says they are.

#define HT_COLS      1600u   // occupancy columns; >= any sane output width
#define HT_LANES     4u
#define HT_RING_HALF 512u    // onsets 0..511, beats 512..1023
#define HT_BEAT_LANE 3u

struct HitRec { uint lane_id; uint onset_serial; uint hop_index; uint sample_position; };

// tstate[0]: .x now (samples, float), .y last _Time, .z newest seen, .w valid
struct TState { float4 v; };

// Column centre -> sample position, given the right edge `now` and a window
// width in samples. Column HT_COLS-1 sits exactly at `now`.
float ht_col_to_sample(uint col, float now, float win) {
    float f = ((float)col + 0.5) / (float)HT_COLS;   // 0..1 across the window
    return now - (1.0 - f) * win;
}

// Inverse, unclamped and signed so callers can reject out-of-range themselves
// rather than having values silently pinned to column 0.
float ht_sample_to_col(float pos, float now, float win) {
    float f = 1.0 - (now - pos) / max(win, 1.0);
    return f * (float)HT_COLS - 0.5;
}

#endif
