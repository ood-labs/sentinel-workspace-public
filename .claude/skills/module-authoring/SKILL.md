---
name: module-authoring
description: Author Module pipeline projects (multi-pass YAML manifests, typed data ports, compute shaders, 3D rendering). Use when creating or editing Module manifests, working with data_inputs/data_outputs, debugging Module shader compilation, porting Shadertoy effects to Module format, or working with structured buffer I/O.
distribution: true
---

# Module Pipeline Authoring

The "Module" pipeline type (registered as `"module"`) supports multi-pass YAML-driven shader projects with typed structured buffer I/O. Previously called "ShaderProject" — that name is a backward-compat alias only.

## Where to put new modules

New module projects go under **`./modules/<name>/`** in the agent workspace (your cwd when launched from Sentinel's File > Launch Agent). The workspace `modules/` folder is created automatically.

```
./modules/my_module/
├── manifest.yaml
├── pass1.hlsl
└── pass2.hlsl
```

After writing the files, point a Module pipeline at the directory:
```
sentinel_pipeline action="create" type="module" name="my_module" project_dir="<absolute-path-to>/modules/my_module"
```

`project_dir` requires an absolute path. Resolve `./modules/<name>/` against your cwd, or call `sentinel_app action="workspace"` to get the workspace dir as an absolute path.

For data-driven visuals, prefer `sentinel_module action="scaffold_from_ports"` after inspecting the upstream tracker. It writes the module files under the launched workspace, copies the live data schema into `data_inputs`, generates starter HLSL accessors, and uses modern controls.

## Bundling Modules with a Show Project

A saved `.sentinel` show can carry the Module folders it needs as sibling files:

```
my_show/
├── my_show.sentinel
└── modules/
    └── My_Module/
        ├── manifest.yaml
        └── render.hlsl
```

When bundling is requested, Sentinel copies referenced Module folders into
`<projectDir>/modules/<id>/`, skips generated `.sentinel/shader_cache` folders,
and saves each Module pipeline with a relative `project_dir` such as
`modules/My_Module`. The copied files stay real files on disk, so compile and
hot-reload continue to work.

Useful MCP actions:

```
sentinel_app action="save_project" path="C:/shows/my_show/my_show.sentinel" bundle_modules=true
sentinel_module action="bundle"
sentinel_module action="extract" pipeline_id="My_Module" dest_dir="C:/scratch/My_Module"
sentinel_module action="import" from_project="C:/shows/my_show/my_show.sentinel" module_id="My_Module" name="Imported Module"
```

`sentinel_module import` requires the destination project to already be saved so
Sentinel knows where its `modules/` folder lives. After creating or importing a
Module pipeline over MCP, run `sentinel_graph action="auto_layout"`.

## Architecture

- **`PinType::Data`** in the graph — cyan-colored pins, Data<->Data only (never connects to texture pins)
- **`DataPortDescriptor`** carries SRV pointer, element count, schema, generation counter
- **Zero-copy SRV routing** — producer owns the buffer, consumer receives SRV pointer via `setDataInput()`
- **Data output index space is separate from texture outputs** — `getDataOutputPorts()` returns 0-based data-only vector. The routing table computes data-relative indices by counting preceding Data pins on the source node.
- **Data INPUT slot offset** — `getInputSlots()` appends data inputs AFTER video inputs. Graph pin `slotIndex` for data inputs = `videoSlotCount + manifestDataIndex`. Both `updateConstantBuffer()` and `resolvePassInputSRV()` must compute `graphSlot = videoSlotCount + manifestSlot` to correctly index `m_dataInputs[]`. This was a critical bug — data never reached filter-mode Modules until fixed.
- **`refreshNodeInputPins()` must detect type changes** — when pin count matches but types differ (e.g., Video->Data after manifest loads in generator mode), the function updates pin types in place
- **Generator mode `getInputSlots()`** — must NOT return early when data inputs exist. The early return for "no texture inputs" was skipping the data input append loop.
- **Hot-reload is live** — save the manifest; the pipeline picks up the change in place. Param values preserved by name (new/reshaped params take manifest defaults), orphaned GPU buffers deferred-released, orphaned StateTree nodes + expression bindings pruned, graph links survive wherever a pin name still exists. Only a ping-pong buffer pixel-format change currently requires destroy+recreate.

## Manifest data_inputs/data_outputs Syntax

```yaml
data_inputs:
  - name: "Face Data"
    slot: 0
    schema:
      - { name: x, type: float }
      - { name: y, type: float }
      - { name: depth, type: float }
      - { name: confidence, type: float }

data_outputs:
  - name: "Particles"
    buffer: "particle_buffer"  # References buffers: section
    schema:
      - { name: position, type: float3 }
      - { name: velocity, type: float3 }
```

Pass inputs reference data with `source: "data:0"` (data input slot 0). The compiler generates `StructuredBuffer<T>` declarations + `_DataN_Count` cbuffer fields.

## HLSL Conventions (CRITICAL — read before writing ANY Module shader)

These are the compiler-injected names. Do NOT redeclare them or you get "redefinition" errors.

### Auto-injected globals (always available):
- `_Time` (float) — elapsed time in seconds
- `_Resolution` (float2) — output resolution `.x` `.y`
- `OutputUAV` (RWTexture2D<float4>, register u0) — write output here

### Parameters are bare names:
```hlsl
// CORRECT — parameters declared in manifest are injected as bare floats:
float val = my_parameter_name;

// WRONG — there is no _Params struct:
float val = _Params.my_parameter_name;  // COMPILE ERROR
```

### Parameter widget types (manifest `parameters:`)
Every parameter renders a typed UI control and is OSC-addressable. `flags` pick the
widget style; unknown flags warn and are ignored. All are backward compatible (a
manifest with no new keys behaves as before).

```yaml
parameters:
  - { name: amount,    type: int,     min: 1, max: 12, default: 4 }              # int slider -> HLSL int
  - { name: deck,      type: bool,    default: true, flags: button }            # toggle button -> HLSL int (0/1)
  - { name: mode,      type: enum,    default: 0, options: [Solid, Grad, Stripe], flags: button_grid }  # button grid -> HLSL int index
  - { name: center,    type: point2D, min: [-1, -1], max: [1, 1], default: [0, 0] }  # XY pad -> HLSL float2
  - { name: tint,      type: color,   default: [1.0, 0.4, 0.1] }                # RGB color picker -> HLSL float3
  - { name: feedback,  type: float,   min: 0, max: 1, default: 0.5, group: "Global/Mix" }  # nested UI sub-group
```

- `point2D` is an alias of `vec2`; `vec3`/`vec4` render component sliders.
- `color` is RGB (`float3`); for RGBA use `type: vec4`.
- Compounds decompose into per-channel StateTree nodes (`tint_r/_g/_b`, `center_x/_y`),
  each independently OSC-mappable; the UI folds them into one color picker / XY pad.
- A `group: "Parent/Child"` label nests a collapsible sub-tree in the Properties panel.
- Reference module exercising every control: `shaders/projects/param_showcase/`.

### Entry point is `main`, NOT `CSMain`:
```hlsl
// CORRECT:
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) { ... }

// WRONG:
void CSMain(uint3 id : SV_DispatchThreadID) { ... }  // never called
```

### Output to `OutputUAV`, NOT `_Output`:
```hlsl
// CORRECT:
OutputUAV[pixel] = float4(col, 1.0);

// WRONG:
_Output[id.xy] = float4(col, 1.0);  // COMPILE ERROR
```

### Feature libraries inject functions — do NOT redefine:
- **`noise` feature** provides: `hash11(float)`, `hash21(float2)`, `hash31(float3)`, `noise2D`, `noise3D`, `fbm2D`, `fbm3D`
- **`sdf` feature** provides: `sdSphere`, `sdBox`, `sdRoundBox`, `sdTorus`, `sdCylinder`, `sdCapsule`, `sdPlane`, `opUnion`, `opIntersect`, `opSubtract`, `opSmoothUnion`, `opSmoothSubtract`, `opSmoothIntersect`, `opRound`, `opRepeat`, `opRepeatLimited`, `opTwist`, `CALC_NORMAL` macro
- **`camera` feature** provides: `_ViewMatrix`, `_ProjMatrix`, `_ViewProjMatrix`, `_InvViewProjMatrix`, `_CameraPos`, `_CameraNear`, `_CameraFar`, `_CameraFOV`, `_RayDirection(uv)` helper
- **`math3d` feature** provides: common 3D math utilities

If you need a function like `smax` (smooth max) that ISN'T in the built-in library, define it yourself. But check first — redefining a built-in causes instant compile failure.

### HLSL reserved words to avoid as variable names:
`line`, `sample`, `texture`, `point`, `linear`, `register`, `half`, etc. Use `ln`, `samp`, `tex`, `pt` instead.

### Minimal compute shader template:
```hlsl
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float t = _Time;

    float3 col = float3(0, 0, 0);
    // ... your rendering code using bare parameter names ...

    OutputUAV[pixel] = float4(col, 1.0);  // alpha MUST be 1.0
}
```

### Resolution-flexible authoring

Author Modules so the manifest resolution is a default target, not a hidden layout constant.

- Derive normalized coordinates from `_Resolution.xy`: `uv = ((float2)pixel + 0.5) / _Resolution.xy`.
- For physical shapes, correct for aspect ratio before distance math: `p = (uv - 0.5) * float2(_Resolution.x / _Resolution.y, 1.0)`.
- For pixel UI, text, grids, or legacy design-space art, define an explicit logical canvas and map actual pixels into it:
  ```hlsl
  static const float2 DESIGN_SIZE = float2(2048.0, 768.0);
  float2 designPx = ((float2)pixel + 0.5) * DESIGN_SIZE / max(_Resolution.xy, float2(1.0, 1.0));
  ```
- Do not hard-code output bounds like `if (pixel.x >= 896 || pixel.y >= 336) return;`; compare against `_Resolution` for dispatch bounds and use logical-canvas checks only after remapping.
- Do not hard-code panel splits such as `448`, `896`, `1024`, or `384` unless the Module is explicitly a processor/atlas mapper. Prefer named constants (`PANEL_W`, `ROW_H`, `DESIGN_SIZE`) so a future resolution pass has one obvious contract to update.
- For multi-pass Modules, every pass, buffer, and history ring must be scaled intentionally. If a structured history buffer would exceed runtime limits at the new size, split it into banks instead of quietly reducing behavior.
- When porting legacy fixed-resolution Modules, preserve the old look by mapping `_Resolution` into the old logical canvas; do not leave the old resolution in manifest/project params.

## Module Shader Gotchas

- **Always output alpha = 1.0** in color passes. The display pipeline blends with alpha — near-zero alpha makes output invisible. GPU texture capture reads raw data and ignores alpha, masking the bug.
- **GLSL `static const` with cbuffer variables = 0**: HLSL `static const` requires compile-time constants. `static const float X = 1.0 + iTime;` silently evaluates `iTime` as 0. Use `#define` for runtime-dependent expressions.
- **Shadertoy Y-flip**: GLSL UV origin is bottom-left, DX11 is top-left. Add `uv.y = -uv.y` when porting.
- **Mouse cbuffer convention**: `_Mouse.xy` = current cursor pos (normalized 0-1, frozen at last drag pos when LMB releases). `_Mouse.zw` follows the Shadertoy sign rule — positive while LMB held, negated on release. Use `_Mouse.z > 0.0` as the canonical "currently held" check; `abs(_Mouse.zw)` is the press-anchor click position. Edge case: a click exactly at viewport x=0 gives z=0 → "held" check returns false; ignore unless someone reports it.
- **Filter-mode input SRV**: main.cpp must set `inputTex.srv` (not just `.texture`) — Module reads it via `resolvePassInputSRV()`. Missing SRV = black output with no error.
- **Ping-pong: flip after each write, not end of frame**: When multiple passes write the same buffer in one frame (e.g., advect -> inject -> gradient all writing velocity), each must flip immediately so the next pass reads fresh data.
- **Manifest `min`/`max` default to 0-1**: Parameters without explicit `min`/`max` in the YAML manifest are clamped to 0.0-1.0. Always set explicit min/max for any parameter that needs a wider range.
- **MCP pipeline creation**: `"module"` is in the MCP create enum. The old `"shaderproject"` alias requires direct ZMQ IPC.
- **All Module inputs are VideoSource type**: Unlike StreamDiff (which has video/style/controlnet), Module inputs are all equivalent. `getInputSlots()` uses `InputSlotType::VideoSource` for all declared inputs — no Reference pins.
- **Generator mode + explicit inputs**: `mode: generator` with an `inputs:` section gives you both resolution controls AND external video inputs. The pipeline renders at manifest resolution, not input resolution.
- **Resolution caps**: `resolution_width` clamped to 64-16384 (previously 3840, lifted as of commit `59e9483`), `resolution_height` clamped to 64-2160. Values above the caps get silently clamped by `ShaderProjectPipeline::setParameter`. If you hit the height limit, edit `src/pipelines/shaderproject/ShaderProjectPipeline.cpp` lines ~1672 and ~1793 and rebuild.
- **Large static const arrays work fine**: Font bitmaps, node positions, baked data — all fine as `static const` in HLSL. No constant memory limit issues like CUDA `.cu` files.
- **Performance at 1920x1080**: 350 nodes + 100 line segments + 100 text fragments in a single compute pass runs 55+ FPS on RTX 5090. Per-pixel loops over ~500 elements are fine.
- **`type: int` / `enum` / `bool` bind correctly** (fixed Phase 52): these are written to the cbuffer as real ints, so HLSL reads `int`/`int`(enum index)/`int`(bool) as written. The old "always use `type: float` for selectors" workaround is retired — use `type: int` (with `min`/`max`), `type: enum` (with `options:`), and `type: bool` directly. See the Parameter widget types section above for the full set.
- **Local array init from cbuffer can fail**: `float arr[4] = { param1, param2, param3, param4 };` may produce wrong values depending on HLSL compiler optimization. **Fix**: Use getter functions instead: `float getParam(int i) { if (i==0) return param1; if (i==1) return param2; ... }`.
- **Glow falloff: use finite range, not 1/d²**: Inverse-square glow `intensity / (d*d + eps)` never reaches zero — with many glowing points, the accumulated contribution makes the entire background grey. **Fix**: `max(0, 1 - d*k)²` drops to exactly zero beyond `1/k` screen units.
- **Tone mapping + dark backgrounds**: Reinhard + gamma correction boosts very dark values (0.01 linear → 0.15 sRGB). **Fix**: Add background gradient AFTER gamma correction, directly in sRGB space: `col = toneMap(scene); col = gamma(col); col += srgb_background;`

## MCP Workflow for Module Creation

```
1. Create project folder: shaders/projects/<name>/
2. Write ALL shader files first, THEN write manifest.yaml LAST (avoids the hot-reload race below).
3. sentinel_pipeline create type=module name="Name" project_dir="path"
4. sentinel_state set path=/sentinel/pipelines/<id>/parameters/project_dir value="path"
5. Check info for compile errors — fix shader — hot-reload happens automatically (~0.5s)
6. If compile error persists after fix: re-set project_dir to force reload
7. Add/remove/rename params, passes, buffers, output slots: just save the manifest. Hot-reload handles structural changes in place — graph links survive, user-tweaked param values preserved by name. Only a ping-pong buffer's pixel-format change still requires destroy+recreate.
8. sentinel_graph auto_layout after creating new pipelines
```

**Hot-reload race when authoring via tool calls**: file-watch fires the moment `manifest.yaml` is saved, then ~30 frames later async compile tries to open every shader the manifest references. If a referenced shader hasn't been written yet, the compile fails with `Cannot open shader: <path>` and the pipeline stays in the failed state until the NEXT file save retries. **Always write all shader files before saving the manifest.** Same applies to renames — write the new files first, then update the manifest.

**Force reload**: Re-setting `project_dir` to the same path triggers `loadProject()`. With the param-merge fix, user values are preserved across this. Useful after fixing compile errors that left the pipeline stuck.

**If same-path re-set doesn't reload** (happens occasionally after rapid manifest saves with multiple new params added in sequence): set `project_dir` to `""` first, then set it back to the real path. Two separate `set` calls — the empty-set forces the pipeline to drop its current state before reloading. Reliable when the plain re-set appears to dedupe.

## Reference Projects

### Bundled Examples (in this skill folder)

Full working projects are in `examples/` alongside this SKILL.md. Read these files for concrete syntax:

**`examples/lfo_panel/`** — Control outputs + structured buffers + oscilloscope UI
- `manifest.yaml` — `buffers:`, `control_outputs:`, compute→display pipeline, `type: float` for shape selectors
- `lfo_compute.hlsl` — `RWStructuredBuffer` at u0 (NOT OutputUAV), 4 waveform shapes, float threshold comparison
- `lfo_display.hlsl` — `StructuredBuffer` at t0 for buffer input, `OutputUAV` at u0 for texture output, getter functions to avoid array init issues, oscilloscope rendering

**`examples/wave_field/`** — Ray marching + camera + multi-texture output (Color + Depth)
- `manifest.yaml` — `features: [camera]`, `outputs:` section with 2 pins, 3-pass pipeline (compute march → ps extract color → ps extract depth)
- `wave_field.hlsl` — Camera ray generation with Y-flip, `_ViewProjMatrix` projection, finite-range glows, post-gamma background, depth in alpha
- `color_out.hlsl` / `depth_out.hlsl` — Trivial ps_5_0 extract passes (`VS_OUTPUT`, `SV_TARGET0`, `_Tex0.SampleLevel`)

### Other Projects (in `shaders/projects/`)

| Project | Features | Key Patterns |
|---------|----------|-------------|
| `stardust/` | Particle sim, draw pass, depth buffer, post-processing | Compute→draw→post pipeline, `buffer:` ping-pong, vertex pulling, `source: "depth"` |
| `infinite_zoom/` | Feedback, 3 texture outputs (Color/Depth/Flow) | Ping-pong feedback buffer, `outputs:` multi-output, synthetic depth |
| `ink_drop_*/` | Fluid sim, 3 outputs (Color/Mask/Displacement) | Multi-buffer fluid simulation, display passes per output |
| `depthflow/` | Filter mode, camera, parallax | `mode: filter`, dual input (Color+Depth), ray-marched parallax |
| `sdf_scene/` | SDF feature, camera, ray marching | `features: [camera, math3d, sdf, noise]`, built-in SDF primitives |

## Quick-Start Manifest Template

```yaml
name: "My Module"
version: "1.0"
mode: generator          # generator = no input needed, renders at fixed resolution
resolution: [1920, 1080] # default output size; shader layout must still derive from _Resolution
features: [noise]        # available: noise, sdf, camera, math3d

parameters:
  - name: speed           # bare name used in HLSL
    display: "Speed"      # UI display name
    type: float
    min: 0.0              # MUST set explicitly (defaults to 0-1 range!)
    max: 10.0
    default: 1.0
    group: "Animation"    # UI grouping

passes:
  - name: render
    shader: my_shader.hlsl   # relative to project folder
    target: cs_5_0           # compute shader
    output: output           # writes to pipeline output
```

Available feature combinations: `[noise]`, `[sdf, camera, math3d, noise]`, `[camera]`, etc.

## Draw Passes (Hardware Rasterization)

`target: draw` uses the GPU's actual triangle pipeline — vertex shader + rasterizer + pixel shader + depth buffer. Uses **vertex pulling** (SV_VertexID + StructuredBuffer) — no input layouts or vertex buffers needed.

### Manifest Syntax

```yaml
passes:
  - name: geometry
    shader: mesh.hlsl
    target: draw
    vertex_count: 36          # Total vertices to draw (required)
    topology: trianglelist     # trianglelist, linelist, pointlist, linestrip, trianglestrip
    depth: true                # Enable depth testing (default: true for draw)
    depth_write: true          # Write to depth buffer (default: true for draw)
    cull: back                 # back (default for draw), front, none
    vs_entry: VSMain           # Vertex shader entry point (default: VSMain)
    ps_entry: PSMain           # Pixel shader entry point (default: PSMain)
    inputs:
      - { slot: 0, source: "buffer:vertices" }
      - { slot: 1, source: "asset:texture" }
```

### Compilation

Both VS and PS are compiled from the **same .hlsl file** with different entry points. The compiler calls D3DCompile twice. The injected fullscreen quad `VS_OUTPUT` is NOT injected for draw passes — **define your own VS_OUTPUT struct**.

### Key Draw Pass Rules

- **VS_OUTPUT is user-defined**: Must contain `float4 Position : SV_POSITION`. Add any interpolants you need (UV, Normal, Color, etc.)
- **SRVs bound to BOTH VS and PS**: Input textures/buffers are available in both shader stages
- **CBuffer bound to BOTH VS and PS**: Camera matrices, time, parameters available in vertex shader
- **Shared depth buffer**: Single D32_FLOAT depth buffer per pipeline, cleared once at frame start, shared across all draw passes
- **Depth as texture**: Use `source: "depth"` in subsequent passes to read the depth buffer as R32_FLOAT
- **Vertex pulling pattern**: Read from StructuredBuffer using `SV_VertexID` — same pattern as FullscreenQuad
- **Excess vertices**: If `vertex_count` exceeds what your shader needs, output degenerate triangles (`Position = float4(0,0,-999,1)`) for unused verts
- **Camera integration**: Add `camera` to features list — VS gets `_ViewProjMatrix`, `_ViewMatrix`, `_CameraPos` etc. via cbuffer

### Example: Procedural Cube (vertex pulling)

```hlsl
struct VS_OUTPUT {
    float4 Position : SV_POSITION;
    float3 Normal   : NORMAL;
    float3 Color    : COLOR;
};

static const float3 cubeVerts[8] = { ... };
static const uint cubeIndices[36] = { ... };

VS_OUTPUT VSMain(uint vid : SV_VertexID) {
    VS_OUTPUT o;
    float3 pos = cubeVerts[cubeIndices[vid]];
    o.Position = mul(_ViewProjMatrix, float4(pos, 1.0));
    o.Normal = ...;
    return o;
}

float4 PSMain(VS_OUTPUT In) : SV_TARGET { ... }
```

### Multi-Pass: Compute → Draw → Post-Process

All three pass types work together in one project:
1. **Compute** generates data into a structured buffer
2. **Draw** renders geometry by vertex-pulling from that buffer
3. **Pixel** post-processes the draw output (bloom, aberration, etc.)

## Dirty Flagging

Passes with `time_dependent: false` skip GPU dispatch when data inputs haven't changed. Uses generation counter comparison per data port.

```yaml
passes:
  - name: render
    shader: render.hlsl
    target: cs_5_0
    time_dependent: false    # Only re-render when data:0 generation changes
    inputs:
      - { slot: 0, source: "data:0" }
```

- Default `time_dependent: true` (safe — always executes)
- Video inputs (`source: input`) are always dirty
- `data:N` inputs dirty only when upstream generation changes
- `pass:name` inputs dirty if that pass was dirty
- Forced dirty on: first frame, recompile, RT resize, parameter change

## Camera Feature Integration

Add `camera` to features for fly camera (WASD + right-click drag in viewport):

```yaml
features: [camera]
# or combined:
features: [math3d, noise, camera]
```

Provides in cbuffer: `_ViewMatrix`, `_ProjMatrix`, `_ViewProjMatrix`, `_InvViewProjMatrix`, `_CameraPos`, `_CameraNear`, `_CameraFar`, `_CameraFOV`.

For ray-marched scenes, generate rays from camera. **Must Y-flip for DX NDC**:
```hlsl
// Screen UV → NDC (Y-flipped: top=+1, bottom=-1 for DX clip space)
float2 screenUV = ((float2)pixel + 0.5) / _Resolution.xy;
float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);

// Aspect-corrected UV for visual distance calculations (glow radii, line widths)
float aspect = _Resolution.x / _Resolution.y;
float2 uv = float2(ndc.x * aspect, ndc.y);

// Ray from camera
float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0, 1));
float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1, 1));
nearW /= nearW.w; farW /= farW.w;
float3 ro = _CameraPos;
float3 rd = normalize(farW.xyz - nearW.xyz);

// Project 3D point to same aspect-corrected UV space (for overlays)
float2 projectToScreen(float3 wp, float aspect) {
    float4 clip = mul(_ViewProjMatrix, float4(wp, 1.0));
    if (clip.w < 0.01) return float2(-999.0, -999.0);
    float2 ndcPt = clip.xy / clip.w;
    return float2(ndcPt.x * aspect, ndcPt.y);
}
```

## Control Outputs (GPU → StateTree → Expressions)

Module pipelines can compute values on the GPU and publish them as read-only floats to the StateTree. Other pipelines consume them via `ref()` expressions. Green pins in the graph, drag-to-map popup.

### Manifest Syntax

```yaml
buffers:
  - name: control_buf
    structured: true
    element_size: 16    # bytes (e.g., 4 × float = 16)
    element_count: 1

passes:
  # Compute pass writes LFO values to buffer
  - name: compute
    shader: compute.hlsl
    target: cs_5_0
    dispatch: [1, 1, 1]
    thread_group_x: 1
    thread_group_y: 1
    output: "buffer:control_buf"    # UAV at u0 = this buffer, NOT OutputUAV

  # Display pass reads buffer, renders visualization
  - name: display
    shader: display.hlsl
    target: cs_5_0
    inputs:
      - { slot: 0, source: "buffer:control_buf" }   # StructuredBuffer at t0
    # OutputUAV at u0 = display pass render target (texture)

outputs:
  - display

control_outputs:
  - name: lfo1               # StateTree key: /sentinel/pipelines/{id}/control_outputs/lfo1
    buffer: control_buf       # Must match a buffer in buffers: section
    element: 0                # Element index (0-based)
    field_offset: 0           # Byte offset within element (0 = first float)
    description: "Sine LFO"
  - name: lfo2
    buffer: control_buf
    element: 0
    field_offset: 4           # Second float
    description: "Triangle LFO"
```

### Compute Shader (writes to buffer)

When a pass targets `output: "buffer:name"`, the UAV at `register(u0)` is the structured buffer — do NOT declare `OutputUAV`. Declare `RWStructuredBuffer<T>` instead:

```hlsl
struct LFOData {
    float lfo1;
    float lfo2;
    float lfo3;
    float lfo4;
};
RWStructuredBuffer<LFOData> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    LFOData d;
    d.lfo1 = sin(_Time * speed * 6.283) * 0.5 + 0.5;
    // ... compute other values ...
    OutputBuffer[0] = d;
}
```

### Display Shader (reads from buffer)

When a pass reads `source: "buffer:name"` and the buffer is declared with `structured: true` in the manifest, the compiler skips auto-generating `Texture2D _Tex<i>`. Declare your own `StructuredBuffer<T>` at the matching register:

```hlsl
RWTexture2D<float4> OutputUAV : register(u0);  // texture output (display RT)
struct LFOData { float lfo1, lfo2, lfo3, lfo4; };
StructuredBuffer<LFOData> _LFOValues : register(t0);  // buffer input

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    LFOData vals = _LFOValues[0];
    // ... render waveform visualization using vals ...
    OutputUAV[pixel] = float4(col, 1.0);
}
```

For non-structured (texture ping-pong) buffers, the compiler auto-declares `Texture2D<float4> _Tex<i>` exactly as for `input:` slots — no manual declaration needed.

---

## Persistent Texture Buffers (Ping-Pong Feedback)

Use a `buffers:` declaration to create a texture that survives across frames. Reads see the previous frame's contents; writes go into the back texture and a flip happens immediately after the pass.

**Manifest (sequence form — map form will fail to parse):**

```yaml
buffers:
  - name: trail
    format: RGBA16F      # RGBA8, RGBA16F, RGBA32F, R32F, RG16F
    scale: 1.0           # resolution scale relative to pipeline output
    persistent: true     # default; survives across frames

passes:
  - name: accumulate
    shader: accumulate.hlsl
    inputs:
      - { slot: 0, source: "buffer:trail" }   # reads previous frame
    output: "buffer:trail"                    # writes back (back-buffer half)

  - name: display
    shader: display.hlsl
    inputs:
      - { slot: 0, source: "buffer:trail" }   # reads this frame's accumulate result
    # no output: → writes to per-pass RT, displayed via outputs:

outputs:
  - display
```

**Shader side:** the compiler auto-declares `Texture2D<float4> _Tex0` for the buffer read, so the shader is identical to one that reads a regular `input:0`. The pass output (writing to `buffer:foo`) goes through `OutputUAV` (compute) or `SV_TARGET0` (pixel shader) just like any other pass.

If you reference `buffer:foo` without declaring `foo` in `buffers:`, the runtime logs a warning and binds a null SRV (shader reads zeros).

### Consuming Control Outputs via Expressions

Control outputs publish to StateTree at `/sentinel/pipelines/{id}/control_outputs/{name}`.

Wire them to other pipeline parameters using `sentinel_expression`:

```text
sentinel_expression action="set" path="/sentinel/pipelines/module_0/parameters/surface_hue" expression="ref(\"module_1/control_outputs/lfo1\")"
```

Range mapping examples:
- `ref("module_1/control_outputs/lfo1")` — direct 0-1
- `1.47 + ref("module_1/control_outputs/lfo1") * 4.13` — map [0,1] to [1.47, 5.6]
- `3.0 - ref("module_1/control_outputs/lfo3") * 1.5` — map [0,1] to [3.0, 1.5] (inverted)

**Important**: Regular `sentinel_state set` with `=ref(...)` does NOT activate expressions. Use `sentinel_expression action="set"` so Sentinel compiles and registers the per-frame driver.

## Multi-Texture Outputs

Module supports multiple texture output pins via the `outputs:` manifest section. Each output maps to a pass's render target.

```yaml
passes:
  - name: march
    shader: raymarcher.hlsl
    target: cs_5_0
    # no output: field — writes to its own RT, read via "pass:march"

  - name: color_output
    shader: color_extract.hlsl      # ps_5_0 (default target)
    inputs:
      - { slot: 0, source: "pass:march" }

  - name: depth_output
    shader: depth_extract.hlsl
    inputs:
      - { slot: 0, source: "pass:march" }

outputs:
  - { name: "Out", pass: color_output }     # Slot 0 (primary)
  - { name: "Depth", pass: depth_output }   # Slot 1
```

**Pixel shader passes** (default target, no `target:` field) use `VS_OUTPUT` struct with `.Uv` and return `float4 : SV_TARGET0`:
```hlsl
float4 main(VS_OUTPUT In) : SV_TARGET0 {
    float3 col = _Tex0.SampleLevel(PointSampler, In.Uv, 0).rgb;
    return float4(col, 1.0);
}
```

**Pattern**: Compute pass writes color+depth to intermediate (depth in alpha), then two trivial pixel shader passes split channels for separate output pins. See `shaders/projects/infinite_zoom/` and `shaders/projects/wave_field/` for working examples.

## High Bit Depth Passes (Phase 46)

By default every pass render target is 8-bit (`B8G8R8A8_UNORM`). To run a pass at higher precision (for example to manipulate a 32-bit float UV map without quantizing it), declare a format.

```yaml
# Manifest-level default for all passes that don't set their own format.
working_format: RGBA32F      # RGBA8 | RGBA16F | RGBA32F | R32F | R16F | RG16F | RG32F | R8

passes:
  - name: remap              # inherits RGBA32F
    shader: remap.hlsl
  - name: present
    shader: present.hlsl
    format: RGBA8            # explicit per-pass override
    output: output           # final output pass — keep it 8-bit (see below)
```

Resolution order for a pass's format: pass `format:` → manifest `working_format:` → 8-bit.

**Rules:**
- **The final output pass must be 8-bit.** The pass routed to `output:` is copied into the pipeline's 8-bit output texture with `CopyResource`, which requires an exact format match. If you leave it inheriting a float `working_format`, the runtime force-matches it and logs a warning. Set `format: RGBA8` on the output pass explicitly. Run float work in intermediate passes.
- **High-bit-depth input is preserved automatically.** Feed a 16/32-bit float Spout sender into an input slot and the Module samples it at full precision. No manifest field is needed on the input side; `SourceManager` keeps the sender's format and `main.cpp` propagates it to the pipeline input.
- **Float formats are valid as compute UAVs too.** A `target: cs_5_0` pass writing to its own RT gets a UAV at the resolved format, so float compute output works the same way.
- Persistent `buffers:` already accept `format:` independently of this; passes now use the same vocabulary.

Canonical example: `examples/uv_remap_bitdepth/` (32-bit float UV in → float intermediate RT → 8-bit pattern out).

## Node-to-Node Float Output (Phase 47)

A Module can publish its output as 16/32-bit float to the **next graph node**, so an intermediary Module can crop/select a region of a float input and hand float data downstream, where a later node processes it and outputs 8-bit. Declare a root `output_format:`.

```yaml
# Node A: crop a float input and publish float to the next node.
output_format: RGBA32F       # RGBA8 (default) | RGBA16F | RGBA32F | R32F | R16F | RG16F | RG32F | R8
working_format: RGBA32F      # intermediate passes (Phase 46)

passes:
  - name: crop
    shader: crop.hlsl
    output: output             # no `format:` needed — the final pass inherits output_format
```

**Rules:**
- **`output_format:` is the single source of truth** for the node's output texture. It drives both the output-texture allocation and the final-output-pass format, so they always agree — the final pass inherits `output_format` with no per-pass `format:` and no warning. (This is why the Phase 46 "keep the output pass 8-bit" rule above only applies when `output_format` is unset / 8-bit.)
- **It is strictly opt-in.** Omit `output_format:` (or set `RGBA8`) and the node publishes 8-bit exactly as before. Only set it when a downstream node needs the float data.
- **Float auto-converts to 8-bit at the edges.** When a float node is screenshotted, captured, recorded (NVENC), or routed to an NDI output, the runtime converts to 8-bit at that boundary, so those paths are always safe. A Spout output can pass the float through. Plan for the chain to end in an 8-bit node for normal display.
- **Preview caveat.** Float values above 1.0 clamp to white in the Properties/graph preview (the preview is a UNORM view). Fine for 0..1 UV/crop content.

Canonical example: `examples/crop_select/` (float input → cropped RGBA32F output) feeding `examples/crop_present/` (reads the float, samples a fine pattern, outputs 8-bit).
