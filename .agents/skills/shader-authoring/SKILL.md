---
name: shader-authoring
description: Write HLSL .fx shaders for Sentinel (Notch-compatible). Use when creating or editing .fx shaders, debugging shader compile errors, working with the HLSL parameter convention, or ensuring Notch compatibility.
distribution: true
---

# HLSL Shader Authoring

Write `.fx` shaders in Notch HLSL format, hot-reload via MCP:
```
sentinel_state action="set" path="/sentinel/pipelines/hlslshader_0/parameters/shader_file" value="path/to/shader.fx"
```

## HLSL Shader Compiler (`ShaderCompiler.cpp`)

- **Strips** the VS function, sampler, technique, and state blocks from .fx source
- **Generates** `SamplerState LinearClampSampler : register(s0)` (bilinear, clamp) and `InputBuffer : register(t0)`
- **Built-in VS** provides UV (0,0)=top-left, (1,1)=bottom-right via `SV_VertexID`
- Use `InputBuffer.SampleLevel(LinearClampSampler, uv, 0)` for UV-based sampling with distortion
- Use `InputBuffer.Load(uint3(In.Position.xy, 0))` for pixel-coordinate sampling
- Custom `float` params auto-exposed as sliders with range -10 to 10, default 0
- **Parameter convention**: always map so -5 = off/zero, 0 = moderate default, 10 = max
  - Standard: `max(0.0, Param + 5.0) * scale` (scale chosen so 5*scale = desired default)
  - Full-at-zero (colors): `max(0.0, Param + 5.0) * 0.2` -> 0 at -5, 1.0 at 0, 3.0 at 10
  - Inverted (darkness): `saturate(1.0 - max(0.0, Param + 5.0) * scale)`
- `point` and `line` are reserved HLSL keywords - don't use as variable names
- **Always initialize variables**: `float hue;` causes compile errors - must use `float hue = 0.0;`
- **`atan2` seam at +/-PI**: Using `sin(angle * N)` for distortion creates a visible tear on the left edge. Use cartesian-based waves (`sin(p.x * N + p.y * M)`) instead
- **Shader file paths must be absolute** when loading via MCP
- Check compile errors via `sentinel_pipeline action="info"` -> `stats.statusMessage`
- **`BlendAmount` is a built-in 0-1 value** -- do NOT apply the custom parameter mapping formula to it. Use directly: `lerp(original, color, BlendAmount)`
- **Never `saturate()` distorted UVs** -- creates hard clamping seams. Use `softDistortUV()` with `tanh`-based soft limiting: `headroom * tanh(offset / max(headroom, 0.001))`. See `water_ripple_multi.fx`.
- **Central difference `eps` must be large enough** -- `eps = 0.002` causes gradient spikes. Use `eps >= 0.005` for `fbm`-based height fields.

## Notch Compatibility (IMPORTANT)

Shaders must work in BOTH Sentinel and Notch. Every .fx shader must include the full Notch boilerplate -- Sentinel's compiler strips it automatically:

1. **`sampler LinearClampSampler { Filter=...; AddressU=Clamp; ... };`** -- Effects-style (NOT `SamplerState`)
2. **`VS_Fullscreen()` function** -- Standard fullscreen vertex shader
3. **`BlendState`, `DepthStencilState`, `RasterizerState` blocks** -- Render state declarations
4. **Full `technique11` block** -- Use `vs_4_0`/`ps_4_0` (NOT `vs_5_0`/`ps_5_0`), include state setup
5. **Blend with `InputBuffer.Load`** -- `lerp(original, color, BlendAmount)` using `Load(uint3(In.Position.xy, 0))`

See working examples: `shaders/water_ripple.fx`, `shaders/glass_bubbles.fx`
See devlogs: `docs/devlogs/phase-misc-notch-shader-compatibility.md`, `docs/devlogs/phase-misc-shaderfx-authoring.md`
