// TP_Sim / wave_c.hlsl — substep 2 of three.
//
// All three passes read and write the same persistent state target. Module texture buffers flip
// immediately after each write, so every pass sees the preceding substep and the third result is
// already the state read by the next cook. Separate scratch targets can expose stale ping-pong
// halves and produce a real/flat ABAB frame sequence.
#define TP_SUBSTEP 2
#include "wave.hlsli"
