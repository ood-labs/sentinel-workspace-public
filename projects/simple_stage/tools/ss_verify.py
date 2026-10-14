"""Recall exactness: every FULL LOOK and RIG sequence, recalled through the Surface, must reach SS_Program's buffer as
tools/ss_looks.py wrote it, on every field the look owns, on every fixture of the plot.

    python tools/ss_verify.py                 FULL LOOKS 1-16 and RIG sequences 1-16
    python tools/ss_verify.py complete 3      one pad

A FULL look owns every field of every row; a RIG sequence owns aim, levels and every effect field (not palettes, which
stay with COLOR). Reads SS_Program's Fixture Program port, so it proves the whole path: the preset file, the recall,
the programmer's decode and the bridge's upload.
"""
from __future__ import annotations

import sys
import time

import ss_looks as LK
import ss_show as S
from ss_review import Mcp, command

# SS_Program's record (sheet.hlsli): aim=(pan,tilt,level,ring) routing=(beam palette, ring palette, move lane, chase
# lane) movement=(colour lane, pan size, tilt size, spread) timing=(width, offset, direction, look) extra.x=order.
FIELDS = {"pan": ("aim", 0), "tilt": ("aim", 1), "level": ("aim", 2), "ring": ("aim", 3),
          "beam_palette": ("routing", 0), "ring_palette": ("routing", 1), "move_lane": ("routing", 2),
          "int_lane": ("routing", 3), "color_lane": ("movement", 0), "pan_amp": ("movement", 1),
          "tilt_amp": ("movement", 2), "spread": ("movement", 3), "width": ("timing", 0), "offset": ("timing", 1),
          "reverse": ("timing", 2), "look": ("timing", 3), "order": ("extra", 0)}
TOL = {"pan": .01, "tilt": .01, "pan_amp": .01, "tilt_amp": .01}


def expected(kind, slot):
    """The rows a pad sets, field by field, as the generator built them (fmt-rounded, as stored)."""
    if kind == "complete":
        name, st, ef, col, _ = LK.FULL[slot - 1]
        layers = dict(LK.EFFECTS)[ef][0]
        rows = S.merge(LK.full_rows(st, col), LK.look_rows(layers))
        keys = set(S.STATIC_F) | set(S.EFFECT_F)
    else:
        seq = (LK.SEQUENCES + [None])[slot - 1]
        if seq is None:
            # BLACKOUT: every level and ring of every light at 0, the effects left as they were
            name, rows, keys = "BLACKOUT", S.blackout_rows(S.LIGHTS), S.STATIC_MASK
        else:
            name, shape, move, parts, _ = seq
            rows = LK.seq_rows(shape, move, parts)
            keys = S.STATIC_MASK | set(S.EFFECT_F)
    want = {}
    for row, layer in S.LAYER_OF.items():
        f = S.FX[row % S.L.SLOTS] if row < S.L.SLOTS else S.FX[(row - (S.BEAM0 if row < S.LAYER2 else S.LAYER2))]
        if f["unused"] or row not in rows:
            continue
        for k, v in rows[row].items():
            if k in keys and k in S.OWNS[layer]:
                want[(row, k)] = float(S.fmt(k, v))
    assert want, f"{kind} {slot}: nothing to compare"     # a check with no fields cannot fail
    return name, want


def program(m):
    r = m.call("sentinel_pipeline", {"action": "capture_data_port", "pipeline_id": "SS_Program",
                                     "port_name": "Fixture Program", "max_elements": S.L.ROWS})
    return r.get("elements") or []


def check(m, kind, slot):
    name, want = expected(kind, slot)
    ack = command(m, f"preset|recall|{kind}|{slot}")
    deadline, bad = time.time() + 8, None
    while time.time() < deadline:
        time.sleep(.6)
        recs = program(m)
        bad = []
        for (row, k), v in want.items():
            part, i = FIELDS[k]
            got = recs[row][part][i] if row < len(recs) else None
            if got is None or abs(got - v) > TOL.get(k, .002):
                bad.append((row, k, v, got))
        if not bad:
            break
    print(f"{kind:9s} {slot:2d} {name:11s} {ack:9s} {len(want):5d} fields  " +
          ("exact" if not bad else f"{len(bad)} differ, e.g. {bad[:3]}"))
    return not bad


def main():
    m = Mcp()
    try:
        if len(sys.argv) == 3:
            ok = check(m, sys.argv[1], int(sys.argv[2]))
        else:
            ok = all([check(m, k, s) for k in ("complete", "sequence") for s in range(1, 17)])
        print("recall exactness: " + ("ok" if ok else "FAILED"))
        sys.exit(0 if ok else 1)
    finally:
        m.close()


if __name__ == "__main__":
    main()
