#!/usr/bin/env python3
"""Run a compact live sanity check for Interaction Lab's Data Scope.

Load ``interaction_lab.sentinel`` and play meaningful audio through the Windows
default playback endpoint before running this script. The script keeps one
bundled Sentinel MCP process open, verifies that the Audio In and Data Scope
nodes are healthy, checks that the scope drains Spectrum generations at the
stream rate, and measures a captured plot. It restores the original span.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from data_scope_measure import measure

PIPE = "Data_Scope"
AUDIO = "Scope_Audio"
CO = f"/sentinel/pipelines/{PIPE}/control_outputs"
PARAM = f"/sentinel/pipelines/{PIPE}/parameters"


def default_server() -> Path:
    """Resolve the MCP executable from this workspace's own connection file."""
    workspace = Path(__file__).resolve().parents[3]
    config_path = workspace / ".mcp.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    server = config["mcpServers"]["sentinel-mcp"]["command"]
    return Path(server)


class Sentinel:
    """Minimal persistent MCP stdio client for this project-local check."""

    def __init__(self, server: Path) -> None:
        self._next_id = 1
        self.proc = subprocess.Popen(
            [str(server)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            bufsize=1,
        )
        self._rpc(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "data-scope-proof", "version": "1.0"},
            },
        )
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _send(self, payload: dict) -> None:
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.proc.stdin.flush()

    def _rpc(self, method: str, params: dict):
        request_id = self._next_id
        self._next_id += 1
        self._send(
            {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
        )
        assert self.proc.stdout is not None
        while True:
            line = self.proc.stdout.readline()
            if not line:
                stderr = self.proc.stderr.read() if self.proc.stderr else ""
                raise RuntimeError(f"sentinel-mcp closed before responding: {stderr}")
            message = json.loads(line)
            if message.get("id") != request_id:
                continue
            if "error" in message:
                raise RuntimeError(f"{method} failed: {message['error']}")
            return message.get("result", {})

    def call(self, tool: str, **arguments):
        result = self._rpc("tools/call", {"name": tool, "arguments": arguments})
        content = result.get("content", [])
        if not content:
            return result
        text = content[0].get("text", "")
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text

    def get(self, path: str) -> float:
        return float(self.call("sentinel_state", action="get", path=path)["value"])

    def set(self, path: str, value) -> None:
        self.call("sentinel_state", action="set", path=path, value=value)

    def close(self) -> None:
        self.proc.terminate()
        try:
            self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.proc.kill()

    def __enter__(self):
        return self

    def __exit__(self, *_exc) -> bool:
        self.close()
        return False


def require_healthy(client: Sentinel, pipeline_id: str) -> None:
    info = client.call("sentinel_pipeline", action="info", pipeline_id=pipeline_id)
    stats = info.get("stats", {})
    if not stats.get("healthy"):
        raise RuntimeError(
            f"{pipeline_id} is not healthy: {stats.get('health_reasons', [])}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", type=Path, default=default_server())
    parser.add_argument("--settle", type=float, default=2.0)
    parser.add_argument("--keep", action="store_true")
    args = parser.parse_args()

    if not args.server.is_file():
        raise FileNotFoundError(f"Sentinel MCP server not found: {args.server}")

    capture_dir = Path(tempfile.mkdtemp(prefix="sentinel-data-scope-"))
    capture_path = capture_dir / "data_scope.png"
    failures: list[str] = []

    with Sentinel(args.server) as client:
        require_healthy(client, AUDIO)
        require_healthy(client, PIPE)
        original_span = client.get(f"{PARAM}/span_seconds")
        try:
            drained = client.get(f"{CO}/drained")
            hop_dt = client.get(f"{CO}/hop_dt")
            if drained <= 0 or hop_dt <= 0:
                failures.append(
                    f"no live Spectrum generations: drained={drained}, hop_dt={hop_dt}"
                )

            for span in (1.0, 3.0):
                client.set(f"{PARAM}/span_seconds", span)
                time.sleep(args.settle)
                shown = client.get(f"{CO}/samples_shown")
                expected = span / max(hop_dt, 1e-9)
                error = abs(shown - expected) / max(expected, 1e-9)
                if error >= 0.03:
                    failures.append(
                        f"{span:g}s span shows {shown:.1f} samples; "
                        f"expected {expected:.1f} ({error * 100:.1f}% error)"
                    )

            before = client.get(f"{CO}/write_idx")
            started = time.monotonic()
            time.sleep(max(args.settle, 2.0))
            elapsed = time.monotonic() - started
            after = client.get(f"{CO}/write_idx")
            observed_rate = (after - before) / elapsed
            expected_rate = 1.0 / max(hop_dt, 1e-9)
            rate_error = abs(observed_rate - expected_rate) / expected_rate
            if rate_error >= 0.08:
                failures.append(
                    f"write rate {observed_rate:.1f}/s; expected "
                    f"{expected_rate:.1f}/s ({rate_error * 100:.1f}% error)"
                )

            result = client.call(
                "sentinel_capture",
                action="pipeline",
                pipeline_id=PIPE,
                filepath=str(capture_path),
            )
            actual_capture = Path(result.get("filepath", capture_path))
            metrics = measure(str(actual_capture))
            if max(lane["peak_height_frac"] for lane in metrics["lanes"]) <= 0.02:
                failures.append("captured scope contains no measurable signal")
        finally:
            client.set(f"{PARAM}/span_seconds", original_span)

    if failures:
        for failure in failures:
            print(f"FAIL  {failure}")
        print(f"capture: {capture_path}")
        return 1

    print("PASS  Data Scope is healthy, draining live Spectrum data, and plotting it.")
    if args.keep:
        print(f"capture: {capture_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
