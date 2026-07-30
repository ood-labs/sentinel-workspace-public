# Data Scope

Three auto-ranging strip charts over a live scalar stream. This is the worked
example for `modules/_shared/ui/sui3_trace.hlsli`; the component is the
deliverable and this module is the proof that it works.

The plotted scalars are three mel-band aggregates (low, mid, high). That choice
is incidental. Nothing below `sample.hlsl` knows the stream is audio, which is
the point of extracting the component in the first place.

## What it demonstrates

Each of the component's four mechanisms is visible and, where possible,
switchable. A component whose behaviour cannot be turned off cannot be shown to
be doing anything.

| Mechanism | Where you see it |
| --- | --- |
| Ring + generation catch-up | `HOP HZ` and `SAMPLES` in the footer. Samples arrive at 187.5 Hz while the graph cooks at ~60 Hz. |
| Decaying-peak autoscale | The `AUTOSCALE`/`FIXED` header state and each lane's `FS` readout. |
| Max-reduce columns | Hat transients stay visible at the 5 s span, where a column covers several samples. |
| Reference in the scale | The dashed line stays inside the plot instead of pinning to the top edge. |

## Controls

Properties only. There is no authored canvas control surface, deliberately: a
scope is a readout, and `knowledge/ui-authoring.md` reserves viewport UI for
interactions Properties cannot express. Duplicating six sliders onto the canvas
would be exactly the anti-pattern that section names.

`Span`, `Autoscale`, `Fixed Scale`, `Peak Half-Life`, `Reference`, `dB Floor`,
`Accent`.

Flip `Autoscale` off to see what the mechanism is buying: the plot either clips
or crawls along the floor depending on where `Fixed Scale` sits.

## Source

The saved project uses Audio In in Device/Loopback mode and follows the Windows
default playback endpoint. Route any meaningful program audio through that
endpoint, then verify the Audio In diagnostics report an active endpoint and a
present signal before judging the scope.

## Proof

```
python projects/interaction_lab/tools/data_scope_proof.py
python projects/interaction_lab/tools/data_scope_measure.py <capture.png>
```

The measure tool discriminates the three states that matter, which is the only
reason to trust it: an empty plot reads 0.000, a healthy one 0.875 (exactly the
1.15 headroom), and a clipping one 1.000.

## Known behaviour

Full scale is `max(windowMax, decayedPeak)`. The decayed peak alone is not
enough: it is anchored at the present moment while the plot shows history, so a
short half-life against a long span lets the scale fall below its own on-screen
samples. Measured at a 5 s span and 0.25 s half-life, the decayed peak alone
plotted p95 1.000 (fully clipped) where the combined term plotted 0.855.
