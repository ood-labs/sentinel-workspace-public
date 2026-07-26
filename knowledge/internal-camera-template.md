# Internal Camera Template for Authored 3D

This is the mandatory default camera contract for authored 3D Modules in Sentinel. Read and apply it before writing any ray-marched, rasterized, procedural-geometry, depth-producing, or otherwise camera-dependent 3D renderer.

## Non-negotiable default

A normal 3D Module owns and uses Sentinel's native internal camera. Do not create a separate `camera` or `camswitch` node, do not set `camera_ref`, and do not invent a shader-local orbit, hero view, target rig, or alternate camera equation.

Use the internal camera for:

- one 3D renderer;
- multiple 3D passes inside the same Module;
- a 3D renderer followed by 2D post-processing;
- color, depth, normals, masks, picking, and overlays produced by the same renderer;
- a renderer whose viewpoint only needs to be manipulated in its own preview.

The fact that a Module contains several passes does not justify an external camera. All passes in that Module already receive the same injected internal camera state.

## Required manifest contract

Declare the native camera feature and viewport interaction:

```yaml
features: [camera]

viewport:
  hint: "Fly camera: RMB look, WASD move, wheel adjusts speed"
  interactions: [camera]
```

Combine `camera` with other features when needed:

```yaml
features: [camera, math3d, sdf, noise]
```

Keep `camera_ref` empty. Save the native `camera_mode` as `0` (`Fly`) unless the project explicitly demonstrates another host-owned navigation mode. Camera parameters belong to the renderer's own Properties and preview; never expose binding, mode, position, orbit, target, FOV, near/far, or other camera rows on a Scene Group or authored top-level performance interface.

## Required shader integration

The `camera` feature injects `_ViewMatrix`, `_ProjMatrix`, `_ViewProjMatrix`, `_InvViewProjMatrix`, `_CameraPos`, `_CameraNear`, `_CameraFar`, `_CameraFOV`, and `_RayDirection(uv)`.

Ray-marched and compute renderers must construct rays from the injected internal camera with the DirectX Y flip:

```hlsl
float2 screenUV = ((float2)pixel + 0.5) / _Resolution.xy;
float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);

float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
nearW /= nearW.w;
farW /= farW.w;

float3 ro = _CameraPos;
float3 rd = normalize(farW.xyz - nearW.xyz);
```

Draw passes must transform geometry with the injected `_ViewProjMatrix`:

```hlsl
output.Position = mul(_ViewProjMatrix, float4(worldPosition, 1.0));
```

Every camera-dependent pass must use the same injected matrices. Do not keep a parallel hard-coded `ro`/`rd`, animate an authored orbit with `_Time`, or calculate projection from unrelated position, yaw, pitch, target, or FOV parameters.

Camera-aligned depth, normals, picking, and screen overlays must derive from the same internal camera state as color. A later overlay appearing in the right place does not prove that the underlying 3D pass uses the correct camera.

## External-camera exception

Create an explicit `camera` or `camswitch` only when at least two separate camera-capable 3D renderer nodes must share one synchronized viewpoint, or when the show explicitly requires camera cuts or blends across those renderers.

The following do not justify an external camera:

- several passes inside one Module;
- one 3D renderer plus post-processing;
- convenience, habit, or uncertainty about internal-camera integration;
- a single renderer that could be operated from its own preview;
- exposing camera movement on a Scene Group.

Before creating an external camera, state which separate renderer nodes require the shared rig and why independent internal cameras cannot satisfy the composition. Bind those renderers through `camera_ref` or the documented Scene Group mechanism, keep exactly one owner, and remember that their local camera rows become inactive while bound.

## Required proof

A 3D Module is not complete merely because it renders an image. Before continuing downstream:

1. Confirm the manifest declares `features: [camera]` and `viewport.interactions: [camera]`.
2. Confirm `camera_ref` is empty for the normal internal-camera case.
3. Open the renderer preview and operate the native camera through real viewport interaction.
4. Capture visibly different viewpoints and confirm geometry, depth, normals, picking, and overlays remain aligned.
5. Confirm no shader-local camera equation or external camera node is silently controlling the result.
6. Save a useful internal-camera pose with Fly as the default.

If the preview does not respond correctly to the internal camera, stop and fix the renderer before adding downstream nodes. A StateTree write, exposed camera parameter, compile success, or nonblank preview is not camera proof.

The original focused example remains `projects/procedural_building_system/CAMERA-TEMPLATE.md`; this knowledge file is the workspace-wide canonical contract.
