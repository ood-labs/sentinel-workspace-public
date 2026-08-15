---
name: laser-content-authoring
description: Author Module pipeline projects that drive physical lasers — vectorizable binary outputs, pixel-exact stroke and dot sizing, blanking margins, calibration sources, persistent trail buffers, click-driven spawning, multi-laser color routing, and HStack composition for routing N laser channels through a single Spout/NDI sender to MadMapper. Use when building laser-show content, calibrating real line and dot sizes, or multi-output Module projects that combine a "watch this" color channel with one or more "trace this" laser channels.
---

# Laser Content Authoring (Module Patterns)

Patterns for Module projects that produce content for physical laser projection. The output goes Spout/NDI → MadMapper → laser DAC. The laser controller traces white pixels as beam paths, so laser channels must be **vectorizable**: pure white-on-black, crisp edges, no gradients or anti-aliasing. The color channel beside it can be lush HDR for monitor preview / video projection.

The patterns below are self-contained and are intended to be authored as bundled
Module projects under `projects/<project>/modules/`.

---

## Design bar: every control must earn its slot

A laser module is an instrument, but that is an argument for controls that do
something, not for a quota of them. There is no minimum parameter count and no
mandatory knob vocabulary. Derive the controls from the piece: name the quantities
the operator actually needs to change mid-show, ship those, and cut the rest.

- **Name every control after the thing it changes.** `line_thickness_px`,
  `dot_radius_px`, `zip_time`, `outline_ms` — sizes in pixels, times in seconds or
  milliseconds. An operator dialing a laser is matching a physical result on a wall,
  so an abstract 0-1 knob is worse than a real unit.
- **Every range must stay usable.** No dead zones. Curate min/max so both extremes
  and everything between produce something you would actually run.
- **Reducing traced geometry makes lasers brighter.** A galvo concentrates its
  energy on however many pixels are lit, so a small moving section reads far brighter
  than a full static shape. This is a real physical property and worth exploiting —
  but express it however the piece calls for, and only if the piece calls for it. Do
  NOT bolt on a generic chase/strobe control surface.
- **No strobe, flash, or shutter controls unless explicitly requested.** They are
  rarely what the work needs, they crowd out the controls that matter, and a strobing
  laser is a safety question rather than a default.
- **Dark by default.** Pitch black, not bluish, not grey. Invert a light reference so
  it reads on a dark booth wall.
- **Viewport interactivity** where it earns its place. Click ring buffers for
  spawn-driven modules; `_RayDirection(_Mouse.xy)` for 3D raycasts to world hit points.
- **Input fallback.** If a module declares a texture input, the unwired procedural
  fallback must look good on its own.

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

**`_Mouse` cbuffer convention**:
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

1. Create folder `projects/<project>/modules/<name>/`
2. **Write all `.hlsl` shader files first.**
3. **Write `manifest.yaml` last.**
4. Now create the pipeline via MCP — first compile sees a complete project.

If you save the manifest before all shader files exist, the file-watch hot-reload fires and async compile fails with `Cannot open shader: <path>`. The pipeline stays stuck until the next file save retries.

For LIVE iteration on an already-loaded module, the order doesn't matter — every change triggers a fresh reload. The race only bites the initial save.

---

## Param Conventions for Laser Content

Group parameters by the thing they control, and size everything in real units.

- **Layout**: `edge_buffer_px` (blanking margin), `pattern_scale`
- **Lines**: `line_thickness_px` — the TOTAL stroke width, never a half-width
- **Dots**: `dot_radius_px`, plus whatever count/spacing the piece needs
- **Trail**: `trail_decay`, `trail_threshold`
- **Laser N color**: `laserN_r`, `laserN_g`, `laserN_b`
- **Laser output**: a `laser_output_mode` enum selecting which masks reach the DAC

All laser-output passes that produce colors should write
`OutputUAV[pixel] = float4(col, 1.0)` — alpha = 1.0 keeps the output visible in
downstream ImGui previews and sinks.

### The blanking margin is not optional

`edge_buffer_px` (8 px is a sane default at 1080p) keeps every element off the frame
edge. A galvo has to decelerate and turn around somewhere, and content that runs to
the edge gets clipped or smeared by the scanner rather than by anything visible in
the preview. Apply it first, then scale the working rect inside it.

### Sizes must be pixel-exact, which means minding parity

A calibration number is worthless if it lies. Build coverage so the binary threshold
lands on the true geometric edge:

```hlsl
// s is the signed distance to the stroke's own edge, so the 0.5 crossing sits on
// that edge for any feather. Feather then softens the preview without ever moving
// the edge the laser actually sees.
float strokeCov(float dPx, float totalWidthPx, float featherPx)
{
    float s = dPx - totalWidthPx * 0.5;
    return saturate(0.5 - s / max(featherPx, 0.001));
}
```

That is necessary but not sufficient. Pixel centres sit at integer+0.5, so a feature
centred on a pixel BOUNDARY is symmetric about it and can only ever light an EVEN
number of pixels. Ask for 5 px and both edge pixels land at exactly half-width,
coverage ties at exactly 0.5, `step(0.5, cov)` loses the tie to float rounding, and
you measure 4. Snap the centre by the parity of the extent:

```hlsl
float snapCentre(float cFrame, float extentPx)
{
    float e = max(round(extentPx), 0.0);
    return (fmod(e, 2.0) >= 1.0) ? (floor(cFrame) + 0.5) : round(cFrame);
}
```

Snapping also stops a moving dot shimmering between D and D+1 px as it drifts, which
otherwise makes a size impossible to dial in at all. Prove it by capturing the binary
output and counting lit pixels across BOTH parities — a test at only 2 and 4 px
passes while the bug is still there.

### Output naming

When a project sends both channels over Spout, the output nodes are named `Laser` and
`Projector`, with sender names `Sentinel-Laser` and `Sentinel-Projector`. MadMapper
and the DAC get patched once against those names; a per-project sender name means
re-patching every show. Only create output nodes when the user explicitly asks for
them — they are never a default finishing step.

---
## Performance Notes

- Click ring buffer (16 entries) loop in a fragment-rate pass: trivial. Don't worry about it.
- Per-frame full-resolution height field with 16 ripples × 2 sine layers: ~64M sin/frame at 1080p. Fast on RTX 30+.
- 5760×1080 HStack output: 6.2M pixels per frame, single texture sample per pixel — trivial.
- Trail buffer: a single SampleLevel per pixel + the ring loop. Use R16F format unless you need color.
- Splitting normal-derivation into a separate height pass (so the color pass only does 5 samples per pixel instead of recomputing height 5×) is the standard win when ripple-source counts get into the dozens.

---

## Pattern: 3D Camera Fly-Through

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

This scales to a few hundred projected edges per frame in a single compute dispatch
before it costs anything noticeable; measure with `sentinel_graph action=profile`
rather than assuming.

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

## Pattern: Heightfield Raymarching

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

96 steps at 1920×1080 with color plus two laser passes is comfortably real-time on
current hardware, but step count is the dominant cost — profile before raising it.

---

## Pattern: 3-Output Module + Dedicated HStack

Each laser-content installation module has three outputs at 1920×1080, pin-named **exactly** `Color`, `Laser 1`, `Laser 2` (with the space).

Each module gets its own dedicated `HStack 3` pipeline at **5760×1080** wired:
- module.Color → hstack.`Video Input` (A, slot 0)
- module.Laser 1 → hstack.`B` (slot 1)
- module.Laser 2 → hstack.`C` (slot 2)

Multiple modules + HStacks can render simultaneously. A downstream switcher/mux module routes one HStack's Out at a time into the single `FullOut` Spout sender — MadMapper sees one 5760×1080 stream and slices it into three 1920-wide zones.

If an HStack silently clamps its width, check the module's declared `resolution`
against what the node reports in `sentinel_pipeline action=info` before assuming
anything about the host build.

---

## Optional: Post-FX On The Color Channel Only

Post-fx is a per-piece decision, not a house stack. Nothing here is required, and
**every one of these defaults to 0** — a laser piece that wants grain or scanlines is
unusual, and switching them on by default buries whatever the module is actually for.
Never apply any of it to a laser output; those stay binary and crisp on black.

Bloom deserves particular suspicion while you are still building: it smears exactly
the structure you are trying to judge, so tune the renderer with it off.

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

If a piece genuinely wants these, put them in a `"Post FX"` group with ranges
`fx_grain` (0-0.3), `fx_aberration` (0-20), `fx_scanlines` (0-1), `fx_vignette`
(0-1), `fx_bloom` (0-3) — every default 0. Ship only the ones the piece uses.

---

## Gotchas

- **`hash11` / `hash21` / `fbm2D` / `voronoi2D` / `sdTorus` are auto-injected by feature libraries.** Redeclaring them locally gives `error X3003: redefinition`. If copying helpers from an older shader, strip the local `hash11` definition.
- **`line` is an HLSL reserved keyword** (also `sample`, `texture`, `point`, `linear`, `register`, `half`). `float line = ...` fails with `error X3000: syntax error: unexpected token 'line'`. Rename to `ln`.
- **Re-setting `project_dir` to the same path doesn't always reload** after rapid manifest saves. Workaround: set to `""` first, then back to the path. Two separate `set` calls.
- **MediaPipe Face Depth is not a binary mask.** It's a per-triangle depth rasterization with hole-fill + alpha blur. Edge detection on it produces internal gradient edges everywhere. For face-outline lasers, trace the FACE_OVAL landmark polyline (36 points) directly instead.
- **`type: int`, `type: enum`, and `type: bool` all work.** Older guidance here claimed
  integer-typed manifest params arrive as garbage through bit reinterpretation and that
  everything had to be declared `float`. That is not true on current builds — `VT_LaserGrid`
  and `VT_LaserTest` both ship `int`, `enum` (read in HLSL as `mode == 1` / `>= 2`), and
  `bool` params that behave correctly. Use the type that matches the quantity.
- **`compile_check` is offline.** It validates the files on disk and tells you nothing
  about the running node. After editing a shader, `force_reload` the live pipeline before
  capturing or measuring anything, or you will be grading the previous build.

---

## Reference implementations

Real, inspectable modules in `projects/pulse_vitrine/modules/`. Read them rather than
copying them — they solve their own project's problem.

- **`VT_LaserTest`** — the calibration source. Reference line, rotating polygon, and
  moving dots, each independently switchable, all sized in exact pixels with the parity
  snap above. This is where line and dot sizes get dialed in before a show. Ships
  narrow-scoped presets: sizes and view isolation saved separately.
- **`VT_LaserGrid`** — alignment grid with the `render` → `video` + `laser` three-pass
  split, where `render` writes channel-separated masks (R = lines, G = dots) and the
  laser pass picks channels via a `laser_output_mode` enum and hard-thresholds at 0.5.
- **`VT_Laser`** — the show-side lane: a beat-triggered zip point travelling a path,
  path hold, and a snare outline flash, with every control named for what it does
  (`zip_time`, `tail_frac`, `outline_ms`) and an explicit on/off per lane.
