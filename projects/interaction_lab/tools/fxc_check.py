"""Offline compile check + timing for one Module pass (NOT used by Sentinel).

    python tools/fxc_check.py Kit layout            # compile modules/Kit/layout.hlsl as cs_5_0
    python tools/fxc_check.py Kit raster --O1       # try another optimisation level

Builds a stub prelude for the globals Sentinel injects (cbuffer with the manifest's parameters,
viewport events, host control state, panel labels, samplers, _TexN for texture inputs), then runs
the Windows SDK fxc.exe and reports wall time. Use it to find which pass makes a reload slow and
to test a fix in seconds instead of a live reload round trip. Final truth is always
`sentinel_pipeline compile_check`.
"""
import glob
import os
import re
import shutil
import sys
import time
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def find_fxc():
    """FXC env var, then PATH, then the newest Windows 10/11 SDK under Program Files (x86)."""
    if os.environ.get('FXC') and os.path.isfile(os.environ['FXC']):
        return os.environ['FXC']
    if shutil.which('fxc'):
        return shutil.which('fxc')
    kits = os.path.join(os.environ.get('ProgramFiles(x86)', ''), 'Windows Kits', '10', 'bin')
    found = sorted(glob.glob(os.path.join(kits, '10.*', 'x64', 'fxc.exe')),
                   key=lambda p: [int(n) for n in re.findall(r'\d+', os.path.basename(os.path.dirname(os.path.dirname(p))))])
    if found:
        return found[-1]
    sys.exit('fxc.exe not found: install the Windows SDK or set FXC to its path')


FXC = find_fxc()

TYPES = {'float': 'float', 'int': 'int', 'bool': 'int', 'button': 'int', 'enum': 'int',
         'point2D': 'float2', 'vec2': 'float2', 'vec3': 'float3', 'color': 'float3', 'vec4': 'float4'}

PRELUDE = r'''
struct ViewportEvent { uint type; uint phase; uint code; uint modifiers; float2 position; float2 delta; float value; uint sequence; uint flags; uint device; };
StructuredBuffer<ViewportEvent> _ViewportEvents : register(t127);
static const uint VIEWPORT_EVENT_FLAG_REPEAT = 1u;
static const uint VIEWPORT_EVENT_FLAG_SYNTHETIC = 2u;
static const uint VIEWPORT_EVENT_FLAG_HOST_CONSUMED = 4u;
static const uint VIEWPORT_EVENT_FLAG_CAPTURE_CANCEL = 8u;
static const uint VIEWPORT_MODIFIER_SHIFT = 1u;
static const uint VIEWPORT_MODIFIER_CONTROL = 2u;
static const uint VIEWPORT_MODIFIER_ALT = 4u;
static const uint VIEWPORT_MODIFIER_SUPER = 8u;
struct ViewportControlState { uint flags; float value; float value2; uint rgba; float fade; uint label; uint state; uint mode; };
StructuredBuffer<ViewportControlState> _ViewportControlState : register(t126);
StructuredBuffer<uint> _PanelLabels : register(t124);
static const uint PANEL_LABEL_WORDS = 16u;
static const uint VIEWPORT_CONTROL_HOVER = 1u;
static const uint VIEWPORT_CONTROL_ACTIVE = 2u;
static const uint VIEWPORT_CONTROL_HELD = 4u;
static const uint VIEWPORT_CONTROL_LIT = 8u;
#define SENTINEL_PANEL_TEXT 1
SamplerState LinearSampler : register(s0);
SamplerState PointSampler : register(s1);
struct GPUEventInputRecord { uint event_type; float4 payload; float intra_frame_offset; uint timestamp_lo; uint timestamp_hi; };
struct GPUEventRecord { uint event_type; float4 payload; uint sub_step; float sub_step_fraction; uint sub_step_count; };
'''


def params(manifest):
    """Single-line `- { name: ..., type: ... }` entries of the top-level `parameters:` block only
    (schemas elsewhere use the same shape)."""
    out = []
    inside = False
    for raw in open(manifest, encoding='utf-8'):
        if re.match(r'^[A-Za-z_]+:', raw):
            inside = raw.startswith('parameters:')
            continue
        if not inside:
            continue
        m = re.match(r'^\s*-\s*\{\s*name:\s*([A-Za-z_][A-Za-z0-9_]*).*?\btype:\s*([A-Za-z0-9]+)', raw)
        if m and m.group(2) in TYPES:
            out.append((m.group(1), TYPES[m.group(2)]))
    return out


def texture_buffers(txt):
    """Names of declared buffers that are textures (no `structured: true`)."""
    names = set()
    for m in re.finditer(r'^\s*-\s*\{\s*name:\s*([A-Za-z_][A-Za-z0-9_]*)([^}\n]*)\}', txt, re.M):
        if 'structured' not in m.group(2) and ('format:' in m.group(2) or 'scale:' in m.group(2)):
            names.add(m.group(1))
    return names


def pass_inputs(manifest, pass_name):
    """Texture slots (assets, inputs, passes, texture buffers) for the named pass - the slots for
    which Sentinel declares _TexN itself (structured-buffer inputs are declared by the pass)."""
    txt = open(manifest, encoding='utf-8').read()
    texbufs = texture_buffers(txt)
    m = re.search(r'-\s*name:\s*' + re.escape(pass_name) + r'\b(.*?)(?=\n\s*-\s*name:|\n[a-z_]+:|\Z)', txt, re.S)
    slots = []
    if m:
        for sm in re.finditer(r'slot:\s*(\d+)\s*,\s*source:\s*"([^"]+)"', m.group(1)):
            slot, src = int(sm.group(1)), sm.group(2)
            if src.startswith('asset:') or src.startswith('input') or src.startswith('pass:') or src == 'depth' \
                    or (src.startswith('buffer:') and src[7:] in texbufs):
                slots.append(slot)
    return slots


def event_ports(manifest, key):
    """Port names of a top-level `event_inputs:` / `event_outputs:` list, in order."""
    names, inside = [], False
    for raw in open(manifest, encoding='utf-8'):
        if re.match(r'^[A-Za-z_]+:', raw):
            inside = raw.startswith(key + ':')
            continue
        m = re.match(r'^\s*-\s*\{\s*name:\s*"?([^",}]+)"?', raw) if inside else None
        if m:
            names.append(m.group(1).strip())
    return names


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    mod, pas = sys.argv[1], sys.argv[2]
    flags = [a.replace('--', '/') for a in sys.argv[3:]] or ['/O3']
    mdir = os.path.join(ROOT, 'modules', mod)
    manifest = os.path.join(mdir, 'manifest.yaml')
    shader = os.path.join(mdir, pas + '.hlsl')
    # the viewport block as sentinel.exe 0.6.3 declares it, plus the `camera` feature's globals
    cb = 'cbuffer P : register(b0) {\n float _Time; float _DeltaTime; float2 _Resolution;\n'
    cb += ' float4 _Mouse; int _Frame; float _BlendAmount; float2 _pad0;\n'
    cb += ' uint _ViewportAbiVersion; uint _ViewportEventCount; uint _ViewportOverflowCount; uint _ViewportFrameSequence;\n'
    cb += ' float2 _ViewportPointerPosition; float2 _ViewportPointerDelta; float _ViewportWheelDelta;\n'
    cb += ' uint _ViewportButtons; uint _ViewportModifiers; uint _ViewportCaptureFlags; uint4 _ViewportKeyBits;\n'
    cb += ' uint4 _ViewportControlFlags[4]; float4 _ViewportPickRayOrigin; float4 _ViewportPickRayDirection;\n'
    cb += ' uint4 _ViewportPickQuery; uint4 _ViewportSelectionIds[16]; uint4 _ViewportSelectionMeta;\n'
    cb += ' float4x4 _ViewMatrix; float4x4 _ProjMatrix; float4x4 _ViewProjMatrix; float4x4 _InvViewProjMatrix;\n'
    cb += ' float3 _CameraPos; float _CameraNear; float _CameraFar; float _CameraFOV;\n'
    cb += ''.join(f' {t} {n};\n' for n, t in params(manifest))
    ins, outs = event_ports(manifest, 'event_inputs'), event_ports(manifest, 'event_outputs')
    cb += ''.join(f' uint _EventIn{i}_Count; uint3 _EventIn{i}_pad;\n' for i in range(len(ins)))
    cb += '};\n'
    # module event ports as sentinel.exe 0.6.3 declares them (EventOut<N> append UAVs at u1..u7)
    cb += ''.join(f'StructuredBuffer<GPUEventInputRecord> EventIn{i} : register(t{110 + i});\n' for i in range(len(ins)))
    cb += ''.join(f'AppendStructuredBuffer<GPUEventRecord> EventOut{i} : register(u{1 + i});\n' for i in range(len(outs)))
    # the viewport helpers sentinel.exe injects after the cbuffer
    cb += ('bool ViewportKeyDown(uint key) { uint word = key >> 5; uint bit = key & 31; return word < 4 && ((_ViewportKeyBits[word] & (1u << bit)) != 0); }\n'
           'bool ViewportButtonDown(uint button) { return button < 3 && ((_ViewportButtons & (1u << button)) != 0); }\n'
           'bool ViewportModifierDown(uint modifier) { return (_ViewportModifiers & modifier) != 0; }\n')
    tex = ''.join(f'Texture2D<float4> _Tex{s} : register(t{s});\n' for s in pass_inputs(manifest, pas))
    fd, tmp = tempfile.mkstemp(suffix=f'_{mod}_{pas}.hlsl')
    os.close(fd)
    with open(tmp, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(PRELUDE + cb + tex + f'#line 1 "{pas}.hlsl"\n' + open(shader, encoding='utf-8').read())
    t0 = time.time()
    r = subprocess.run([FXC, '/nologo', '/T', 'cs_5_0', '/E', 'main', '/I', mdir, *flags, '/Fo', os.devnull, tmp],
                       capture_output=True, text=True, cwd=mdir)
    dt = time.time() - t0
    os.remove(tmp)
    msg = (r.stdout + r.stderr).strip()
    msg = '\n'.join(l for l in msg.splitlines() if 'compilation object save succeeded' not in l)
    print(f'{mod}/{pas}: {"OK" if r.returncode == 0 else "FAILED"} in {dt:.1f}s {" ".join(flags)}')
    if msg:
        print(msg[-4000:])


if __name__ == '__main__':
    main()
