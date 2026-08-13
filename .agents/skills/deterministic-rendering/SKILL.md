---
name: deterministic-rendering
description: Render exact frame-locked PNG sequences from Sentinel pipeline outputs through sentinel_capture render_sequence, render_status, and render_cancel. Use for offline deterministic renders, reproducible procedural animation frames, synthetic datasets, per-frame parameter tracks, Conductor-driven cue renders, PNG8 or PNG16 sequences, render-job monitoring or cancellation, and manifest integrity checks. Do not use for live MP4 recording or ordinary motion sweeps.
---

# Deterministic Rendering

Render a pipeline at exact content times without tying content time to wall-clock
presentation speed. Frame `i` receives `start_time + i / fps`, and a successful
job writes exactly one PNG for every requested frame.

## Select the correct capture mode

- Use `render_sequence` for an offline, fixed-step PNG sequence.
- Use `capture_at` for one or more review stills.
- Use `sweep_record` for a parameter sweep encoded as an MP4 motion proof.
- Use `record_pipeline` for a live recording whose cadence follows the running
  application.

Never emulate deterministic rendering with repeated StateTree writes, sleeps,
or `capture_at` calls. That approach reintroduces wall-clock and IPC timing.

## Preflight

1. Call `sentinel_app action=ping` and `sentinel_app action=capabilities`.
   Require `RENDER_SEQUENCE`, `RENDER_STATUS`, and `RENDER_CANCEL`. If they are
   absent, report that the installed Sentinel build lacks deterministic
   rendering and stop.
2. Inspect the subject with `sentinel_pipeline action=info`. Require a healthy,
   compiled pipeline and select a texture output slot. Data and control outputs
   cannot be rendered.
3. Identify the determinism boundary. Procedural Modules driven by injected
   Sentinel time can produce bit-identical reruns. Live capture, media playback,
   AI inference, external Spout or NDI, and similar inputs may vary. Preserve
   and report the manifest's `nondeterministic_sources` entries.
4. Choose a fresh output directory. A strict job rejects an existing
   `manifest.json`, `frame_*.png`, or temporary sequence artifact. Use an
   absolute path when the output must be easy to find.
5. Choose `png8` for compact delivery or `png16` for 16-bit/channel linear RGBA
   and precision-sensitive data. Trial builds may clamp the delivered
   resolution. Confirm `trial_clamped` and the source/delivered dimensions in
   status and the manifest before claiming native-resolution output.

## Start a basic job

Use `filepath` for the output directory at the MCP layer:

```text
sentinel_capture action="render_sequence"
  pipeline_id="module_0"
  slot=0
  fps=30
  frame_count=240
  start_time=0
  format="png16"
  filepath="C:\\renders\\shot_01"
```

`fps` is required and must be greater than 0 and at most 240. `frame_count` is
required and must be between 1 and 1,000,000. `slot` and `start_time` default to
0, and `format` defaults to `png8`.

Record the returned `job_id`. Sentinel permits one render job at a time.

## Apply parameter tracks

Pass `tracks` as an object. A short key resolves under the subject pipeline's
parameter path. An absolute StateTree path can target another pipeline's
writable parameter.

Dense tracks contain exactly one primitive value per output frame:

```json
{
  "gain": [0.0, 0.25, 0.5, 1.0]
}
```

Sparse tracks use strictly increasing in-range frame indices and sample-and-hold
values:

```json
{
  "/sentinel/pipelines/module_1/parameters/look": {
    "frames": [1, 3],
    "values": [0.25, 0.75]
  }
}
```

Before the first sparse key, the parameter keeps its pre-job value. Sentinel
applies every key through StateTree before that frame cooks. It temporarily
suspends any expression on a tracked parameter, then restores the original
value and expression on every terminal path. Confirm restoration after jobs
that alter important show state.

Limits are 64 tracked parameters and 2,000,000 total track values. Values must
be strings, booleans, or numbers.

## Drive Conductor from render time

Set `use_conductor=true` to drive every active Conductor from the exact job
time. At least one Conductor must be active, `start_time` must be non-negative,
and each Conductor's configured duration must cover:

```text
start_time + frame_count / fps
```

Validate that duration before starting. Conductor returns to its normal live
transport behavior when the job becomes terminal.

## Monitor to a terminal state

Poll with the returned job ID:

```text
sentinel_capture action="render_status" job_id="render_..."
```

Monitor `state`, `frames_stepped`, `frames_accepted`, `frames_encoded`,
`in_flight`, `last_*_frame`, `stop_reason`, `manifest_path`, and
`trial_clamped`. Poll at a moderate cadence and keep the UI responsive.

While a job runs:

- Do not mutate the graph. Sentinel rejects graph edits and names the active
  job.
- Do not start another render job.
- Treat `frames_accepted` as the authoritative captured-frame count.
- Wait for encoder drain. A completed job has zero in-flight frames.

Accept success only when all of these hold:

- `state` and `stop_reason` are `completed`.
- stepped, accepted, and encoded counts equal `frame_count`.
- `last_stepped_frame`, `last_accepted_frame`, and `last_encoded_frame` equal
  `frame_count - 1`.
- `manifest.json` exists and lists the same contiguous PNG set present on disk.
- Every recorded SHA-256 matches its PNG.

## Cancel or diagnose a failed job

Request cancellation with the exact job ID, then continue polling until the
job is terminal:

```text
sentinel_capture action="render_cancel" job_id="render_..."
```

Cancellation stops after the in-flight frame and finalizes an honest partial
manifest. Validate that its entries match the contiguous PNG files on disk.

Common terminal reasons include:

| Reason | Meaning |
|---|---|
| `completed` | Every requested frame was accepted and encoded |
| `cancelled` | Cancellation completed after the in-flight frame |
| `capture_failed` | Readback, encode, or file commit failed at `failed_frame` |
| `pipeline_destroyed` | The subject pipeline disappeared |
| `subject_compile_error` | The subject entered a compile-error state |
| `resolution_changed` | The subject changed dimensions during the job |
| `track_apply_failed` | A tracked StateTree write failed |
| `shutdown` | Sentinel finalized accepted frames during normal shutdown |

Do not relabel a partial or failed job as successful. Fix the cause and use a
new output directory for the retry.

## Verify determinism

Compare the PNG bytes or per-file SHA-256 values across identical jobs. Exclude
the manifests from byte-for-byte comparison because elapsed and wall-clock
fields intentionally vary. Report:

- requested and delivered dimensions, format, fps, and frame count;
- first and last hashes plus whether every PNG matched;
- exact frame contiguity and manifest integrity;
- `nondeterministic_sources` and any trial clamp;
- tracked-value restoration and Conductor use when applicable.

Only claim bit-identical determinism when the complete upstream content path is
inside the deterministic boundary and the PNG comparison passes.
