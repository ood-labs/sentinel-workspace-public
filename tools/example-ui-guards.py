"""Project-agnostic gesture and pixel guards for Phase 5 example panels.

The harness intentionally proves both halves of an authored control:

* the host gesture changes the bound parameter; and
* pixels inside the manifest rectangle move or change state with that value.

Run ``python tools/example-ui-guards.py --help`` for the offline bundle check,
live build discovery, and per-project gesture commands.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time

from PIL import Image, ImageChops, ImageDraw
import yaml


ROOT = Path(__file__).resolve().parents[1]
SERVER = os.environ.get(
    "SENTINEL_MCP",
    r"C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe",
)
SUI3_HEADERS = (
    "sui3_core.hlsli",
    "sui3_controls.hlsli",
    "sui3_text.hlsli",
    "sui3_theme.hlsli",
    "sui3_events.hlsli",
)
PROJECTS = {
    "topographic_hud": {
        "project": "projects/topographic_hud/topographic_hud.sentinel",
        "targets": {"signal": "projects/topographic_hud/modules/signal"},
    },
    "strata": {
        "project": "projects/strata/strata.sentinel",
        "targets": {"strata_control": "projects/strata/modules/strata_control"},
    },
    "desert_totem": {
        "project": "projects/desert_totem/desert_totem.sentinel",
        "targets": {"dada_control": "projects/desert_totem/modules/dada_control"},
    },
    "living_room_sdf": {
        "project": "projects/living_room_sdf/living_room_sdf.sentinel",
        "targets": {
            "LR_Furnishings": "projects/living_room_sdf/modules/LR_Furnishings",
            "LR_Lighting": "projects/living_room_sdf/modules/LR_Lighting",
            "LR_Architecture": "projects/living_room_sdf/modules/LR_Architecture",
        },
    },
    "showcase_gallery": {
        "project": "projects/showcase_gallery/showcase_gallery.sentinel",
        "targets": {
            "Fruit_LFO": "projects/showcase_gallery/modules/Fruit_LFO",
            "signal": "projects/showcase_gallery/modules/signal",
            "strata_control": "projects/showcase_gallery/modules/strata_control",
            "dada_control": "projects/showcase_gallery/modules/dada_control",
            "LR_Furnishings": "projects/showcase_gallery/modules/LR_Furnishings",
            "LR_Lighting": "projects/showcase_gallery/modules/LR_Lighting",
            "LR_Architecture": "projects/showcase_gallery/modules/LR_Architecture",
        },
    },
}
MODULE_COPY_SETS = {
    "signal": (
        "projects/topographic_hud/modules/signal",
        "modules/signal",
        "projects/showcase_gallery/modules/signal",
    ),
    "strata_control": (
        "projects/strata/modules/strata_control",
        "modules/strata_control",
        "projects/showcase_gallery/modules/strata_control",
    ),
    "dada_control": (
        "projects/desert_totem/modules/dada_control",
        "modules/dada_control",
        "projects/showcase_gallery/modules/dada_control",
    ),
    "LR_Furnishings": (
        "projects/living_room_sdf/modules/LR_Furnishings",
        "projects/showcase_gallery/modules/LR_Furnishings",
    ),
    "LR_Lighting": (
        "projects/living_room_sdf/modules/LR_Lighting",
        "projects/showcase_gallery/modules/LR_Lighting",
    ),
    "LR_Architecture": (
        "projects/living_room_sdf/modules/LR_Architecture",
        "projects/showcase_gallery/modules/LR_Architecture",
    ),
}


class Mcp:
    """One long-lived sentinel-mcp stdio session."""

    def __init__(self, client_name: str = "example-ui-guards"):
        self.proc = subprocess.Popen(
            [SERVER],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            bufsize=1,
        )
        self.next_id = 1
        self.response_queue = queue.Queue()
        self.reader = threading.Thread(target=self._read_stdout, daemon=True)
        self.reader.start()
        self._request(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": client_name, "version": "1.0"},
            },
        )
        self._notify("notifications/initialized")

    def _read_stdout(self):
        assert self.proc.stdout is not None
        for line in self.proc.stdout:
            self.response_queue.put(line)
        self.response_queue.put(None)

    def _send(self, payload):
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.proc.stdin.flush()

    def _notify(self, method, params=None):
        self._send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def _request(self, method, params):
        request_id = self.next_id
        self.next_id += 1
        self._send(
            {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
        )
        while True:
            try:
                line = self.response_queue.get(
                    timeout=float(os.environ.get("SENTINEL_MCP_TIMEOUT", "90"))
                )
            except queue.Empty as exc:
                raise TimeoutError(
                    f"sentinel-mcp request {request_id} timed out"
                ) from exc
            if line is None:
                stderr = self.proc.stderr.read() if self.proc.stderr else ""
                raise RuntimeError("sentinel-mcp closed: " + stderr)
            message = json.loads(line)
            if message.get("id") == request_id:
                if "error" in message:
                    raise RuntimeError(json.dumps(message["error"], indent=2))
                return message["result"]

    def call(self, tool, arguments):
        result = self._request("tools/call", {"name": tool, "arguments": arguments})
        for block in result.get("content", []):
            if block.get("type") != "text":
                continue
            try:
                return json.loads(block["text"])
            except json.JSONDecodeError:
                return {"text": block["text"]}
        return result

    def close(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def normalized_bytes(path: Path) -> bytes:
    return path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def normalized_hash(path: Path) -> str:
    return hashlib.sha256(normalized_bytes(path)).hexdigest()


def bundle_report():
    authority = ROOT / "modules/_shared/ui"
    rows = []
    for header in SUI3_HEADERS:
        source = authority / header
        expected = normalized_hash(source)
        copies = {}
        for project in PROJECTS:
            candidate = ROOT / f"projects/{project}/modules/_shared/ui/{header}"
            copies[str(candidate.relative_to(ROOT))] = (
                normalized_hash(candidate) if candidate.exists() else None
            )
        rows.append(
            {
                "header": header,
                "normalized_sha256": expected,
                "copies": copies,
                "all_match": all(value == expected for value in copies.values()),
            }
        )
    return rows


def copy_roots_report(copies):
    """Compare complete normalized inventories across a module copy set."""
    inventories = []
    for root in copies:
        inventories.append(
            {
                path.relative_to(root)
                for path in root.rglob("*")
                if path.is_file() and ".sentinel" not in path.parts
            }
        )
    files = sorted(set().union(*inventories))
    rows = []
    for relative in files:
        hashes = {
            str(root): (
                normalized_hash(root / relative) if (root / relative).exists() else None
            )
            for root in copies
        }
        expected = hashes[str(copies[0])]
        rows.append(
            {
                "file": relative.as_posix(),
                "normalized_sha256": expected,
                "copies": hashes,
                "all_match": expected is not None
                and all(value == expected for value in hashes.values()),
            }
        )
    return rows


def module_copy_report(module_name):
    """Compare every relative file in every declared module copy."""
    copies = [ROOT / relative for relative in MODULE_COPY_SETS[module_name]]
    report = copy_roots_report(copies)
    for row in report:
        row["copies"] = {
            str(Path(label).relative_to(ROOT)): value
            for label, value in row["copies"].items()
        }
    return report


def load_manifest(module_dir: Path):
    with (module_dir / "manifest.yaml").open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def controls_for(module_dir: Path):
    manifest = load_manifest(module_dir)
    controls = manifest.get("viewport", {}).get("controls", [])
    return {control["id"]: control for control in controls}


def state_value(mcp: Mcp, pipeline: str, param: str):
    return mcp.call(
        "sentinel_state",
        {
            "action": "get",
            "path": f"/sentinel/pipelines/{pipeline}/parameters/{param}",
        },
    )


def scalar_from_response(response):
    if isinstance(response, (str, int, float, bool)):
        return response
    for key in ("value", "current", "result"):
        if key in response and not isinstance(response[key], (dict, list)):
            return response[key]
    values = response.get("values")
    if isinstance(values, dict) and len(values) == 1:
        return next(iter(values.values()))
    return response


def focus_panel(mcp: Mcp, pipeline: str):
    mcp.call("sentinel_graph", {"action": "focus", "entity_id": pipeline})
    mcp.call("sentinel_pipeline", {"action": "open_window", "pipeline_id": pipeline})
    time.sleep(0.8)


def gesture_phase(
    mcp: Mcp, pipeline: str, control: str, x: float, y: float, phase: str
):
    return mcp.call(
        "sentinel_ui",
        {
            "action": "viewport_control_drag",
            "pipeline": pipeline,
            "control": control,
            "x": x,
            "y": y,
            "phase": phase,
        },
    )


def drag(mcp: Mcp, pipeline: str, control: str, x: float, y: float):
    # Most 0.5.49 surfaces commit and release on begin; narrow/restored native
    # windows can retain capture until an explicit end. Always send the paired
    # end. Hosts that already released return a harmless not-owned response,
    # while hosts retaining capture are left ready for the next proof target.
    responses = [
        gesture_phase(mcp, pipeline, control, x, y, "begin"),
        gesture_phase(mcp, pipeline, control, x, y, "end"),
    ]
    time.sleep(0.35)
    return responses


def point_value(mcp: Mcp, pipeline: str, param: str):
    return [
        scalar_from_response(state_value(mcp, pipeline, f"{param}_x")),
        scalar_from_response(state_value(mcp, pipeline, f"{param}_y")),
    ]


def capture(mcp: Mcp, pipeline: str, output: Path):
    output.parent.mkdir(parents=True, exist_ok=True)
    result = mcp.call(
        "sentinel_capture",
        {"action": "pipeline", "pipeline_id": pipeline, "filepath": str(output)},
    )
    time.sleep(0.2)
    return result


def crop_rect(path: Path, rect):
    image = Image.open(path).convert("RGB")
    width, height = image.size
    x0 = max(0, min(width - 1, round(rect[0] * width)))
    y0 = max(0, min(height - 1, round(rect[1] * height)))
    x1 = max(x0 + 1, min(width, round(rect[2] * width)))
    y1 = max(y0 + 1, min(height, round(rect[3] * height)))
    return image.crop((x0, y0, x1, y1))


def slider_head_fraction(path: Path, rect):
    """Locate the strongest full-height vertical edge in the control well."""
    crop = crop_rect(path, rect)
    width, height = crop.size
    pixels = crop.load()
    y0, y1 = max(1, height // 4), max(2, 3 * height // 4)
    scores = []
    for x in range(1, width - 1):
        score = 0.0
        for y in range(y0, y1):
            left = sum(pixels[x - 1, y])
            right = sum(pixels[x + 1, y])
            score += abs(right - left)
        scores.append(score / max(1, y1 - y0))
    if not scores or max(scores) < 4.0:
        return None
    index = max(range(len(scores)), key=scores.__getitem__) + 1
    return index / max(1, width - 1)


def amber_count(path: Path, rect):
    crop = crop_rect(path, rect)
    count = 0
    for red, green, blue in crop.getdata():
        if red > 110 and red > green * 1.08 and red - blue > 35:
            count += 1
    return count


def changed_pixel_fraction(before: Path, after: Path, rect):
    first = crop_rect(before, rect)
    second = crop_rect(after, rect)
    if first.size != second.size:
        return None
    diff = ImageChops.difference(first, second)
    changed = 0
    for red, green, blue in diff.getdata():
        if red + green + blue > 24:
            changed += 1
    return changed / max(1, first.width * first.height)


def pad_reticle_fraction(path: Path, rect):
    """Find the compact ring; return x-left/y-up fractions.

    sui3 uses amber. The v1 baseline uses a neutral grey ring, so the component
    candidate also admits bright low-chroma pixels for the explicit not-ported
    measurement.
    """
    crop = crop_rect(path, rect)
    width, height = crop.size
    amber = set()
    for y in range(height):
        for x in range(width):
            red, green, blue = crop.getpixel((x, y))
            amber_pixel = red > 110 and red > green * 1.08 and red - blue > 35
            neutral_pixel = max(red, green, blue) > 135 and (
                max(red, green, blue) - min(red, green, blue) < 25
            )
            if amber_pixel or neutral_pixel:
                amber.add((x, y))
    seen = set()
    components = []
    for seed in amber:
        if seed in seen:
            continue
        stack = [seed]
        seen.add(seed)
        component = []
        while stack:
            x, y = stack.pop()
            component.append((x, y))
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    item = (x + dx, y + dy)
                    if item in amber and item not in seen:
                        seen.add(item)
                        stack.append(item)
        components.append(component)
    candidates = []
    for component in components:
        xs = [item[0] for item in component]
        ys = [item[1] for item in component]
        box_w = max(xs) - min(xs) + 1
        box_h = max(ys) - min(ys) + 1
        aspect = box_w / max(1, box_h)
        fill = len(component) / max(1, box_w * box_h)
        if (
            len(component) >= 8
            and 0.5 <= aspect <= 2.0
            and box_w >= 5
            and box_h >= 5
            and fill < 0.75
        ):
            score = len(component) - abs(box_w - box_h) * 2
            candidates.append((score, component))
    if not candidates:
        return None
    component = max(candidates)[1]
    x = sum(item[0] for item in component) / len(component)
    y = sum(item[1] for item in component) / len(component)
    return x / max(1, width - 1), 1.0 - y / max(1, height - 1)


def as_bool(value):
    value = scalar_from_response(value)
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("1", "true", "on")


def validate_control_entry(control_id, entry, parameters):
    """Return concrete two-half-gate failures for one exercised control."""
    kind = entry["kind"]
    probes = entry["probes"]
    failures = []
    if kind == "slider":
        parameter = parameters.get(entry["param"], {})
        span = abs(
            float(parameter.get("max", 1.0)) - float(parameter.get("min", 0.0))
        )
        value_tolerance = max(0.05, span * 0.05)
        for probe in probes:
            value = float(probe["value"])
            expected = float(probe["expected_value"])
            head = probe["head_fraction"]
            if abs(value - expected) > value_tolerance:
                failures.append(
                    f"{control_id}: value {value} misses {expected} by more than "
                    f"{value_tolerance}"
                )
            if head is None or abs(float(head) - float(probe["target"])) > 0.05:
                failures.append(
                    f"{control_id}: slider head {head} misses {probe['target']}"
                )
        heads = [probe["head_fraction"] for probe in probes]
        if (
            len(heads) != 2
            or any(head is None for head in heads)
            or abs(float(heads[1]) - float(heads[0])) < 0.1
        ):
            failures.append(f"{control_id}: slider heads are not visibly separated")
    elif kind == "xypad":
        for probe in probes:
            value = probe["value"]
            target = probe["target"]
            reticle = probe["reticle_fraction"]
            if max(abs(float(value[i]) - float(target[i])) for i in (0, 1)) > 0.05:
                failures.append(
                    f"{control_id}: point value {value} misses target {target}"
                )
            if reticle is None or max(
                abs(float(reticle[i]) - float(target[i])) for i in (0, 1)
            ) > 0.12:
                failures.append(
                    f"{control_id}: reticle {reticle} misses target {target}"
                )
    elif kind == "toggle":
        probe, roundtrip = probes
        before = as_bool(probe["before_value"])
        after = as_bool(probe["after_value"])
        restored = as_bool(roundtrip["roundtrip_value"])
        low = min(probe["before_accent_pixels"], probe["after_accent_pixels"])
        high = max(probe["before_accent_pixels"], probe["after_accent_pixels"])
        visual = high >= max(5, low * 2) or probe["changed_pixel_fraction"] >= 0.01
        if before == after or restored != before:
            failures.append(
                f"{control_id}: toggle did not complete off/on/off round trip"
            )
        if not visual:
            failures.append(f"{control_id}: toggle has no verified visual transition")
    elif kind == "button":
        probe = probes[0]
        before = scalar_from_response(probe["before_value"])
        held = scalar_from_response(probe["held_value"])
        released = scalar_from_response(probe["released_value"])
        visual = (
            probe["held_changed_pixel_fraction"] >= 0.01
            or probe["held_accent_pixels"]
            >= max(5, probe["before_accent_pixels"] * 2)
        )
        if held == before:
            failures.append(f"{control_id}: button never reached a held state")
        if released != before:
            failures.append(f"{control_id}: button latch did not release")
        if not visual:
            failures.append(f"{control_id}: held button has no visual transition")
    else:
        failures.append(f"{control_id}: unsupported control kind {kind}")
    return failures


def inspect_build(mcp: Mcp):
    ping = mcp.call("sentinel_app", {"action": "ping"})
    status = mcp.call("sentinel_app", {"action": "status"})
    capabilities = mcp.call("sentinel_app", {"action": "capabilities"})
    diagnostic = mcp.call(
        "sentinel_app", {"action": "diagnostic", "include_state_tree": False}
    )
    command_names = [
        item.get("name", "") for item in capabilities.get("commands", [])
    ]
    build = diagnostic.get("application", diagnostic.get("app"))
    if build is None and isinstance(diagnostic.get("text"), str):
        text = diagnostic["text"]
        start = text.find("{")
        if start >= 0:
            try:
                build = json.loads(text[start:]).get("app")
            except json.JSONDecodeError:
                build = None
    return {
        "ping": ping,
        "status": status,
        "build": build,
        "command_count": capabilities.get("command_count"),
        "viewport_control_drag_present": "VIEWPORT_CONTROL_DRAG" in command_names,
        "viewport_control_drag": next(
            (
                item
                for item in capabilities.get("commands", [])
                if item.get("name") == "VIEWPORT_CONTROL_DRAG"
            ),
            None,
        ),
    }


def broken_variant_report():
    """Prove each 5A guard kind can reject a deliberately wrong result."""
    fixture = tempfile.TemporaryDirectory(prefix="sentinel-example-ui-guards-")
    proof = Path(fixture.name)
    slider_png = proof / "master_rate_0.25.png"
    pad_png = proof / "motion_bias_0.23_0.71.png"
    toggle_off = proof / "mute_before.png"
    toggle_on = proof / "mute_after.png"

    slider_rect = (0.600, 0.080, 0.820, 0.145)
    pad_rect = (0.800, 0.280, 0.950, 0.485)
    toggle_rect = (0.840, 0.080, 0.950, 0.145)
    size = (1000, 500)
    slider_image = Image.new("RGB", size, (5, 5, 5))
    slider_draw = ImageDraw.Draw(slider_image)
    slider_draw.line((655, 40, 655, 72), fill=(240, 240, 240), width=2)
    slider_image.save(slider_png)
    pad_image = Image.new("RGB", size, (5, 5, 5))
    pad_draw = ImageDraw.Draw(pad_image)
    pad_draw.ellipse((829, 164, 841, 176), outline=(255, 112, 28), width=2)
    pad_image.save(pad_png)
    Image.new("RGB", size, (5, 5, 5)).save(toggle_off)
    toggle_image = Image.new("RGB", size, (5, 5, 5))
    ImageDraw.Draw(toggle_image).rectangle(
        (840, 40, 950, 72), fill=(255, 112, 28)
    )
    toggle_image.save(toggle_on)

    slider_measured = slider_head_fraction(slider_png, slider_rect)
    pad_measured = pad_reticle_fraction(pad_png, pad_rect)
    toggle_before = amber_count(toggle_off, toggle_rect)
    toggle_after = amber_count(toggle_on, toggle_rect)

    copy_a = proof / "copy-a"
    copy_b = proof / "copy-b"
    copy_a.mkdir()
    copy_b.mkdir()
    (copy_a / "manifest.yaml").write_text("name: fixture\n", encoding="utf-8")
    (copy_b / "manifest.yaml").write_text("name: fixture\n", encoding="utf-8")
    (copy_b / "stale.hlsl").write_text("// stale\n", encoding="utf-8")
    extra_file_report = copy_roots_report([copy_a, copy_b])

    authority = ROOT / "modules/_shared/ui/sui3_core.hlsli"
    broken_hash = hashlib.sha256(
        normalized_bytes(authority) + b"\n// deliberately broken identity\n"
    ).hexdigest()
    expected_hash = normalized_hash(authority)
    module_authority = (
        ROOT / "projects/topographic_hud/modules/signal/manifest.yaml"
    )
    broken_module_hash = hashlib.sha256(
        normalized_bytes(module_authority)
        + b"\n# deliberately broken module copy\n"
    ).hexdigest()
    expected_module_hash = normalized_hash(module_authority)
    strata_authority = ROOT / "projects/strata/modules/strata_control/manifest.yaml"
    broken_strata_hash = hashlib.sha256(
        normalized_bytes(strata_authority)
        + b"\n# deliberately broken module copy\n"
    ).hexdigest()
    expected_strata_hash = normalized_hash(strata_authority)
    dada_authority = ROOT / "projects/desert_totem/modules/dada_control/manifest.yaml"
    broken_dada_hash = hashlib.sha256(
        normalized_bytes(dada_authority)
        + b"\n# deliberately broken module copy\n"
    ).hexdigest()
    expected_dada_hash = normalized_hash(dada_authority)
    lighting_authority = (
        ROOT / "projects/living_room_sdf/modules/LR_Lighting/manifest.yaml"
    )
    broken_lighting_hash = hashlib.sha256(
        normalized_bytes(lighting_authority)
        + b"\n# deliberately broken module copy\n"
    ).hexdigest()
    expected_lighting_hash = normalized_hash(lighting_authority)
    architecture_authority = (
        ROOT / "projects/living_room_sdf/modules/LR_Architecture/manifest.yaml"
    )
    broken_architecture_hash = hashlib.sha256(
        normalized_bytes(architecture_authority)
        + b"\n# deliberately broken module copy\n"
    ).hexdigest()
    expected_architecture_hash = normalized_hash(architecture_authority)

    rows = [
        {
            "guard": "bundle identity",
            "broken_variant": "content has an extra non-whitespace line",
            "measured": broken_hash,
            "expected": expected_hash,
            "rejected": broken_hash != expected_hash,
        },
        {
            "guard": "module copy identity",
            "broken_variant": "authority manifest has an extra content line",
            "measured": broken_module_hash,
            "expected": expected_module_hash,
            "rejected": broken_module_hash != expected_module_hash,
        },
        {
            "guard": "module copy inventory",
            "broken_variant": "destination contains an extra stale file",
            "measured": extra_file_report,
            "expected": "every relative file exists with the same hash in every copy",
            "rejected": any(not row["all_match"] for row in extra_file_report),
        },
        {
            "guard": "strata module copy identity",
            "broken_variant": "authority manifest has an extra content line",
            "measured": broken_strata_hash,
            "expected": expected_strata_hash,
            "rejected": broken_strata_hash != expected_strata_hash,
        },
        {
            "guard": "dada module copy identity",
            "broken_variant": "authority manifest has an extra content line",
            "measured": broken_dada_hash,
            "expected": expected_dada_hash,
            "rejected": broken_dada_hash != expected_dada_hash,
        },
        {
            "guard": "living-room lighting copy identity",
            "broken_variant": "authority manifest has an extra content line",
            "measured": broken_lighting_hash,
            "expected": expected_lighting_hash,
            "rejected": broken_lighting_hash != expected_lighting_hash,
        },
        {
            "guard": "living-room architecture copy identity",
            "broken_variant": "authority manifest has an extra content line",
            "measured": broken_architecture_hash,
            "expected": expected_architecture_hash,
            "rejected": broken_architecture_hash != expected_architecture_hash,
        },
        {
            "guard": "slider head",
            "broken_variant": "0.25 capture asserted as 0.75",
            "measured": slider_measured,
            "expected": 0.75,
            "error": abs(slider_measured - 0.75),
            "rejected": abs(slider_measured - 0.75) > 0.05,
        },
        {
            "guard": "pad reticle",
            "broken_variant": "0.23/0.71 capture asserted as 0.77/0.29",
            "measured": pad_measured,
            "expected": [0.77, 0.29],
            "error": max(
                abs(pad_measured[0] - 0.77), abs(pad_measured[1] - 0.29)
            ),
            "rejected": max(
                abs(pad_measured[0] - 0.77), abs(pad_measured[1] - 0.29)
            )
            > 0.12,
        },
        {
            "guard": "toggle accent",
            "broken_variant": "non-firing v1 toggle, identical off/on captures",
            "measured": [toggle_before, toggle_before],
            "expected": "on >= max(5, off * 2)",
            "rejected": toggle_before < max(5, toggle_before * 2),
        },
    ]
    fixture.cleanup()
    return rows


def wait_for_project(mcp: Mcp, expected_pipeline: str, timeout: float = 45.0):
    deadline = time.time() + timeout
    last = {}
    while time.time() < deadline:
        last = mcp.call("sentinel_pipeline", {"action": "list"})
        pipelines = last.get("pipelines", last if isinstance(last, list) else [])
        ids = {
            item.get("pipeline_id", item.get("id"))
            for item in pipelines
            if isinstance(item, dict)
        }
        if expected_pipeline in ids:
            return last
        time.sleep(0.5)
    raise RuntimeError(f"{expected_pipeline} not present after project load: {last}")


def live_exercise(args):
    project = PROJECTS[args.project]
    module_dir = ROOT / project["targets"][args.pipeline]
    controls = controls_for(module_dir)
    manifest = load_manifest(module_dir)
    parameters = {
        item["name"]: item for item in manifest.get("parameters", []) if "name" in item
    }
    requested = args.controls or list(controls)
    unknown = sorted(set(requested) - set(controls))
    if unknown:
        raise SystemExit(f"Unknown controls for {args.pipeline}: {unknown}")

    proof_dir = ROOT / "captures/phase5" / args.project / args.pipeline
    mcp = Mcp()
    try:
        if args.load:
            mcp.call(
                "sentinel_app",
                {
                    "action": "load_project",
                    "path": str(ROOT / project["project"]),
                    "confirm": True,
                },
            )
            wait_for_project(mcp, args.pipeline)
        focus_panel(mcp, args.pipeline)
        info = mcp.call(
            "sentinel_pipeline", {"action": "info", "pipeline_id": args.pipeline}
        )
        report = {
            "project": args.project,
            "pipeline": args.pipeline,
            "port_state": "sui3"
            if any(
                "sui3_" in path.read_text(encoding="utf-8", errors="ignore")
                for path in module_dir.rglob("*.hlsl*")
            )
            else "v1",
            "panel": info.get("panel"),
            "controls": {},
        }
        panel_size = report["panel"].get("render_size", [0, 0])
        size_tag = f"{panel_size[0]}x{panel_size[1]}"
        for control_id in requested:
            control = controls[control_id]
            kind = control["kind"]
            param = control["param"]
            rect = control["rect"]
            entry = {"kind": kind, "param": param, "rect": rect, "probes": []}
            if kind == "slider":
                parameter = parameters.get(param, {})
                minimum = float(parameter.get("min", 0.0))
                maximum = float(parameter.get("max", 1.0))
                for target in (0.25, 0.75):
                    gestures = drag(mcp, args.pipeline, control_id, target, 0.5)
                    png = proof_dir / f"{control_id}_{target:.2f}_{size_tag}.png"
                    capture(mcp, args.pipeline, png)
                    entry["probes"].append(
                        {
                            "target": target,
                            "expected_value": minimum + target * (maximum - minimum),
                            "value": scalar_from_response(
                                state_value(mcp, args.pipeline, param)
                            ),
                            "head_fraction": slider_head_fraction(png, rect),
                            "gesture_responses": gestures,
                            "png": str(png.relative_to(ROOT)),
                        }
                    )
            elif kind == "xypad":
                for x, value_y in ((0.23, 0.71), (0.77, 0.29)):
                    gestures = drag(
                        mcp, args.pipeline, control_id, x, 1.0 - value_y
                    )
                    png = (
                        proof_dir
                        / f"{control_id}_{x:.2f}_{value_y:.2f}_{size_tag}.png"
                    )
                    capture(mcp, args.pipeline, png)
                    entry["probes"].append(
                        {
                            "target": [x, value_y],
                            "value": point_value(mcp, args.pipeline, param),
                            "reticle_fraction": pad_reticle_fraction(png, rect),
                            "gesture_responses": gestures,
                            "png": str(png.relative_to(ROOT)),
                        }
                    )
            elif kind == "toggle":
                before = proof_dir / f"{control_id}_before_{size_tag}.png"
                capture(mcp, args.pipeline, before)
                before_value = state_value(mcp, args.pipeline, param)
                gestures = drag(mcp, args.pipeline, control_id, 0.5, 0.5)
                after = proof_dir / f"{control_id}_after_{size_tag}.png"
                capture(mcp, args.pipeline, after)
                after_value = state_value(mcp, args.pipeline, param)
                entry["probes"].append(
                    {
                        "before_value": before_value,
                        "after_value": after_value,
                        "before_accent_pixels": amber_count(before, rect),
                        "after_accent_pixels": amber_count(after, rect),
                        "changed_pixel_fraction": changed_pixel_fraction(
                            before, after, rect
                        ),
                        "gesture_responses": gestures,
                        "before_png": str(before.relative_to(ROOT)),
                        "after_png": str(after.relative_to(ROOT)),
                    }
                )
                drag(mcp, args.pipeline, control_id, 0.5, 0.5)
                off = proof_dir / f"{control_id}_off_roundtrip_{size_tag}.png"
                capture(mcp, args.pipeline, off)
                entry["probes"].append(
                    {
                        "roundtrip_value": state_value(mcp, args.pipeline, param),
                        "accent_pixels": amber_count(off, rect),
                        "png": str(off.relative_to(ROOT)),
                    }
                )
            elif kind == "button":
                before = proof_dir / f"{control_id}_before_{size_tag}.png"
                held = proof_dir / f"{control_id}_held_{size_tag}.png"
                released = proof_dir / f"{control_id}_released_{size_tag}.png"
                capture(mcp, args.pipeline, before)
                before_value = state_value(mcp, args.pipeline, param)
                begin = gesture_phase(
                    mcp, args.pipeline, control_id, 0.5, 0.5, "begin"
                )
                time.sleep(0.2)
                capture(mcp, args.pipeline, held)
                held_value = state_value(mcp, args.pipeline, param)
                end = gesture_phase(mcp, args.pipeline, control_id, 0.5, 0.5, "end")
                time.sleep(0.2)
                capture(mcp, args.pipeline, released)
                entry["probes"].append(
                    {
                        "before_value": before_value,
                        "held_value": held_value,
                        "released_value": state_value(mcp, args.pipeline, param),
                        "before_accent_pixels": amber_count(before, rect),
                        "held_accent_pixels": amber_count(held, rect),
                        "held_changed_pixel_fraction": changed_pixel_fraction(
                            before, held, rect
                        ),
                        "gesture_responses": [begin, end],
                        "before_png": str(before.relative_to(ROOT)),
                        "held_png": str(held.relative_to(ROOT)),
                        "released_png": str(released.relative_to(ROOT)),
                    }
                )
            else:
                entry["probes"].append(
                    {"unsupported": f"no live guard for control kind {kind}"}
                )
            report["controls"][control_id] = entry
        failures = []
        for control_id, entry in report["controls"].items():
            failures.extend(validate_control_entry(control_id, entry, parameters))
        report["failures"] = failures
        report["passed"] = not failures
        return report
    finally:
        mcp.close()


def parse_args():
    parser = argparse.ArgumentParser()
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument("--check-bundles", action="store_true")
    actions.add_argument(
        "--check-module-copies", choices=sorted(MODULE_COPY_SETS)
    )
    actions.add_argument("--discover", action="store_true")
    actions.add_argument("--self-test", action="store_true")
    actions.add_argument("--exercise", action="store_true")
    parser.add_argument("--project", choices=sorted(PROJECTS))
    parser.add_argument("--pipeline")
    parser.add_argument("--controls", nargs="*")
    parser.add_argument(
        "--load",
        action="store_true",
        help="Load the project first. Use only once per Sentinel session.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    if args.check_bundles:
        report = bundle_report()
        print(json.dumps(report, indent=2))
        return 0 if all(row["all_match"] for row in report) else 1
    if args.check_module_copies:
        report = module_copy_report(args.check_module_copies)
        print(json.dumps(report, indent=2))
        return 0 if report and all(row["all_match"] for row in report) else 1
    if args.discover:
        mcp = Mcp()
        try:
            print(json.dumps(inspect_build(mcp), indent=2))
        finally:
            mcp.close()
        return 0
    if args.self_test:
        report = broken_variant_report()
        print(json.dumps(report, indent=2))
        return 0 if all(row["rejected"] for row in report) else 1
    if not args.project or not args.pipeline:
        raise SystemExit("--exercise requires --project and --pipeline")
    report = live_exercise(args)
    print(json.dumps(report, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
