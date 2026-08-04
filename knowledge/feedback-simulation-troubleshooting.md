# Feedback Simulation Troubleshooting

Use this playbook when an authored Sentinel Module contains a persistent field, iterative GPU
solver, accumulation buffer, or temporal feedback path and the result flickers, alternates,
explodes, refuses to settle, or remains damaged after reload. The worked water example is
`projects/tessera_pool/`; structured-buffer-specific solver guidance also lives in
`knowledge/gpu-cloth-and-xpbd.md`.

## Classify Before Tuning

Do not begin by changing damping, gain, or quality. First determine which class of failure is
present:

| Symptom | First hypothesis | Discriminating test |
| --- | --- | --- |
| Exact bright/dark or live/flat alternation | stale ping-pong half or wrong pass history | compare frame `t` with `t-2`; an ABAB fault repeats every second frame |
| Smooth growth over seconds | unbounded drive or insufficient nonlinear loss | disable all drives; if it settles, inspect how energy enters and leaves |
| One permanent dimple, stripe, or bad texel | persistent-state corruption | reset the owning buffer before changing physics |
| Preview flashes but the field metric is calm | downstream display, auto-range, lighting, or post | measure delivered pixels as well as internal state |
| Effect survives every solver control | analytic or post-solver contribution | bypass downstream additions one at a time |
| Only one control quadrant responds | scaled-pass coordinate mismatch | derive dimensions from the real texture and capture the producing pass |

Freeze exogenous input before diagnosis: disable automatic emitters, stop pointer injection, and
reset persistent state. A solver cannot prove it settles while it is still being driven.

## Use Two Independent Measurements

An internal metric answers whether the field is moving. An external temporal probe answers
whether the pixels delivered to the viewer are flickering. Neither substitutes for the other.

For a wave state with height `h` and velocity `v`, absolute height is a poor activity metric: a
standing wave and still water can have the same height peak at the instant sampled. Measure a
motion envelope such as `sqrt(v*v + (h/tau)*(h/tau))`, and publish peak plus RMS. Tessera Pool
does this in `TP_Sim/measure.hlsl`.

For the visible output, use temporal second difference:

```text
step_t    = luminance_t - luminance_(t-1)
flicker_t = abs(step_t - step_(t-1))
```

A first difference is primarily a motion detector and flags a smooth traveling ripple. The
second difference remains comparatively quiet under smooth motion but reacts strongly to ABAB
alternation, discontinuities, and flashing. Publish mean, peak-held magnitude, and affected
area; the area fraction distinguishes one noisy pixel from a frame-wide fault. Keep history
read/write in one pass when possible. A separate "store current frame" pass may be scheduled
before the analysis pass and turn every difference into zero.

## Audit The Feedback Contract

Sentinel schedules Module passes by declared buffer dependencies, not by YAML order. A pass that
must follow another pass needs a real dependency or a design that does not depend on ordering.
Do not infer a runtime sequence from adjacent manifest entries.

Texture buffers ping-pong after writes. In a multi-pass substepped solver, separate named
scratch targets can expose alternating old and new halves and create exact ABAB output even when
the equation is stable. Tessera Pool's reliable contract is three passes reading and writing the
same persistent `state` texture: each runtime flip exposes the preceding substep, and the final
write is already the state for the next cook. Structured buffers have different semantics; see
`knowledge/gpu-cloth-and-xpbd.md` before applying the texture pattern to them.

The producer should publish any bookkeeping fact only it knows. If an accumulator chooses an
active half from cook parity, write that choice into the owned buffer and make the consumer read
it. Recomputing parity in a later pass can be one cook out of phase.

Persistent resources are not guaranteed to start zeroed and can survive shader reloads. Every
feedback loop needs:

- a magnitude-based finite-value guard on read;
- an explicit reset control that clears the owning state;
- bounded values or a self-healing overflow path;
- a visible metric that distinguishes valid rest from NaN or saturation.

Prefer a self-healing bound over a hard clamp. A hard-clamped field can remain pinned at a finite
ceiling forever. Above an impossible physical threshold, bleed velocity and pull the state back
toward rest; reserve a broad final clamp only for last-resort containment.

## Audit Time And Energy

For `N` substeps, continuous integration uses `frame_dt / N`. Discrete events should generally
fire once per full cook, while continuous forces apply every substep with the divided timestep.
Giving every substep the full frame interval advances the simulation `N` frames per cook,
multiplies continuous input by `N`, changes wavelengths, and removes the stability headroom that
substepping was meant to buy.

Continuous sources should add force or velocity, not overwrite displacement. Repeatedly forcing
`h` toward an imposed target acts like a rigid piston in a resonant cavity: returning waves are
re-reflected and re-driven. A spring-style drive, `v += (target - h) * stiffness * mask * dt`,
does bounded work and lets the simulated medium move through the driver.

Linear damping sets a driven steady-state amplitude; it does not guarantee a useful bound when
low loss is required for long travel. Add a nonlinear loss tied to a physically meaningful
failure measure, such as wave steepness, that costs nearly nothing in the normal regime and
rises quickly above the limit. Normalize extended source types by affected area so a line source
and point source have comparable stored amplitude semantics.

Anything added after the solver must share the solver's rest contract. Analytic chop, noise,
auto-exposure, or post effects with independent clocks can keep moving after the state settles
and impersonate a runaway. Gate these additions from a local motion envelope or give them an
explicit bypass during diagnosis.

## Treat Interaction As Fallible Input

Acquire viewport tools from raw button edges so left-button surface interaction cannot be
confused with right-button camera flight. Do not store a held boolean that can only be cleared by
a release event: release can be lost when focus changes. Use an expiring hold timer renewed by
continued input, or another lease-like state that heals when events stop.

## Verify The Repair

1. Reset the persistent field and disable all automatic sources.
2. Capture the raw simulation field, the final output, and the independent temporal probe.
3. Confirm `frame(t)` no longer alternates with `frame(t-1)` while matching `frame(t-2)`.
4. Apply one bounded impulse and watch motion peak/RMS rise and return toward zero.
5. Re-enable one continuous source and verify a bounded steady state.
6. Test lost-focus interaction and confirm the input lease expires.
7. Run `compile_check`, then `force_reload`; offline compilation alone does not update the live node.
8. Inspect live health and rolling cook rate, then capture parameter sweeps with baseline restore.
9. Save a project checkpoint only after the diagnostic controls are returned to deliberate defaults.

Keep the diagnostic node in the graph when it is cheap. A visible pass/fail instrument is more
valuable than rediscovering the same temporal fault from screenshots months later.
