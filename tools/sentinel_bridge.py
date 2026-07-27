#!/usr/bin/env python3
"""A persistent sentinel-mcp session for scripted proofs.

tools/sentinel_mcp_call.py spawns the server, does one call, and tears it down.
That is fine for a single lookup and useless for a proof that has to sample live
state over twenty seconds: process startup dominates, and the sampling cadence
ends up measuring the harness rather than the graph.

This keeps one server open for the life of the script.
"""

from __future__ import annotations

import json
import subprocess

SERVER = r"C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe"


class Sentinel:
    def __init__(self, server: str = SERVER):
        self._next_id = 1
        self.proc = subprocess.Popen(
            [server],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            bufsize=1,
        )
        self._rpc("initialize", {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "sentinel-bridge", "version": "1.0"},
        })
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _send(self, payload) -> None:
        self.proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.proc.stdin.flush()

    def _rpc(self, method: str, params):
        rid = self._next_id
        self._next_id += 1
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError(
                    f"sentinel-mcp closed before responding: {self.proc.stderr.read()}"
                )
            msg = json.loads(line)
            if msg.get("id") == rid:
                if "error" in msg:
                    raise RuntimeError(f"{method} failed: {msg['error']}")
                return msg.get("result", {})

    def call(self, tool: str, **arguments):
        """Call an MCP tool and return its parsed JSON payload.

        Sentinel returns tool results as a text content block holding JSON, so
        the parse happens here rather than at every call site.
        """
        res = self._rpc("tools/call", {"name": tool, "arguments": arguments})
        parts = res.get("content", [])
        if not parts:
            return res
        text = parts[0].get("text", "")
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text

    def get(self, path: str) -> float:
        """Read one StateTree value as a float."""
        res = self.call("sentinel_state", action="get", path=path)
        return float(res["value"])

    def set(self, path: str, value) -> None:
        self.call("sentinel_state", action="set", path=path, value=value)

    def capture(self, pipeline_id: str, filepath: str) -> str:
        res = self.call("sentinel_capture", action="pipeline",
                        pipeline_id=pipeline_id, filepath=filepath)
        return res["filepath"]

    def close(self) -> None:
        self.proc.terminate()
        try:
            self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.proc.kill()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False
