---
name: motion-eval
description: Record a deterministic parameter sweep of a Sentinel pipeline to MP4 and evaluate the motion with sentinel_vision. Use when you need to see how an animation looks in motion (not from stills), check whether a Module's phase loop is seamless, or discover what a numeric parameter does across its range. Covers sentinel_capture action="sweep_record" plus the sentinel_vision hand-off.
distribution: true
---

# Motion Eval (sweep-record → sentinel_vision)

To understand how a pipeline animates, do not step a parameter and screenshot each
value. Record a deterministic sweep to a video and let a vision model watch it move.

`sentinel_capture action="sweep_record"` drives a numeric pipeline parameter from
`start` to `end` **frame-locked** (each recorded frame is one evenly-spaced step,
set on the render thread before that frame renders) while recording the pipeline
output, plays the pass `loops` times back-to-back into one clip, auto-stops on an
exact frame count, and returns the finished `.mp4` path in a single blocking call.
The clip uses no B-frames, so it is frame-exact and seek-clean. Feed the path to
`sentinel_vision action="eval"`.

## Two recipes

### 1. Phase loop eval (the default)
Most Module content animates a normalized `phase` 0..1. Defaults are tuned for this:
`parameter="phase"`, `start=0`, `end=1`, `frames=60`, `loops=2`. Playing the loop
twice makes the wrap from end back to start appear twice, so the model can judge
whether it reads as a seamless loop.

```
sentinel_capture action="sweep_record" pipeline_id="module_0"
# -> { output_path: "captures/recordings/module_0_<ts>.mp4", frames_written: 120, ... }
```

Then evaluate, and **tell the model the clip plays the loop twice** so it knows to
watch the seam:

```
sentinel_vision action="eval" path="<output_path>" preset="animation_quality"
  prompt="This clip plays the phase animation 0->1 twice back-to-back. Describe the
          motion (what moves, which direction). Then judge whether it reads as a
          seamless loop -- watch the reset from end back to start (it happens twice):
          continuous, or an abrupt pop? Note any stutter or out-of-order frames."
```

### 2. Parameter explorer (any numeric parameter)
To discover what a single parameter does, sweep just that one across its range with
`loops=1` (a single A->B pass, no loop) while everything else stays static.

```
sentinel_capture action="sweep_record" pipeline_id="module_0"
  parameter="hue" start=0 end=1 frames=90 loops=1
```

```
sentinel_vision action="eval" path="<output_path>"
  prompt="This clip sweeps a parameter named 'hue' from 0 to 1; the rest of the scene
          is static. Describe concretely what visually changes from start to end --
          which property does this parameter control, and how does it progress?"
```

This also works on non-Module pipelines: any numeric StateTree parameter under
`/sentinel/pipelines/<id>/parameters/<name>` can be swept (StreamDiff denoise,
ColorCorrect brightness, a shader uniform, etc.).

## Arguments

| arg | default | meaning |
|-----|---------|---------|
| `pipeline_id` | (required) | pipeline whose output is recorded |
| `parameter` | `phase` | parameter name under the pipeline's `/parameters/` |
| `start` / `end` | `0.0` / `1.0` | sweep range; for partial ranges use the param's min/max |
| `frames` | `60` | frames per `start->end` pass; raise for smoother motion |
| `loops` | `2` | passes recorded back-to-back; use `1` for an explorer pass |
| `slot` | `0` | pipeline output slot to record |
| `mode` | `video` | `video` (MP4) or `png_sequence` |
| `pixel_budget` | `1080p` | `720p` / `1080p` / `none` / int; `720p` keeps eval clips small |
| `bitrate_mbps`, `target_fps_metadata`, `filepath` | 20 / 30 / auto | standard recording args |

The call returns `output_path`, `frames_written` (== `frames * loops`),
`stop_reason` (`frame_limit` on success), and the sweep settings.

## If sentinel_vision is not set up

An `eval` call that fails with a missing or rejected key means the provider key was never configured. Walk the user through setup; the key never goes through chat or tool arguments:

1. Run `sentinel_vision action="status"` and read the returned `config_path` (the workspace `vision.json`).
2. Tell the user to open that file and replace the selected provider profile's `api_key` placeholder (`PASTE-YOUR-KEY-HERE`) with their key. The default profile is OpenRouter; any OpenAI-compatible provider profile works the same way.
3. Rerun `sentinel_vision action="status"` until it reports `key_present: true` and `key_ok: true`.
4. Environment variables also work: `SENTINEL_VISION_API_KEY` (or `OPENROUTER_API_KEY` for the openrouter profile) set before launching the MCP client, then reconnect.

## Video size and provider limits

Inline video eval needs a video-capable provider (the default OpenRouter Gemini model qualifies) and a raw file at or below 14 MiB; the default `pixel_budget="1080p"` at 20 Mbps stays under that for short sweeps, and `720p` gives extra headroom. If the clip is too large or the provider lacks video support, rerun the sweep with `mode="png_sequence"` and pass the recording directory to `sentinel_vision action="eval" max_frames=16`, which samples labeled frames from the manifest.

## Setup and gotchas

- **The module must be loaded and producing frames.** Create it and set
  `project_dir`, then confirm the parameter exists with
  `sentinel_state list_values /sentinel/pipelines/<id>/parameters` before sweeping.
  A missing parameter returns an error listing the available ones.
- **`phase` must be externally driven, not auto-animated.** sweep_record sets the
  parameter every frame; if the module advances `phase` itself on `_Time`, the two
  fight. The convention: combine them as `frac(phase + _Time * animation_speed)` and
  leave `animation_speed` at 0 while sweeping so `phase` fully controls position.
  Raise `animation_speed` only for free-run playback.
- **Frame count, not duration.** The clip length is `frames * loops` exactly,
  independent of render speed; dropped/slow frames just retry the same step.
- **Seam expectations.** A progress-style element (an arc that fills then resets) is
  intentionally non-seamless; orbiting/rotating elements that complete a full
  revolution per loop are seamless. Say which you expect in the prompt.

## Example module

`.claude/skills/module-authoring/examples/phase_loop/` is a 1280x720 geometric loop
exposing both a normalized `phase` (deterministic scrub) and `animation_speed`
(free-run), handy for testing this workflow.
