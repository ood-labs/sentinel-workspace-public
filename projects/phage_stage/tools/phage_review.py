"""Review PHAGE looks on the live rig through the Surface's rig_command seam.

Talks to a running Sentinel over its bundled MCP server (stdio), recalls looks exactly as the desk
does, and writes stills to captures/looks/ (gitignored).

    python tools/phage_review.py recall complete 1           recall one look, print the ack
    python tools/phage_review.py steady                      paste neutral effect rows (no lanes, no
                                                             motion, strobes on GLOW) for repeatable frames
    python tools/phage_review.py sheet complete full.png     contact sheet of a bank (BUILD looks are
                                                             captured further into their 16-beat ramp)
    python tools/phage_review.py strip effects 13,14 f.png   frames 1.5 / 1.75 / 2.0 / 2.25 s after
                                                             each recall, one row per look
    python tools/phage_review.py mounts                      re-capture tools/mounts_rest.json from the
                                                             Kinetics Mounts port at the Rest pose
                                                             (after changing the anatomy or counts)

The MCP server comes from the workspace's own .mcp.json; set SENTINEL_MCP to override it.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATE = "/sentinel/pipelines/Phage_Surface/state/"
OUT = ROOT / "captures" / "looks"


def server() -> str:
    """The sentinel-mcp executable: SENTINEL_MCP, else this workspace's own connection file."""
    if os.environ.get("SENTINEL_MCP"):
        return os.environ["SENTINEL_MCP"]
    config = json.loads((ROOT.parents[1] / ".mcp.json").read_text(encoding="utf-8"))
    return config["mcpServers"]["sentinel-mcp"]["command"]


def call(tool: str, args: dict):
    """One MCP tool call; returns the parsed JSON result (or {'raw': text})."""
    p = subprocess.Popen([server()], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         text=True, encoding="utf-8", bufsize=1)

    def send(message):
        p.stdin.write(json.dumps(message) + "\n")
        p.stdin.flush()

    def receive(request_id):
        while True:
            line = p.stdout.readline()
            if not line:
                raise RuntimeError(p.stderr.read())
            try:
                value = json.loads(line)
            except ValueError:
                continue
            if value.get("id") == request_id:
                return value

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "phage_review", "version": "1"}}})
        receive(1)
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": tool, "arguments": args}})
        text = receive(2)["result"]["content"][0]["text"]
        try:
            return json.loads(text)
        except ValueError:
            return {"raw": text}
    finally:
        p.kill()


def get(path: str):
    result = call("sentinel_state", {"action": "get", "path": path})
    return result.get("value", result)


def command(*args, timeout: float = 6.0) -> str:
    """Send one rig_command with a fresh id and wait for its ack."""
    cid = f"rv{int(time.time() * 1000) % 10000000}"
    call("sentinel_state", {"action": "set", "path": STATE + "rig_command", "value": "|".join((cid,) + tuple(map(str, args)))})
    start = time.time()
    ack = ""
    while time.time() - start < timeout:
        ack = str(get(STATE + "rig_command_ack"))
        if ack.startswith(cid + ":"):
            break
        time.sleep(.15)
    return ack


def recall(kind: str, slot: int, timeout: float = 8.0) -> str:
    """Recall a look and wait until the Surface reports it applied."""
    command("preset", "recall", kind, slot)
    want = f"Recalled {kind} {slot} /"
    start = time.time()
    message = str(get(STATE + "programmer_message"))
    while not message.startswith(want) and time.time() - start < timeout:
        time.sleep(.2)
        message = str(get(STATE + "programmer_message"))
    return message


def capture(path: Path, pipeline: str = "Phage_Renderer") -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    call("sentinel_capture", {"action": "pipeline", "pipeline_id": pipeline, "filepath": str(path)})
    return path


def steady() -> None:
    """Neutral effect rows in the live programmer: every fixture holds its static, strobes GLOW."""
    sys.path.insert(0, str(ROOT / "tools"))
    import phage_looks as looks
    rows = {f["slot"]: {k: looks.DEFAULT[k] for k in looks.EFFECT_F} for f in looks.FX if not f["unused"]}
    for f in looks.STROBES:
        rows[f["slot"]]["look"] = looks.STROBE["GLOW"]
    for bank, text in enumerate(looks.pack(rows, looks.EFFECT_F)):
        print("steady bank", bank, command("rows", "effects", bank, text))


def mounts(settle: float = 10.0) -> None:
    """Hold the truss at Rest, capture every Kinetics mount and write tools/mounts_rest.json."""
    drive = "/sentinel/pipelines/Phage_Kinetics/parameters/drive"
    before = int(float(get(drive)))
    call("sentinel_state", {"action": "set", "path": drive, "value": 3})       # Programmer, Manual, Demo, Rest
    try:
        time.sleep(settle)                                                      # the slowest axis is ~1 m/s
        port = call("sentinel_pipeline", {"action": "capture_data_port", "pipeline_id": "Phage_Kinetics",
                                          "port_name": "Mounts", "max_elements": 248})
    finally:
        call("sentinel_state", {"action": "set", "path": drive, "value": before})
    elements = port.get("elements") or []
    assert len(elements) == 248, f"expected 248 mounts, got {len(elements)}"
    def rounded(v):
        return [round(x, 5) for x in v] if isinstance(v, list) else round(v, 5)
    data = {"source": "Phage_Kinetics Mounts at drive=Rest", "generation": port.get("generation"),
            "mounts": [{k: rounded(v) for k, v in sorted(e.items())} for e in elements]}
    path = ROOT / "tools" / "mounts_rest.json"
    path.write_text(json.dumps(data, indent=1), newline="\n")
    print("wrote", path, "- now run tools/phage_rig.py and tools/phage_looks.py")


def titles(kind: str) -> list[str]:
    source = (ROOT / "scripts" / "show" / "preset_titles.luau").read_text()
    segment = source.split(kind + "={", 1)[1].split("}", 1)[0]
    return [s.strip().strip('"') for s in segment.split(",")]


def _tile(rows, out: Path, columns: int, tile=(480, 270)):
    from PIL import Image, ImageDraw, ImageFont
    tw, th = tile
    image = Image.new("RGB", (columns * tw, len(rows) * (th + 24)), (8, 8, 9))
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("consola.ttf", 16)
    except OSError:
        font = ImageFont.load_default()
    for r, (label, frames) in enumerate(rows):
        y = r * (th + 24)
        if label:
            draw.text((6, y + 3), label, fill=(210, 206, 200), font=font)
        for c, (caption, seconds, path) in enumerate(frames):
            image.paste(Image.open(path).convert("RGB").resize((tw, th), Image.LANCZOS), (c * tw, y + 24))
            if caption:
                draw.text((c * tw + 6, y + 3), caption, fill=(210, 206, 200), font=font)
            draw.text((c * tw + tw - 70, y + 3), f"+{seconds:.1f}s", fill=(128, 126, 124), font=font)
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    print("wrote", out)


def sheet(kind: str, out: Path, settle: float = 3.0, build_settle: float = 7.0) -> None:
    """Every slot of a bank, four per row; BUILD looks (9-12 of effects/complete) settle longer."""
    names = titles(kind)
    tiles = []
    for slot in range(1, 17):
        wait = build_settle if kind in ("effects", "complete") and 9 <= slot <= 12 else settle
        print(slot, recall(kind, slot))
        start = time.time()
        while time.time() - start < wait:
            time.sleep(.02)
        tiles.append((f"{kind.upper()} {slot:02d} {names[slot - 1]}", time.time() - start,
                      capture(OUT / f"{out.stem}_tiles" / f"{kind}_{slot:02d}.png")))
    _tile([("", tiles[i:i + 4]) for i in range(0, 16, 4)], out, 4)


def strip(kind: str, slots: list[int], out: Path, times=(1.5, 1.75, 2.0, 2.25)) -> None:
    """Frames at fixed times after each recall: one row per look, to judge motion and pulses."""
    names = titles(kind)
    rows = []
    for slot in slots:
        print(slot, recall(kind, slot))
        start = time.time()
        frames = []
        for j, t in enumerate(times):
            while time.time() - start < t:
                time.sleep(.02)
            frames.append(("" if j else f"{kind.upper()} {slot}  {names[slot - 1]}", time.time() - start,
                           capture(OUT / f"{out.stem}_frames" / f"{kind}_{slot:02d}_{j}.png")))
        rows.append(("", frames))
    _tile(rows, out, len(times))


def main(argv: list[str]) -> None:
    if not argv:
        print(__doc__)
        return
    verb = argv[0]
    if verb == "recall":
        print(recall(argv[1], int(argv[2])))
    elif verb == "steady":
        steady()
    elif verb == "mounts":
        mounts()
    elif verb == "sheet":
        sheet(argv[1], OUT / argv[2])
    elif verb == "strip":
        strip(argv[1], [int(s) for s in argv[2].split(",")], OUT / argv[3])
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
