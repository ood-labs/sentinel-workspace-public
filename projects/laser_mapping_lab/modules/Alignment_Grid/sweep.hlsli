// Sync Sweep: one vertical line sweeping left and right at a constant speed, drawn by the laser
// and the projector from the same clock, so any gap between the two lines on the wall is latency.
//
// The projector also draws a ruler that rides with its line: a tick wherever the line WAS 10, 20,
// 30... ms ago (top band) and WILL BE 10, 20, 30... ms from now (bottom band), longer every 50 ms.
// A laser that lags shows an older position, so it lands on a top tick: count the ticks for the lag
// in 10 ms steps. On a bottom tick the laser is early. Positions come from sweepX itself, so the
// ruler stays right through the turnarounds, where the line doubles back over its own ticks.
static const float SWEEP_TICK_S = 0.010;
static const int SWEEP_TICKS = 12;

// Line position at time t, in the [-1,1] frame (x right), bouncing between -extent and +extent.
float sweepX(float t, float extentIn, float hz)
{
 float u = frac(t * hz);
 return extentIn * (2 * abs(2 * u - 1) - 1);
}
