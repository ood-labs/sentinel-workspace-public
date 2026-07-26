"""Sweep 2C3 lateral inhibition on NON-HELD-OUT patterns only.

`halftime_shuffle_88` and `kick_snare_coincident_124` are held out by the phase
doc and must never influence a tuning choice. kick_snare_coincident is exactly
the pattern symmetric inhibition should hurt most, which is precisely why it is
not allowed to pick the value.

LANE MAP IS EXPLICIT AND NOT OPTIONAL. score_detector.py defaults to
`lane_map.json`, which targets the OLD `pulse_baseline` detector on Mel Bands.
Scoring pulse2 with that default silently measures the wrong pipeline and
reports it as a regression. That mistake cost one full corpus run; the constant
below exists so it cannot recur here.
"""
import json, subprocess, sys

LANE_MAP = "lane_map_pulse2.json"

HELD_OUT = {"halftime_shuffle_88", "kick_snare_coincident_124"}
TUNE = ["four_on_floor_128", "hats_only_150", "dense_140",
        "breakbeat_170", "sparse_90", "syncopated_funk_105",
        "hats_under_loud_kick_150", "quiet_intro_drop_128"]
assert not (set(TUNE) & HELD_OUT), "held-out pattern leaked into the tuning set"

with open(LANE_MAP) as f:
    assert json.load(f)["detector"] == "pulse2_analyzer", \
        f"{LANE_MAP} does not target pulse2_analyzer"


def tag(cfg):
    g, tau = cfg
    return f"_sweep_inhibit_g{g}_t{tau}"


def run(cfg):
    g, tau = cfg
    out = subprocess.run(
        [sys.executable, "score_detector.py",
         "--lane-map", LANE_MAP,
         "--subphase", tag(cfg),
         "--patterns", *TUNE,
         "--set", f"inhibit_gain={g}", f"inhibit_tau_hops={tau}"],
        capture_output=True, text=True, timeout=3600)
    return out.stdout + out.stderr


def summarise(cfg):
    """Aggregate F1 plus the cross-lane false positives 2C3 actually targets."""
    with open(f"scores/{tag(cfg)}.json") as f:
        d = json.load(f)
    # The saved table records which pipeline produced it. Assert it, so a wrong
    # --lane-map can never again be read as a detector regression.
    assert d["detector"] == "pulse2_analyzer", \
        f"scored the wrong detector: {d['detector']}"
    tot = {}
    for r in d["results"]:
        for ln, v in r["lanes"].items():
            a = tot.setdefault(ln, {"fp": 0, "tp": 0, "fn": 0})
            a["fp"] += v["fp"]; a["tp"] += v["tp"]; a["fn"] += v["fn"]
    agg = d.get("aggregate_f1") if isinstance(d, dict) else None
    return agg, tot


if __name__ == "__main__":
    # args are "gain,tau" pairs, e.g.  python sweep_inhibit.py 0,6 0.5,12 0.8,12
    cfgs = [tuple(float(v) for v in a.split(",")) for a in sys.argv[1:]]
    for cfg in cfgs:
        txt = run(cfg)
        with open(f"scores/{tag(cfg)}.txt", "w") as f:
            f.write(txt)
        print(f"===== inhibit_gain={cfg[0]} tau_hops={cfg[1]} =====")
        print("\n".join([l for l in txt.splitlines() if l.strip()][-14:]))
        try:
            agg, tot = summarise(cfg)
            print(f"  aggregate_f1={agg}")
            for ln, a in sorted(tot.items()):
                rec = a["tp"] / max(a["tp"] + a["fn"], 1)
                print(f"  {ln:6s} fp={a['fp']:4d} tp={a['tp']:4d} "
                      f"fn={a['fn']:3d} recall={rec:.3f}")
        except Exception as e:
            print(f"  (summary unavailable: {e})")
        sys.stdout.flush()
