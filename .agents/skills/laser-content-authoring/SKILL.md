---
name: laser-content-authoring
description: Author Module pipeline projects that drive physical lasers — click-driven ripples, vectorizable binary outputs, persistent trail buffers, multi-laser color routing, auto-spawn modes, and HStack composition for routing N laser channels through a single Spout/NDI sender to MadMapper. Use when building laser-show content, interactive content with mouse-driven point spawning, or multi-output Module projects that combine a "watch this" color channel with one or more "trace this" laser channels.
distribution: true
---

# Laser Content Authoring (Module Patterns)

Patterns for Module projects that produce content for physical laser projection. The output goes Spout/NDI → MadMapper → laser DAC. The laser controller traces white pixels as beam paths, so laser channels must be **vectorizable**: pure white-on-black, crisp edges, no gradients or anti-aliasing. The color channel beside it can be lush HDR for monitor preview / video projection.

The patterns below are self-contained and are intended to be authored as Module projects under `modules/`.

---

## Design bar: these are AV instruments, not demos

Every laser-content module ships as an **expressive instrument** for live laser shows. The artist should be able to tweak, play, sequence, and perform on it in tempo with music. Minimum standards for every new module:

- **At least 10 user-facing parameters**, not counting the laser color RGBs. `anim_speed` + laser colors alone is a first-draft sketch, not a finished module.
- **Every range of every param must stay interesting**. No dead zones. Curate min/max so the two extremes and every point between produce something expressive.
- **Three categories of knobs per module**: (1) shared trace-control vocabulary (see "Trace Control Pattern" below), (2) 3-5 module-specific shape/arrangement knobs, (3) post-FX / look modifiers.
- **Reducing traced geometry makes lasers brighter**. Always provide `trace_count` / `trace_reveal` / `flash_strobe` so the operator can concentrate beam energy into a small moving section + periodic full-shape flashes. This is the canonical "chase + flash" pattern for laser-safe high-impact visuals.
- **Dark mode by default**. Pitch-black background (not bluish, not grey). If the reference image has a white bg, invert the palette so it reads on a dark-booth wall.
- **Always in motion**. Static frames waste expressivity. Every module must have at least 2-3 continuously-moving elements even with zero user input.
- **Viewport interactivity**. Click/drag + WASD camera where it makes sense. Click ring buffers for spawn-driven modules; `_RayDirection(_Mouse.xy)` for 3D raycasts to world hit points.
- **Input fallback**. If a module declares a texture input, the procedural fallback for "unwired" state must always look good on its own. Don't assume an input is connected.

---

## Architecture: Multi-Output Module

A laser-content Module typically declares 2-4 outputs:

- **Color** — HDR water/fluid/visual rendering for screen preview and projection
- **Laser N** — single-channel binary white-on-black, one per physical laser channel

```yaml
outputs:
  - { name: "Color",   pass: color }
  - { name: "Laser 1", pass: laser1 }
  - { name: "Laser 2", pass: laser2 }
```

Each output goes to its own Spout sender in the graph. Downstream, an HStack module can pack them into one wide Spout sender (see "HStack Composition" below) for routing efficiency.

---

## Pattern: Click Ring Buffer (Mouse-Driven Spawning)

A 1-thread compute pass maintains a small ring buffer of "active points" (clicks, ripple sources, particle origins). The buffer is a structured buffer with the last slot reserved for state.

**Buffer declaration:**

```yaml
buffers:
  - name: ripple_sources
    structured: true
    element_size: 16          # 4 floats per entry
    element_count: 17         # 16 active sources + 1 state slot
```

**Common entry layout (16 bytes, reused for state):**

```hlsl
struct RippleSource {
    float2 origin;     // UV (or prev_click on state slot)
    float  t_spawn;    // spawn time (or head_index on state slot)
    float  strength;   // 1.0 (or next_random_spawn_time on state slot)
};
```

**Spawn pass (1×1 compute, output: structured buffer):**

```hlsl
RWStructuredBuffer<RippleSource> Data : register(u0);
#define RIPPLE_COUNT 16
#define STATE_SLOT   16

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    RippleSource state = Data[STATE_SLOT];
    float2 prevClick = state.origin;
    uint   headIdx   = (uint)state.t_spawn;

    // Press-edge detection — _Mouse.zw changes only on LMB-down edge.
    bool   held = _Mouse.z > 0.0;
    float2 d    = _Mouse.zw - prevClick;
    bool   newClick = held && dot(d, d) > 1e-8;

    if (newClick) {
        headIdx = (headIdx + 1u) % (uint)RIPPLE_COUNT;
        RippleSource r;
        r.origin = _Mouse.xy;
        r.t_spawn = max(_Time, 1e-4);
        r.strength = 1.0;
        Data[headIdx] = r;
    }

    // Update state for next frame.
    RippleSource s;
    s.origin = held ? _Mouse.zw : prevClick;
    s.t_spawn = (float)headIdx;
    s.strength = state.strength;
    Data[STATE_SLOT] = s;
}
```

**Why a ring buffer:** older sources naturally cycle out as the head wraps around. No per-source "is alive" bookkeeping needed — consumer passes just check `t_spawn > 0` and `_Time - t_spawn < lifetime`.

**`_Mouse` cbuffer convention** (post-Phase 34.13):
- `_Mouse.xy` — current cursor pos (normalized 0-1, frozen at last drag pos when LMB releases)
- `_Mouse.zw` — Shadertoy sign rule: positive while LMB held, negated on release
- `_Mouse.z > 0.0` is the canonical "currently held" check
- `abs(_Mouse.zw)` is the press-anchor click position (latched on press edge)

---

## Pattern: Auto-Spawn Mode (Hands-Off Random Points)

Add a `random_spawn_rate` parameter (points/second). Reuse the ring buffer's state slot to track the next-spawn-time stamp.

```hlsl
// Reuse state.strength for next_random_spawn_time
float nextRandT = state.strength;

if (random_spawn_rate > 0.0 && _Time >= nextRandT) {
    headIdx = (headIdx + 1u) % (uint)RIPPLE_COUNT;
    float seed = _Time * 1000.0 + (float)headIdx * 17.31;
    RippleSource r;
    r.origin   = float2(hash11(seed), hash11(seed + 1.1));
    r.t_spawn  = max(_Time, 1e-4);
    r.strength = 1.0;
    Data[headIdx] = r;
    nextRandT = _Time + 1.0 / max(random_spawn_rate, 0.01);
} else if (random_spawn_rate <= 0.0) {
    // Reset cooldown so re-enabling fires immediately.
    nextRandT = _Time;
}
```

`hash11` is provided by the `noise` feature library (`features: [noise]`).

---

## Pattern: Trail Accumulation Buffer

For laser content you usually want a brief trail behind moving points (a paint-stroke feel). Persistent ping-pong buffer + per-frame decay does this cleanly.

**Buffer:**

```yaml
buffers:
  - name: laser_trail
    format: R16F
    persistent: true
```

**Accumulate pass** — reads previous trail, multiplies by `trail_decay`, stamps new points:

```hlsl
RWTexture2D<float> OutputUAV : register(u0);
StructuredBuffer<RippleSource> Sources : register(t1);   // ripple_sources

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;

    // Decay previous-frame trail. trail_decay = 0 → no history (single dot).
    // trail_decay = 0.95 keeps stamps visible ~60 frames (~1s @ 60 FPS).
    float v = _Tex0.SampleLevel(LinearSampler, uv, 0).r * trail_decay;

    [loop]
    for (int i = 0; i < 16; ++i) {
        RippleSource r = Sources[i];
        if (r.t_spawn <= 0.0) continue;
        float age = _Time - r.t_spawn;
        if (age < 0.0 || age > 0.25) continue;   // brief stamp window

        float2 d = uv - r.origin;
        d.x *= aspect;
        if (length(d) < dot_radius) v = max(v, 1.0);
    }
    OutputUAV[pixel] = v;
}
```

**Display pass** — read trail and either pass through grayscale or hard-threshold for crisp binary edges:

```hlsl
float trail = _Tex0.SampleLevel(LinearSampler, uv, 0).r;
float v = (trail_threshold <= 0.0)
    ? saturate(trail)                     // grayscale falloff (nice on screen)
    : (trail > trail_threshold ? 1.0 : 0.0);  // crisp binary (vectorizer-friendly)
```

Two parameters control the look:
- `trail_decay` (0.0-0.995) — how long stamps persist
- `trail_threshold` (0.0-1.0) — 0 = grayscale, >0 = hard edge cutoff

---

## Pattern: Multi-Laser Color Tinting

Two near-identical display passes that share the trail buffer, each tinting with its own color params.

**Manifest:**

```yaml
parameters:
  - { name: laser1_r, type: float, min: 0, max: 1, default: 1.0, group: "Laser 1" }
  - { name: laser1_g, type: float, min: 0, max: 1, default: 0.0, group: "Laser 1" }
  - { name: laser1_b, type: float, min: 0, max: 1, default: 0.0, group: "Laser 1" }
  - { name: laser2_r, type: float, min: 0, max: 1, default: 0.0, group: "Laser 2" }
  - { name: laser2_g, type: float, min: 0, max: 1, default: 1.0, group: "Laser 2" }
  - { name: laser2_b, type: float, min: 0, max: 1, default: 1.0, group: "Laser 2" }

passes:
  - { name: laser1, shader: laser1.hlsl, target: cs_5_0, inputs: [{ slot: 0, source: "buffer:laser_trail" }] }
  - { name: laser2, shader: laser2.hlsl, target: cs_5_0, inputs: [{ slot: 0, source: "buffer:laser_trail" }] }

outputs:
  - { name: "Laser 1", pass: laser1 }
  - { name: "Laser 2", pass: laser2 }
```

**laser1.hlsl** (laser2.hlsl is the same with `laser2_*` params):

```hlsl
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float trail = _Tex0.SampleLevel(LinearSampler, uv, 0).r;
    float v = (trail_threshold <= 0.0) ? saturate(trail)
                                       : (trail > trail_threshold ? 1.0 : 0.0);

    float3 col = float3(laser1_r, laser1_g, laser1_b) * v;
    OutputUAV[pixel] = float4(col, 1.0);
}
```

Why two near-identical files instead of one parameterized pass: Module passes share a single cbuffer, so per-pass param overrides aren't possible. Splitting points between lasers (e.g., even/odd ripple indices) is also viable — drive that off the source's index parity in the accumulate pass.

---

## Pattern: HStack Composition (TouchDesigner Layout TOP equivalent)

For routing N laser channels through a single physical Spout sender (so MadMapper only needs one input zone instead of N), build a thin Module that takes N video inputs and packs them horizontally into a wide output.

**`hstack_3` project — manifest:**

```yaml
name: "HStack 3"
mode: generator
resolution: [5760, 1080]   # 1920 * 3

inputs:
  - { name: "A", slot: 0 }
  - { name: "B", slot: 1 }
  - { name: "C", slot: 2 }

passes:
  - name: hstack
    shader: hstack.hlsl
    target: cs_5_0
    inputs:
      - { slot: 0, source: "input:0" }
      - { slot: 1, source: "input:1" }
      - { slot: 2, source: "input:2" }

outputs:
  - { name: "Out", pass: hstack }
```

**`hstack.hlsl`:**

```hlsl
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float sliceW = _Resolution.x / 3.0;
    int   slice  = clamp((int)floor((float)pixel.x / sliceW), 0, 2);
    float localX = (float)pixel.x - (float)slice * sliceW;
    float2 uv    = float2((localX + 0.5) / sliceW, ((float)pixel.y + 0.5) / _Resolution.y);

    float4 col;
    if (slice == 0)      col = _Tex0.SampleLevel(LinearSampler, uv, 0);
    else if (slice == 1) col = _Tex1.SampleLevel(LinearSampler, uv, 0);
    else                 col = _Tex2.SampleLevel(LinearSampler, uv, 0);

    OutputUAV[pixel] = col;
}
```

Wire all your laser-content module's outputs (Color + Laser 1 + Laser 2) into HStack's three inputs, then point HStack's single Out at one Spout sender. MadMapper receives a 5760×1080 stream and slices it into three 1920-wide zones — left = video preview, middle = laser 1, right = laser 2.

**Why this pattern beats N separate Spout senders:** one sender is one DX11 shared texture; three senders are three. Less driver overhead, less bandwidth, simpler routing config.

**Future extension:** swap HStack for a "switcher" Module that crossfades between multiple laser-content modules, all at once — one downstream Spout sender, but the upstream content can change live without re-wiring MadMapper.

---

## Authoring Workflow (Avoid Hot-Reload Race)

When building a Module via tool calls in sequence:

1. Create folder `modules/<name>/`
2. **Write all `.hlsl` shader files first.**
3. **Write `manifest.yaml` last.**
4. Now create the pipeline via MCP — first compile sees a complete project.

If you save the manifest before all shader files exist, the file-watch hot-reload fires and async compile fails with `Cannot open shader: <path>`. The pipeline stays stuck until the next file save retries.

For LIVE iteration on an already-loaded module, the order doesn't matter — every change triggers a fresh reload. The race only bites the initial save.

---

## Param Conventions for Laser Content

Suggested parameter groups (match `laser_ripples` reference project):

- **Spawn**: `random_spawn_rate` (0-20, default 0)
- **Laser shared**: `dot_radius`, `trail_decay`, `trail_threshold`
- **Laser N color**: `laserN_r`, `laserN_g`, `laserN_b` (defaults: 1,0,0 / 0,1,1 / 1,1,0 / etc.)
- **Visual**: ripple frequency, speed, lifetime, falloff, caustic mix, specular, water tint RGB

All laser-output passes that produce colors should write `OutputUAV[pixel] = float4(col, 1.0)` — alpha = 1.0 keeps the output visible in downstream ImGui previews and sinks.

---

## Pattern: Shared Trace-Control Vocabulary

Every finished laser module should expose the same 8-knob "trace control" surface so the operator has a consistent performative vocabulary across the whole module set. Keep the shared trace helpers in a project-local `_shared/trace_utils.hlsli` and include that header from each related Module.

### Shared params (always present in the manifest)

| Param | Range | Default | Meaning |
|---|---|---|---|
| `trace_reveal` | 0..1 | 1.0 | Progressive build-up. 0 = nothing drawn, 1 = everything |
| `trace_count` | -1..32 | -1 | Window of elements visible at once. -1 = all |
| `trace_mode` | 0..5 | 0 | Order: sequential / scan / radial / random / reverse / breath |
| `trace_speed` | 0..8 | 1.0 | Chase loop speed multiplier |
| `trace_cycle` | 0.05..10 | 2.0 | Full cycle period (seconds) |
| `flash_strobe` | 0..1 | 0.0 | Full-shape flash brightness mix |
| `flash_rate` | 0..10 | 2.0 | Flashes per second |
| `flash_width` | 0..0.5 | 0.1 | Duty cycle of each flash |

All eight params must be declared as `type: float` in the manifest (including `trace_count` and `trace_mode` despite being integer-valued). The ShaderProject cbuffer writer stores every param value as a float in the cbuffer slot, but HLSL reads slots declared as `int` with bit-level reinterpretation — so `type: int` in the manifest gives garbage values in the shader. Use float + threshold comparisons everywhere. The canonical snippet lives inline in each module's `manifest.yaml`:

```yaml
parameters:
  - { name: trace_reveal,  display: "Reveal",       type: float, min: 0.0,  max: 1.0,  default: 1.0, group: "Trace" }
  - { name: trace_count,   display: "Count",        type: float, min: -1.0, max: 32.0, default: -1.0, group: "Trace" }
  - { name: trace_mode,    display: "Mode",         type: float, min: 0.0,  max: 5.0,  default: 0.0, group: "Trace" }
  - { name: trace_speed,   display: "Speed",        type: float, min: 0.0,  max: 8.0,  default: 1.0, group: "Trace" }
  - { name: trace_cycle,   display: "Cycle (s)",    type: float, min: 0.05, max: 10.0, default: 2.0, group: "Trace" }
  - { name: flash_strobe,  display: "Flash Strobe", type: float, min: 0.0,  max: 1.0,  default: 0.0, group: "Flash" }
  - { name: flash_rate,    display: "Flash Rate",   type: float, min: 0.0,  max: 10.0, default: 2.0, group: "Flash" }
  - { name: flash_width,   display: "Flash Width",  type: float, min: 0.0,  max: 0.5,  default: 0.1, group: "Flash" }
```

### HLSL API

```hlsl
#include "../_shared/trace_utils.hlsli"

// Per-element intensity (0..1), including flash contribution. Use this as a
// brightness multiplier on every discrete element your module renders.
float elementIntensity(int idx, int total, float time);

// Rank-aware variant for modules that have a natural spatial rank (distance
// from centre, bin index, path length, etc.) instead of a flat element index.
// Pass rank in [0,1]; `total` is used for window-width math.
float elementIntensityRank(float rank, int total, float time);

// Convenience: true if this element is currently visible at all.
bool shouldTrace(int idx, int total, float time);

// 0..1 global flash pulse; modules can multiply output by (1 + flashMask * flash_strobe * 2).
float flashMask(float time);
```

Modules with per-pixel procedural geometry (quadtree cells, voronoi cells, radial elements without a discrete idx) use the `elementIntensityRank` variant. Derive a mode-aware `cellRank(spatialPos)` helper in the module shader that mirrors the vocabulary:

```hlsl
float cellRank(float2 cellCenter) {
    if (trace_mode < 0.5)      return saturate((cellCenter.x + cellCenter.y) * 0.5);        // seq: diag sweep
    else if (trace_mode < 1.5) return saturate(cellCenter.x);                               // scan: left→right
    else if (trace_mode < 2.5) return saturate(length(cellCenter - 0.5) * 1.4142);          // radial
    else if (trace_mode < 3.5) return hash21(cellCenter * 13.371 + 0.5);                    // random
    else if (trace_mode < 4.5) return saturate(1.0 - (cellCenter.x + cellCenter.y) * 0.5);  // reverse
    else                       return saturate(length(cellCenter - 0.5) * 1.4142);          // breath
}
static const int TRACE_TOTAL_HINT = 64;  // rough element count; used for window-width math.
```

Then multiply the module's output brightness by `elementIntensityRank(cellRank(pos), TRACE_TOTAL_HINT, _Time)`. For modules with a literal element loop (bars, bolts, glyphs), use `elementIntensity(i, N, time)` directly with `i` as the discrete index.

### Canonical render loop

```hlsl
float ap = _Time * anim_speed;
for (int i = 0; i < N; i++) {
    float I = elementIntensity(i, N, ap);
    if (I < 0.001) continue;
    // ... draw element i, multiply its brightness by I
}
```

### Chase-plus-flash laser brightness pattern

Physical lasers concentrate their energy on however many pixels are "on" — fewer traced pixels = higher perceived brightness. The canonical expressive pattern is: trace a small moving section fast (e.g. `trace_count=1, trace_cycle=0.3`), then strobe the full shape occasionally (`flash_strobe=1, flash_rate=2`). This feels dramatically brighter than a static full-shape trace and gives the show a rhythmic quality. Every module should support this by default.

---

---

## Performance Notes

- Click ring buffer (16 entries) loop in a fragment-rate pass: trivial. Don't worry about it.
- Per-frame full-resolution height field with 16 ripples × 2 sine layers: ~64M sin/frame at 1080p. Fast on RTX 30+.
- 5760×1080 HStack output: 6.2M pixels per frame, single texture sample per pixel — trivial.
- Trail buffer: a single SampleLevel per pixel + the ring loop. Use R16F format unless you need color.
- Splitting normal-derivation into a separate height pass (so the color pass only does 5 samples per pixel instead of recomputing height 5×) is the standard win when ripple-source counts get into the dozens.

---

## Pattern: 3D Camera Fly-Through (laser_cube_chaser, laser_wavefield)

Add `features: [camera]` to the manifest — WASD + right-click drag fly-through works with zero additional code. The feature auto-injects cbuffer fields `_ViewMatrix`, `_ProjMatrix`, `_ViewProjMatrix`, `_InvViewProjMatrix`, `_CameraPos`, `_CameraNear`, `_CameraFar`, `_CameraFOV`, plus the helper `_RayDirection(uv)`. It also auto-exposes user params: `camera_pos_x/y/z`, `camera_yaw/pitch`, `camera_fov` (deg), `camera_move_speed`, `camera_look_sensitivity`, `camera_near/far`.

**Projecting a world point to screen space** (when you want compute-shader-drawn 3D wireframe geometry without hardware rasterization):

```hlsl
// Returns (screen_px, screen_py, w) — w = camera-space depth (positive = in front).
float3 project(float3 p) {
    float4 clip = mul(_ViewProjMatrix, float4(p, 1.0));
    float w = clip.w;
    if (w <= 1e-4) return float3(-1e6, -1e6, -1.0);  // behind camera sentinel
    float2 ndc = clip.xy / w;
    float2 scr = (ndc * float2(0.5, -0.5) + 0.5) * _Resolution.xy;
    return float3(scr, w);
}
```

`laser_cube_chaser` uses this for 8 cubes × 12 edges × N chaser beads per edge, all per-pixel in a single compute dispatch, at 59 FPS on RTX 5090.

**Inverse projection (screen UV → world ray)** via `_RayDirection(uv)`. Standard ray-plane intersection with y=0 ground:

```hlsl
float3 ro = _CameraPos;
float3 rd = _RayDirection(uv);
if (rd.y >= -1e-4) { /* sky, discard or gradient */ }
else {
    float t = -ro.y / rd.y;
    float3 hit = ro + t * rd;
    // hit.xz is world XZ on the ground
}
```

For click-to-world (spawn passes), pass `_Mouse.xy` as the UV.

---

## Pattern: Heightfield Raymarching (laser_wavefield)

For a 3D generative landscape with displaced ripples, raymarch an implicit heightfield. Use the same `sceneH` in every pass (color, laser1, laser2, spawn) so the hit point is consistent.

```hlsl
float terrainBase(float2 xz) {
    float2 p = xz * landscape_scale + float2(_Time * landscape_drift, _Time * landscape_drift * 0.5);
    int oct = (int)clamp(floor(landscape_octaves + 0.5), 1.0, 6.0);
    return fbm2D(p, oct) * landscape_amp - 0.35 * landscape_amp;
}

// Pulses: oscillating Y displacement from expanding ring fronts
void sampleRipples(float2 xz, out float heightAdd, out float ringBright) {
    // iterate _Pulses, sum cos(dR * freq) * envelope * decay * strength
}

float sceneH(float2 xz) {
    float add, rb; sampleRipples(xz, add, rb);
    return terrainBase(xz) + add;
}
```

**Iterative secant raymarch** with adaptive step size:

```hlsl
float3 ro = _CameraPos;
float3 rd = _RayDirection(uv);
float t = 0.1;
float prevT = 0.0;
float prevDiff = ro.y - sceneH(ro.xz);
float hitT = -1.0;
[loop]
for (int i = 0; i < 96; i++) {
    float step_ = max(0.15, abs(prevDiff) * 0.35);  // smaller step near surface
    t = prevT + step_;
    if (t > 80.0) break;
    float3 p = ro + rd * t;
    float h = sceneH(p.xz);
    float diff = p.y - h;
    if (prevDiff > 0.0 && diff <= 0.0) {
        float f = prevDiff / (prevDiff - diff);
        hitT = prevT + f * (t - prevT);  // secant interpolate the crossing
        break;
    }
    prevDiff = diff;
    prevT = t;
}
```

96 steps at 1920×1080: `laser_wavefield` runs color + laser1 + laser2 all at 57 FPS on a 5090.

---

## Pattern: 3-Output Module + Dedicated HStack

Each laser-content installation module has three outputs at 1920×1080, pin-named **exactly** `Color`, `Laser 1`, `Laser 2` (with the space).

Each module gets its own dedicated `HStack 3` pipeline at **5760×1080** wired:
- module.Color → hstack.`Video Input` (A, slot 0)
- module.Laser 1 → hstack.`B` (slot 1)
- module.Laser 2 → hstack.`C` (slot 2)

Multiple modules + HStacks can render simultaneously. A downstream switcher/mux module routes one HStack's Out at a time into the single `FullOut` Spout sender — MadMapper sees one 5760×1080 stream and slices it into three 1920-wide zones.

HStack resolution cap lifted to 16384 in commit `59e9483`. If you see HStack silently clamping to 3840, the source tree wasn't rebuilt — check `ShaderProjectPipeline.cpp` lines ~1672 and ~1793.

---

## Pattern: Shared Post-FX Recipe

All laser-content color passes apply the same post-fx stack (bottom of `color.hlsl`, after composition). Never apply to laser outputs — those stay binary/crisp on black.

```hlsl
// Bloom (cheap additive highlight boost)
if (fx_bloom > 0.01) {
    float lum = max(col.r, max(col.g, col.b));
    col += col * saturate(lum - 0.4) * fx_bloom * 0.7;
}
// Chromatic aberration (radial bias)
if (fx_aberration > 0.01) {
    float2 dir = uv - 0.5;
    col.r += length(dir) * fx_aberration * 0.002;
    col.b += length(dir) * fx_aberration * 0.002;
    col.g -= length(dir) * fx_aberration * 0.001;
}
// Scanlines (optional, for HUD feel)
if (fx_scanlines > 0.01) {
    float sl = 0.5 + 0.5 * sin(px.y * 3.1416);
    col *= lerp(1.0, sl, fx_scanlines);
}
// Vignette
if (fx_vignette > 0.01) {
    float vd = length((uv - 0.5) * float2(1.3, 0.8));
    col *= 1.0 - smoothstep(0.55, 0.95, vd) * fx_vignette;
}
// Film grain
if (fx_grain > 0.01) {
    float g = hash21(px + floor(_Time * 60.0));
    col += (g - 0.5) * fx_grain;
}
```

Default param group `"Post FX"` with typical values: `fx_grain` (0-0.3, default 0.04), `fx_aberration` (0-20, default 3), `fx_scanlines` (0-1, default 0.15), `fx_vignette` (0-1, default 0.5), `fx_bloom` (0-3, default 1.2).

---

## Gotchas

- **`hash11` / `hash21` / `fbm2D` / `voronoi2D` / `sdTorus` are auto-injected by feature libraries.** Redeclaring them locally gives `error X3003: redefinition`. If copying helpers from a `laser_ripples`-era shader, strip the local `hash11` definition.
- **`line` is an HLSL reserved keyword** (also `sample`, `texture`, `point`, `linear`, `register`, `half`). `float line = ...` fails with `error X3000: syntax error: unexpected token 'line'`. Rename to `ln`.
- **Re-setting `project_dir` to the same path doesn't always reload** after rapid manifest saves. Workaround: set to `""` first, then back to the path. Two separate `set` calls.
- **MediaPipe Face Depth is not a binary mask.** It's a per-triangle depth rasterization with hole-fill + alpha blur. Edge detection on it produces internal gradient edges everywhere. For face-outline lasers, trace the FACE_OVAL landmark polyline (36 points) directly instead.
