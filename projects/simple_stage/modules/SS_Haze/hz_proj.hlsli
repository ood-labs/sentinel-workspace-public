// SS_Haze / hz_proj — the projections hzsum reduces the field to: the haze and the air averaged through the
// hall, seen in plan (down through its height) and in long section (across its width). The preview draws them
// and hzstats reads its numbers from them, so neither walks the whole field.
//
//   P_FE  haze, section: one line per (z, y) across x     (mean, peak, sum, cells in the hall)
//   P_FP  haze, plan:    one line per (z, x) down y       (mean, peak, -, -)
//   P_AE  air, section:  one line per (z, y) across x     (mean speed, mean temperature, sum |div| before the
//                                                          projection, sum |div| after it)
//   P_AP  air, plan:     one line per (z, x) down y       (mean speed, mean temperature, top speed, -)
// Line j of each: section j = y * nz + z, plan j = z * nx + x.
#ifndef SS_HZ_PROJ_HLSLI
#define SS_HZ_PROJ_HLSLI
#define P_FE 0u
#define P_FP 19200u      // + FZ * FY
#define P_AE 61440u      // + FZ * FX
#define P_AP 66240u      // + AZ * AY
#define P_END 76800u     // + AZ * AX
#endif
