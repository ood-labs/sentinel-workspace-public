# Signal Trails

Four connected trails over any scalar you can route into a parameter. This is
the second consumer of `modules/_shared/ui/sui3_trace.hlsli` and the phase's
reusability proof: the component is used **unmodified**.

It is deliberately as unlike Data Scope as the component allows.

| | Data Scope | Signal Trails |
| --- | --- | --- |
| Source | Audio In, a data port | any scalar, **no data port at all** |
| Rate | 187.5 Hz, many samples per cook | cook rate, one sample per cook |
| Drawing | filled area | connected trail |
| Lanes | 3 | 4 |

## Wiring

Channels are ordinary float parameters, so anything that can drive a parameter
can be plotted: a control output through an expression, OSC, a Conductor cue, or
a hand on a slider. The reference wiring is Motion Console's LFOs:

```
sentinel_expression action=set \
  path=/sentinel/pipelines/Signal_Trails/parameters/ch1 \
  expression='ref("Motion_Console/control_outputs/lfo1")'
```

`ch1..ch3` take `lfo1..lfo3` and `ch4` takes `energy`. Each channel autoscales
independently, so a channel that barely moves is still legible next to one that
swings full range.

## Controls

`Channel 1-4`, `Span`, `Autoscale`, `Peak Half-Life`, `Bipolar`, `Accent`.

`Bipolar` folds -1..1 around a mid-height zero line and pins full scale to 1.0.
Autoscaling a bipolar channel is refused on purpose: it would move the baseline
away from zero as the signal grew, so a centred trace would drift off centre.

## What it taught the component

**Max-reduce is only right when downsampling.** At 60 Hz over an 8 s span the
plot holds 481 samples across ~1600 px, so roughly three columns share each
sample. Max-reducing that drew every LFO as a staircase with a three-pixel
tread. The renderer now tests `sui3TraceUpsampling` and interpolates via
`sui3TraceFrac` when the plot has more columns than samples.

**A fill is wrong for a smooth signal.** `sui3StripTrail` was added for this:
a solid slab under an LFO hides the shape that is the entire content.

## Note on catch-up

Sampling once per cook means the ring's generation catch-up degenerates to a
single sample per frame. That is not a limitation being hidden: catch-up exists
for streams that outpace the frame rate, and this one does not. Data Scope is
where that mechanism is exercised and proven.
