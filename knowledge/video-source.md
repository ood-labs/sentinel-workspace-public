# Video Source

Video File is a source type, not a pipeline node. Use it when a graph should start from a clip on disk.

## Create Or Replace

Use live capabilities for the exact argument names in the installed build:

```text
sentinel_app action=capabilities
sentinel_pipeline action=create_source source_type=video name=clip video_path=C:\path\clip.mp4
```

You can also create an empty Video source in the UI and drag-replace the clip later. Project save/reload preserves the path, and Collect Assets copies referenced clips under `videos/`.

## Supported Media

Current release support:

- Containers: `.mp4`, `.mov`.
- Hardware decode through NVDEC: H.264 and H.265.
- Native decode: HAP and HAP Alpha.
- Output: BGRA8 textures.

Unsupported codecs render a black fallback and report a concrete status message in Properties, such as `Unsupported video codec: AV1 (av01)`.

## Transport Controls

Video source controls are exposed through Properties, StateTree, OSC, and MCP. Inspect the source with `sentinel_pipeline action=info` and live capabilities before scripting. Common controls include play/pause, loop, rate, current time, and frame stepping.

This release does not include audio playback, AV1 decode, HDR/float source output, trim/cue points, reverse playback, ping-pong playback, or seamless dual-decoder looping.
