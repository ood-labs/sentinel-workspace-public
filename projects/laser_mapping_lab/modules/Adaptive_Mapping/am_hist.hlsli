// Adaptive_Mapping / am_hist.hlsli - the records-out history ring, written by history.hlsl and
// plotted by layout.hlsl. One sample of the compiler's stats every 1/32 s, whatever the cook rate.
//   H[0]          (newest slot, clock s, samples held (capped at the ring), magic)
//   H[1 + slot]   (records out, preferred budget, status, cycle ms)
#ifndef AM_HIST_HLSLI
#define AM_HIST_HLSLI
#define AM_HIST_N     128u
#define AM_HIST_DT    (1.0 / 32.0)
#define AM_HIST_MAGIC 6211.0
#endif
