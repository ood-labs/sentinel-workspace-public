# Video Source

Video File is a source type, not a pipeline node. Use it when a graph should start from a clip on disk, including show playback: HAP clips play from a background reader, a wired Mux crossfades between them, and a Script can sequence them from one Event.

## Create Or Replace

Use live capabilities for the exact argument names in the installed build:

```text
sentinel_app action=capabilities
sentinel_pipeline action=create_source source_type=video name=clip video_path=C:\path\clip.mov
```

`create_source` also takes `playing`, `loop_playback` and `playback_rate` for the starting transport. To swap the clip of an existing source, write its `videoPath`; the id, links and transport settings stay, and `codec`, `duration`, `totalFrames`, `currentFps` and `decoderState` update for the new file. You can also create an empty Video source in the UI and drag-replace the clip later. Project save/reload preserves the path, and Collect Assets copies referenced clips under `videos/`.

## Supported Media

| Codec | Decode | Notes |
|---|---|---|
| HAP, HAP Alpha | background reader | the show codec: the main thread only uploads |
| HAP Q, HAP Q Alpha | background reader | higher quality, twice the frame size of HAP |
| H.264, H.265 | NVDEC | colour range and matrix come from the file's tags; H.265 written as `hvc1` or `hev1` both play |

- Containers: `.mov` and `.mp4`.
- HAP R (`Hap7`), HAP HDR (`HapH`) and alpha-only HAP (`HapA`) are refused by name in `decoderState`.
- Unsupported codecs render a black fallback and report a concrete status message in Properties, such as `Unsupported video codec: AV1 (av01)`.

## Controls

Every control is a StateTree path under `/sentinel/sources/<id>/`, also shown in Properties.

| Path | Use |
|---|---|
| `playing`, `loop`, `playbackRate`, `currentTime`, `step_frame` | transport (`sentinel_state action=set`) |
| `actions/preroll` with `{"time": seconds}` | seek, pause and fill the reader so the clip starts at once when played |
| `actions/restart` | seek to 0 and play |
| `ended_count`, `ended_at_ns` | read-only: rises once each time a non-looping clip reaches its end, and when |
| `shownFrame`, `currentFrame` | read-only: the frame on screen, and the playback clock's frame |
| `ready_frames`, `late_frames`, `read_MBps`, `vram_MB` | read-only reader status (also a row in Properties) |
| `demanded`, `reader_idle` | read-only: whether anything consumes the clip right now |
| `color_matrix`, `color_range` | H.264/H.265 overrides; `Auto` follows the file, `detected_color` shows its tags |
| `videoPath` | the file; writing it swaps the clip and keeps the source |
| `codec`, `duration`, `totalFrames`, `currentFps`, `decoderState` | read-only file facts and decoder status (`Ready (HAP Q)`, or the reason a file is refused) |

```text
sentinel_state action=invoke path=/sentinel/sources/clip/actions/preroll args={"time": 0}
sentinel_state action=set path=/sentinel/sources/clip/playing value=true
sentinel_state action=get path=/sentinel/sources/clip/ended_count
```

A clip decodes only while something consumes it: a running pipeline input, an active output, a recording, or a pipeline window showing its input tiles. The graph thumbnail and the Properties tile do not count. A playing clip with nothing consuming it keeps time and reads nothing, so loading many clips costs only their VRAM (about 75 MB each at 4K).

## Fading Between Clips

Wire the clips to a Mux in Wired mode (`source_mode` 0) with `sentinel_pipeline action=set_input`. Set `fade_time` in seconds; changing `selected` then crossfades (0 cuts). Every cut and fade waits up to 4 frames for the incoming clip's current frame, so an idle clip never flashes its old frame. Selecting an input with nothing connected fades to black. `switcher/fading` and `switcher/fade_progress` report the fade. In Properties the Mux shows one tile per input; clicking a tile selects it.

## Sequencing Clips From One Event

`tools/templates/scripts/clip_sequencer.luau` plays a clip list through a wired Mux:

1. Create the clips, the Mux, and wire clip i to Mux input i - 1.
2. Copy the script into the project's `scripts/` folder, create a `script` node and set its `script_path` parameter to it.
3. Set its parameters: `sources` (comma-separated source ids in order), `mux` (the Mux's id), `fade` (seconds), `end_mode` (`hold` keeps the last frame, `black` fades to `black_input`, an unconnected Mux input).
4. Fire it from the Go button in its window, or wire any Event (a MIDI In node's `events`, for example) to its `go` input. `next` and `stop` inputs and buttons skip ahead and stop.

It prerolls each next clip while the current one plays, starts it `fade` seconds before the current one ends, and emits `clip_started`, `clip_ended` (within a frame of the true end) and `sequence_ended` Events with the clip's position as payload.

## Preparing Show Clips

Transcode to HAP Q with four chunks:

```text
ffmpeg -i master.mov -c:v hap -format hap_q -chunks 4 clip_q.mov
```

`-format` takes `hap`, `hap_alpha` or `hap_q`; HAP Q Alpha needs an encoder that writes it. Four chunks let the reader decompress a frame in parallel, about half the time of one chunk at 4K60. Match the clip's frame rate to the show output (30 or 60 for a 60 Hz output) so every frame is held exactly the same number of display frames.

## Show Machine Setting

In NVIDIA Control Panel, Manage 3D settings, Program Settings, set Power management mode to **Prefer maximum performance** for `sentinel.exe`. On a light graph the GPU otherwise drops to a low power state and falls behind 4K video copies for a few frames at a time.

## Not Supported

Audio playback, AV1 decode, HDR/float source output, trim/cue points inside a clip, reverse and ping-pong playback.
