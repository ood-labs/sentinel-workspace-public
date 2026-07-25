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
        d = self.sen.data_port(self.detector, self.hits_port, max_elements=512)
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
        gen_before = self.generation()
        self.sen.set(self._audio_param("restart_file"), 1)

        # Assert the producer is advancing generations into the detector before
        # any scoring happens, per knowledge/audio-reactivity.md.
        time.sleep(0.5)
        if self.generation() <= gen_before:
            raise SentinelError(
                f"{self.audio}: generation not advancing after restart_file "
                f"({gen_before}); playback did not start")

        by_serial: dict[int, dict] = {}
        samples: list[dict] = []
        pos_trace: list[int] = []
        t0 = time.time()
        last_pos, stalled = -1, 0
        started = False

        while True:
            time.sleep(self.poll_s)
            pos = self.head_sample_position()
            pos_trace.append(pos)

            for h in self.read_hits():
                by_serial[int(h["onset_serial"])] = h

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

            # Completion: playback head reached the end of the WAV, or stopped
            # advancing for several consecutive polls after it had started.
            if started and pos >= duration_samples - EOF_SLACK_SAMPLES:
                break
            if started and stalled >= 4:
                break
            if time.time() - t0 > timeout_s:
                break

        # Final sweep so the last hits before end-of-file are not missed.
        for h in self.read_hits():
            by_serial[int(h["onset_serial"])] = h

        hits = [by_serial[s] for s in sorted(by_serial)]

        # The detector keeps firing between configure_file and restart_file, so
        # the ring can still hold records from the PREVIOUS playthrough. Those
        # carry lower serials but HIGHER sample positions. Playback within one
        # run is monotonic, so the last backwards step in sample_position marks
        # the restart; drop everything before it.
        cut = 0
        for i in range(1, len(hits)):
            if int(hits[i]["sample_position"]) < int(hits[i - 1]["sample_position"]):
                cut = i
        dropped, hits = cut, hits[cut:]

        return {
            "hits": hits,
            "pre_restart_dropped": dropped,
            "position_trace": pos_trace,
            "samples": samples,
            "elapsed_s": round(time.time() - t0, 2),
            "final_sample_position": last_pos,
            "completed": bool(started and last_pos >= duration_samples - EOF_SLACK_SAMPLES),
        }


def reset_detector(sen: Sentinel, detector_id: str, audio_id: str,
                   mel_slot: int = 2, gate_expr: bool = True,
                   params: dict | None = None, timeout_s: float = 30.0) -> None:
    """force_reload the detector and put back everything reload drops.

    force_reload drops data-port links, clears ref() drivers and resets params
    to manifest defaults (docs/lessons.md, 2026-07-08). Video links survive.
    The harness therefore re-adds the link, re-applies the expression, restores
    non-default params, and asserts the generation is advancing again.
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
