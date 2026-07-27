# Bands Demo

A consumer of `audio_bands`, built to show what its outputs are actually good
for. Not part of the detector — delete it freely.

## Wiring

No data link. Control outputs reach parameters through expressions:

```
sentinel_expression set /sentinel/pipelines/bands_demo/parameters/kick_env
  expression: ref("audio_bands/control_outputs/kick")
```

Six of them: `kick_env`/`snare_env`/`hat_env` from `kick`/`snare`/`hat`, and
`kick_hits`/`snare_hits`/`hat_hits` from `kick_count`/`snare_count`/`hat_count`.

## The point

The two kinds of output are not interchangeable, and the demo uses each lane a
different way to make that concrete:

| lane | output used | what it demonstrates |
| --- | --- | --- |
| KICK | count | each hit spawns a ring that expands and dies on its own clock |
| SNARE | count | each hit throws the scan line to a new height, which springs into place |
| HAT | count | the counter is read straight as `% 32` to step the top rail |

An **envelope** multiplies into a size or a brightness and needs no state. It is
the easy half, and here it only adds weight: the kick core, the glow on the
current hat segment, the leading edge of each bar.

A **counter** is monotonic, so the interesting quantity is its *change*, which
is a discrete trigger. A trigger can seed an object that then lives its own
life, which an envelope cannot do — that is the difference between a shape that
throbs along with the music and a shape that is built by it. Hat shows the cheap
end of the same idea: a counter read directly as an index needs no state at all.

The strip along the bottom prints all six numbers raw, so the picture above can
always be checked against the data that produced it.

## The one thing worth knowing if you copy this

Counter deltas larger than `DM_ADOPT_JUMP` (8) are adopted silently instead of
fired. The counts are lifetime totals in the thousands and they arrive through
expressions, which evaluate whenever they evaluate — well after the module's
first cook. Without the guard, every load saw the full total land as one delta
and fired a phantom hit on all three lanes.

A settling delay was tried first and does not work, because there is no window
short enough to be worth waiting that the drivers reliably beat. A magnitude
threshold is timing-independent, and it covers counter resets and upstream
reloads for free. Refractory caps the fastest lane near 25 hits a second, so a
genuine per-frame delta is 0 or 1 and never remotely close to 8.
