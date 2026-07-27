# Procedural Building Camera Contract

The architectural renderer uses Sentinel's native Module camera as its only
camera owner.

The workspace-wide authoritative version of this rule is
`knowledge/internal-camera-template.md`. Internal camera ownership is the
mandatory default for authored 3D; an external camera is reserved for multiple
separate 3D renderer nodes that genuinely require one synchronized viewpoint or
show-level switching.

## Manifest

```yaml
features: [camera, noise]
viewport:
  hint: "Fly camera: RMB look, WASD move, wheel adjusts speed"
  interactions: [camera]
```

Do not add an authored `cam_mode`, hero view, orbit parameters, target
parameters, or a second ray-construction path. Keep `camera_ref` empty. Multiple
passes inside this Module do not justify an external Camera node. Do not expose
camera parameters on the Scene Group.

The saved native `camera_mode` must be `0` (`Fly`). Orbit remains a host camera
navigation capability, not a renderer-authored look mode.

## Ray construction

Use the injected `_InvViewProjMatrix` and `_CameraPos` for every frame, with the
DirectX Y flip:

```hlsl
float2 clip = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
float4 nearW = mul(_InvViewProjMatrix, float4(clip, 0.0, 1.0));
float4 farW  = mul(_InvViewProjMatrix, float4(clip, 1.0, 1.0));
nearW /= nearW.w;
farW /= farW.w;
float3 ro = _CameraPos;
float3 rd = normalize(farW.xyz - nearW.xyz);
```

## Published color and depth

The ray marcher remains linear `RGBA16F` internally. The public color pass uses
an ACES-like tone map plus sRGB encoding and publishes `RGBA8`; that is the only
texture connected to StreamDiff Video and Style. Native Depth is a separate
0..1 grayscale `RGBA8` output connected only to StreamDiff Control Image.
