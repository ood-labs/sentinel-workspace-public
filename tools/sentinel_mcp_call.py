import json
import subprocess
import sys


SERVER = r"C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe"


def send(proc, payload):
    proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
    proc.stdin.flush()


def receive(proc, request_id):
    while True:
        line = proc.stdout.readline()
        if not line:
            stderr = proc.stderr.read()
            raise RuntimeError(f"sentinel-mcp closed before response: {stderr}")
        message = json.loads(line)
        if message.get("id") == request_id:
            return message


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: sentinel_mcp_call.py tools/list | <tool-name> [json-args]")

    proc = subprocess.Popen(
        [SERVER],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        bufsize=1,
    )
    try:
        send(
            proc,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "clientInfo": {"name": "codex-workspace-bridge", "version": "1.0"},
                },
            },
        )
        receive(proc, 1)
        send(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})

        if sys.argv[1] == "tools/list":
            method = "tools/list"
            params = {}
        else:
            raw_args = (
                sys.stdin.read()
                if len(sys.argv) > 2 and sys.argv[2] == "-"
                else (sys.argv[2] if len(sys.argv) > 2 else "{}")
            )
            method = "tools/call"
            params = {
                "name": sys.argv[1],
                "arguments": json.loads(raw_args),
            }

        send(proc, {"jsonrpc": "2.0", "id": 2, "method": method, "params": params})
        print(json.dumps(receive(proc, 2), indent=2))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()


if __name__ == "__main__":
    main()
