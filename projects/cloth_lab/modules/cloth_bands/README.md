# Audio Bands

Kick / snare / hat detection in one node. Pick a frequency band on the spectrum,
set a threshold, get a trigger. There is no BPM tracking, no beat clock, no
classifier and no second node.

## Wiring

```
Audio In / Spectrum  ->  Audio Bands / Spectrum
```

One data link, nothing else. Drive anything downstream from the control outputs:

```
ref("audio_bands/control_outputs/kick")
```

## The view

It is a full-bleed Canvas panel at `follow_panel` resolution: the whole dock is
the instrument, and it redraws at whatever size you give it. Every size in it —
plot extents, gutters, stroke widths, text, the threshold grab zone — is a
multiple of one UI unit derived from the panel height, and the spectrum reduces
to one column per real pixel rather than stretching a fixed-width picture. Drag
the dock wider and you get more frequency resolution, not a blurrier image.

The top half is the live spectrum on a log-Hz axis. Each lane's band is drawn on
it as a shaded slab, and that slab is exactly the set of FFT bins the detector
sums. Under each band name is its span in Hz and its current level in dB.

The bottom half is one strip per lane. Each shows that lane's onset value at
analysis-hop resolution (187.5 Hz at the default hop size) over the last few
seconds, with its threshold drawn across it as a dashed line, a tick where it
fired, a flash block and a running hit count. The number at the strip's left is
the strip's current full scale in dB.

Everything you need to answer "why did that not trigger" is in that one picture:
the peak is either above the dashed line or it is not.

## Setting a band

| gesture | effect |
| --- | --- |
| left-drag on a band's **threshold bar** | set that lane's threshold |
| left-drag anywhere else **on a band** | move the band |
| middle- or right-drag on a band | resize it about its centre |

There is no lane selector and no create gesture. All three bands always exist,
so you point at the one you mean.

Move and resize work in log-axis coordinates, so the gesture feels identical at
50 Hz and at 10 kHz, and moving a band keeps its musical interval instead of
stretching as it travels up the axis. The threshold fader maps absolutely, so
the bar stays under the pointer rather than drifting over a long drag. The
button and the grabbed band are latched on press and held for the whole drag, so
a fast pointer cannot drop the edit or jump it to a neighbouring band.

The threshold bar is drawn in the accent with a grab tab on the band's right
edge, deliberately styled as a control rather than as a reading: it is a *flux*
threshold, while the axis behind it is *level*, and those are not the same
quantity. Its value in dB is printed beside it, and the trace strip below shows
the same threshold against the axis it actually belongs to.

**Reset Bands** (hold above 0.5, then return it to 0) puts all three back to
their opening positions.

Band edges are not parameters. They live in a durable state buffer, so they are
saved with the project, captured in node presets, and covered by undo, but they
cannot be typed as numbers. That is deliberate: which frequencies are "the kick"
is a spatial judgement against visible evidence, and a pair of Hz sliders typed
against a picture you cannot see is what the previous design got wrong.

## How detection works

Per lane, per analysis hop:

```
E     = weighted mean of the band's magnitude bins   (weights from Band Shape)
flux  = max(0, dB(E) - rolling dB baseline of this band)
fire  = flux is a local peak, above threshold, refractory elapsed, band above gate
```

Four properties worth knowing:

- **Weight-normalised.** Widening a band does not change its level, so resizing
  a band never forces a threshold re-tune.
- **Gain-independent sensitivity.** `flux` is dB above the band's *own* rolling
  level, so input gain cancels out of it exactly. **Input Gain** therefore does
  not make the detector more sensitive. What it does is lift a quiet source
  clear of the signal gate: a source running 40 dB down puts every band under
  -70 dB and switches all three lanes off, which reads as "detection stopped
  working" rather than "the input is too quiet". Turn it up until the band level
  readouts stop being greyed out. To actually change sensitivity, move the
  threshold.
- **Peak-triggered, not level-triggered.** A drum stays above threshold for its
  whole decay, so a level test fires twice per hit. An upward-crossing test fixes
  that but swallows hits on busy material, where the flux stops returning below a
  low threshold at all. A peak survives both cases. Costs one hop of latency,
  5.3 ms.
- **Gated at -70 dB** absolute band level. Measured: real drums put the kick band
  at about -41 dB and a -44 dBFS noise floor puts it at -79 dB. Without the gate,
  a noise floor produced phantom hits, because flux is relative and noise
  produces the same small excursions a quiet drum does. A gated lane greys out
  its level readout rather than going silently dead.

## Tuning notes

The shipped defaults were tuned against varied drum material. Treat them as a
starting point and validate counts against the user's actual source:

- Kick and hat land within roughly 10-12% on count.
- `silence` and `noise_floor_44db` produce exactly zero on every lane.
- Snare over-counts on patterns containing kicks. Its band is on the snare's
  1.5-5 kHz noise burst rather than its 180-420 Hz fundamental, which removes
  the kick-body overlap, and a hats-only pattern confirms zero bleed from hats.
  What remains is the kick's own broadband onset click landing inside the snare
  band. Band-plus-threshold detection cannot separate those two by frequency
  alone; that is a limit of the method, not a defect in the implementation.

Snare is therefore the lane most worth dragging yourself against your own
material. The view exists precisely so that is a thing you can do by looking.

## Limits

- Count accuracy is not timing accuracy. Nothing here measures onset placement.
- `halftime_shuffle_88` and `kick_snare_coincident_124` are held out of the
  corpus and were not used to choose any default.
- The Spectrum port always publishes 1024 bins regardless of FFT size, so at
  `fft_size 4096` real coverage is only 0-12 kHz. The axis reads its top from the
  record's own `sample_rate / fft_size` and follows it down, rather than claiming
  a range that is not there.
