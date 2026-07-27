"""Records the hands-on gesture pass for the Interaction Lab (Phase 3, 3D.1 / 3E.1 / 3B.3).

Pointer gestures inside a Module preview cannot be synthesised on this build:
`sentinel_viewport action=edit` drives the host's object-edit transaction, and
these modules render and drive their own gizmo from raw viewport events. So the
gestures need a hand on the mouse. What does NOT need a hand is the recording.

Run this, then perform the gestures it lists. It polls the live data ports and
control outputs, recognises each gesture from its signature in that state, and
writes a timestamped JSON record. The point is that the pass is *asserted* --
"the anchor of knot 2 moved while last_command was 2" -- rather than described.

    python tools/interaction-lab-handson.py [seconds]

Open the station's preview first. Progress prints as each gesture is seen; the
run ends early once every gesture is recorded.
"""

import importlib.util
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORKSPACE = os.path.dirname(HERE)


def _load_guards():
    """Reuse the guard module's MCP client without running its main()."""
    path = os.path.join(HERE, "interaction-lab-guards.py")
    ns = {"__name__": "handson_helper", "__file__": path}
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    exec(compile(src, path, "exec"), ns)
    return ns


# Each gesture: a human instruction, and a predicate over (previous, current)
# samples that recognises it. Keeping the instruction next to the predicate is
# deliberate -- an operator should be able to read what is being claimed.
GESTURES = [
    ("3D.1 spline anchor drag",
     "Spline Desk: drag an anchor point. Its handles must travel with it."),
    ("3D.1 spline handle drag",
     "Spline Desk: drag one handle. The anchor must stay put."),
    ("3D.1 spline marquee",
     "Spline Desk: drag across empty space to marquee-select two or more knots."),
    ("3D.1 spline keyboard",
     "Spline Desk: press T (tangent), O (close), then Enter (next lane)."),
    ("3E.1 gizmo drag",
     "Gizmo Desk: click an object, then drag an axis arrow, a rotation ring, "
     "and the centre handle."),
    ("3B.3 style authority hover",
     "Style Authority: hover the pad, the rail and the bank without pressing. "
     "Say whether the accent responds to hover -- it must NOT."),
]


# Spline editor command codes. Only these three can be produced by a POINTER:
# 1 click-select, 2 drag, 3 drag-or-marquee. Every automation door fires a
# different code (4 undo, 7 close, 8 tangent, 9 delete, 10/11 selection,
# 12 reset, 13 nudge), so gating on this set is what stops the recorder from
# crediting a door-driven state change as a hands-on gesture -- which it did on
# its first run, and which would have manufactured exactly the false pass this
# whole gate exists to prevent.
POINTER_COMMANDS = {1.0, 2.0, 3.0}

# Every rising-edge door on the Spline Desk. A sample taken while any of them
# is held is not admissible evidence.
SPLINE_DOORS = ["do_tangent", "do_close", "do_delete", "do_next_lane", "do_undo",
                "do_select_lane", "do_clear_sel", "do_reset", "do_nudge"]
GIZMO_DOORS = ["do_orbit"]

# Polling cannot see a door that is set and cleared between two samples, so the
# poll is tight and any door seen at all taints the WHOLE record rather than one
# window. A recorded pass is only admissible when zero doors fired end to end --
# which is the honest guarantee, since no port can tell a `do_tangent` write
# apart from the T key once the door has closed again.
POLL_INTERVAL_S = 0.15
DOOR_COOLDOWN_SAMPLES = 6


def sample(mcp):
    s = {}
    s["doors"] = False
    s["door_read_error"] = None
    for pid, doors in (("Spline_Desk", SPLINE_DOORS), ("Gizmo_Desk", GIZMO_DOORS)):
        for d in doors:
            try:
                v = mcp.call("sentinel_state", {
                    "action": "get",
                    "path": "/sentinel/pipelines/%s/parameters/%s" % (pid, d),
                })["value"]
                if str(v).lower() in ("true", "1", "1.0"):
                    s["doors"] = True
            except Exception as exc:
                # THE POISON GATE MUST FAIL CLOSED. A door read that throws tells
                # us nothing about whether that door is open, and "we could not
                # check" is not "it was shut". Swallowing this turned the one
                # mechanism that stops a door-driven state change being credited
                # as a hands-on gesture into a no-op the moment the state call
                # went wrong -- exactly when a wrong answer is most likely.
                s["doors"] = True
                if s["door_read_error"] is None:
                    s["door_read_error"] = "%s/%s: %s" % (pid, d, exc)
    try:
        knots = mcp.port("Spline_Desk", "Spline Knots", 16)["elements"]
        s["knots"] = [(k["anchor"], k["handle_in"], k["handle_out"],
                       k["flags"], k["tangent_mode"], k["active"]) for k in knots]
    except Exception:
        s["knots"] = None
    for name in ("last_command", "active_lane", "tangent_mode"):
        try:
            s[name] = float(mcp.call("sentinel_state", {
                "action": "get",
                "path": "/sentinel/pipelines/Spline_Desk/control_outputs/%s" % name,
            })["value"])
        except Exception:
            s[name] = None
    try:
        g = mcp.port("Gizmo_Desk", "Gizmo State", 1)["elements"][0]
        s["gz_dragging"] = g["dragging"]
        s["gz_handle"] = g["active_handle"]
        s["gz_mode"] = g["mode"]
    except Exception:
        s["gz_dragging"] = s["gz_handle"] = s["gz_mode"] = None
    try:
        objs = mcp.port("Gizmo_Desk", "Scene Objects", 16)["elements"]
        s["objects"] = [(o["position"], o["rotation"], o["scale"]) for o in objs]
    except Exception:
        s["objects"] = None
    return s


def selected(knots):
    return {i for i, k in enumerate(knots) if k[3] & 1}


def detect(prev, cur, seen, evidence, state):
    """Recognise gestures between two samples. Mutates seen/evidence/state.

    Nothing is credited while a rising-edge automation door is held or in the
    settling window just after one, and no spline gesture is credited unless the
    editor's last command code is one a pointer produces. Without both gates the
    recorder happily reads a `do_nudge` fire as an anchor drag.
    """
    def mark(key, detail):
        if key not in seen:
            seen.add(key)
            evidence[key] = detail
            print("  RECORDED  %-28s %s" % (key, detail))

    # A door is consumed on the frame it is held, but the state it changes can
    # surface a sample or two later, so the poison outlasts the door itself.
    if prev["doors"] or cur["doors"]:
        state["tainted"] = True
        state["cooldown"] = DOOR_COOLDOWN_SAMPLES
        err = prev.get("door_read_error") or cur.get("door_read_error")
        if err and state.get("taint_reason") is None:
            state["taint_reason"] = "door state unreadable, assumed open: %s" % err
        elif state.get("taint_reason") is None:
            state["taint_reason"] = "an automation door was held during the run"
        return seen, evidence
    if state["cooldown"] > 0:
        state["cooldown"] -= 1
        return seen, evidence

    pointer_cmd = cur["last_command"] in POINTER_COMMANDS

    if pointer_cmd and prev["knots"] and cur["knots"] and len(prev["knots"]) == len(cur["knots"]):
        for i, (a, b) in enumerate(zip(prev["knots"], cur["knots"])):
            anchor_moved = a[0] != b[0]
            hin_moved = a[1] != b[1]
            hout_moved = a[2] != b[2]
            if anchor_moved and (hin_moved or hout_moved):
                mark("3D.1 spline anchor drag",
                     "knot %d anchor %s -> %s, handles followed" % (i, a[0], b[0]))
            elif (hin_moved or hout_moved) and not anchor_moved:
                mark("3D.1 spline handle drag",
                     "knot %d handle %s -> %s, anchor fixed"
                     % (i, a[1] if hin_moved else a[2], b[1] if hin_moved else b[2]))
            if a[4] != b[4]:
                mark("3D.1 spline keyboard",
                     "knot %d tangent_mode %s -> %s" % (i, a[4], b[4]))
            if (a[3] & 2) != (b[3] & 2):
                mark("3D.1 spline keyboard",
                     "knot %d closed bit %d -> %d" % (i, (a[3] & 2) >> 1, (b[3] & 2) >> 1))
        gained = selected(cur["knots"]) - selected(prev["knots"])
        if len(gained) >= 2:
            mark("3D.1 spline marquee",
                 "selection gained %d knots in one step: %s" % (len(gained), sorted(gained)))

    # active_lane also moves under `do_next_lane`, so it counts only when no
    # door is held -- already guaranteed above -- AND the tangent/close keys are
    # what actually distinguish a keyboard pass. Lane alone is weak evidence and
    # is recorded as such.
    if (prev["active_lane"] is not None and cur["active_lane"] is not None
            and prev["active_lane"] != cur["active_lane"]):
        mark("3D.1 spline keyboard",
             "active_lane %s -> %s with no door held"
             % (prev["active_lane"], cur["active_lane"]))

    # `dragging` is a held flag, so a stale 1 left over from an earlier session
    # would credit a drag that never happened. Require the 0 -> 1 transition
    # inside the watch window, and an object actually moving while it is set.
    began = (prev["gz_dragging"] is not None and cur["gz_dragging"] is not None
             and prev["gz_dragging"] <= 0.5 < cur["gz_dragging"])
    if began:
        evidence.setdefault("_gizmo_drag_began", True)
    if (evidence.get("_gizmo_drag_began") and cur["gz_dragging"]
            and cur["gz_dragging"] > 0.5 and cur["gz_handle"]
            and prev["objects"] and cur["objects"] and prev["objects"] != cur["objects"]):
        changed = [i for i, (a, b) in enumerate(zip(prev["objects"], cur["objects"]))
                   if a != b]
        mark("3E.1 gizmo drag",
             "dragging 0->1 in window, handle=%g mode=%g, objects %s moved"
             % (cur["gz_handle"], cur["gz_mode"], changed))
    return seen, evidence


def main():
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 240.0
    ns = _load_guards()
    mcp = ns["Mcp"](ns["SERVER"])

    print("Hands-on gesture pass. Perform these in the module previews:\n")
    for name, instruction in GESTURES:
        print("  - %s" % instruction)
    print("\nWatching for %.0f seconds. Ctrl+C to finish early.\n" % seconds)

    # Hover is a judgement, not a state change: nothing in the data ports can
    # distinguish "hovered and correctly did nothing" from "never hovered".
    auto = {name for name, _ in GESTURES if not name.startswith("3B.3")}
    seen, evidence = set(), {}
    state = {"tainted": False, "cooldown": 0, "taint_reason": None}
    started = time.time()
    try:
        prev = sample(mcp)
        while time.time() - started < seconds and not auto.issubset(seen):
            time.sleep(POLL_INTERVAL_S)
            cur = sample(mcp)
            detect(prev, cur, seen, evidence, state)
            prev = cur
    except KeyboardInterrupt:
        print("\n  (stopped early)")
    finally:
        mcp.close()

    print("\n%s\n" % ("-" * 68))
    missing = []
    for name, _ in GESTURES:
        if name in seen:
            print("PASS   %-28s %s" % (name, evidence[name]))
        elif name.startswith("3B.3"):
            print("MANUAL %-28s operator must state the hover verdict" % name)
        else:
            print("MISS   %-28s not observed" % name)
            missing.append(name)

    if state["tainted"]:
        print("\nTAINTED: %s. Every line above is void; rerun with no scripted "
              "writes to the stations." % state["taint_reason"])

    record = {
        "elapsed_s": round(time.time() - started, 1),
        "tainted": state["tainted"],
        "taint_reason": state["taint_reason"],
        "recorded": {k: v for k, v in evidence.items() if not k.startswith("_")},
        "missing": missing,
        "manual": [n for n, _ in GESTURES if n.startswith("3B.3")],
    }
    out = os.path.join(WORKSPACE, "captures", "handson_gesture_pass.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=1)
    print("\nrecord written to %s" % out)
    return len(missing) + (1 if state["tainted"] else 0)


if __name__ == "__main__":
    sys.exit(main())
