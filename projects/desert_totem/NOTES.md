# desert_totem — example show

A surrealist Dada assemblage (a totem of primitive painted solids on a plank in a desert),
built as **real-time procedural 3D** and pushed into a deep **domain-warp** system. Loads
`desert_totem.sentinel` (self-contained: bundled modules + `_shared/sdf`).

The bundled shaders demonstrate the project's domain-distortion warp toolkit directly.

## The graph
```
dada_control ─┐  (master macros: melt/sag/spread/explode → control outputs)
signal ───────┤  (LFO bus)
              ↓  ref() expressions
dada_layout ──┐  (compute → StructuredBuffer<DadaPart>: the totem, ~33 records)
dada_scatter ─┤→ dada_render ──▶ post ──▶ out
              │  (compute → DadaPart: scattered accent field)
```
Everything is SDF math — no meshes. The arrangement is data (`DadaPart` records); the whole
scene is one distance field, so a domain warp melts/twists/shatters it all coherently.
`dada_layout`/`dada_scatter` node previews show a **front-view layout map** of what they author.

## Camera
`dada_render → Camera Mode`: **Fly** (WASD + right-drag) or **Orbit** (deterministic, framed).
Orbit ≈ 87° is the frontal hero. Opens on a moderate, stable warp preset (melt 0.12 + twist +
painterly).

## Warp presets to try (in `dada_render`, groups Warp 1/2/3 + Deform + Surface)
The 3 warp slots each have 7 modes (Flow/Ripple/Turbulent/Fractal · Steps/Boxes/Shatter),
their own freq/speed/orientation/offset, summed under **Melt (Master)**.

- **Dalí melt** — Melt 0.25, Warp 1 = Flow amt 0.6. Slow oozing liquid.
- **Cubist glitch** — Warp 1 = Boxes amt 0.7, Warp 2 = Shatter amt 0.5. Blocky/datamosh.
- **Multi-layer** — Warp 1 Flow + Warp 2 Ripple (yaw 1.57) + Warp 3 Fractal (pitch 1.57),
  each amt ~0.4. Rich multi-directional warp.
- **Deform** — try Twist, Swirl, Bend, or Mirror (Radial, count 3–6) for a kaleidoscope.
- **Surface** — Hue Shift rotates the whole palette up the tower; Facet gives low-poly.

## ⚠️ Performance note
Heavy warp on this many-primitive raymarch can exceed the GPU watchdog (TDR) — the app has
crashed at high melt on an RTX 5090. It ships at 760×1140 with a Lipschitz under-step for
headroom. If you crank many distortions to max at once, drop resolution / march distance, or
back off Melt.
