"""Generate HLSL label tables for the PHAGE canvases.

HLSL has no strings, so every caption lives in one flat ASCII table with a
(start, length) range per label id. `phLabel(P, anchor, scale, id)` in the
generated header draws label `id` with the shared sui3 bitmap face.

Usage: python tools/phage_labels.py   (rewrites every modules/*/labels.hlsli listed below)
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "modules"

LABELS = {
    "Phage_Plan": [
        "PHAGE / CONSTRUCTION PLAN",            # 0
        "PLAN",                                 # 1
        "SECTION THROUGH LEG",                  # 2
        "AUDIENCE",                             # 3
        "DRAG FEET IN PLAN, KNEES IN SECTION.  1-6 LEG  S SYMMETRY  R RESET  ESC CLEAR",  # 4
        "SYM ON",                               # 5
        "SYM OFF",                              # 6
        "UPPER",                                # 7
        "LOWER",                                # 8
        "REACH",                                # 9
        "OUT OF REACH",                         # 10
        "KNEE BELOW HIP",                       # 11
        "FEET CLASH",                           # 12
        "STANCE",                               # 13
        "REFERENCE",                            # 14
        "SPIDER",                               # 15
        "MANTIS",                               # 16
        "CRAB",                                 # 17
        "MOVERS",                               # 18
        "STROBES",                              # 19
        "BARS",                                 # 20
        "M",                                    # 21
        "HEAD CLEARANCE",                       # 22
        "EDITED",                               # 23
        "%",                                    # 24
        "DJ",                                   # 25
    ],
    "Phage_Kinetics": [
        "PHAGE / MOTION CONTROL",               # 0
        "BODY",                                 # 1
        "CAPSID",                               # 2
        "LEG",                                  # 3
        "HEIGHT",                               # 4
        "YAW",                                  # 5
        "SPIN",                                 # 6
        "SHEATH",                               # 7
        "LIFT",                                 # 8
        "SWING",                                # 9
        "PLAN",                                 # 10
        "ELEVATION",                            # 11
        "PROGRAMMER",                           # 12
        "REST HOLD",                            # 13
        "STRETCH",                              # 14
        "TARGET",                               # 15
        "M",                                    # 16
        "DEG",                                  # 17
        "MANUAL",                               # 18
        "DEMO",                                 # 19
        "FRONT ELEVATION",                      # 20
        "PLAN (LIVE)",                          # 21
        "REST",                                 # 22
    ],
    "Phage_Lighting": [
        "PHAGE / FIXTURES",                     # 0
        "ALL", "NONE", "MOVERS", "STROBES", "BARS", "AXES", "LEFT", "RIGHT",           # 1-8
        "PLATE", "CAPSID", "COLLAR", "KNEES", "FEET", "BOOTH", "LEGS", "ODD",         # 9-16
        "FRONT ELEVATION",                      # 17
        "PLAN (AUDIENCE BELOW)",                # 18
        "SELECTED",                             # 19
        "CLICK / DRAG SELECT   SHIFT ADD   CTRL TOGGLE   A ALL   ESC CLEAR",  # 20
        "PROGRAMMER",                           # 21
        "REFERENCE",                            # 22
        "HIGHLIGHT",                            # 23
        "SOLO",                                 # 24
        "WAITING FOR MOUNTS",                   # 25
    ],
    "Phage_Assembly": [
        "PHAGE / TRUSS ASSEMBLY",               # 0
        "TUBES",                                # 1
        "SOLIDS",                               # 2
    ],
    "Phage_Venue": [
        "PHAGE / ARENA",                        # 0
        "PLAN",                                 # 1
        "LONG SECTION",                         # 2
        "AUDIENCE",                             # 3
        "PEOPLE",                               # 4
        "HALL",                                 # 5
        "M",                                    # 6
        "ROOF CLEARANCE AT KINETIC MAX",        # 7
        "KINETIC MAX",                          # 8
        "BARS LIT",                             # 9
        "STAGE",                                # 10
        "X",                                    # 11
        "ROOF STEEL",                           # 12
        "CAPSID TOP AT REST",                   # 13
        "TOO LOW",                              # 14
        "OF 96",                                # 15
    ],
    "Phage_Program": [
        "PHAGE / PROGRAMMER SHEET",             # 0
        "PAN", "TILT", "LEVEL", "RING / PLATE", "COLOUR", "COLOUR 2", "MOVE LANE", "CHASE LANE",   # 1-8
        "COLOUR LANE", "PAN SIZE", "TILT SIZE", "SPREAD", "WIDTH", "OFFSET", "DIRECTION", "LOOK",  # 9-16
        "ORDER",                                # 17
        "MOVERS",                               # 18
        "STROBES",                              # 19
        "BARS",                                 # 20
        "AXES",                                 # 21
        "COMMIT",                               # 22
        "MASTER",                               # 23
        "PITCH",                                # 24
    ],
    "Phage_Show": [
        "PHAGE / SHOW STATE",                   # 0
        "KICK",                                 # 1
        "SNARE",                                # 2
        "HI-HAT",                               # 3
        "BUILD",                                # 4
        "PHRASE",                               # 5
        "BPM",                                  # 6
        "BEAT",                                 # 7
        "PALETTES",                             # 8
        "A",                                    # 9
        "B",                                    # 10
        "C",                                    # 11
        "STROBE",                               # 12
        "BLACKOUT",                             # 13
        "PROGRAMMER",                           # 14
        "REFERENCE CHASE",                      # 15
        "KINETICS",                             # 16
        "RAMP",                                 # 17
        "HELD",                                 # 18
        "SURFACE LANES",                        # 19
        "INTERNAL LANES",                       # 20
        "PER BEAT",                             # 21
        "DUTY",                                 # 22
        "STOPPED",                              # 23
        "HOLD",                                 # 24
    ],
    "Phage_LED": [
        "PHAGE / PIXEL BARS",                   # 0
        "LEGS",                                 # 1
        "PLATE",                                # 2
        "SHEATH",                               # 3
        "COLLAR",                               # 4
        "CAPSID",                               # 5
        "BOOTH",                                # 6
        "SOLID", "CHASE", "PULSE", "SEGMENTS", "SCATTER", "COMET", "TWIN", "FILL",       # 7-14
        "SCANNER", "BARCODE", "PLASMA", "SPARKLE", "HEARTBEAT", "CLIMB", "STROBE", "RIPPLE",  # 15-22
        "PROGRAMMER",                           # 23
        "REFERENCE",                            # 24
        "LIT",                                  # 25
        "PX",                                   # 26
    ],
}


def emit(labels):
    chars, ranges = [], []
    for text in labels:
        ranges.append((len(chars), len(text)))
        chars.extend(ord(c) for c in text.upper())
    lines = [
        "// Generated by tools/phage_labels.py. Edit the generator, not this file.",
        "#ifndef PH_LABELS_HLSLI",
        "#define PH_LABELS_HLSLI",
        f"static const uint PH_LBL_CH[{len(chars)}]={{" + ",".join(map(str, chars)) + "};",
        f"static const uint2 PH_LBL_RANGE[{len(ranges)}]={{" + ",".join(f"uint2({a},{b})" for a, b in ranges) + "};",
        "float phLabelWidth(uint id,float s){return (float)PH_LBL_RANGE[id].y*SUI3_ADVANCE*s;}",
        "float phLabel(float2 P,float2 anchor,float s,uint id){",
        " uint2 r=PH_LBL_RANGE[id];if(sui3RunMiss(P,anchor,s,(int)r.y))return 0;",
        " int k=(int)floor((P.x-anchor.x)/(SUI3_ADVANCE*s));if(k<0||k>=(int)r.y)return 0;",
        " float cov=sui3Glyph(P,anchor+float2((float)k*SUI3_ADVANCE*s,0),s,(int)PH_LBL_CH[r.x+(uint)k]);",
        " if(k>0)cov=max(cov,sui3Glyph(P,anchor+float2((float)(k-1)*SUI3_ADVANCE*s,0),s,(int)PH_LBL_CH[r.x+(uint)k-1]));",
        " return cov;}",
        "#endif",
    ]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    for module, labels in LABELS.items():
        folder = ROOT / module
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "labels.hlsli").write_text(emit(labels), encoding="utf-8")
        print(f"{module}: {len(labels)} labels")
