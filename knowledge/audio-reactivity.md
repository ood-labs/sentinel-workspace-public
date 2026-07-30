# Audio Reactivity

Pipeline type: `audio`

## Start Here: Cloth Lab's Bundled Audio Bands

**For any beat, onset, or drum-driven work, use
`projects/cloth_lab/modules/cloth_bands` as the maintained reference.**

Older `pulse2_*`, `cryo_pulse*`, and `bands_demo` experiments are superseded and
are not part of the curated public seed. Do not recreate them or treat historical
mentions as references. New shows must bundle their own owning-project copy rather
than link to Cloth Lab at runtime.

Only use something else if the request is genuinely outside `audio_bands`' spec, or
if a newer module has replaced it.

### The standard chain

```text
audio (Audio In)  --Spectrum-->  audio_bands  --control outputs / expressions-->  consumers
```

`audio_bands` consumes the **Spectrum** port (not Mel Bands). Wire it with the pin
name:

```text
sentinel_graph action=add_link from_entity=<audio> from_slot="Spectrum" \
                               to_entity=<bands>  to_slot="Spectrum"
```

### What it publishes

| Output | Use |
| --- | --- |
| `kick_count`, `snare_count`, `hat_count` | **Monotonic hit counters.** The correct signal for per-hit EDGES. |
| `kick`, `snare`, `hat` | 0..1 envelopes, for continuous modulation. |
| `kick_level`, `snare_level`, `hat_level` | Absolute band level in dB. Answers "is there anything in this band at all". |
| `kick_peak`, `snare_peak`, `hat_peak` | Recent peak flux in dB — the range a threshold must live in for this material. |
| `kick_thresh`, `snare_thresh`, `hat_thresh` | Read-only mirrors of the state-buffer thresholds. |

**Prefer a counter over an envelope for discrete events.** A counter gives an
unambiguous edge with no threshold of your own to tune, and cannot re-fire while an
envelope decays. Latch the last value seen and act on the change. A large counter
jump (which happens when a driver is swapped or a project loads) should fire once,
not burst — adopt the new value without acting when the stored cursor is fresh.

The per-lane dB thresholds gate internally, so **the counters are already gated**.
No separate `signal_present` check is needed, unlike the older `pulse2` chain.

### Threshold Mode

`adapt_mode` defaults to **Fixed**, deliberately. Fixed measures each threshold
against a constant reference (`fixed_ref_db`), so a threshold is an absolute level
you set once and trust, and a quiet passage simply cannot reach it. Adaptive
measures against the band's own rolling level: it is immune to input gain, but the
reference drifts with the music, so a threshold set during a loud section quietly
changes meaning later and a dying track starts triggering on nothing.

Use Adaptive only when the source gain varies unpredictably and immunity to input
level matters more than a stable threshold.

Its Canvas panel is the tuning surface — a spectrogram with per-lane trace strips
and draggable threshold handles. Tune there, not by guessing numbers.

### Worked example

`projects/cloth_lab/` drives a physics simulation from `kick_count` by expression.
See its README for the counter-edge pattern and why an impulse rather than a force.

---


Audio In captures a Windows playback endpoint, microphone endpoint, or paced PCM WAV file. It publishes timestamped PCM, Spectrum, and Mel Bands data for GPU Module consumers, plus scalar `level` and `peak` control outputs.

Published builds at or below 0.5.48 may omit Audio In. Call `sentinel_pipeline action=list_types` and require an `audio` entry before using this page as an available-build contract.

## Create And Select A Source

Create the node:

```text
sentinel_pipeline action=create type=audio name="Show Audio"
```

Important parameters:

| Parameter | Values | Purpose |
| --- | --- | --- |
| `source_mode` | `Device`, `File` | Select live capture or deterministic WAV playback. |
| `device_flow` | `Loopback`, `Microphone` | Select playback-endpoint loopback or a recording endpoint. |
| `device` | live endpoint list | Select the default or an explicit endpoint. |
| `file_path` | absolute PCM WAV path | File used by paced File mode. |
| `restart_file` | button | Restart File mode at its configured sample offset. |
| `rescan_devices` | button | Refresh endpoints while preserving the selected GUID. |
| `fft_size` | 512, 1024, 2048, 4096 | CPU analysis window size. |
| `hop_size` | 128, 256, 512 | Samples advanced per analysis hop. |
| `window` | Hann, Hamming, Blackman-Harris | FFT window. |
| `dc_highpass` | boolean | Remove DC before spectral analysis. |
| `signal_floor_db` | -90 to -20 dBFS | RMS threshold for recent signal presence. Default: -55 dBFS. |
| `no_signal_timeout_s` | 1 to 60 seconds | Delay before Streaming status reports a no-signal warning. Default: 5 seconds. |

The normal live configuration is `source_mode=Device`, `device_flow=Loopback`, FFT 2048, hop 256, Hann window, and DC high-pass enabled.

## Loopback, Microphones, And Virtual Cables

`Loopback` captures audio being rendered to a Windows playback endpoint. Select the speakers, interface output, or virtual-cable playback endpoint that receives the producing application's audio.

`Microphone` captures a Windows recording endpoint. Select a physical microphone, interface input, or virtual-cable recording endpoint.

A typical virtual-cable route is:

```text
player or DAW output
    -> virtual-cable playback endpoint
    -> Audio In with device_flow=Loopback
```

Some virtual-cable packages expose matching playback and recording endpoints with different names. Use `sentinel_capture action=list_audio_devices` or the Audio In dropdown to inspect the live endpoint names. Confirm activity through Audio In `level`, `peak`, and `statusMessage`.

Audio In is separate from a video Capture source. It shares the application's audio-device infrastructure and endpoint discovery, while its node parameters own the selected audio stream.

## The Three Data Outputs

| Port | Shape | Record size | Use |
| --- | --- | --- | --- |
| `PCM` | 1 header plus 16,384 stereo frames | 48 bytes | Waveforms and time-domain processing. |
| `Spectrum` | 64 hops by 1,024 bins | 40 bytes | Exact linear FFT-bin analysis. |
| `Mel Bands` | 64 hops by 138 bands | 40 bytes | Perceptual musical analysis and onset detection. |

At 48 kHz, the PCM ring retains about 341 ms. Spectrum and Mel Bands retain 64 complete analysis hops. Each record carries generation and timing metadata so a Module can process every retained hop in chronological order after a slow render frame.

The scalar `level` and `peak` outputs are ordinary control pins. Use them for simple amplitude reactivity without a data-consuming Module.

Every connected data input also receives compiler-generated metadata:

- `_DataN_Count`: total records currently bound to the slot.
- `_DataN_Generation`: latest generation published by the producer.
- `_DataN_ValueCount`: records in one logical generation or hop.
- `_DataN_HopCapacity`: retained generation count.

Use these uniforms for indexing and dirty propagation. Spectrum and Mel Bands
have no separate header record, so reading `_DataN[0].generation_counter` only
observes slot zero and becomes stale until the 64-hop ring wraps.

## CPU And GPU Ownership

The CPU owns:

- WASAPI capture and endpoint recovery;
- native-format conversion, channel mapping, and subscriber queues;
- DC filtering and FFT windowing;
- PFFFT SIMD transforms and magnitude calculation;
- Mel-band aggregation;
- sample positions, QPC timestamps, ring generations, and silence gap filling.

The completed rings are uploaded as D3D11 structured buffers. GPU HLSL Modules consume those buffers for onset detection, envelopes, counters, and visual rendering. Audio In does not require CUDA, TensorRT, or an AI engine pack.

At 48 kHz with a 256-sample hop, the analysis thread processes 187.5 hops per second. A smaller hop lowers analysis latency and increases CPU work.

## Device Changes While Sentinel Is Open

Audio In keeps endpoint identity by Windows device GUID.

- Adding an unrelated device leaves the active stream unchanged.
- `rescan_devices` refreshes the dropdown and preserves the current GUID when it is still present.
- Choosing a different device restarts capture on that endpoint.
- `Default loopback` and `Default microphone` follow Windows default-endpoint changes automatically.
- An explicitly selected endpoint ignores unrelated Windows default changes.
- If an explicit endpoint disappears, Audio In enters device-lost state, publishes timestamped silence, and retries the same endpoint about once per second.
- Reconnecting the same endpoint resumes capture without restarting Sentinel.
- A missing explicit endpoint is never silently replaced by an unrelated newly connected device.
- Rescanning while the saved endpoint is absent can activate the documented default fallback. Pipeline health and `statusMessage` identify the missing requested device.
- A format change on the active endpoint triggers a controlled stream restart.

The endpoint notification listener runs asynchronously. Device callbacks enqueue migration, loss, or format events; capture teardown and restart occur away from the Windows notification thread.

### Capture and signal diagnostics

Audio In publishes read-only values under:

```text
/sentinel/pipelines/<audio_id>/diagnostics/
```

Useful fields include:

| Field | Meaning |
| --- | --- |
| `capture_state` | Current capture lifecycle state, such as Streaming or DeviceLost. |
| `resolved_endpoint_id`, `resolved_endpoint_name` | Endpoint actually in use. |
| `endpoint_active` | Whether Windows still reports the resolved endpoint active. |
| `last_packet_age_ms` | Age of the newest real capture packet. |
| `real_packets_captured` | Lifetime real-packet count for the node. |
| `migration_count` | Default-endpoint migrations. |
| `device_lost_count` | Endpoint-loss recoveries. |
| `format_invalidation_count` | Audio-client format invalidations. |
| `retry_count` | Capture restart retries. |
| `gap_fill_frames`, `overrun_count` | Synthesized continuity and subscriber pressure. |
| `signal_present`, `silence_seconds` | Recent content relative to the configured signal floor. |

Capture health and content presence are separate. A healthy silent endpoint
stays Streaming with `endpoint_active=true` and `signal_present=false`. A lost
or stale endpoint degrades pipeline health even when timestamped silence keeps
the data timeline advancing.

## Module Wiring

Inspect the live schemas:

```text
sentinel_pipeline action=get_data_schemas pipeline_id=Show_Audio
```

Create or scaffold a Module, then wire the reported graph pin by name with `sentinel_graph action=add_link`. Common routes are:

```text
Audio In / Mel Bands -> Audio Drum Detector
Audio In / Mel Bands -> Audio Spectrum Bars
Audio In / PCM       -> Audio Waveform Oscilloscope
Audio In / Mel Bands -> Audio Reactive Starter
```

Use `sentinel_expression action=set` to drive any writable parameter from `level`, `peak`, or a detector control output:

```text
ref("Audio_Drum_Detector/control_outputs/kick")
```

The stock Drum Detector publishes:

- envelopes: `kick`, `snare`, `hihat`;
- counters: `kick_count`, `snare_count`, `hihat_count`, `onset_count`;
- smoothed energy: `bass`, `mid`, `treble`;
- `Hits` records containing accepted-onset lane, sample position, QPC timestamp, and sequence.

## Authoring An Audio Module

Start with `sentinel_module action=scaffold_from_ports` against the desired Audio In port. Add this manifest feature:

```yaml
features: [audio]
```

The injected audio helpers include safe dB conversion, Hz/Mel conversion, Spectrum and Mel range lookup, chronological ring catch-up, and asymmetric attack/release envelopes.

Store the next unread generation in a persistent buffer and consume retained hops in order:

```hlsl
uint latest = _Data0_Generation;
uint value_count = _Data0_ValueCount;
uint hop_capacity = _Data0_HopCapacity;
uint start = AudioRingCatchupStart(
    read_cursor, latest, hop_capacity);

for (uint generation = start; generation <= latest; ++generation) {
    uint slot = AudioRingGenerationToSlot(
        generation, hop_capacity);
    uint base = slot * value_count;
    if (_Data0[base].generation_counter != generation) continue;

    // Consume _Data0[base + index].magnitude or .energy.
}

read_cursor = latest + 1u;
```

Generation remains monotonic across Audio In source and file restarts. A consumer that falls more than 64 hops behind resumes at the oldest retained generation.

Adaptive thresholds normalize to whatever reaches them, including steady
noise. Gate onset-driven behavior with a signal floor. Audio In exposes
`signal_present` for the captured stream, while the stock Drum Detector
publishes an adaptive Mel-energy `signal_present` control output for detector
logic. Keep BPM confidence, counters, and pulse outputs inactive below that
gate.

## Runtime Proof

For live device proof:

1. Confirm `list_types` includes `audio`.
2. Create Audio In and select the intended flow and endpoint.
3. Inspect `sentinel_pipeline action=info` for a healthy Streaming status.
4. Read the diagnostics subtree and confirm `endpoint_active`, packet age, and
   signal presence agree with the physical setup.
5. Verify frames and data generations advance.
6. Read a small sample from each wired port with `capture_data_port`.
7. Confirm `level` and `peak` respond to audio and decay during silence.
8. Exercise the reactive Module and verify its output and counters.
9. Run `sentinel_graph action=profile sort_by=cook_hz` and compare rolling
   `cook_hz`, `cooks_in_window`, and `cook_window_ms`, rather than comparing
   lifetime `frames_processed` totals between nodes created at different times.
10. Record a short segment and listen for the expected audio.

For a device-loss proof, remove or disable the explicitly selected endpoint, verify device-lost status with advancing timestamped silence, then reconnect it and confirm automatic recovery.

The Phase 99 retained battery also verifies exact in-band hit counts at FFT
1024/hop 128 and FFT 2048/hop 256, plus identical detector counters across a
measured render hitch. MCP transports the completed records; sample positions
and QPC timestamps inside those records define latency.
