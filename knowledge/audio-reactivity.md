# Audio Reactivity

Pipeline type: `audio`

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
uint latest = _Data0[0].generation_counter;
uint start = AudioRingCatchupStart(
    read_cursor, latest, AUDIO_HOP_RING_CAPACITY);

for (uint generation = start; generation <= latest; ++generation) {
    uint slot = AudioRingGenerationToSlot(
        generation, AUDIO_HOP_RING_CAPACITY);
    uint base = slot * value_count;
    if (_Data0[base].generation_counter != generation) continue;

    // Consume _Data0[base + index].magnitude or .energy.
}

read_cursor = latest + 1u;
```

Generation remains monotonic across Audio In source and file restarts. A consumer that falls more than 64 hops behind resumes at the oldest retained generation.

## Runtime Proof

For live device proof:

1. Confirm `list_types` includes `audio`.
2. Create Audio In and select the intended flow and endpoint.
3. Inspect `sentinel_pipeline action=info` for a healthy Streaming status.
4. Verify frames and data generations advance.
5. Read a small sample from each wired port with `capture_data_port`.
6. Confirm `level` and `peak` respond to audio and decay during silence.
7. Exercise the reactive Module and verify its output and counters.
8. Record a short segment and listen for the expected audio.

For a device-loss proof, remove or disable the explicitly selected endpoint, verify device-lost status with advancing timestamped silence, then reconnect it and confirm automatic recovery.
