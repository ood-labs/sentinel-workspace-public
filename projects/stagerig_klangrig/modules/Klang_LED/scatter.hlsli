// A fixed permutation visits each of the 12 wing loops once per snare burst.
// Phase comes from the selected musical lane, never wall time or frame noise.
float wingScatter(uint wing, float phase, float active, float spread, float width,
                  float offset, float reverse, float rate, float duty, float cycleBeats)
{
    float rank = ((wing * 5u + 3u) % 12u) / 11.0;
    if (reverse > .5) rank = 1 - rank;
    float age = (phase + offset - rank * spread) / max(.01, width);
    if (active < .5 || age < 0 || age >= 1) return 0;
    // Rate is flashes per musical beat; duty is the lit fraction of each flash.
    float pulse = frac(age * max(.01, width) * cycleBeats * rate);
    float edge = min(.035, duty * .2);
    return smoothstep(0, edge, pulse) * (1 - smoothstep(duty-edge, duty, pulse));
}
