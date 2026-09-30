"""Minimal stdio client for sentinel-mcp, shared by the Laser Mapping Lab scripts.

Set SENTINEL_MCP to the sentinel-mcp executable if it is not in the default
install location or on PATH. Sentinel must already be running.
"""
import json
import os
import shutil
import subprocess
from pathlib import Path


def _exe():
    env = os.environ.get("SENTINEL_MCP")
    if env:
        return env
    program_files = os.environ.get("ProgramFiles")
    for cand in (shutil.which("sentinel-mcp"),
                 Path(program_files) / "OODLabs" / "Sentinel" / "sentinel-mcp.exe" if program_files else None):
        if cand and Path(cand).exists():
            return str(cand)
    raise SystemExit("sentinel-mcp not found; set SENTINEL_MCP")


class Client:
    def __init__(self):
        self.p = subprocess.Popen([_exe()], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, encoding="utf-8")
        self.i = 0
        self._rpc("initialize", dict(protocolVersion="2024-11-05", capabilities={},
                                     clientInfo=dict(name="laser-mapping-lab", version="1")))
        self._send(dict(jsonrpc="2.0", method="notifications/initialized"))

    def _send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def _rpc(self, method, params):
        self.i += 1
        self._send(dict(jsonrpc="2.0", id=self.i, method=method, params=params))
        while True:
            line = self.p.stdout.readline()
            if not line:
                raise RuntimeError("sentinel-mcp exited")
            data = json.loads(line)
            if data.get("id") == self.i:
                return data

    def call(self, tool, **args):
        res = self._rpc("tools/call", dict(name=tool, arguments=args))
        if "error" in res:
            raise RuntimeError(res["error"])
        texts = [c["text"] for c in res.get("result", {}).get("content", []) if c.get("type") == "text"]
        body = "\n".join(texts)
        try:
            return json.loads(body)
        except ValueError:
            return body

    # conveniences
    def port(self, pipeline, port, n):
        return self.call("sentinel_pipeline", action="capture_data_port", pipeline_id=pipeline,
                         port_name=port, max_elements=n)["elements"]

    def set(self, path, value):
        return self.call("sentinel_state", action="set", path=path, value=value)

    def set_many(self, values):
        return self.call("sentinel_state", action="set_many", values=values)

    def close(self):
        self.p.terminate()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()
