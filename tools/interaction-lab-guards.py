"""Re-runnable regression guards for the Interaction Lab (Phase 3).

Every defect Phase 3 fixed is asserted here against the live graph, so a future
session can prove the fix is still in place instead of trusting a number
recorded once in a devlog. Run with Sentinel open on
``projects/interaction_lab/interaction_lab.sentinel``::

    python tools/interaction-lab-guards.py

Each guard prints PASS or FAIL with the measured values. Exit code is the
number of failures.

Guards that need a hand on the mouse are listed at the end as SKIP with the
reason, so the gap stays visible rather than silently absent.
"""

import json
import os
import subprocess
import sys
import time

SERVER = os.environ.get(
    "SENTINEL_MCP",
    r"C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe",
)
WORKSPACE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STATIONS = ["Style_Authority", "Motion_Console", "Spline_Desk", "Gizmo_Desk", "Spline_Output"]

# Workspace module directory -> bundled directory under projects/interaction_lab/modules.
BUNDLE_PAIRS = [
    ("style_authority", "Style_Authority"),
    ("motion_console", "Motion_Console"),
    ("spline_desk", "Spline_Desk"),
    ("gizmo_desk", "Gizmo_Desk"),
    ("spline_render", "Spline_Output"),
]


class Mcp:
    """One long-lived sentinel-mcp stdio session, so guards do not pay per-call startup."""

    def __init__(self, server):
        self.proc = subprocess.Popen(
            [server],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            bufsize=1,
        )
        self.next_id = 1
        self._request(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "interaction-lab-guards", "version": "1.0"},
            },
        )
        self._notify("notifications/initialized")

    def _send(self, payload):
        self.proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.proc.stdin.flush()

    def _notify(self, method, params=None):
        self._send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def _request(self, method, params):
        request_id = self.next_id
        self.next_id += 1
        self._send({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError("sentinel-mcp closed: " + self.proc.stderr.read())
            message = json.loads(line)
            if message.get("id") == request_id:
                return message

    def call(self, tool, arguments):
        message = self._request("tools/call", {"name": tool, "arguments": arguments})
        result = message.get("result", {})
        for block in result.get("content", []):
            if block.get("type") == "text":
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

    # Convenience wrappers.

    def set_param(self, pipeline, name, value):
        return self.call(
            "sentinel_state",
            {
                "action": "set",
                "path": "/sentinel/pipelines/%s/parameters/%s" % (pipeline, name),
                "value": value,
            },
        )

    def port(self, pipeline, port_name, count):
        return self.call(
            "sentinel_pipeline",
            {
                "action": "capture_data_port",
                "pipeline_id": pipeline,
                "port_name": port_name,
                "max_elements": count,
            },
        )

    def edge(self, pipeline, name, settle=0.35):
        """Fire a rising-edge bool door and release it."""
        self.set_param(pipeline, name, True)
        time.sleep(settle)
        self.set_param(pipeline, name, False)
        time.sleep(settle)


RESULTS = []


def record(name, ok, detail):
    RESULTS.append((name, ok, detail))
    print("%-6s %-38s %s" % ("PASS" if ok else "FAIL", name, detail))


def skip(name, reason):
    RESULTS.append((name, None, reason))
    print("%-6s %-38s %s" % ("SKIP", name, reason))


def guard_health(mcp):
    profile = mcp.call("sentinel_graph", {"action": "profile", "summary": True, "sort_by": "id"})
    nodes = {n["entity_id"]: n for n in profile.get("nodes", [])}
    missing = [s for s in STATIONS if s not in nodes]
    if missing:
        record("all stations present", False, "missing %s" % missing)
        return
    unhealthy = [s for s in STATIONS if not nodes[s].get("healthy")]
    record("all stations healthy", not unhealthy, "unhealthy %s" % unhealthy if unhealthy else "5/5 healthy")

    # Cook cadence is the honest performance measure. The per-node wall_time_ms
    # in this profile is CPU wall-clock and tracks which station owns the active
    # canvas panel, so it is deliberately NOT asserted on. See the 3F devlog.
    slow = {s: nodes[s].get("cook_hz") for s in STATIONS if (nodes[s].get("cook_hz") or 0) < 55}
    record(
        "all stations cook at >=55 Hz",
        not slow,
        "slow %s" % slow if slow else "cook_hz %s" % sorted({nodes[s]["cook_hz"] for s in STATIONS}),
    )


def guard_spline_undo(mcp):
    """3D: undo must reverse a close, preserve the selection bit, and leave knots identical.

    v1 preserved the whole flags word to protect the selection, which made the
    closed-path bit (also in flags) the one edit undo could never reverse.
    """
    before = mcp.port("Spline_Desk", "Spline Knots", 4)["elements"]
    mcp.edge("Spline_Desk", "do_close")
    closed = mcp.port("Spline_Desk", "Spline Knots", 4)["elements"]
    mcp.edge("Spline_Desk", "do_undo")
    after = mcp.port("Spline_Desk", "Spline Knots", 4)["elements"]

    set_bit = (closed[0]["flags"] & 2) and not (before[0]["flags"] & 2)
    record("undo: close sets the closed bit", bool(set_bit),
           "flags %d -> %d" % (before[0]["flags"], closed[0]["flags"]))
    record("undo: close is reversed", not (after[0]["flags"] & 2),
           "flags %d -> %d" % (closed[0]["flags"], after[0]["flags"]))
    record("undo: selection bit survives", (after[0]["flags"] & 1) == (before[0]["flags"] & 1),
           "selection bit %d" % (after[0]["flags"] & 1))
    moved = [i for i, (b, a) in enumerate(zip(before, after))
             if b["anchor"] != a["anchor"] or b["handle_in"] != a["handle_in"]
             or b["handle_out"] != a["handle_out"]]
    record("undo: knot geometry unchanged", not moved,
           "moved %s" % moved if moved else "4 knots bit-identical")


def guard_gizmo_orbit(mcp):
    """3E: a +N / -N numeric orbit about the shared pivot must round-trip exactly.

    Two objects are selected so the guard exercises the shared-pivot path, which
    is the one a multi-selection drag uses. ``selection_action=set`` reports
    ``source: MCP`` rather than the ``source: User`` a real click produces; that
    difference is irrelevant here, because what is under test is the transform
    maths downstream of the selection, not the pick path.
    """
    mcp.call("sentinel_viewport", {"action": "selection", "pipeline": "Gizmo_Desk",
                                   "selection_action": "set", "ids": [1, 2]})
    time.sleep(0.35)
    before = mcp.port("Gizmo_Desk", "Scene Objects", 4)["elements"]
    mcp.set_param("Gizmo_Desk", "orbit_degrees", 40.0)
    mcp.edge("Gizmo_Desk", "do_orbit")
    turned = mcp.port("Gizmo_Desk", "Scene Objects", 4)["elements"]
    mcp.set_param("Gizmo_Desk", "orbit_degrees", -40.0)
    mcp.edge("Gizmo_Desk", "do_orbit")
    after = mcp.port("Gizmo_Desk", "Scene Objects", 4)["elements"]
    mcp.set_param("Gizmo_Desk", "orbit_degrees", 40.0)
    mcp.call("sentinel_viewport", {"action": "selection", "pipeline": "Gizmo_Desk",
                                   "selection_action": "clear"})

    record("gizmo: orbit moves the selection", before != turned,
           "no change, so the orbit door did not fire" if before == turned
           else "object 1 %s -> %s" % (before[0]["position"], turned[0]["position"]))

    # The rotation Euler angles DO return bit-identically, because the orbit adds
    # a scalar to one component. Positions go through sin/cos in float32, so they
    # return to round-off, not to the bit. Asserting equality here would be
    # asserting something the arithmetic cannot deliver.
    rot_exact = all(b["rotation"] == a["rotation"] for b, a in zip(before, after))
    record("gizmo: orbit round-trips rotation exactly", rot_exact,
           "rotation bit-identical" if rot_exact else "rotation drifted")
    worst = max(abs(b - a)
                for rb, ra in zip(before, after)
                for b, a in zip(rb["position"], ra["position"]))
    record("gizmo: orbit round-trips position to float32", worst < 1e-5,
           "max position delta %.3e" % worst)


def guard_bundle_identity():
    """3F: every bundled module source file must match its workspace original byte for byte."""
    import hashlib

    def digest(path):
        with open(path, "rb") as handle:
            return hashlib.sha256(handle.read()).hexdigest()

    mismatches = []
    checked = 0
    for src_name, bundle_name in BUNDLE_PAIRS:
        src = os.path.join(WORKSPACE, "modules", src_name)
        dst = os.path.join(WORKSPACE, "projects", "interaction_lab", "modules", bundle_name)
        for root, dirs, files in os.walk(src):
            # .sentinel holds the per-module shader cache: a build artifact, never bundled.
            dirs[:] = [d for d in dirs if d != ".sentinel"]
            for name in files:
                full = os.path.join(root, name)
                rel = os.path.relpath(full, src)
                twin = os.path.join(dst, rel)
                checked += 1
                if not os.path.exists(twin):
                    mismatches.append("missing %s/%s" % (bundle_name, rel))
                elif digest(full) != digest(twin):
                    mismatches.append("differs %s/%s" % (bundle_name, rel))
    record("bundle matches the workspace modules", not mismatches,
           "%s" % mismatches[:4] if mismatches else "%d source files identical" % checked)


def guard_group_surfaces(mcp):
    """3F: four to eight curated controls per group, and never a camera control."""
    groups = mcp.call("sentinel_graph", {"action": "list_scene_groups"}).get("groups", [])
    record("four Scene Groups", len(groups) == 4, "%d groups" % len(groups))
    for group in groups:
        params = group.get("parameters", [])
        # A colour or XY compound is one control, not three.
        logical = {p["compound_key"] or p["name"] for p in params}
        name = group.get("display_name", group.get("entity_id"))
        record("%s: 4-8 controls" % name, 4 <= len(logical) <= 8, "%d controls" % len(logical))
        camera = sorted(p["name"] for p in params if "camera" in p["name"].lower()
                        or "fov" in p["name"].lower() or "orbit_pitch" in p["name"].lower())
        record("%s: no camera control" % name, not camera, camera if camera else "none")


def guard_presets(mcp):
    """3F: every surviving preset recalls fully; nothing lands in skipped[].

    Recalling a preset overwrites live parameters, so each station is snapshotted
    first and restored afterwards. A guard that leaves the graph in a different
    look than it found it is not a guard anyone will run twice.
    """
    expected = {
        "Style_Authority": ["Dense Instrument", "Airy Review"],
        "Motion_Console": ["Motion Reference", "Slow Drift"],
        "Spline_Desk": ["Spline Desk Default"],
        "Gizmo_Desk": ["Gizmo Desk Default"],
    }
    for pipeline, names in expected.items():
        saved = mcp.call("sentinel_state", {"action": "snapshot", "pipeline_id": pipeline})
        for preset in names:
            result = mcp.call(
                "sentinel_preset",
                {"action": "recall", "pipeline": pipeline, "preset": preset},
            )
            applied = result.get("applied") or []
            skipped = result.get("skipped")
            ok = bool(applied) and skipped == []
            record("preset %s" % preset, ok,
                   "applied %d, skipped %s" % (len(applied), skipped))
        mcp.call("sentinel_state", {"action": "restore", "values": saved.get("values", {})})


def guard_ui_rects():
    """3B: the generated hit rects must still match the manifest."""
    script = os.path.join(WORKSPACE, "tools", "module-ui.ps1")
    for module in ("style_authority", "motion_console", "spline_desk", "gizmo_desk"):
        path = os.path.join(WORKSPACE, "modules", module)
        # -File mis-binds the positional module path on Windows PowerShell 5.1,
        # so invoke through -Command with the call operator instead.
        proc = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command",
             "& '%s' validate '%s'" % (script, path)],
            capture_output=True, text=True,
        )
        out = (proc.stdout or proc.stderr).strip().splitlines()
        record("module-ui validate %s" % module, proc.returncode == 0,
               out[-1] if out else "no output")


def main():
    mcp = Mcp(SERVER)
    try:
        if mcp.call("sentinel_app", {"action": "ping"}).get("text", "").strip() == "":
            pass  # ping returns a bare PONG string on some builds
        guard_health(mcp)
        guard_spline_undo(mcp)
        guard_gizmo_orbit(mcp)
        guard_group_surfaces(mcp)
        guard_presets(mcp)
    finally:
        mcp.close()

    guard_bundle_identity()
    guard_ui_rects()

    # Not automatable on this build: sentinel_viewport action=edit drives the
    # host object-edit transaction, and these modules render their own gizmo
    # from raw viewport events. Left visible so the gap is not mistaken for
    # coverage.
    skip("spline: anchor / handle drag", "needs a real pointer drag in the module preview")
    skip("spline: marquee select", "needs a real pointer drag in the module preview")
    skip("gizmo: axis / ring drag", "needs a real pointer drag in the module preview")
    skip("style authority: hover feedback", "needs a real pointer hover in the module preview")

    failed = sum(1 for _, ok, _ in RESULTS if ok is False)
    passed = sum(1 for _, ok, _ in RESULTS if ok is True)
    skipped = sum(1 for _, ok, _ in RESULTS if ok is None)
    print("\n%d passed, %d failed, %d skipped" % (passed, failed, skipped))
    return failed


if __name__ == "__main__":
    sys.exit(main())
