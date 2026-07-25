# Research Prompt: GPU Audio Analysis, Region-Based Onset Detection, and Beat Tracking

## Objective

We want to build a reusable, production-grade audio analysis Module for Sentinel that drives every future audio-reactive project. It must do three things extremely well: isolate individual instruments from a live mix, detect their onsets reliably, and track tempo and beat phase accurately enough to stay locked through a whole set.

**The core question: what is the best achievable real-time onset-detection and beat-tracking architecture when the entire analysis must run as HLSL compute passes over structured buffers, the only inputs are magnitude-only FFT data, and the interface for configuring it is a spectrogram the user clicks on directly?**

A first attempt (`modules/cryo_pulse`) already works: spectral flux over Mel bands, per-lane adaptive thresholds, autocorrelation tempo, beat PLL. It tracks BPM on real material. But it was tuned by eye, has no way to be scored, and its weakest lane (snare) is an information limit rather than a tuning problem. This research should establish what the *right* system looks like before we build the second one.

## Context

### Current State / Pain Point

Existing implementation, `modules/cryo_pulse`:

- Consumes `Mel Bands` (64 hops x 138 bands, 40-byte records).
- Per-hop log compression, half-wave-rectified spectral flux in three fixed band lanes split at authored band indices (12 and 58).
- Per-lane adaptive threshold: `EMA(flux) + k * EMA(|flux - EMA|)` plus a single global floor.
- Refractory gating per lane; instant-attack / authored-release envelopes.
- Tempo: autocorrelation over a self-maintained 512-hop history ring, run as a parallel pass with one thread per candidate lag, plus half/double-time correction and a beat-phase PLL nudged by kick onsets.
- Publishes 15 control outputs consumed by expressions.

Known problems:

- **Kick and hi-hat separate acceptably by frequency; snare does not.** Snare is broadband and overlaps everything. No amount of band-split tuning fixed it.
- **A single global `threshold_floor` is wrong.** High-frequency flux is small in absolute terms, so a floor tuned for kick swamps the hat lane entirely; the hat lane sat below threshold until the floor was dropped, at which point the kick lane over-triggered.
- **No way to score a detector.** Tuning was done by watching traces. There is no ground truth, no precision/recall, no BPM error measurement.
- **Fixed band lanes are a blunt instrument.** Three contiguous ranges with two split points cannot isolate, say, a snare's body from a tom, or a rimshot from a clap.
- **Adaptive thresholds hallucinate.** The detector reported BPM 96 at 99% confidence on a dead endpoint delivering a noise floor, because adaptive thresholds normalise to whatever is present. A signal gate was added afterward.

Live data contract (verified this session on Sentinel 0.5.49):

| Port | Shape | Record | Notes |
| --- | --- | --- | --- |
| `PCM` | 1 header + 16384 stereo frames | 48 B | ~341 ms at 48 kHz; carries `left`, `right` |
| `Spectrum` | 64 hops x 1024 bins, no header | 40 B | `magnitude` only |
| `Mel Bands` | 64 hops x 138 bands, no header | 40 B | `energy` only |

Measured live: `sample_rate 48000`, `hop_size 256`, `fft_size 4096`, `value_count 1024`. Stereo is documented as summed `0.5 * (left + right)` before analysis. Every data input receives `_DataN_Generation`, `_DataN_ValueCount`, `_DataN_HopCapacity` uniforms.

Platform constraints:

- All analysis runs as HLSL compute passes. Persistent structured buffers survive across cooks and serialize into the project.
- Only 64 hops (~341 ms) are retained by the producer. Anything needing longer context must maintain its own ring.
- Single-thread passes (`dispatch [1,1,1]`) are the documented pattern for sequential reduction, but they are one serial GPU lane and become a cliff at tens of thousands of iterations. Parallel passes (one thread per lag/bin/region) are cheap.
- No phase data. `Spectrum` publishes magnitude only.
- Modules cook at display rate (~60 Hz) while hops arrive at ~187 Hz, so roughly 3 hops arrive per cook.

### What We Want

- Surgical isolation of individual instruments from a live mix, configured visually rather than numerically.
- Onset detection that is robust across genres, mix densities, and loudness without per-track re-tuning.
- Tempo estimation and beat-phase tracking accurate and stable enough to drive synchronised visuals for an entire set, including through tempo changes and breakdowns.
- A detector that reports uncertainty honestly instead of producing confident wrong answers.
- A measurable system — we should be able to score a change as better or worse, not argue about it.
- A reusable base other projects consume, not a bespoke one-off.

## Key Questions

### 0. Choosing the Input Representation

0a. **Linear `Spectrum` vs perceptual `Mel Bands` for onset detection and for instrument isolation.**
   - MEASURED, not to be re-researched: `value_count` is always 1024 and bin width is exactly `sample_rate / fft_size`. A 440 Hz tone peaks at bin 37.5 with `fft_size 4096` (11.7 Hz/bin) and at bin 18.8 with `fft_size 2048` (23.4 Hz/bin). Coverage is therefore `1024 x sr/fft_size`: **4096 gives 11.7 Hz resolution but only 0–12 kHz; 2048 gives 23.4 Hz across the full 0–24 kHz.** Everything above the cutoff is simply absent from the port.
   - Given that trade-off, which setting is correct for a drum-oriented detector? Is losing 12–24 kHz acceptable when hi-hat and cymbal fundamentals sit lower, or does the missing air band materially hurt hat detection?
   - Is there a case for running two analysis paths at different `fft_size` values, and can a single Audio In node even provide that?
   - At what frequency does 138-band Mel resolution become worse than 1024-bin linear for discriminating two nearby percussive sources?
   - Which representation do production onset detectors actually use, and does the answer differ for onset detection versus tempo estimation?

0b. **Does `PCM` have a role beyond waveform display?**
   - Are there onset detection functions that operate in the time domain and outperform spectral methods for percussive transients — envelope followers, energy derivative, high-order statistics?
   - Could a short-window time-domain detector run alongside the spectral one to sharpen onset *timing* while the spectral one determines *which instrument*?
   - What does the ~341 ms PCM retention allow and forbid?

0c. **Window and hop trade-offs.**
   - `fft_size 4096` at 48 kHz is an 85 ms window. What does that smearing cost for transient localisation, and is 2048 or 1024 materially better for onset timing?
   - Is there a standard approach of running multiple resolutions simultaneously (multi-resolution / multi-band onset detection) and combining them?
   - Given hop 256 (5.3 ms) is fixed by the producer, how much does window length actually matter for onset *detection* versus onset *localisation*?

### 1. Onset Detection Functions

1a. **Which onset detection functions are strongest for percussive material, and how do they rank?**
   - Spectral flux, high-frequency content, phase deviation, complex domain, weighted phase deviation, rectified complex domain, spectral difference on log-magnitude.
   - Which of these are viable with magnitude only, and how much is genuinely lost by not having phase?
   - Is it worth requesting phase or real/imaginary output from the audio node, and what specifically would it unlock?

1b. **Spectral whitening and adaptive normalisation.**
   - How does per-bin adaptive whitening (running max, median, or percentile per bin) change detection quality, especially for letting quiet high-frequency events compete with loud low-frequency ones?
   - Does this eliminate the need for per-lane threshold floors entirely?
   - What are the standard time constants, and how do they interact with a mix that changes loudness?

1c. **SuperFlux and related refinements.**
   - What does maximum-filtering across frequency contribute, and does it matter for drums or only for pitched/vibrato material?
   - What is the current state of the art for onset detection functions that are *not* neural, given we cannot run a network here?
   - How much of the modern gain in onset detection comes from the detection function versus the peak-picking stage?

1d. **Peak picking.**
   - What are the standard peak-picking algorithms (moving-average threshold, local-maximum with lookahead, Böck-style multi-condition picking) and how do they compare?
   - How much lookahead is needed, and what latency does that impose? Is lookahead acceptable for live visuals?
   - How should refractory periods be chosen per instrument, and should they adapt to detected tempo?

### 2. Region-Based Instrument Isolation

2a. **Does drawing a region on a spectrogram actually work as instrument isolation?**
   - Is a frequency-band region sufficient to isolate a kick, snare, or hat from a dense mix, or does it fail as soon as another instrument shares the band?
   - What do production tools that do spectral selection (iZotope RX, SpectraLayers, Photosounder) actually do beyond a rectangular selection — edge feathering, harmonic tracking, spectral masks?
   - What region *shape* is most useful: rectangle, freeform mask, weighted profile, multiple disjoint bands for a fundamental plus its harmonics?

2b. **Beyond simple band-limiting.**
   - Would a matched template or spectral profile learned from a few example hits dramatically outperform a static region? How would a user "teach" it a kick in a live setting?
   - Is there a lightweight source separation technique viable in a shader — NMF with a small fixed dictionary, median-filter harmonic/percussive separation, transient/steady-state decomposition?
   - How does harmonic/percussive separation (HPSS) actually work, what does it cost, and is a 2D median filter over a spectrogram feasible with our buffer sizes?

2c. **Discriminating overlapping instruments.**
   - Snare and kick frequently overlap in the low-mid. What techniques separate them — spectral shape, decay time, noise-versus-tonal ratio, onset sharpness?
   - Could a per-region detector use multiple features (flux, spectral centroid, flatness, decay slope) combined into a classifier rather than a single flux threshold?
   - How do drum transcription systems distinguish simultaneous hits?

2d. **How many independent regions are practical?**
   - What is the realistic upper bound on simultaneous detector lanes before it becomes unusable to configure?
   - Should regions be independent, or should there be a competition/inhibition step so one transient does not fire five lanes?

### 3. Tempo Estimation

3a. **Which tempo estimation methods are actually best, and why?**
   - Autocorrelation of the onset strength signal, Fourier tempogram, comb-filter resonator banks (Scheirer), cyclic tempogram, predominant local pulse.
   - What are the accuracy, latency, and stability trade-offs of each?
   - Which are naturally parallel and therefore well suited to one-thread-per-candidate GPU passes?

3b. **The octave / metrical level problem.**
   - Half-time and double-time errors are the dominant failure mode. What are the established approaches for choosing the correct metrical level?
   - Do tempo priors (a preference curve peaked around 120 BPM) genuinely help, and what shape is standard?
   - How do systems decide between 3/4 and 4/4, or handle shuffled/swung material?

3c. **How much history is required?**
   - What observation window do production tempo trackers use, and how does accuracy scale with it?
   - Our producer retains 341 ms, so all history is consumer-maintained. What ring length is actually needed for stable tempo — 4 seconds, 8, 30?
   - What are the memory and compute implications at those lengths in structured buffers?

3d. **Tempo changes and live performance.**
   - How should a tracker handle a DJ pitch-bending, a tempo ramp, or a hard cut between tracks?
   - What is the right balance between fast re-acquisition and stability, and how do systems expose that as a control?
   - How should confidence be computed so that it collapses honestly during a breakdown or ambiguous passage?

### 4. Beat Tracking and Phase

4a. **Beat phase, not just tempo.**
   - What are the main beat-tracking architectures — dynamic programming over an onset curve (Ellis), multi-agent (BeatRoot), particle filters, coupled oscillators / PLL, hidden Markov models?
   - Which produce a usable *causal* phase estimate for live visuals, given non-causal methods that see the whole file are unusable here?
   - What is the standard accuracy achievable causally versus offline?

4b. **Dynamic programming beat tracking in a GPU context.**
   - Ellis-style DP is sequential over frames. Can it run over a bounded horizon in a single-thread pass at an acceptable rate, or is there a parallel formulation?
   - What horizon is required for the DP to give a materially better answer than a PLL?

4c. **Oscillator and PLL approaches.**
   - How do coupled-oscillator beat trackers work, and how do they compare to DP for live use?
   - What are the standard coupling and correction laws, and how are they kept from being destabilised by a single spurious onset?
   - How should downbeat (bar position) be estimated, and is that realistic without a full metrical model?

4d. **Predictive scheduling.**
   - For visuals it is often better to predict the *next* beat than to react to the current one. What are the standard methods for beat prediction and how far ahead can they be trusted?
   - How should a predicted beat be reconciled when the actual onset arrives early or late?

### 5. GPU / Shader Implementation Strategy

5a. **Mapping these algorithms onto compute passes.**
   - Which stages are naturally parallel (per-bin whitening, per-region flux, per-lag correlation, per-tempo resonator) and which are irreducibly sequential (peak picking with state, DP, PLL update)?
   - What is the right decomposition into passes, and how should state flow between them across cooks?
   - Are there known GPU implementations of tempo/beat tracking, and what did they do?

5b. **State management across cooks.**
   - Modules cook at ~60 Hz while hops arrive at ~187 Hz. What is the correct pattern for consuming a variable number of hops per cook without drift or double-counting?
   - How should a large state buffer be carried forward without a serial copy every cook? Is there a ping-pong or partial-update pattern that avoids copying a full history ring?
   - What happens on a render hitch, and how should the analyser resynchronise?

5c. **Numerical and precision concerns.**
   - What precision is required for long-running accumulators, phase, and counters, and where will float32 bite?
   - Are there known pitfalls in shader hash functions and running statistics for this class of algorithm?

5d. **Cost budget.**
   - What is a realistic per-frame GPU budget for a full analysis stack (whitening + N region detectors + tempogram + beat tracker) so it can coexist with a heavy renderer?
   - Which stage dominates, and what are the standard optimisations?

### 6. The Spectrogram Interface

6a. **What makes a spectral selection interface genuinely usable?**
   - How do RX, SpectraLayers, and similar tools lay out the display — linear versus log frequency, scrolling versus static, colour mapping, dynamic range compression for display?
   - What display transform makes a kick, a snare, and a hat all simultaneously visible and clickable in one view?
   - How much history should be shown, and does the user need to scrub back to place a region on a hit they already heard?

6b. **Feedback while configuring.**
   - What visual feedback tells a user their region is working — a live flux trace, threshold overlay, firing indicators, hit-rate readout?
   - How should a detector communicate that it is over-triggering or missing, without ground truth?
   - Is there a "learn from the last N hits" affordance that is standard in DJ or VJ software?

6c. **Presets and portability.**
   - Do regions tuned on one track transfer to another, or does every track need re-tuning? What does that imply for the interface?
   - Should regions be defined in absolute Hz, or relative to detected spectral features so they adapt?

### 7. Evaluation and Ground Truth

7a. **How do we score a detector?**
   - What are the standard metrics for onset detection (F-measure with a tolerance window, typically 25–50 ms) and for beat tracking (F-measure, CMLc/CMLt, AMLc/AMLt, information gain)?
   - What tolerance windows are standard, and why?

7b. **Where does ground truth come from?**
   - What annotated datasets exist for onset detection and beat tracking, and are any usable for offline validation of an implementation?
   - Could we synthesise a test corpus with known hit positions — programmed drum patterns rendered to WAV with an annotation sidecar? What does that fail to test that real music would catch?
   - Sentinel supports deterministic paced WAV playback in File mode. How should a scoring harness be built around it?

7c. **Regression testing.**
   - How should a detector be regression-tested so a tuning change can be proven better rather than argued about?
   - What is the minimum useful test corpus size and genre spread?

### 8. Build or Borrow

8a. **What existing implementations should we study or port?**
   - aubio, madmom, Essentia, librosa, BTrack, Mixxx and Serato/Rekordbox beat grids — which are closest to our constraints and what are their core algorithms?
   - Which are permissively licensed enough to port the *approach* from?
   - Where do these libraries put their complexity, and which parts are essential versus incidental?

8b. **What belongs in the Module versus the engine?**
   - Which capabilities would be dramatically better implemented inside Audio In on the CPU (longer retention, phase, mid/side, multi-resolution FFT) rather than reconstructed in a shader?
   - What is the minimal set of engine-side additions that would most improve what a Module can achieve?

## Desired Output

- A recommendation on input representation: Spectrum versus Mel versus both, with the reasoning and the experiment that settles the 12 kHz versus 24 kHz coverage question.
- A ranked comparison of onset detection functions viable with magnitude-only data, with expected quality differences and what phase would add.
- A concrete architecture for region-based instrument isolation, including region shape, weighting, and whether anything beyond band-limiting is required to make snare detection work.
- A recommended tempo estimation method and a recommended beat-phase tracker, with justification against the alternatives, and explicit treatment of the half/double-time problem.
- A pass-by-pass decomposition mapping the chosen algorithms onto parallel and sequential compute passes, with a state-flow diagram and a per-frame cost estimate.
- A required-history analysis: how many hops of ring the tempo and beat stages actually need.
- A design for the spectrogram interface: display transform, region editing model, and the live feedback that makes tuning possible without ground truth.
- An evaluation plan: metrics, tolerance windows, how to construct a test corpus, and how regression testing would work.
- A prioritised list of engine-side asks for Audio In, ordered by how much each would improve achievable quality.
- A phased roadmap from a minimal working replacement for `cryo_pulse` to the full system.
