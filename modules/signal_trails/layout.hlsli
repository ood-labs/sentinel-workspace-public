#ifndef SIGNAL_TRAILS_LAYOUT_HLSLI
#define SIGNAL_TRAILS_LAYOUT_HLSLI

#include "../_shared/ui/sui3_trace.hlsli"

static const uint ST_CHANS = 4u;
static const uint ST_CAP   = 1024u;
static const uint ST_STRIDE = 1026u;

uint stStateA(uint ch) { return ch * ST_STRIDE + 0u; }
uint stStateB(uint ch) { return ch * ST_STRIDE + 1u; }
uint stTraceBase(uint ch) { return ch * ST_STRIDE + 2u; }

float stUI(float H) { return clamp(floor(H / 300.0), 1.0, 5.0); }

// Type scales and lane rects live in render.hlsl, so the sampling pass never
// pulls in a font table it does not draw with.

#endif
