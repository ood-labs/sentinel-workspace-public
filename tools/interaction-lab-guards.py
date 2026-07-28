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


# Pad wells, as normalized manifest rects: (pipeline, param stem, rect, display).
# These are the same numbers `_ui.generated.hlsli` carries, so the guard measures
# the well the HOST hit-tests, not one the guard invented.
PAD_WELLS = [
    ("Style_Authority", "demo_pad", (0.015625, 0.120833, 0.559375, 0.315278),
     "style authority pad", "pad"),
    ("Motion_Console", "motion_bias", (0.82, 0.02, 0.97, 0.13),
     "motion console bias", "bias"),
]


def _reticle_row(png_path, rect, w, h):
    """Row only, for callers that do not care where the reticle sits across."""
    pos = _reticle_pos(png_path, rect, w, h)
    return None if pos is None else pos[1]


def _reticle_pos(png_path, rect, w, h):
    """(col, row) of the amber reticle inside `rect`, each 0..1.

    Col is 0 at the well's LEFT edge, row is 0 at its BOTTOM, so the pair is
    directly comparable with the pad's (x, y) value.

    Amber is the accent, but the reticle is NOT the only accent-coloured thing in
    a well: both stations print an XY readout inside the same rect. Averaging
    every amber pixel put a value-0.9 reticle at 0.49, because the readout does
    not move between probes.

    Grouping amber ROWS into bands and taking the tallest was the second attempt
    and it also failed: when the reticle sits at the top of the well it shares
    rows with the readout, the two merge into one band, and the weighted mean
    lands between them (0.70 for a value of 0.90, measured).

    So this picks by SHAPE, in 2D. The reticle is a ring, compact and roughly
    square; a readout is a wide, flat line of text. Nothing here depends on
    where either one sits, which matters because these panels follow the dock
    and the layout reflows with the panel size.
    """
    from PIL import Image
    img = Image.open(png_path).convert("RGB")
    x0, y0, x1, y1 = (int(rect[0] * w), int(rect[1] * h), int(rect[2] * w), int(rect[3] * h))
    crop = img.crop((x0, y0, x1, y1))
    px = crop.load()
    cw, chh = crop.size

    amber = set()
    for yy in range(chh):
        for xx in range(cw):
            r, g, b = px[xx, yy]
            if r > 120 and r - b > 60 and r > g:
                amber.add((xx, yy))
    if not amber:
        return None

    # Flood-fill 8-connected components.
    seen, comps = set(), []
    for seed in amber:
        if seed in seen:
            continue
        stack, comp = [seed], []
        seen.add(seed)
        while stack:
            cx, cy = stack.pop()
            comp.append((cx, cy))
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (cx + dx, cy + dy)
                    if n in amber and n not in seen:
                        seen.add(n)
                        stack.append(n)
        comps.append(comp)

    best, best_score = None, None
    for comp in comps:
        xs = [c[0] for c in comp]
        ys = [c[1] for c in comp]
        bw, bh = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
        aspect = bw / float(max(bh, 1))
        fill = len(comp) / float(max(bw * bh, 1))
        if (len(comp) < 8 or bw < 5 or bh < 5
                or not 0.5 <= aspect <= 2.0 or fill >= 0.75):
            continue
        # At a wide dock, several orange numeric glyphs are nearly square.
        # Prefer the ring's larger connected perimeter, then penalise skew.
        score = len(comp) - abs(bw - bh) * 2
        if best_score is None or score > best_score:
            best, best_score = comp, score
    if best is None:
        return None

    mean_x = sum(c[0] for c in best) / float(len(best))
    mean_y = sum(c[1] for c in best) / float(len(best))
    return (mean_x / max(cw - 1, 1), 1.0 - (mean_y / max(chh - 1, 1)))


def guard_pad_direction(mcp):
    """A module pad must draw Y-UP: value 1 at the TOP.

    Both host surfaces now use that convention. They used to disagree -- the
    Properties row Y-up, the canvas gesture Y-down -- and the kit drew Y-down to
    keep the reticle under the pointer, so this guard asserted Y-down too. The
    host closed the defect on 2026-07-27 and the compensation became the bug:
    the operator saw a correct Properties row and an inverted pad.

    An earlier version of this guard asserted the Properties convention and
    passed while the pad was undraggable, which is how a green suite once
    shipped a broken control. See `guard_pad_gesture_tracks` for the check that
    now covers the part a drawing-only assertion cannot.
    """
    import shutil
    tmp = os.path.join(WORKSPACE, "captures", "_padguard")
    os.makedirs(tmp, exist_ok=True)
    try:
        for pid, stem, rect, label, _ctrl in PAD_WELLS:
            before = {}
            for ax in ("x", "y"):
                before[ax] = mcp.call("sentinel_state", {
                    "action": "get",
                    "path": "/sentinel/pipelines/%s/parameters/%s_%s" % (pid, stem, ax),
                })["value"]
            seen = {}
            try:
                for probe in (0.9, 0.1):
                    mcp.set_param(pid, "%s_x" % stem, 0.5)
                    mcp.set_param(pid, "%s_y" % stem, probe)
                    time.sleep(0.6)
                    shot = os.path.join(tmp, "%s_%s.png" % (pid, probe))
                    cap = mcp.call("sentinel_capture", {
                        "action": "pipeline", "pipeline_id": pid, "filepath": shot})
                    seen[probe] = _reticle_row(shot, rect, cap["width"], cap["height"])
            finally:
                for ax in ("x", "y"):
                    mcp.set_param(pid, "%s_%s" % (stem, ax), float(before[ax]))

            hi, lo = seen.get(0.9), seen.get(0.1)
            if hi is None or lo is None:
                record("pad tracks gesture: %s" % label, False,
                       "no reticle found in the well (hi=%s lo=%s)" % (hi, lo))
                continue
            # `_reticle_row` reports 0 at the well BOTTOM, so a Y-up pad puts
            # value 0.9 HIGH and value 0.1 LOW.
            ok = hi > 0.72 and lo < 0.28
            record("pad draws Y-up: %s" % label, ok,
                   "value 0.9 drew at %.2f, value 0.1 at %.2f (0 = well bottom)" % (hi, lo))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def guard_pad_gesture_tracks(mcp):
    """The reticle must land under the DRAG, not merely draw the stored number.

    `guard_pad_direction` writes the parameter and checks where the pad draws.
    That proves the drawing but not the loop, and the gap is exactly where this
    defect kept hiding: a pad can draw a stored value perfectly while the host
    writes the opposite end of the range for a given pointer position, so the
    dot runs away from the cursor. Both times the operator caught this, a
    drawing-only assertion was green.

    `sentinel_ui action=viewport_control_drag` closes it. Coordinates are
    control-local 0..1 with y measured DOWN from the top, and the parameter
    receives (x, 1 - y), so a drag at y writes a value that must draw at
    (1 - y) up from the well's bottom. Asserting the round trip pointer ->
    host -> parameter -> pixels means neither half can be wrong on its own.

    The drag only lands on the FOCUSED viewport, and it fails silently when it
    does not: the call returns success and the parameter simply does not move.
    Every window is opened first for that reason. Diagnosing this cost a round
    of chasing a phantom stuck-capture theory, so check `viewport info`'s
    `focused` before believing the tool is broken.
    """
    import shutil
    tmp = os.path.join(WORKSPACE, "captures", "_padtrack")
    os.makedirs(tmp, exist_ok=True)
    # Off-centre and asymmetric so a transposed or mirrored mapping cannot
    # coincidentally satisfy the check.
    TARGETS = [(0.22, 0.18), (0.78, 0.83)]
    try:
        for pid, stem, rect, label, ctrl in PAD_WELLS:
            before = {ax: mcp.call("sentinel_state", {
                "action": "get",
                "path": "/sentinel/pipelines/%s/parameters/%s_%s" % (pid, stem, ax),
            })["value"] for ax in ("x", "y")}
            worst, detail = 0.0, []
            try:
                mcp.call("sentinel_pipeline", {"action": "open_window", "pipeline_id": pid})
                time.sleep(1.0)
                if not mcp.call("sentinel_viewport", {
                        "action": "info", "pipeline": pid}).get("focused"):
                    record("pad follows the drag: %s" % label, False,
                           "viewport never took focus; a drag cannot land")
                    continue
                for dx, dy in TARGETS:
                    for phase in ("begin", "update", "end"):
                        mcp.call("sentinel_ui", {
                            "action": "viewport_control_drag", "pipeline": pid,
                            "control": ctrl, "phase": phase, "x": dx, "y": dy})
                    time.sleep(0.6)
                    shot = os.path.join(tmp, "%s_%.2f.png" % (pid, dy))
                    cap = mcp.call("sentinel_capture", {
                        "action": "pipeline", "pipeline_id": pid, "filepath": shot})
                    pos = _reticle_pos(shot, rect, cap["width"], cap["height"])
                    if pos is None:
                        detail.append("drag(%.2f,%.2f): no reticle found" % (dx, dy))
                        worst = 1.0
                        continue
                    want = (dx, 1.0 - dy)
                    err = max(abs(pos[0] - want[0]), abs(pos[1] - want[1]))
                    worst = max(worst, err)
                    detail.append("drag(%.2f,%.2f) -> drew (%.2f,%.2f), want (%.2f,%.2f)"
                                  % (dx, dy, pos[0], pos[1], want[0], want[1]))
            finally:
                for ax in ("x", "y"):
                    mcp.set_param(pid, "%s_%s" % (stem, ax), float(before[ax]))
            record("pad follows the drag: %s" % label, worst <= 0.12,
                   "%s (worst err %.2f)" % ("; ".join(detail), worst))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


THEME_FOLLOWERS = ["Motion_Console", "Spline_Desk", "Gizmo_Desk"]


def guard_theme_governs(mcp):
    """The Style Authority must actually govern the other three stations.

    Deliverable D3 rests entirely on "the other stations consume them by
    sentinel_expression... tuning the authority therefore visibly retunes the
    whole lab, which is what makes it a tool rather than a swatch page." That was
    proven in 3B against UI_Style_Tuner, a module 3F deleted, and the shipped
    project then carried zero expressions -- so the claim was true of a graph
    that no longer existed. This drives the authority and asserts the followers
    move, which is the causal chain itself rather than a pixel diff that would
    also pass if one of the three were unwired.
    """
    def accent(pid):
        return tuple(round(float(mcp.call("sentinel_state", {
            "action": "get",
            "path": "/sentinel/pipelines/%s/parameters/accent_color_%s" % (pid, c),
        })["value"]), 4) for c in "rgb")

    base = accent("Style_Authority")
    probe = (0.18, 0.86, 0.42)
    try:
        for c, v in zip("rgb", probe):
            mcp.set_param("Style_Authority", "accent_color_%s" % c, v)
        time.sleep(1.0)
        moved = {f: accent(f) for f in THEME_FOLLOWERS}
    finally:
        for c, v in zip("rgb", base):
            mcp.set_param("Style_Authority", "accent_color_%s" % c, v)
        time.sleep(0.8)
    restored = {f: accent(f) for f in THEME_FOLLOWERS}

    lagging = [f for f, v in moved.items()
               if any(abs(v[i] - probe[i]) > 0.01 for i in range(3))]
    record("theme: authority drives all three stations", not lagging,
           "did not follow: %s" % lagging if lagging else "all three -> %s" % (probe,))
    stuck = [f for f, v in restored.items()
             if any(abs(v[i] - base[i]) > 0.01 for i in range(3))]
    record("theme: followers restore with the authority", not stuck,
           "still off: %s" % stuck if stuck else "all three back to %s" % (base,))


def guard_spline_readout_matches_knots(mcp):
    """The tangent readout must equal the tangent actually stored on the knots.

    `interaction.hlsl` advances `st.tangent_mode` on every fire but only writes it
    onto the knots when command 8 runs, so divergence means a command was lost
    somewhere between arming and executing.

    WHAT THIS DOES NOT COVER, stated because it was written believing otherwise:
    it does NOT guard the arm-then-execute queueing fix. That defect needs a
    non-snap command to land on the cook immediately after a snap command armed,
    and the only non-snap command a pointer produces is a drag move. Firing doors
    from here cannot reproduce it -- each MCP round trip is slower than the 16 ms
    cook, so every command gets a cook to itself and never collides. Verified by
    reverting the fix, recompiling, and watching this guard pass anyway. The
    queueing fix is unguarded and is listed as such in the devlog.
    """
    # `do_reset` runs update.hlsl's initialize(), which reseeds to these four
    # fixed anchors. It does NOT restore whatever was on screen beforehand, so
    # the probe asserts the seed rather than a round trip.
    SEED = [(0.16, 0.62), (0.36, 0.30), (0.62, 0.68), (0.84, 0.35)]
    try:
        mcp.edge("Spline_Desk", "do_select_lane")
        # Deliberately NO settle between fires -- the collision is the point.
        for _ in range(6):
            mcp.set_param("Spline_Desk", "do_tangent", True)
            mcp.set_param("Spline_Desk", "do_tangent", False)
        time.sleep(1.2)

        readout = int(round(float(mcp.call("sentinel_state", {
            "action": "get",
            "path": "/sentinel/pipelines/Spline_Desk/control_outputs/tangent_mode",
        })["value"])))
        knots = mcp.port("Spline_Desk", "Spline Knots", 4)["elements"]
        sel = [k for k in knots if k["flags"] & 1]
        off = [(i, k["tangent_mode"]) for i, k in enumerate(knots)
               if (k["flags"] & 1) and k["tangent_mode"] != readout]
        record("spline: tangent readout matches the knots",
               bool(sel) and not off,
               "no selection to test" if not sel else
               ("readout %d but knots %s" % (readout, off) if off
                else "%d selected knots all at tangent_mode %d" % (len(sel), readout)))
    finally:
        mcp.edge("Spline_Desk", "do_reset")
        time.sleep(0.4)
    after = mcp.port("Spline_Desk", "Spline Knots", 4)["elements"]
    off = [(i, [round(v, 4) for v in k["anchor"]])
           for i, k in enumerate(after[:4])
           if abs(k["anchor"][0] - SEED[i][0]) > 1e-4
           or abs(k["anchor"][1] - SEED[i][1]) > 1e-4]
    record("spline: readout probe left the desk seeded", not off,
           "four anchors at the seed" if not off else "off-seed: %s" % off)


# Kept as a literal on purpose, NOT parsed out of gizmo_desk/types.hlsli. A
# guard that reads the expected value from the thing it is checking passes
# whatever the shader says, which is how four pad surfaces once agreed with each
# other while all four were upside down. This is the contract value, asserted
# independently; if the shader changes it, this is supposed to fail.
GD_MAGIC = 7321.0


def guard_gizmo_state_integrity(mcp):
    """The reseed sentinel ran, and the published schema covers the whole stride.

    Both are audit findings with the same shape: something that is silently fine
    until it is not. The reseed used to guard on `st.mode` being out of 0..2, but
    0 is a legal mode, so a zeroed buffer looked valid and the seed never ran --
    and a garbage auto_latch masks do_orbit off permanently, because a rising
    edge cannot fire against a latch that is already set. Separately the schema
    summed to 80 bytes against a 96-byte buffer, so a consumer deriving its
    stride from the schema walked off by 16 bytes per element.
    """
    # The persistent buffer can be recreated (and so zeroed) by the host, and the
    # reseed lands on the NEXT cook -- a read inside that one-frame window sees
    # zeros. Observed once in practice. Recovery is the thing under test, so
    # re-read rather than fail on a single sample: a sentinel that never comes
    # back is the real defect, and this still catches it.
    cap = mcp.port("Gizmo_Desk", "Gizmo State", 1)
    g = cap["elements"][0]
    for _ in range(4):
        if abs(g.get("magic", 0.0) - GD_MAGIC) < 0.5:
            break
        time.sleep(0.4)
        cap = mcp.port("Gizmo_Desk", "Gizmo State", 1)
        g = cap["elements"][0]
    record("gizmo: reseed sentinel is set", abs(g.get("magic", 0.0) - GD_MAGIC) < 0.5,
           "magic %s" % g.get("magic"))
    record("gizmo: idle auto_latch is clear", abs(g.get("auto_latch", 1.0)) < 0.5,
           "auto_latch %s, pending %s" % (g.get("auto_latch"), g.get("pending")))
    # float/uint fields are 4 bytes; float2 8; float3 12.
    widths = {"pointer": 8, "drag_start": 8, "pivot": 12, "drag_pad": 12}
    described = sum(widths.get(k, 4) for k in g)
    record("gizmo: schema covers the whole stride", described == cap["elementSize"],
           "schema %d bytes vs element_size %d" % (described, cap["elementSize"]))


def guard_spline_undo(mcp):
    """3D: undo must reverse a close, preserve the selection bit, and leave knots identical.

    v1 preserved the whole flags word to protect the selection, which made the
    closed-path bit (also in flags) the one edit undo could never reverse.

    The knot readback is lane 0's, but `do_close` acts on whatever lane is
    ACTIVE, so an ambient lane other than 0 makes this guard fail for a reason
    that has nothing to do with undo. Assert the precondition instead of
    inheriting it.
    """
    lane = float(mcp.call("sentinel_state", {
        "action": "get",
        "path": "/sentinel/pipelines/Spline_Desk/control_outputs/active_lane",
    })["value"])
    record("undo: station is on lane 0 to begin with", lane == 0.0,
           "active_lane %g" % lane)
    if lane != 0.0:
        return

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


def guard_spline_arm_settles(mcp):
    """3D: the arm-then-execute latch must not stay armed once an edit has run.

    The arm machinery is what gives the desk an undo point, and it has now broken
    twice in ways nothing else could see: once by never arming, once by arming on
    every cook of a drag. A latched ``snapshot_armed`` is the silent version of
    the second failure -- the snapshot re-captures the CURRENT knots every cook,
    so undo restores the desk to exactly where it already is while the geometry,
    the readouts and the health all look perfectly correct.

    This cannot catch the mid-drag re-arm itself; no MCP call can produce a
    pointer drag, and the fix is retired by the hands-on pass rather than here.
    What it does catch is the latch failing to clear, which is the state that
    failure leaves behind and the one an automated run can actually reach.

    The zeros are not vacuous. A control output aimed at padding would read zero
    forever and pass this hollowly, so the offsets are anchored by their
    neighbour: ``last_command`` sits at byte 84 between ``pending_command`` (80)
    and ``snapshot_armed`` (88) in a 96-byte ``EditorState``, and it reads a live
    changing value below. If 84 is right, 80 and 88 are right.
    """
    def state(name):
        return float(mcp.call("sentinel_state", {
            "action": "get",
            "path": "/sentinel/pipelines/Spline_Desk/control_outputs/%s" % name,
        })["value"])

    idle_armed, idle_pending = state("snapshot_armed"), state("pending_command")
    record("spline: idle desk is not armed", idle_armed == 0.0 and idle_pending == 0.0,
           "snapshot_armed %g, pending_command %g" % (idle_armed, idle_pending))

    # A structural edit goes through the arm path by construction. After it has
    # settled both fields must be back to zero, and last_command must show the
    # edit actually executed rather than being stuck waiting.
    mcp.edge("Spline_Desk", "do_close")
    armed, pending = state("snapshot_armed"), state("pending_command")
    last = state("last_command")
    record("spline: arm latch clears after a structural edit",
           armed == 0.0 and pending == 0.0,
           "snapshot_armed %g, pending_command %g" % (armed, pending))
    record("spline: the armed edit reached execution", last == 7.0,
           "last_command %g (7 = close)" % last)
    mcp.edge("Spline_Desk", "do_undo")


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


# ---------------------------------------------------------------------------
# Phase 4 scope guards.
#
# Two of these assert defects the OPERATOR caught by looking at the running
# graph after the whole 4B harness had passed the audio scope eight ways. Both
# were invisible on Data Scope and obvious on Signal Trails: an audio stream's
# sample interval is exactly constant so the axis cannot jitter, and a filled
# area chart hid the stale live-edge column that a trail drawing exposed. They
# are guarded here so the next reader does not have to catch them by eye.

SCOPE_PIPE = "Data_Scope"
TRAIL_PIPE = "Signal_Trails"


def _scope_present(mcp, pipeline):
    listing = mcp.call("sentinel_pipeline", {"action": "list"})
    return any(p.get("id") == pipeline for p in listing.get("pipelines", []))


def _capture(mcp, pipeline, tag):
    import tempfile
    png = os.path.join(tempfile.gettempdir(), "guard_%s.png" % tag)
    mcp.call("sentinel_capture", {"action": "pipeline", "pipeline_id": pipeline, "filepath": png})
    return png


def _measure_mod():
    if WORKSPACE not in sys.path:
        sys.path.insert(0, os.path.join(WORKSPACE, "tools"))
    import data_scope_measure
    return data_scope_measure


def guard_scope_no_clipping(mcp):
    """Full scale must cover the samples on screen.

    The decayed peak is anchored at now while the plot shows history, so on its
    own it lets the scale fall below its own visible samples. Signature is a
    plotted height of 1.000: columns pinned flat against the top edge. A healthy
    plot tops out at 1/1.15 = 0.870, the headroom.
    """
    if not _scope_present(mcp, SCOPE_PIPE):
        skip("scope: autoscale covers the window", "%s not in the graph" % SCOPE_PIPE)
        return
    res = _measure_mod().measure(_capture(mcp, SCOPE_PIPE, "scope_clip"))
    peaks = [l["peak_height_frac"] for l in res["lanes"]]
    p95s = [l["p95_height_frac"] for l in res["lanes"]]
    clipped = [p for p in peaks if p > 0.95]
    empty = max(peaks) < 0.2
    record(
        "scope: autoscale covers the window",
        not clipped and not empty,
        "peaks %s p95 %s" % ([round(p, 3) for p in peaks], [round(p, 3) for p in p95s]),
    )


def guard_scope_reference_in_scale(mcp):
    """A reference above the recent peak must pull full scale up, not pin itself
    to the top edge where it stops reading as a reference at all.

    The reference only shows up in the answer when it EXCEEDS the peak, so the
    peak has to be out of the way first. Asserting against the material as-found
    passed with the mechanism deliberately deleted, because the audio was loud
    enough to set the same scale on its own. Raising the dB floor does not help
    either -- it compresses toward 0 dB, and this material's transients reach it.

    So the measurement is taken in the loop's quiet intro: rewind the WAV, shrink
    the span and half-life so the peak reflects only what has played since, and
    read within the first second and a half, before the drop.
    """
    if not _scope_present(mcp, SCOPE_PIPE):
        skip("scope: reference participates in scale", "%s not in the graph" % SCOPE_PIPE)
        return
    get = lambda p: float(mcp.call("sentinel_state", {
        "action": "get", "path": "/sentinel/pipelines/%s/%s" % (SCOPE_PIPE, p)})["value"])
    base = {k: get("parameters/" + k)
            for k in ("reference", "peak_halflife", "span_seconds")}
    try:
        mcp.set_param(SCOPE_PIPE, "peak_halflife", 0.25)
        # The window max holds the peak up until the loud samples scroll off, so
        # the span has to shrink too or this waits out the whole plot.
        mcp.set_param(SCOPE_PIPE, "span_seconds", 1.0)
        mcp.set_param(SCOPE_PIPE, "reference", 0.95)
        mcp.call("sentinel_state", {
            "action": "invoke",
            "path": "/sentinel/pipelines/Scope_Audio/actions/restart_file"})
        time.sleep(1.5)
        peak = get("control_outputs/low_peak")
        fs = get("control_outputs/low_fs")
        want = 0.95 * 1.15
        record(
            "scope: reference participates in scale",
            peak < 0.9 and fs >= want - 0.02,
            "quiet intro peak %.3f, reference 0.95 -> fs %.3f (need >= %.3f)"
            % (peak, fs, want),
        )
    finally:
        for k, v in base.items():
            mcp.set_param(SCOPE_PIPE, k, v)
        time.sleep(0.5)


def guard_trails_axis_stable(mcp):
    """The time axis must not be rebuilt from the instantaneous frame delta.

    samples_shown sets the horizontal mapping. Derived from a raw _DeltaTime it
    swung 12.4 samples of an 8 s span at a nominal 60 fps -- a 2.6% stretch every
    cook, about 42 px at 1727 wide -- and the operator saw the whole trace
    shivering. Smoothed, it holds inside 0.2%.
    """
    if not _scope_present(mcp, TRAIL_PIPE):
        skip("trails: time axis is stable", "%s not in the graph" % TRAIL_PIPE)
        return
    path = "/sentinel/pipelines/%s/control_outputs/samples_shown" % TRAIL_PIPE
    vals = []
    for _ in range(30):
        vals.append(float(mcp.call("sentinel_state", {"action": "get", "path": path})["value"]))
        time.sleep(0.05)
    mean = sum(vals) / len(vals)
    spread = (max(vals) - min(vals)) / max(mean, 1e-6)
    record(
        "trails: time axis is stable",
        spread < 0.01,
        "samples_shown %.1f-%.1f = %.2f%% of mean (need <1%%)" % (min(vals), max(vals), spread * 100),
    )


def guard_trails_live_edge(mcp):
    """The rightmost column must plot the newest sample, not a stale one.

    writeIdx is the NEXT slot to write and still holds the sample from one full
    ring ago, so fetching it draws thousand-sample-old data at the live edge.
    Because the trail connects consecutive columns, that renders as a vertical
    bar welded to the right edge that never scrolls away. See
    `data_scope_measure.edge_segment_lit` for the measured separation.

    Sampled over frames and channels rather than asserted once: the stale slot
    holds a different ring-old value every cook, so an individual frame can land
    close enough to the live value to look continuous. Against the break, 2 of
    24 channel-frames did.
    """
    if not _scope_present(mcp, TRAIL_PIPE):
        skip("trails: live edge is not stale", "%s not in the graph" % TRAIL_PIPE)
        return
    time.sleep(2.0)  # settle past the preset guard's console changes
    seg = _measure_mod().edge_segment_lit
    tall, total, worst = 0, 0, 0
    for k in range(3):
        for lane in seg(_capture(mcp, TRAIL_PIPE, "trail_edge_%d" % k), 2, 4):
            for n in lane:
                total += 1
                worst = max(worst, n)
                if n > 6:
                    tall += 1
        if k < 2:
            time.sleep(0.5)
    record(
        "trails: live edge is not stale",
        tall < 3,
        "%d/%d edge columns over 6 lit px, tallest %d (healthy max 5)"
        % (tall, total, worst),
    )


def run_guard(fn, *args):
    """Run one guard; an exception fails that guard only, not the whole suite.

    Without this a single guard raising -- a renamed port, a station that did not
    come back from a reload -- aborts the run, and every guard after it silently
    produces no line at all. A short run then looks like a clean one unless
    somebody counts the results, which is the failure mode this suite exists to
    prevent. The exception becomes a FAIL with its text attached, so the count
    stays honest and the cause is visible.
    """
    try:
        fn(*args)
    except Exception as exc:
        record("%s raised" % fn.__name__, False, "%s: %s" % (type(exc).__name__, exc))


def main():
    mcp = Mcp(SERVER)
    try:
        if mcp.call("sentinel_app", {"action": "ping"}).get("text", "").strip() == "":
            pass  # ping returns a bare PONG string on some builds
        for guard in (guard_health, guard_pad_direction, guard_pad_gesture_tracks,
                      guard_theme_governs,
                      guard_gizmo_state_integrity, guard_spline_readout_matches_knots,
                      guard_spline_undo, guard_spline_arm_settles, guard_gizmo_orbit,
                      guard_group_surfaces, guard_presets,
                      guard_scope_no_clipping, guard_scope_reference_in_scale,
                      guard_trails_axis_stable, guard_trails_live_edge):
            run_guard(guard, mcp)
    finally:
        mcp.close()

    run_guard(guard_bundle_identity)
    run_guard(guard_ui_rects)

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
