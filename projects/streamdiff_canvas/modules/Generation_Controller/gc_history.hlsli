// Generation_Controller / gc_history - the activity ring, shared by history.hlsl (the only writer)
// and layout.hlsl (which draws and inspects it).
//
//   [0]        head, sample clock (s), stamp cycle at the last sample, window seen since it
//   [1]        magic, -, -, -
//   [2 .. 257] one sample every GH_DT s, oldest overwritten: (window open, stamps fired, -, -)
#ifndef GC_HISTORY_HLSLI
#define GC_HISTORY_HLSLI

#define GH_N      256u
#define GH_FIRST  2u
#define GH_DT     (1.0 / 32.0)
#define GH_SPAN   8.0              // GH_N * GH_DT seconds on screen
#define GH_MAGIC  4711.0

#endif
