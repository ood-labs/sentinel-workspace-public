#!/usr/bin/env python3
"""Minimal ZMQ client for Sentinel's automation bridge, plus the Phase 2
File-mode run harness.

The scoring harness must be able to run standalone and repeatedly, so it talks
to Sentinel's IPC listener (tcp://127.0.0.1:5555) directly rather than through
an agent. The envelope is {"cmd": "<COMMAND>", ...args} -> {"status", "data"}.
Command names and their accepted args come from GET_CAPABILITIES.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import zmq

ENDPOINT = "tcp://127.0.0.1:5555"

# head_sample_position() reads Mel ring slot 0, which only refreshes once per
# 64-hop wrap (16384 samples), so the last observable position legitimately
# trails the true end of file.
EOF_SLACK_SAMPLES = 32768
# Seconds of throwaway playback before the scored run, so the detector's
# persistent whitening peaks adapt to THIS pattern instead of inheriting the
# previous one's. See the note in run_pattern.
PREROLL_S = 2.0

# Lane ids emitted by the `Hits` export contract (see
# modules/cryo_pulse_baseline/manifest.yaml).
LANE_KICK, LANE_SNARE, LANE_HAT, LANE_BEAT = 0, 1, 2, 3
LANE_NAMES = {LANE_KICK: "kick", LANE_SNARE: "snare", LANE_HAT: "hat", LANE_BEAT: "beat"}


class SentinelError(RuntimeError):
    pass


class Sentinel:
    def __init__(self, endpoint: str = ENDPOINT, timeout_ms: int = 8000):
        self._ctx = zmq.Context.instance()
        self._endpoint = endpoint
        self._timeout = timeout_ms

    def call(self, cmd: str, **args):
        s = self._ctx.socket(zmq.REQ)
        s.setsockopt(zmq.RCVTIMEO, self._timeout)
        s.setsockopt(zmq.SNDTIMEO, self._timeout)
        s.setsockopt(zmq.LINGER, 0)
        s.connect(self._endpoint)
        try:
            s.send_string(json.dumps({"cmd": cmd, **args}))
            reply = json.loads(s.recv_string())
        except zmq.error.Again as exc:
            raise SentinelError(f"{cmd}: timed out after {self._timeout} ms") from exc
        finally:
            s.close()
        if reply.get("status") != "ok":
            raise SentinelError(f"{cmd}: {reply.get('msg', reply)}")
        return reply.get("data")

    # -- convenience -------------------------------------------------------

    def ping(self) -> bool:
        return self.call("PING") == "PONG"

    def get(self, path: str):
        return self.call("GET_STATE_VALUE", path=path)

    def get_float(self, path: str) -> float:
        v = self.get(path)
        if isinstance(v, dict):
            v = v.get("value")
        return float(v)

    def set(self, path: str, value):
        return self.call("SET_STATE_VALUE", path=path, value=value)

    def set_many(self, values: dict):
        return self.call("SET_STATE_VALUES", values=values)

    def data_port(self, pipeline: str, port_name: str, max_elements: int = 512):
        return self.call(
            "CAPTURE_DATA_PORT",
            pipeline=pipeline,
            port_name=port_name,
            max_elements=max_elements,
        )

    def pipeline_info(self, pipeline: str):
        return self.call("GET_PIPELINE_INFO", pipeline=pipeline)

    def control_output(self, pipeline: str, name: str) -> float:
        return self.get_float(f"/sentinel/pipelines/{pipeline}/control_outputs/{name}")


# ---------------------------------------------------------------------------
# File-mode run harness
# ---------------------------------------------------------------------------


def cut_pre_restart(by_serial: dict) -> tuple[int, list[dict]]:
    """Drop records left over from the previous playthrough, then order by time.

    A few records land between reading the watermark and the restart taking
    effect. Those carry the PREVIOUS playthrough's high sample positions, so the
    restart boundary is found as a backwards step in sample position and
    everything before it is dropped.

    THE SCAN MUST RUN IN DETECTION ORDER, PER LANE, WHICH IS WHY THIS IS A
    SEPARATE FUNCTION WITH ITS OWN TEST. A backwards step only exists while
    records are ordered by serial. Sorting by sample position first makes one
    impossible, so the scan silently becomes a no-op and every stale record
    survives as a false positive near the end of the file. Measured when the
    beat ring's separate serial sequence forced a sort: twelve per-lane F1 drops
    between 0.011 and 0.022, the whole regression gate, from a harness change
    with no detector change behind it.

    Per lane because the two rings carry independent serial sequences, so their
    restart boundaries are found separately and only then merged. `by_serial` is
    keyed (lane_id, onset_serial); tuple ordering sorts by lane then serial,
    which is exactly the order the scan needs.

    Returns (records_dropped, hits_ordered_by_sample_position).
    """
    dropped = 0
    kept: list[dict] = []
    for lane in sorted({k[0] for k in by_serial}):
        seq = [h for k, h in sorted(by_serial.items()) if k[0] == lane]
        cut = 0
        for i in range(1, min(len(seq), 12)):
            if int(seq[i]["sample_position"]) < int(seq[i - 1]["sample_position"]):
                cut = i
        dropped += cut
        kept.extend(seq[cut:])

    # Only now ordered by sample position: two independent serial sequences do
    # not interleave into one meaningful order, and the scorer times everything
    # by sample position anyway.
    return dropped, sorted(kept, key=lambda h: int(h["sample_position"]))


class AudioRunner:
    """Drives an Audio In node through one corpus pattern and collects Hits.

    Completion is detected by `sample_position` reaching the WAV length, per the
    phase doc: File mode is *paced* playback with no documented position or
    completion field, so wall-clock timing and MCP poll order are never used as
    the timebase.
    """

    def __init__(self, sen: Sentinel, audio_id: str, detector_id: str,
                 hits_port: str = "Hits", poll_s: float = 1.0,
                 fft_size: str = "2048", hop_size: str = "256"):
        self.sen = sen
        self.audio = audio_id
        self.detector = detector_id
        self.hits_port = hits_port
        self.poll_s = poll_s
        # Held on the runner so run_pattern's internal reconfigure cannot
        # silently revert an explicitly requested analysis setting.
        self.fft_size = fft_size
        self.hop_size = hop_size

    def _audio_param(self, name: str) -> str:
        return f"/sentinel/pipelines/{self.audio}/parameters/{name}"

    def head_sample_position(self) -> int:
        d = self.sen.data_port(self.audio, "Mel Bands", max_elements=1)
        els = d.get("elements") or []
        return int(els[0]["sample_position"]) if els else -1

    def generation(self) -> int:
        return int(self.sen.data_port(self.audio, "Mel Bands", max_elements=1)["generation"])

    def configure_file(self, wav_path: Path, fft_size: str | None = None,
                       hop_size: str | None = None) -> None:
        if fft_size is not None:
            self.fft_size = fft_size
        if hop_size is not None:
            self.hop_size = hop_size
        self.sen.set_many({
            self._audio_param("file_path"): str(wav_path).replace("\\", "/"),
            self._audio_param("source_mode"): "File",
            self._audio_param("fft_size"): self.fft_size,
            self._audio_param("hop_size"): self.hop_size,
        })

    def read_hits(self) -> list[dict]:
        # 1024, not 512: since 2E2 the port carries the picker's onsets in slots
        # 0..511 and the PLL's beats in 512..1023. Reading only the first half
        # would silently return zero beats and score CMLc/AMLc as 0.
        d = self.sen.data_port(self.detector, self.hits_port, max_elements=1024)
        return [e for e in (d.get("elements") or []) if int(e.get("onset_serial", 0)) > 0]

    def run_pattern(self, wav_path: Path, duration_samples: int,
                    settle_s: float = 0.6, timeout_s: float = 90.0,
                    extra_polls: dict | None = None) -> dict:
        """Play one pattern start to finish, accumulating Hits by serial.

        `extra_polls` maps a label -> control-output name on the detector; each
        is sampled on every poll so tempo can be summarised over the run.
        """
        self.configure_file(wav_path)
        time.sleep(settle_s)

        # WHITENING PRE-ROLL. force_reload does not clear `persistent: true`
        # buffers, so the detector's per-bin running peaks arrive carrying
        # whatever the PREVIOUS pattern left in them. Measured: sparse_90 scored
        # 0.636/0.636/0.933 on the run that followed syncopated_funk_105 and
        # 0.609/0.667/0.903 on two consecutive runs that followed itself --
        # identical settings, identical code, ~0.03 apart on every lane, purely
        # from inherited state.
        #
        # Playing the pattern once before the scored run lets the peaks adapt to
        # its own spectrum, so the scored pass starts from the same place no
        # matter what ran before it. whiten_decay 0.992 at 187.5 hops/s is a
        # 0.67 s time constant, so PREROLL_S is three of them.
        self.sen.set(self._audio_param("restart_file"), 1)
        time.sleep(PREROLL_S)

        gen_before = self.generation()

        # Serial watermark. The detector's onset serial is monotonic and
        # survives across playthroughs, so any record at or below the serial
        # standing just before restart belongs to a PREVIOUS run. This is exact,
        # unlike inferring the boundary from a backwards step in
        # sample_position, which breaks as soon as the ring wraps within a run.
        # PER LANE. Onsets and beats carry independent serial sequences, so one
        # global maximum would be the larger of the two and would discard every
        # record of the other stream for the whole run.
        watermark: dict[int, int] = {}
        try:
            for h in self.read_hits():
                ln = int(h["lane_id"])
                watermark[ln] = max(watermark.get(ln, 0), int(h["onset_serial"]))
        except SentinelError:
            watermark = {}

        self.sen.set(self._audio_param("restart_file"), 1)

        # Assert the producer is advancing generations into the detector before
        # any scoring happens, per knowledge/audio-reactivity.md.
        time.sleep(0.5)
        if self.generation() <= gen_before:
            raise SentinelError(
                f"{self.audio}: generation not advancing after restart_file "
                f"({gen_before}); playback did not start")

        by_serial: dict[tuple[int, int], dict] = {}
        samples: list[dict] = []
        pos_trace: list[int] = []
        t0 = time.time()
        last_pos, stalled = -1, 0
        started = False
        reached_eof = False

        while True:
            time.sleep(self.poll_s)
            pos = self.head_sample_position()
            pos_trace.append(pos)

            for h in self.read_hits():
                key = (int(h["lane_id"]), int(h["onset_serial"]))
                if key[1] > watermark.get(key[0], 0):
                    by_serial[key] = h

            if extra_polls:
                row = {"sample_position": pos}
                for label, co in extra_polls.items():
                    try:
                        row[label] = self.sen.control_output(self.detector, co)
                    except SentinelError:
                        row[label] = float("nan")
                samples.append(row)

            if pos > 0:
                started = True
            if pos == last_pos:
                stalled += 1
            else:
                stalled = 0
            last_pos = pos

            # Completion: the playback head must STOP, not merely get close.
            #
            # Breaking the moment a poll lands inside the EOF window silently
            # truncated the run. The window is EOF_SLACK_SAMPLES (0.68 s at
            # 48 kHz) and the poll cadence is 1 s, so the break point fell
            # anywhere in the last second of audio, and every onset after it was
            # simply never analysed. Measured on tempo_ramp_120_132: two
            # otherwise identical runs broke 13312 samples apart and differed by
            # exactly one beat -- one kick, one snare, one hat -- moving snare F1
            # by 0.033 with ZERO change in false positives. That is three times
            # the standing 0.01 regression tolerance, arriving from nothing but
            # poll phase, and it lands hardest on the pattern whose onsets get
            # densest at the end.
            #
            # File mode goes Inactive at end of file, so the head freezes and the
            # stall path fires. Two stalled polls after entering the EOF window
            # is enough for the remaining audio to play out and the analyser to
            # drain; the pre-EOF stall threshold stays at 4 to keep tolerating a
            # transient hiccup mid-pattern.
            if started and pos >= duration_samples - EOF_SLACK_SAMPLES:
                reached_eof = True
            if started and stalled >= (2 if reached_eof else 4):
                break
            if time.time() - t0 > timeout_s:
                break

        # Final sweep so the last hits before end-of-file are not missed.
        for h in self.read_hits():
            key = (int(h["lane_id"]), int(h["onset_serial"]))
            if key[1] > watermark.get(key[0], 0):
                by_serial[key] = h

        dropped, hits = cut_pre_restart(by_serial)

        return {
            "hits": hits,
            "pre_restart_dropped": dropped,
            "position_trace": pos_trace,
            "samples": samples,
            "elapsed_s": round(time.time() - t0, 2),
            "final_sample_position": last_pos,
            "completed": bool(started and last_pos >= duration_samples - EOF_SLACK_SAMPLES),
        }


def manifest_defaults(sen: Sentinel, detector_id: str) -> dict:
    """Every writable numeric parameter's manifest default, from the module dir.

    Read from the manifest on disk rather than the live `default` field so the
    committed file is the authority and a drifted tree cannot vote. `project_dir`
    is a string and `gate_level` is expression-driven, so both are skipped.
    """
    import yaml

    pdir = sen.get(f"/sentinel/pipelines/{detector_id}/parameters/project_dir")
    if isinstance(pdir, dict):
        pdir = pdir.get("value")
    path = Path(str(pdir)) / "manifest.yaml"
    if not path.is_file():
        raise SentinelError(f"{detector_id}: no manifest at {path}")

    man = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    out = {}
    for p in man.get("parameters") or []:
        name, dflt = p.get("name"), p.get("default")
        if name in (None, "project_dir", "gate_level") or dflt is None:
            continue
        if isinstance(dflt, (int, float)) and not isinstance(dflt, bool):
            out[name] = float(dflt)
    return out


def reset_detector(sen: Sentinel, detector_id: str, audio_id: str,
                   mel_slot: int = 2, gate_expr: bool = True,
                   params: dict | None = None, timeout_s: float = 30.0) -> None:
    """force_reload the detector, force it to manifest defaults, put back what
    reload drops.

    force_reload drops data-port links and clears ref() drivers; video links
    survive. It does NOT reset parameters to manifest defaults, whatever
    docs/lessons.md said on 2026-07-08 -- a live `beat_snap` of 0.15 survived a
    reload with a manifest default of 0.0 and silently scored the whole corpus
    against a mechanism that ships disabled, dropping mean kick F1 by 0.3 and
    reading ~103 BPM on every pattern. The table looked like a real regression
    from the change under test.

    So defaults are now WRITTEN, not assumed. Every scored run starts from the
    committed manifest plus an explicit `params` override, and nothing a
    previous experiment left in the tree can reach the numbers.
    """
    sen.call("FORCE_RELOAD", pipeline_id=detector_id)

    t0 = time.time()
    while time.time() - t0 < timeout_s:
        st = sen.call("COMPILE_STATUS", pipeline_id=detector_id)
        if st.get("state") == "ok":
            break
        if st.get("state") == "error":
            raise SentinelError(f"reload failed: {st.get('error')}")
        time.sleep(0.3)
    else:
        raise SentinelError("reload timed out")

    sen.call("ADD_LINK", from_entity=audio_id, from_slot=mel_slot,
             to_entity=detector_id, to_slot=0)

    defaults = manifest_defaults(sen, detector_id)
    if defaults:
        sen.set_many({f"/sentinel/pipelines/{detector_id}/parameters/{k}": v
                      for k, v in defaults.items()})

    if gate_expr:
        sen.call("SET_EXPRESSION",
                 path=f"/sentinel/pipelines/{detector_id}/parameters/gate_level",
                 expression=f'ref("{audio_id}/control_outputs/level")')

    if params:
        sen.set_many({f"/sentinel/pipelines/{detector_id}/parameters/{k}": v
                      for k, v in params.items()})

    # Assert the detector is actually cooking again, and that the producer is
    # still advancing generations into it. Uses framesProcessed rather than a
    # data-output generation so this works for detectors with no data_outputs
    # (the original cryo_pulse publishes control_outputs only).
    def frames() -> int:
        return int(sen.pipeline_info(detector_id)["stats"]["framesProcessed"])

    # Note: producer generations are NOT asserted here. File mode stops
    # publishing at end-of-file, so between runs the generation is legitimately
    # frozen. run_pattern() asserts it is advancing immediately after
    # restart_file, which is the point the phase doc actually cares about.
    f0 = frames()
    time.sleep(1.0)
    f1 = frames()
    if f1 <= f0:
        raise SentinelError(
            f"{detector_id}: not cooking after reload (frames {f0} -> {f1})")
