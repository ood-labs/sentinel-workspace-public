"""Interaction Lab type tool: one SDF atlas, many kerned label tables.

    python tools/il_type.py atlas            # bake modules/_shared/type/il_type.png + il_type_metrics.hlsli
    python tools/il_type.py labels           # regenerate every modules/*/labels.txt -> _labels.generated.hlsli
    python tools/il_type.py labels Kit Touch # only these modules
    python tools/il_type.py all              # both

A module whose manifest declares host `viewport.controls` also gets `_ui.generated.hlsli`: the
control indices and rects, stamped with the manifest's hash the way tools/module-ui.ps1 stamps
its header, so the workspace validator can tell when they are stale.

THE ATLAS packs three faces into the R, G and B channels of one texture, on one shared cell
grid, so a single texture sample serves any face:

    R  IBM Plex Sans Condensed Regular   labels, captions, body
    G  IBM Plex Sans Condensed SemiBold  titles, selected names
    B  IBM Plex Mono Regular             numbers and anything that must not jitter

Every glyph sits at the same origin inside its cell, so a glyph's quad is just its cell placed
at (pen - origin). Each channel stores a signed distance (0.5 = edge, inside bright, +-SPREAD
base px mapped to 0..1), rendered at 4x and reduced so edges are exact at the base size.

LABELS are generated per module from `labels.txt`, one line per label:

    TITLE @bold @track=0.06 = INTERACTION LAB
    HINT                    = drag to move, wheel to scale

Flags: @sans (default), @bold, @mono, @track=<em>. Kerning and tracking are baked into each
label's glyph offsets here, at generation time, so the shader never needs a kerning table:
it binary-searches the precomputed offsets. Dynamic text (numbers) is set in the mono face,
whose fixed advance makes glyph lookup O(1).

Fonts: SIL Open Font License 1.1 - tools/fonts/IBM_PLEX_OFL.txt (copied beside the atlas).
"""
import hashlib
import os
import re
import sys
import shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MODULES = os.path.join(ROOT, 'modules')
FONT_DIR = os.path.join(HERE, 'fonts')

FACES = [
    ('sans', 'IBMPlexSansCondensed-Regular.ttf'),
    ('bold', 'IBMPlexSansCondensed-SemiBold.ttf'),
    ('mono', 'IBMPlexMono-Regular.ttf'),
]
FACE_INDEX = {name: i for i, (name, _) in enumerate(FACES)}

EM = 48          # base em size in atlas pixels
SPREAD = 8       # +-distance (base px) stored in 0..1
SS = 4           # supersample factor for the masks
COLS = 16
FIRST, LAST = 32, 126
GLYPHS = [chr(c) for c in range(FIRST, LAST + 1)]
OFFSET_SCALE = 16.0   # label offsets are stored in 1/16 base px

ATLAS_PNG = os.path.join(MODULES, '_shared', 'type', 'il_type.png')
METRICS_HLSLI = os.path.join(MODULES, '_shared', 'ui', 'il_type_metrics.hlsli')


def load(face, size):
    return ImageFont.truetype(os.path.join(FONT_DIR, FACES[face][1]), size)


def bake_atlas():
    from scipy.ndimage import distance_transform_edt   # only the atlas needs scipy
    hi = [load(f, EM * SS) for f in range(len(FACES))]
    # Shared cell geometry from the union of every glyph's ink box (hi-res px, origin at pen/baseline)
    L = R = A = D = 0
    for f in hi:
        for ch in GLYPHS:
            x0, y0, x1, y1 = f.getbbox(ch, anchor='ls')
            L, R, A, D = max(L, -x0), max(R, x1), max(A, -y0), max(D, y1)
    L, R, A, D = [int(np.ceil(v / SS)) for v in (L, R, A, D)]
    cw = SPREAD + L + R + SPREAD
    ch_ = SPREAD + A + D + SPREAD
    ox, oy = SPREAD + L, SPREAD + A
    rows = (len(GLYPHS) + COLS - 1) // COLS
    W, H = COLS * cw, rows * ch_

    channels = []
    for fi, f in enumerate(hi):
        mask = Image.new('L', (W * SS, H * SS), 0)
        d = ImageDraw.Draw(mask)
        for gi, ch in enumerate(GLYPHS):
            cx, cy = (gi % COLS) * cw, (gi // COLS) * ch_
            d.text(((cx + ox) * SS, (cy + oy) * SS), ch, font=f, fill=255, anchor='ls')
        m = np.asarray(mask) > 127
        di = distance_transform_edt(m)
        do = distance_transform_edt(~m)
        sd = (di - do) / SS                               # base px, + inside
        sd = sd.reshape(H, SS, W, SS).mean(axis=(1, 3))   # reduce to base resolution
        channels.append(np.clip(0.5 + sd / (2.0 * SPREAD), 0.0, 1.0))
        print(f'  face {FACES[fi][0]}: done')

    rgb = np.stack(channels, axis=-1)
    img = np.concatenate([rgb, np.ones((H, W, 1))], axis=-1)
    os.makedirs(os.path.dirname(ATLAS_PNG), exist_ok=True)
    Image.fromarray((img * 255.0 + 0.5).astype(np.uint8), 'RGBA').save(ATLAS_PNG)
    shutil.copy(os.path.join(FONT_DIR, 'IBM_PLEX_OFL.txt'), os.path.join(os.path.dirname(ATLAS_PNG), 'IBM_PLEX_OFL.txt'))

    # Metrics at the base em
    base = [load(f, EM) for f in range(len(FACES))]
    adv, cap, xh, asc, desc = [], [], [], [], []
    for fi, f in enumerate(hi):
        adv += [f.getlength(c) / SS for c in GLYPHS]
        cap.append(-f.getbbox('H', anchor='ls')[1] / SS)
        xh.append(-f.getbbox('x', anchor='ls')[1] / SS)
        a, dd = f.getmetrics()
        asc.append(a / SS)
        desc.append(dd / SS)
    mono_adv = hi[2].getlength('0') / SS

    def flist(v, per=12):
        rows_ = [', '.join(f'{x:.3f}' for x in v[i:i + per]) for i in range(0, len(v), per)]
        return ',\n    '.join(rows_)

    out = f"""// GENERATED by tools/il_type.py atlas - do not edit.
// IBM Plex Sans Condensed (Regular, SemiBold) + IBM Plex Mono, SIL OFL 1.1.
#ifndef IL_TYPE_METRICS_HLSLI
#define IL_TYPE_METRICS_HLSLI

#define IL_TYPE_EM      {EM:.1f}
#define IL_TYPE_SPREAD  {SPREAD:.1f}
#define IL_TYPE_COLS    {COLS}u
#define IL_TYPE_FIRST   {FIRST}u
#define IL_TYPE_COUNT   {len(GLYPHS)}u
#define IL_TYPE_CELL    float2({cw:.1f}, {ch_:.1f})
#define IL_TYPE_ORIGIN  float2({ox:.1f}, {oy:.1f})
#define IL_TYPE_ATLAS   float2({W:.1f}, {H:.1f})
#define IL_MONO_ADV     {mono_adv:.4f}

// cap height, x height, ascent, descent per face (sans, bold, mono), base px at the em
static const float IL_TYPE_CAP[3]  = {{ {cap[0]:.3f}, {cap[1]:.3f}, {cap[2]:.3f} }};
static const float IL_TYPE_XH[3]   = {{ {xh[0]:.3f}, {xh[1]:.3f}, {xh[2]:.3f} }};
static const float IL_TYPE_ASC[3]  = {{ {asc[0]:.3f}, {asc[1]:.3f}, {asc[2]:.3f} }};
static const float IL_TYPE_DESC[3] = {{ {desc[0]:.3f}, {desc[1]:.3f}, {desc[2]:.3f} }};

// advance per glyph (ASCII 32..126), base px, face-major
static const float IL_TYPE_ADV[{len(adv)}] = {{
    {flist(adv)}
}};

#endif
"""
    with open(METRICS_HLSLI, 'w', newline='\n') as fh:
        fh.write(out)
    print(f'atlas {W}x{H}, cell {cw}x{ch_}, origin ({ox},{oy}) -> {ATLAS_PNG}')


LINE = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*((?:@[a-z]+(?:=[-0-9.]+)?\s*)*)=\s?(.*)$')


def parse_labels(path):
    labels = []
    with open(path, encoding='utf-8') as fh:
        for n, raw in enumerate(fh, 1):
            s = raw.rstrip('\n')
            if not s.strip() or s.lstrip().startswith('#'):
                continue
            m = LINE.match(s)
            if not m:
                raise SystemExit(f'{path}:{n}: cannot parse: {s!r}')
            name, flags, text = m.group(1), m.group(2).split(), m.group(3)
            face, track = 'sans', 0.0
            for fl in flags:
                if fl in ('@sans', '@bold', '@mono'):
                    face = fl[1:]
                elif fl.startswith('@track='):
                    track = float(fl.split('=')[1])
                else:
                    raise SystemExit(f'{path}:{n}: unknown flag {fl}')
            bad = [c for c in text if not (FIRST <= ord(c) <= LAST)]
            if bad:
                raise SystemExit(f'{path}:{n}: non-ASCII characters {bad!r} in {name}')
            if len(text) > 63:
                raise SystemExit(f'{path}:{n}: label {name} longer than 63 characters')
            labels.append((name, FACE_INDEX[face], track, text))
    names = [l[0] for l in labels]
    dup = {x for x in names if names.count(x) > 1}
    if dup:
        raise SystemExit(f'{path}: duplicate label ids {sorted(dup)}')
    return labels


CONTROL = re.compile(r'^\s*-\s*\{.*?\bid:\s*([A-Za-z_][A-Za-z0-9_]*).*?\brect:\s*\[([^\]]+)\]')


def parse_controls(manifest):
    """viewport.controls entries in manifest order, as (id, [x0,y0,x1,y1] strings)."""
    if not os.path.isfile(manifest):
        return []
    out, inside = [], False
    with open(manifest, encoding='utf-8') as fh:
        for raw in fh:
            s = raw.split('#', 1)[0].rstrip()
            if re.match(r'^\s*controls:\s*$', s):
                inside = True
                continue
            if inside and s and not s.lstrip().startswith('-') and not re.match(r'^\s{4,}', s):
                inside = False
            m = CONTROL.match(s) if inside else None
            if m:
                nums = [x.strip() for x in m.group(2).split(',')]
                assert len(nums) == 4, s
                out.append((m.group(1), nums))
    return out


def manifest_sha256(manifest):
    """The hash tools/validate-official-examples.ps1 compares: UTF-8 text, line endings folded to LF."""
    with open(manifest, 'rb') as fh:
        text = fh.read().decode('utf-8-sig').replace('\r\n', '\n').replace('\r', '\n')
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def gen_controls(module_dir, controls):
    rows = '\n'.join(f'#define UI_{cid.upper():<22} {i}u\nstatic const float4 UI_RECT_{cid.upper()} = float4({", ".join(r)});'
                     for i, (cid, r) in enumerate(controls))
    out = f"""// GENERATED by tools/il_type.py labels from manifest.yaml - do not edit.
// manifest-sha256: {manifest_sha256(os.path.join(module_dir, 'manifest.yaml'))}
#ifndef IL_UI_GENERATED_HLSLI
#define IL_UI_GENERATED_HLSLI

// host viewport.controls, manifest order (index into _ViewportControlState)
{rows}
#define UI_CONTROL_COUNT {len(controls)}u

#endif
"""
    dst = os.path.join(module_dir, '_ui.generated.hlsli')
    with open(dst, 'w', newline='\n') as fh:
        fh.write(out)
    print(f'{os.path.basename(module_dir)}: {len(controls)} host controls -> {dst}')


def gen_labels(module_dir):
    src = os.path.join(module_dir, 'labels.txt')
    labels = parse_labels(src)
    fonts = [load(f, EM * SS) for f in range(len(FACES))]
    info, chars, offs = [], [], []
    for name, face, track, text in labels:
        f = fonts[face]
        start = len(chars)
        xs = []
        for k in range(len(text) + 1):
            x = f.getlength(text[:k]) / SS + track * EM * k   # kerned prefix + tracking
            xs.append(x)
        if text:
            xs[-1] -= track * EM                          # no trailing tracking on the width
        chars += [ord(c) - FIRST for c in text]
        offs += [int(round(x * OFFSET_SCALE)) for x in xs]
        assert max(offs[-len(xs):]) < 65536, name
        info.append((start, len(text), face, len(offs) - len(xs)))

    def pack(vals, per, bits):
        out = []
        for i in range(0, len(vals), per):
            w = 0
            for j, v in enumerate(vals[i:i + per]):
                w |= (v & ((1 << bits) - 1)) << (bits * j)
            out.append(w)
        return out or [0]

    char_words = pack(chars, 4, 8)
    off_words = pack(offs, 2, 16)
    # info word: char start (14b) | len (6b) | face (2b) ; offset start in its own array
    info_words = [(s & 0x3FFF) | ((n & 0x3F) << 14) | ((f & 3) << 20) for s, n, f, _ in info]
    off_start = [o for _, _, _, o in info]
    total = len(char_words) + len(off_words) + 2 * len(info_words)
    if total > 3600:
        raise SystemExit(f'{module_dir}: label tables use {total} literals; split labels.txt (shader limit 4096)')

    def ulist(v, per=10):
        rows = [', '.join(f'0x{x:08X}u' for x in v[i:i + per]) for i in range(0, len(v), per)]
        return ',\n    '.join(rows)

    defs = '\n'.join(f'#define LB_{name:<24} {i}u   // {FACES[face][0]:<4} "{text}"'
                     for i, (name, face, _, text) in enumerate(labels))
    controls = parse_controls(os.path.join(module_dir, 'manifest.yaml'))
    ctl = ''
    if controls:
        gen_controls(module_dir, controls)
        ctl = '#include "_ui.generated.hlsli"   // host viewport.controls\n'
    out = f"""// GENERATED by tools/il_type.py labels from labels.txt + manifest.yaml - do not edit.
#ifndef IL_LABELS_GENERATED_HLSLI
#define IL_LABELS_GENERATED_HLSLI

{defs}

{ctl}

#define IL_LABEL_COUNT {len(labels)}u
static const uint IL_LB_INFO[{len(info_words)}] = {{
    {ulist(info_words)}
}};
static const uint IL_LB_OFF0[{len(off_start)}] = {{
    {ulist(off_start)}
}};
static const uint IL_LB_CHARS[{len(char_words)}] = {{
    {ulist(char_words)}
}};
static const uint IL_LB_OFFS[{len(off_words)}] = {{
    {ulist(off_words)}
}};

#endif
"""
    dst = os.path.join(module_dir, '_labels.generated.hlsli')
    with open(dst, 'w', newline='\n') as fh:
        fh.write(out)
    print(f'{os.path.basename(module_dir)}: {len(labels)} labels, {total} literals -> {dst}')


def all_label_modules(selected):
    dirs = []
    for name in sorted(os.listdir(MODULES)):
        d = os.path.join(MODULES, name)
        if os.path.isfile(os.path.join(d, 'labels.txt')) and (not selected or name in selected):
            dirs.append(d)
    return dirs


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if cmd in ('atlas', 'all'):
        bake_atlas()
    if cmd in ('labels', 'all'):
        for d in all_label_modules(sys.argv[2:]):
            gen_labels(d)
