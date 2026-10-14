#!/usr/bin/env python3
"""Write PHAGE's fixtures as GDTF 1.2 types into assets/gdtf/, with their meshes, thumbnails and a spec sheet.

    python tools/phage_gdtf.py

PHAGE draws three fixtures of its own: a beam mover with a 24-cell halo ring, a linear strobe (a white tube between
two RGB plates) and a one metre pixel batten, chained along every pixel run. This writes each of them as a GDTF that any visualiser, console or Sentinel
Fixture Rig reads, built from the SAME constants the renderer draws them with: the head's lathe profile is read from
modules/Phage_Renderer/movers.hlsl, the yoke outline from modules/Phage_Renderer/yoke.hlsli, the mover scale and
strobe length from the Plan's defaults, and the boxes and offsets are the ones in movers.hlsl and emitters.hlsl. A
change to the drawn fixture is a change here on the next run.

These are Sentinel's own designs, so the example ships them. None models a manufacturer's product. Photometry is a
design figure for each fixture, not a measurement.

GDTF frame: hanging, front view; X left to right, Y away from the viewer, Z up, beams emit along -Z; the origin is
the mounting face. Meshes are glTF (Y up, metres) centred on their geometry's origin, so Length, Width and Height
are exactly their extents. Archives use a fixed timestamp and entry order: a rerun is byte-identical, which keeps
each type's sha256 (and the refinement that verifies it) stable.

Needs numpy (thumbnails are rendered here, in software).
"""
from __future__ import annotations

import io
import json
import math
import re
import struct
import uuid
import zipfile
import zlib
from pathlib import Path
from xml.sax.saxutils import quoteattr

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "gdtf"
STAMP = (2026, 10, 3, 0, 0, 0)
MANUFACTURER = "Sentinel"
NS = uuid.UUID("2b8f3c61-7d4e-4f0a-b9c5-0e6a1d7f4c22")
REVISION = "Written by PHAGE tools/phage_gdtf.py from the renderer's own fixture constants"


# ---------------------------------------------------------------- the renderer's constants

def _text(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def _float2_array(rel, name):
    body = re.search(name + r"\[\d+\]\s*=\s*\{(.*?)\};", _text(rel), re.S).group(1)
    return [(float(a), float(b)) for a, b in re.findall(r"float2\(\s*([-\d.eE]+)\s*,\s*([-\d.eE]+)\s*\)", body)]


def _uint_array(rel, name):
    body = re.search(name + r"\[\d+\]\s*=\s*\{(.*?)\};", _text(rel), re.S).group(1)
    return [int(v) for v in re.findall(r"\d+", body)]


def _plan_default(name):
    return float(re.search(r"name:\s*" + name + r"\b[^}]*default:\s*([-\d.]+)", _text("modules/Phage_Plan/manifest.yaml")).group(1))


PROFILE = _float2_array("modules/Phage_Renderer/movers.hlsl", "Profile")          # head lathe, (radius, z)
YOKE_POINTS = _float2_array("modules/Phage_Renderer/yoke.hlsli", "YokePoints")    # yoke outline, (x, y)
YOKE_TRIS = _uint_array("modules/Phage_Renderer/yoke.hlsli", "YokeTriangles")
MOVER_SCALE = _plan_default("mover_scale")                                          # model units -> metres
STROBE_LEN = _plan_default("strobe_length")
assert len(PROFILE) == 8 and len(YOKE_POINTS) == 32 and len(YOKE_TRIS) == 90, "the renderer's fixture tables changed shape"

# movers.hlsl, in model units (metres at scale 1). Base space: +y away from the mount; the yoke pivots at
# y=0.075 and the head at yoke y=0.152; the head's beam leaves along -z.
BASE_BOX = ((0, .037, 0), (.125, .028, .094))
FEET = [((sx * .094, .008, sz * .065), (.016, .008, .019)) for sz in (-1, 1) for sx in (-1, 1)]
LABEL = ((0, .04, -.0945), (.027, .010, .001))
PAN_PIVOT, TILT_PIVOT = .075, .152
BEARING = (.061, .013)                       # pan bearing radius, half length (base space, axis +y at the pivot)
HUBS = (.104, .014, .014)                    # tilt hubs at x=+-.104: radius, half length
YOKE_HALF_DEPTH = .04
LENS_R, LENS_Z0, LENS_SAG = .067, -.045, .025   # concave lens: z = Z0 - SAG (r/R)^2
BACK_CAP = (.075, .08)                       # z, radius
RING_R, RING_Z, RING_CELLS = .086, -.077, 24  # the halo: 24 cells on the profile's front annulus (band 4)

# emitters.hlsl, metres. Strobe: housing behind the face, tube proud of it, two plates either side of the tube.
STROBE_HOUSING = (.13, .065, .07)            # half width, half depth, centre behind the mount point
STROBE_TUBE = (.93, .02, .012)               # length fraction, half section, centre in front of the mount point
STROBE_PLATE = (.075, .045, .004)            # centre offset across, half width, in front of the mount point
STROBE_SEGMENTS = 8
# Pixel batten: a 9 x 6 cm extrusion with a 4.4 cm strip of 5 cm pixels on its face (PHAGE's LED pitch).
BAR_SECTION = (.045, .03)                    # half width, half depth (the body sits behind the face)
BAR_STRIP = (.022, .002)                     # half width, proud of the face
BAR_PITCH = .05


# ---------------------------------------------------------------- meshes

class Mesh:
    """Triangles grouped by material: {material: [positions (n,3), normals (n,3)]}, three vertices a triangle."""

    def __init__(self):
        self.parts: dict[str, list[list]] = {}

    def tri(self, mat, ps, ns):
        p = self.parts.setdefault(mat, [[], []])
        p[0].extend(ps)
        p[1].extend(ns)

    def quad(self, mat, a, b, c, d, na, nb=None, nc=None, nd=None):
        nb, nc, nd = nb or na, nc or na, nd or na
        self.tri(mat, [a, b, c], [na, nb, nc])
        self.tri(mat, [a, c, d], [na, nc, nd])

    def add(self, other, fn=None, nfn=None):
        for mat, (ps, ns) in other.parts.items():
            ps2 = [fn(p) for p in ps] if fn else ps
            ns2 = [nfn(n) for n in ns] if nfn else ns
            self.tri(mat, ps2, ns2)
        return self

    def arrays(self):
        return {m: (np.array(ps, dtype=np.float64), np.array(ns, dtype=np.float64)) for m, (ps, ns) in self.parts.items()}

    def bounds(self):
        allp = np.concatenate([np.array(ps) for ps, _ in self.parts.values()])
        return allp.min(axis=0), allp.max(axis=0)


def _norm(v):
    l = math.sqrt(sum(c * c for c in v))
    return tuple(c / l for c in v) if l > 1e-12 else (0.0, 0.0, 1.0)


def bevel_box(mat, centre, ext, bevel):
    """movers.hlsl's bevelled box: each face a 3x3 grid whose outer rows fold onto a chamfer with blended normals."""
    m = Mesh()
    b = min(bevel, min(ext) * .4)

    def edge(k, e):
        return (-e, -e + b, e - b, e)[k]

    for face in range(6):
        axis, s = face // 2, (-1 if face % 2 == 0 else 1)
        grid = {}
        for i in range(4):
            for j in range(4):
                if axis == 0:
                    cube = (s * ext[0], edge(i, ext[1]), edge(j, ext[2]))
                elif axis == 1:
                    cube = (edge(i, ext[0]), s * ext[1], edge(j, ext[2]))
                else:
                    cube = (edge(i, ext[0]), edge(j, ext[1]), s * ext[2])
                core = tuple(max(-e + b, min(e - b, c)) for c, e in zip(cube, ext))
                n = _norm(tuple(c - k for c, k in zip(cube, core)))
                p = tuple(cc + k + nn * b for cc, k, nn in zip(centre, core, n))
                grid[i, j] = (p, n)
        for i in range(3):
            for j in range(3):
                (a, na), (bb, nb), (c, nc), (d, nd) = grid[i, j], grid[i + 1, j], grid[i + 1, j + 1], grid[i, j + 1]
                m.quad(mat, a, bb, c, d, na, nb, nc, nd)
    return m


def cylinder(mat, centre, axis, radius, half, segs=48, caps=True):
    m = Mesh()
    ax = _norm(axis)
    u = _norm(np.cross(ax, (0, 0, 1) if abs(ax[2]) < .9 else (1, 0, 0)))
    w = tuple(np.cross(ax, u))
    c = np.array(centre, dtype=float)
    A, B = c - np.array(ax) * half, c + np.array(ax) * half
    for k in range(segs):
        a0, a1 = 2 * math.pi * k / segs, 2 * math.pi * (k + 1) / segs
        r0 = np.array(u) * math.cos(a0) + np.array(w) * math.sin(a0)
        r1 = np.array(u) * math.cos(a1) + np.array(w) * math.sin(a1)
        m.quad(mat, tuple(A + r0 * radius), tuple(A + r1 * radius), tuple(B + r1 * radius), tuple(B + r0 * radius),
               tuple(r0), tuple(r1), tuple(r1), tuple(r0))
        if caps:
            m.tri(mat, [tuple(A), tuple(A + r1 * radius), tuple(A + r0 * radius)], [tuple(-np.array(ax))] * 3)
            m.tri(mat, [tuple(B), tuple(B + r0 * radius), tuple(B + r1 * radius)], [ax] * 3)
    return m


def mover_head():
    """The head shell (movers.hlsl): the lathe of PROFILE in 96 segments, the halo's annulus left dark (its cells are
    the Ring Cell beams), and the vented back cap. The lens is the Beam's own model."""
    m = Mesh()
    segs = 96
    for band in range(len(PROFILE) - 1):
        (r0, z0), (r1, z1) = PROFILE[band], PROFILE[band + 1]
        d = (r1 - r0, z1 - z0)
        mat = "ring_face" if band == 4 else ("bezel" if band >= 5 else "shell")
        for k in range(segs):
            a0, a1 = 2 * math.pi * (k - 2) / segs, 2 * math.pi * (k - 1) / segs
            s0, c0, s1, c1 = math.sin(a0), math.cos(a0), math.sin(a1), math.cos(a1)
            n0, n1 = _norm((s0 * -d[1], c0 * -d[1], d[0])), _norm((s1 * -d[1], c1 * -d[1], d[0]))
            m.quad(mat, (s0 * r0, c0 * r0, z0), (s1 * r0, c1 * r0, z0), (s1 * r1, c1 * r1, z1), (s0 * r1, c0 * r1, z1),
                   n0, n1, n1, n0)
    z, r = BACK_CAP
    for k in range(segs):
        a0, a1 = 2 * math.pi * k / segs, 2 * math.pi * (k + 1) / segs
        m.tri("grille", [(0, 0, z), (math.sin(a0) * r, math.cos(a0) * r, z), (math.sin(a1) * r, math.cos(a1) * r, z)], [(0, 0, 1)] * 3)
    return m


def mover_lens():
    m = Mesh()
    segs, rings = 96, 4

    def pt(r, a):
        x, y = math.sin(a) * r, math.cos(a) * r
        return (x, y, LENS_Z0 - LENS_SAG * (r / LENS_R) ** 2), _norm((-x * 2 * LENS_SAG / LENS_R ** 2, -y * 2 * LENS_SAG / LENS_R ** 2, -1))

    for band in range(rings):
        ra, rb = LENS_R * band / rings, LENS_R * (band + 1) / rings
        for k in range(segs):
            a0, a1 = 2 * math.pi * k / segs, 2 * math.pi * (k + 1) / segs
            (p0, n0), (p1, n1), (p2, n2), (p3, n3) = pt(ra, a0), pt(ra, a1), pt(rb, a1), pt(rb, a0)
            m.quad("lens", p0, p1, p2, p3, n0, n1, n2, n3)
    return m


def mover_base():
    """Base space (+y away from the mount): the bevelled box, four feet, the display window and the pan bearing."""
    m = Mesh()
    m.add(bevel_box("body", *BASE_BOX, .006))
    for c, e in FEET:
        m.add(bevel_box("rubber", c, e, .004))
    m.add(bevel_box("display", *LABEL, .0005))
    m.add(cylinder("body", (0, PAN_PIVOT, 0), (0, 1, 0), BEARING[0], BEARING[1]))
    return m


def mover_yoke():
    """Yoke space (pivot at the origin, +y toward the head): the outline extruded +-4 cm, and the tilt hubs."""
    m = Mesh()
    d = YOKE_HALF_DEPTH
    for side in (0, 1):
        z = -d if side == 0 else d
        for t in range(0, len(YOKE_TRIS), 3):
            ps = [(YOKE_POINTS[YOKE_TRIS[t + k]][0], YOKE_POINTS[YOKE_TRIS[t + k]][1], z) for k in range(3)]
            m.tri("yoke", ps, [(0, 0, -1 if side == 0 else 1)] * 3)
    n = len(YOKE_POINTS)
    for k in range(n):
        (ax, ay), (bx, by) = YOKE_POINTS[k], YOKE_POINTS[(k + 1) % n]
        nn = _norm((by - ay, -(bx - ax), 0))
        m.quad("yoke", (ax, ay, -d), (bx, by, -d), (bx, by, d), (ax, ay, d), nn)
    for sx in (-1, 1):
        m.add(cylinder("body", (sx * HUBS[0], TILT_PIVOT, 0), (1, 0, 0), HUBS[1], HUBS[2], 32))
    return m


def box_mesh(mat, ext):
    return bevel_box(mat, (0, 0, 0), ext, 0.0)


# ---------------------------------------------------------------- glTF binary

MATERIALS = {   # name: (base colour sRGB, metallic, roughness, emissive sRGB) - the GLB's look in other visualisers
    "body": ((.07, .072, .078), .35, .45, None), "yoke": ((.085, .087, .094), .4, .4, None),
    "shell": ((.06, .062, .068), .3, .5, None), "bezel": ((.18, .18, .19), .9, .25, None),
    "ring_face": ((.03, .03, .035), .2, .6, None), "grille": ((.02, .02, .022), .2, .8, None),
    "rubber": ((.02, .02, .02), 0, .9, None), "display": ((.01, .02, .03), 0, .1, (.02, .06, .09)),
    "lens": ((.75, .8, .85), 0, .05, None), "housing": ((.05, .052, .058), .35, .5, None),
}


def glb(mesh: Mesh) -> bytes:
    """A GLB of the mesh, centred on its bounds. Input is the GDTF frame (Z up); glTF is Y up: (x, y, z) -> (x, z, -y)."""
    lo, hi = mesh.bounds()
    centre = (lo + hi) / 2
    blob, views, accessors, prims, mats = bytearray(), [], [], [], []
    for mat, (ps, ns) in mesh.arrays().items():
        p = ps - centre
        p = np.stack([p[:, 0], p[:, 2], -p[:, 1]], axis=1).astype("<f4")
        n = np.stack([ns[:, 0], ns[:, 2], -ns[:, 1]], axis=1).astype("<f4")
        idx = np.arange(len(p), dtype="<u4")
        ids = []
        for data, target in ((p, 34962), (n, 34962), (idx, 34963)):
            while len(blob) % 4:
                blob.append(0)
            views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": data.nbytes, "target": target})
            blob += data.tobytes()
            ids.append(len(views) - 1)
        accessors.append({"bufferView": ids[0], "componentType": 5126, "count": len(p), "type": "VEC3",
                          "min": [float(v) for v in p.min(axis=0)], "max": [float(v) for v in p.max(axis=0)]})
        accessors.append({"bufferView": ids[1], "componentType": 5126, "count": len(n), "type": "VEC3"})
        accessors.append({"bufferView": ids[2], "componentType": 5125, "count": len(idx), "type": "SCALAR"})
        base, metal, rough, emis = MATERIALS[mat]
        m = {"name": mat, "doubleSided": True,
             "pbrMetallicRoughness": {"baseColorFactor": [*base, 1.0], "metallicFactor": metal, "roughnessFactor": rough}}
        if emis:
            m["emissiveFactor"] = list(emis)
        mats.append(m)
        a = len(accessors)
        prims.append({"attributes": {"POSITION": a - 3, "NORMAL": a - 2}, "indices": a - 1, "material": len(mats) - 1})
    while len(blob) % 4:
        blob.append(0)
    doc = {"asset": {"version": "2.0", "generator": "PHAGE tools/phage_gdtf.py"}, "scene": 0, "scenes": [{"nodes": [0]}],
           "nodes": [{"mesh": 0}], "meshes": [{"primitives": prims}], "materials": mats, "accessors": accessors,
           "bufferViews": views, "buffers": [{"byteLength": len(blob)}]}
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\x00") + bytes(blob)
    return out


# ---------------------------------------------------------------- thumbnails (software rasterised)

def _srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)


def render(items, eye, target, fov_deg=26.0, size=512, ss=3):
    """items: [(positions (n,3), normals (n,3), albedo sRGB, spec, emissive linear rgb)], triangles three vertices
    a triangle, in a Z-up world. Returns an RGBA uint8 image with a transparent ground."""
    W = size * ss
    eye, target = np.array(eye, float), np.array(target, float)
    f = target - eye
    f /= np.linalg.norm(f)
    r = np.cross(f, (0, 0, 1))
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    t = math.tan(math.radians(fov_deg) / 2)
    zbuf = np.full((W, W), np.inf)
    col = np.zeros((W, W, 3))
    emit = np.zeros((W, W, 3))
    cov = np.zeros((W, W))
    key, fill, rim = _norm((-.55, -.75, .65)), _norm((.8, -.3, .15)), _norm((.2, .9, .4))
    for ps, ns, albedo, spec, emissive in items:
        alb = _srgb_to_lin(albedo)
        em = np.array(emissive if emissive is not None else (0, 0, 0), float)
        V = ps - eye
        xv, yv, zv = V @ r, V @ u, V @ f
        sx = (xv / zv) / t * W / 2 + W / 2
        sy = -(yv / zv) / t * W / 2 + W / 2
        for i in range(0, len(ps), 3):
            X, Y, Z = sx[i:i + 3], sy[i:i + 3], zv[i:i + 3]
            if (Z < 1e-3).any():
                continue
            x0, x1 = max(int(math.floor(X.min())), 0), min(int(math.ceil(X.max())), W - 1)
            y0, y1 = max(int(math.floor(Y.min())), 0), min(int(math.ceil(Y.max())), W - 1)
            if x0 > x1 or y0 > y1:
                continue
            area = (X[1] - X[0]) * (Y[2] - Y[0]) - (X[2] - X[0]) * (Y[1] - Y[0])
            if abs(area) < 1e-12:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + .5, np.arange(y0, y1 + 1) + .5)
            w0 = ((X[1] - gx) * (Y[2] - gy) - (X[2] - gx) * (Y[1] - gy)) / area
            w1 = ((X[2] - gx) * (Y[0] - gy) - (X[0] - gx) * (Y[2] - gy)) / area
            w2 = 1 - w0 - w1
            inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            if not inside.any():
                continue
            iz = w0 / Z[0] + w1 / Z[1] + w2 / Z[2]
            depth = 1 / np.where(inside, iz, 1)
            zb = zbuf[y0:y1 + 1, x0:x1 + 1]
            hit = inside & (depth < zb)
            if not hit.any():
                continue
            b0, b1, b2 = (w0 / Z[0])[hit] / iz[hit], (w1 / Z[1])[hit] / iz[hit], (w2 / Z[2])[hit] / iz[hit]
            n = ns[i] * b0[:, None] + ns[i + 1] * b1[:, None] + ns[i + 2] * b2[:, None]
            n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
            p = ps[i] * b0[:, None] + ps[i + 1] * b1[:, None] + ps[i + 2] * b2[:, None]
            v = eye - p
            v /= np.linalg.norm(v, axis=1, keepdims=True)
            flip = (n * v).sum(axis=1) < 0
            n[flip] *= -1
            def lam(l):
                return np.clip(n @ np.array(l), 0, None)
            def blinn(l, power):
                h = v + np.array(l)
                h /= np.linalg.norm(h, axis=1, keepdims=True)
                return np.clip((n * h).sum(axis=1), 0, None) ** power
            ndv = np.clip((n * v).sum(axis=1), 0, 1)
            fres = .04 + .96 * (1 - ndv) ** 5
            diffuse = 1.0 * lam(key) + .35 * lam(fill) + .25 * lam(rim) + .08
            specular = spec * (1.6 * blinn(key, 60) + .5 * blinn(fill, 30) + 1.2 * blinn(rim, 20) * fres) + .05 * fres
            c = diffuse[:, None] * alb[None, :] + specular[:, None]
            zb[hit] = depth[hit]
            col[y0:y1 + 1, x0:x1 + 1][hit] = c
            emit[y0:y1 + 1, x0:x1 + 1][hit] = em
            cov[y0:y1 + 1, x0:x1 + 1][hit] = 1
    # A soft bloom around the lit cells, the way the renderer shows them, then the max-channel tonemap.
    glow = emit.copy()
    for radius in (6 * ss, 18 * ss):
        k = np.exp(-.5 * (np.arange(-3 * radius, 3 * radius + 1) / radius) ** 2)
        k /= k.sum()
        g = emit.copy()
        for axis in (0, 1):
            g = np.apply_along_axis(lambda a: np.convolve(a, k, mode="same"), axis, g)
        glow += g * (.55 if radius == 6 * ss else .35)
    lin = col + emit + glow
    peak = lin.max(axis=2, keepdims=True)
    lin = lin * (np.where(peak > 0, (peak / (1 + peak)) / np.maximum(peak, 1e-9), 1.0))
    alpha = np.clip(cov + np.clip(glow.max(axis=2) * 1.5, 0, 1) * (1 - cov), 0, 1)
    rgb = np.where(lin <= .0031308, lin * 12.92, 1.055 * np.clip(lin, 0, None) ** (1 / 2.4) - .055)
    rgba = np.concatenate([np.clip(rgb, 0, 1) * alpha[..., None], alpha[..., None]], axis=2)
    rgba = rgba.reshape(size, ss, size, ss, 4).mean(axis=(1, 3))
    a = rgba[..., 3:4]
    out = np.concatenate([np.where(a > 1e-6, rgba[..., :3] / np.maximum(a, 1e-6), 0), a], axis=2)
    return (np.clip(out, 0, 1) * 255 + .5).astype(np.uint8)


def png_rgba(img) -> bytes:
    h, w, _ = img.shape
    raw = b"".join(b"\x00" + img[y].tobytes() for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


# ---------------------------------------------------------------- GDTF description

def mat4(x=0.0, y=0.0, z=0.0):
    rows = [(1, 0, 0, x), (0, 1, 0, y), (0, 0, 1, z), (0, 0, 0, 1)]
    return "".join("{" + ",".join(f"{v:.6f}" for v in r) + "}" for r in rows)


def xyY(r, g, b, transmission=None):
    lin = [((c / 12.92) if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4) for c in (r, g, b)]
    X = 0.4124 * lin[0] + 0.3576 * lin[1] + 0.1805 * lin[2]
    Y = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
    Z = 0.0193 * lin[0] + 0.1192 * lin[1] + 0.9505 * lin[2]
    t = X + Y + Z
    x, y = (X / t, Y / t) if t > 0 else (0.3127, 0.3290)
    return f"{x:.6f},{y:.6f},{100.0 * (Y if transmission is None else transmission):.6f}"


# RGB LED emitters shared by every PHAGE type: CIE xyY of each die at full drive and its dominant wavelength.
RGB_EMITTERS = ['<Emitter Name="Red" Color="0.700000,0.299000,22.000000" DominantWaveLength="625.000000"/>',
                '<Emitter Name="Green" Color="0.170000,0.700000,68.000000" DominantWaveLength="525.000000"/>',
                '<Emitter Name="Blue" Color="0.135000,0.050000,10.000000" DominantWaveLength="460.000000"/>']
EMITTER_OF = {"R": "Red", "G": "Green", "B": "Blue"}


class Fixture:
    def __init__(self, name, short, long_name, description):
        self.name, self.short, self.long_name, self.description = name, short, long_name, description
        self.attributes, self.emitters, self.models, self.modes, self.media = [], [], [], [], []
        self.geometries = ""
        self.sheet = {}            # spec-sheet facts for FIXTURES.md
        self.cell_base = {}        # first channel of cell 1, per referenced cell geometry

    def attr(self, name, pretty, feature, unit=None, group=None, main=None):
        self.attributes.append((name, pretty, feature, unit, group, main))

    def model(self, name, l, w, h, prim="Undefined", file=None):
        f = f' File="{file}"' if file else ""
        self.models.append(f'<Model Name="{name}" Length="{l:.6f}" Width="{w:.6f}" Height="{h:.6f}" PrimitiveType="{prim}"{f}/>')

    def mesh_model(self, name, mesh: Mesh):
        lo, hi = mesh.bounds()
        file = name.lower().replace(" ", "_")
        self.model(name, *(hi - lo), "Undefined", file)
        self.media.append((f"models/gltf/{file}.glb", glb(mesh)))
        return (lo + hi) / 2

    def xml(self):
        groups, features = [], {}
        for a in self.attributes:
            fg, f = a[2].split(".")
            features.setdefault(fg, [])
            if f not in features[fg]:
                features[fg].append(f)
            if a[4] and a[4] not in groups:
                groups.append(a[4])
        out = ['<?xml version="1.0" encoding="UTF-8" standalone="no" ?>', '<GDTF DataVersion="1.2">',
               f'  <FixtureType Name={quoteattr(self.name)} ShortName={quoteattr(self.short)} '
               f'LongName={quoteattr(self.long_name)} Manufacturer="{MANUFACTURER}" Description={quoteattr(self.description)} '
               f'FixtureTypeID="{str(uuid.uuid5(NS, self.name)).upper()}" Thumbnail="thumbnail" ThumbnailOffsetX="0" ThumbnailOffsetY="0" RefFT="">',
               '    <AttributeDefinitions>', '      <ActivationGroups>']
        out += [f'        <ActivationGroup Name="{g}"/>' for g in groups]
        out += ['      </ActivationGroups>', '      <FeatureGroups>']
        for fg, fs in features.items():
            out.append(f'        <FeatureGroup Name="{fg}" Pretty="{fg}">' + "".join(f'<Feature Name="{f}"/>' for f in fs) + '</FeatureGroup>')
        out += ['      </FeatureGroups>', '      <Attributes>']
        for name, pretty, feature, unit, group, main in self.attributes:
            extra = (f' ActivationGroup="{group}"' if group else "") + (f' MainAttribute="{main}"' if main else "")
            extra += f' PhysicalUnit="{unit}"' if unit else ""
            out.append(f'        <Attribute Name="{name}" Pretty="{pretty}"{extra} Feature="{feature}"/>')
        out += ['      </Attributes>', '    </AttributeDefinitions>', '    <Wheels/>', '    <PhysicalDescriptions>', '      <Emitters>']
        out += ["        " + e for e in self.emitters]
        out += ['      </Emitters>', '      <ColorSpace Mode="sRGB"/>', '    </PhysicalDescriptions>', '    <Models>']
        out += ["      " + m for m in self.models]
        out += ['    </Models>', '    <Geometries>', self.geometries, '    </Geometries>', '    <DMXModes>']
        for mname, root, channels, relations, _ in self.modes:
            out.append(f'      <DMXMode Name="{mname}" Geometry="{root}">')
            out.append('        <DMXChannels>')
            out += [c[0] for c in channels]
            out.append('        </DMXChannels>')
            out.append('        <Relations>' + "".join(relations) + '</Relations>')
            out.append('        <FTMacros/>')
            out.append('      </DMXMode>')
        out += ['    </DMXModes>', '    <Revisions>',
                f'      <Revision Text={quoteattr(REVISION)} Date="2026-10-03T00:00:00" UserID="0"/>',
                '    </Revisions>', '    <FTPresets/>', '    <Protocols/>', '  </FixtureType>', '</GDTF>', '']
        return "\n".join(out).encode("utf-8")


def channel(geometry, attribute, offset, functions, default=0, master="None", initial=None, label=None):
    """One DMXChannel with one LogicalChannel. functions: [(name, attribute, dmx_from, phys_from, phys_to, extra)],
    dmx_from in the channel's own resolution. Returns (xml, chart row)."""
    res = len(offset.split(","))
    first = initial or functions[0][0]
    lines = [f'          <DMXChannel DMXBreak="1" Offset="{offset}" InitialFunction="{geometry}_{attribute}.{attribute}.{first}" Highlight="None" Geometry="{geometry}">',
             f'            <LogicalChannel Attribute="{attribute}" Snap="No" Master="{master}" MibFade="0.000000" DMXChangeTimeLimit="0.000000">']
    for name, attr, dmx_from, pf, pt, extra in functions:
        d = default if name == first else dmx_from
        lines.append(f'              <ChannelFunction Name="{name}" Attribute="{attr}" OriginalAttribute="" DMXFrom="{dmx_from}/{res}" '
                     f'Default="{d}/{res}" PhysicalFrom="{pf:.6f}" PhysicalTo="{pt:.6f}" RealFade="0.000000"{extra}/>')
    lines += ['            </LogicalChannel>', '          </DMXChannel>']
    return "\n".join(lines), (offset, geometry, label or attribute, functions)


def simple(geometry, attribute, offset, pf=0.0, pt=1.0, default=0, extra="", master="None", label=None):
    return channel(geometry, attribute, offset, [(attribute, attribute, 0, pf, pt, extra)], default=default, master=master, label=label)


def shutter(geometry, offset, max_hz):
    return channel(geometry, "Shutter1", offset, [
        ("Closed", "Shutter1", 0, 0, 0, ""), ("Open", "Shutter1", 8, 1, 1, ""),
        ("Strobe", "Shutter1Strobe", 16, 1, max_hz, ""), ("Open 2", "Shutter1", 240, 1, 1, ""),
    ], default=8, initial="Open", label="Shutter / strobe")


def rgb(geometry, first, label=""):
    return [simple(geometry, f"ColorAdd_{c}", str(first + k), extra=f' Emitter="{EMITTER_OF[c]}"', label=f"{label}{c}".strip())
            for k, c in enumerate("RGB")]


def rgb_attrs(f):
    for c in "RGB":
        f.attr(f"ColorAdd_{c}", c, "Color.RGB", "ColorComponent", "ColorRGB")
    f.emitters += RGB_EMITTERS


# ---------------------------------------------------------------- Halo Beam

def halo_beam():
    s = MOVER_SCALE
    f = Fixture("Halo Beam", "HaloBeam", "Sentinel Halo Beam",
                "LED beam moving head with a 24-cell RGB halo around its lens: PHAGE's mover, written from the shapes its "
                "renderer draws. A Sentinel example fixture, not a model of any manufacturer's product.")
    f.attr("Pan", "P", "Position.PanTilt", "Angle", "PanTilt")
    f.attr("Tilt", "T", "Position.PanTilt", "Angle", "PanTilt")
    f.attr("Dimmer", "Dim", "Dimmer.Dimmer")
    f.attr("Shutter1", "Sh1", "Beam.Beam")
    f.attr("Shutter1Strobe", "Strobe1", "Beam.Beam", "Frequency", main="Shutter1")
    rgb_attrs(f)
    f.attr("Zoom", "Zoom", "Focus.Focus", "Angle")
    f.attr("Frost1", "Frost1", "Beam.Beam")

    # Base and yoke model space -> GDTF: (x, y, z) -> (x, z, -y), scaled. The head's own space is already the
    # GDTF head frame (its beam leaves along -z at tilt 0), so it only scales.
    def by(p):
        return (p[0] * s, p[2] * s, -p[1] * s)

    def bn(n):
        return (n[0], n[2], -n[1])

    def hs(p):
        return (p[0] * s, p[1] * s, p[2] * s)

    base = Mesh().add(mover_base(), by, bn)
    yoke = Mesh().add(mover_yoke(), by, bn)
    head = Mesh().add(mover_head(), hs)
    lens = Mesh().add(mover_lens(), hs)
    c_base = f.mesh_model("Base", base)
    c_yoke = f.mesh_model("Yoke", yoke)
    c_head = f.mesh_model("Head", head)
    c_lens = f.mesh_model("Lens", lens)
    cell = 0.032
    f.model("Ring Cell", cell, cell, 0.002, "Cylinder")

    pan_z, tilt_z = -PAN_PIVOT * s, -TILT_PIVOT * s
    ring = "\n".join(
        f'            <GeometryReference Name="Ring {k + 1}" Geometry="Ring Cell" '
        f'Position="{mat4(math.sin(2 * math.pi * k / RING_CELLS) * RING_R * s, math.cos(2 * math.pi * k / RING_CELLS) * RING_R * s)}">'
        f'<Break DMXBreak="1" DMXOffset="{12 + 3 * k}"/></GeometryReference>' for k in range(RING_CELLS))
    f.geometries = f"""      <Geometry Name="Base" Model="Base" Position="{mat4(*c_base)}">
        <Axis Name="Yoke" Position="{mat4(-c_base[0], -c_base[1], pan_z - c_base[2])}">
          <Geometry Name="Yoke Frame" Model="Yoke" Position="{mat4(*c_yoke)}"/>
          <Axis Name="Head" Position="{mat4(0, 0, tilt_z)}">
            <Geometry Name="Head Shell" Model="Head" Position="{mat4(*c_head)}"/>
            <Beam Name="Beam" Model="Lens" Position="{mat4(*c_lens)}" LampType="LED" PowerConsumption="420.000000" LuminousFlux="8200.000000" ColorTemperature="6500.000000" BeamAngle="3.000000" FieldAngle="4.500000" ThrowRatio="1.000000" RectangleRatio="1.777700" BeamRadius="{LENS_R * s:.6f}" BeamType="Beam" ColorRenderingIndex="70"/>
            <Geometry Name="Ring" Position="{mat4(0, 0, (RING_Z - .0015) * s)}">
{ring}
            </Geometry>
          </Axis>
        </Axis>
      </Geometry>
      <Beam Name="Ring Cell" Model="Ring Cell" Position="{mat4()}" LampType="LED" PowerConsumption="3.000000" LuminousFlux="95.000000" ColorTemperature="6500.000000" BeamAngle="110.000000" FieldAngle="160.000000" ThrowRatio="1.000000" RectangleRatio="1.777700" BeamRadius="{cell / 2:.6f}" BeamType="Glow" ColorRenderingIndex="80"/>"""

    pan = simple("Yoke", "Pan", "1,2", -270, 270, default=32768, label="Pan")
    tilt = simple("Head", "Tilt", "3,4", -135, 135, default=32768, label="Tilt")
    beam = [simple("Beam", "Dimmer", "5", master="Grand", label="Beam dimmer"), shutter("Beam", "6", 25)]
    beam += rgb("Beam", 7, "Beam ")
    beam += [simple("Beam", "Zoom", "10", 1, 20, default=26, label="Zoom (1-20 deg)"), simple("Beam", "Frost1", "11", label="Frost")]
    standard = [pan, tilt] + beam + [simple("Ring", "Dimmer", "12", label="Halo dimmer")] + rgb("Ring", 13, "Halo ")
    pixel = [pan, tilt] + beam + [simple("Ring Cell", f"ColorAdd_{c}", str(1 + k), extra=f' Emitter="{EMITTER_OF[c]}"', label=f"Halo cell {c}")
                                  for k, c in enumerate("RGB")]
    f.modes.append(("Standard 15ch", "Base", standard, [], 15))
    f.modes.append(("Pixel 83ch", "Base", pixel, [], 11 + 3 * RING_CELLS))

    lo_b, hi_b = base.bounds()
    lo_y, hi_y = yoke.bounds()
    head_r = max(r for r, _ in PROFILE) * s
    f.sheet = {"size": f"{(hi_y[0] - lo_y[0]) * 1000:.0f} x {(hi_b[1] - lo_b[1]) * 1000:.0f} mm footprint; head {2 * head_r * 1000:.0f} mm; "
                       f"pan axis {-pan_z * 1000:.0f} mm and tilt axis {-(pan_z + tilt_z) * 1000:.0f} mm below the mounting face",
               "optics": "LED RGB beam engine, 8,200 lm, zoom 1-20 deg (3 deg at home), frost; halo of 24 RGB cells, 110 deg",
               "motion": "pan 540 deg, tilt 270 deg, 16 bit",
               "cells": "Halo cell 1 sits at the head's +Y (away from the viewer at home); cells run counter-clockwise seen from in "
                        "front of the lens, 15 deg apart"}
    f.cell_base = {"Ring Cell": 12}
    f.thumb = lambda: thumb_mover(base, yoke, head, lens, c_base, c_yoke, c_head, c_lens, pan_z, tilt_z, cell)
    return f


def _place(mesh: Mesh, M, mat=None):
    out = []
    for m, (ps, ns) in mesh.arrays().items():
        p = (np.c_[ps, np.ones(len(ps))] @ M.T)[:, :3]
        n = ns @ M[:3, :3].T
        out.append((m if mat is None else mat, p, n))
    return out


def _T(x=0, y=0, z=0):
    M = np.eye(4)
    M[:3, 3] = (x, y, z)
    return M


def _Rz(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    M = np.eye(4)
    M[:2, :2] = [[c, -s], [s, c]]
    return M


def _Rx(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    M = np.eye(4)
    M[1:3, 1:3] = [[c, -s], [s, c]]
    return M


LOOK = {  # thumbnail look: albedo sRGB, spec
    "body": ((.16, .165, .18), .55), "yoke": ((.19, .195, .21), .6), "shell": ((.15, .155, .17), .5),
    "bezel": ((.42, .42, .44), 1.1), "ring_face": ((.05, .05, .055), .3), "grille": ((.04, .04, .045), .2),
    "rubber": ((.04, .04, .04), .05), "display": ((.03, .05, .07), .8), "lens": ((.10, .11, .12), 1.6),
    "housing": ((.14, .145, .16), .5),
}


def _items(parts, emissive=None):
    emissive = emissive or {}
    return [(p, n, LOOK.get(m, ((.5, .5, .5), .3))[0], LOOK.get(m, ((.5, .5, .5), .3))[1], emissive.get(m)) for m, p, n in parts]


def _upright():
    """Thumbnails stand the mover on its base: GDTF hangs it, so turn it over about Y (its display stays in front)."""
    return np.diag([-1.0, 1.0, -1.0, 1.0])


def _facing():
    """Strobes and battens face the camera: their -Z emission turned to -Y."""
    return _Rx(-90)


def _frame(parts, view_dir, fov=24.0, margin=1.12):
    pts = np.concatenate([p for _, p, _ in parts])
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    centre = (lo + hi) / 2
    radius = np.linalg.norm(hi - lo) / 2
    dist = radius * margin / math.sin(math.radians(fov) / 2)
    d = np.array(view_dir, float)
    d /= np.linalg.norm(d)
    return centre + d * dist, centre, fov


def thumb_mover(base, yoke, head, lens, c_base, c_yoke, c_head, c_lens, pan_z, tilt_z, cell):
    # Each mesh is in its parent's frame already (the GDTF centres the model and moves its geometry instead).
    U = _upright()
    Y = U @ _T(0, 0, pan_z) @ _Rz(-38)
    H = Y @ _T(0, 0, tilt_z) @ _Rx(-48)
    parts = _place(base, U) + _place(yoke, Y) + _place(head, H) + _place(lens, H)
    halo = (np.array([.15, .55, 1.0]) * 6.0).tolist()
    for k in range(RING_CELLS):
        a = 2 * math.pi * k / RING_CELLS
        disc = cylinder("cell", (0, 0, 0), (0, 0, 1), cell / 2 * .92, .001, 16)
        parts += _place(disc, H @ _T(math.sin(a) * RING_R * MOVER_SCALE, math.cos(a) * RING_R * MOVER_SCALE, (RING_Z - .0015) * MOVER_SCALE), "cell")
    # The lens reads as dark glass with a hot core, the way PHAGE draws it lit.
    core = cylinder("core", (0, 0, 0), (0, 0, 1), LENS_R * MOVER_SCALE * .38, .0005, 32)
    parts += _place(core, H @ _T(0, 0, (LENS_Z0 - .0005) * MOVER_SCALE), "core")
    emissive = {"cell": halo, "lens": [.10, .12, .16], "core": (np.array([1.0, .97, .92]) * 4.0).tolist()}
    eye, target, fov = _frame(parts, (.75, -1.55, .8))
    return render(_items(parts, emissive), eye, target, fov)


# ---------------------------------------------------------------- Linear Strobe

def linear_strobe():
    L = STROBE_LEN
    hw, hd, back = STROBE_HOUSING
    frac, tube_h, tube_front = STROBE_TUBE
    plate_off, plate_hw, plate_front = STROBE_PLATE
    n = STROBE_SEGMENTS
    f = Fixture("Linear Strobe", "LinStrobe", "Sentinel Linear Strobe",
                f"{L:g} m linear strobe: a tunable white LED tube between two RGB plates. PHAGE's strobe, written from the "
                "shapes its renderer draws. A Sentinel example fixture, not a model of any manufacturer's product.")
    f.attr("Dimmer", "Dim", "Dimmer.Dimmer")
    f.attr("Shutter1", "Sh1", "Beam.Beam")
    f.attr("Shutter1Strobe", "Strobe1", "Beam.Beam", "Frequency", main="Shutter1")
    f.attr("CTC", "CTC", "Color.Color", "Temperature")
    rgb_attrs(f)
    f.emitters.append('<Emitter Name="Tube" Color="0.312700,0.329000,100.000000"/>')

    # The mounting face is the housing's back: PHAGE's mount point is its front, `back + hd` ahead of it.
    depth = 2 * hd
    face_z = -(back + hd)                         # PHAGE's mount point (the emitting face plane) in GDTF Z
    housing = bevel_box("housing", (0, 0, 0), (L / 2, hw, hd), .004)
    c_h = f.mesh_model("Housing", housing)
    seg = L * frac / n
    f.model("Tube Segment", seg, 2 * tube_h, 2 * tube_h, "Cube")
    f.model("Plate Segment", seg, 2 * plate_hw, 0.002, "Cube")
    xs = [-L * frac / 2 + seg * (k + .5) for k in range(n)]
    hz = -hd                                       # housing centre in GDTF Z
    tube = "\n".join(f'          <Beam Name="Tube {k + 1}" Model="Tube Segment" Position="{mat4(x)}" LampType="LED" PowerConsumption="90.000000" '
                     f'LuminousFlux="2600.000000" ColorTemperature="6500.000000" BeamAngle="115.000000" FieldAngle="160.000000" ThrowRatio="1.000000" '
                     f'RectangleRatio="1.777700" BeamRadius="{tube_h:.6f}" BeamType="Wash" ColorRenderingIndex="85"/>' for k, x in enumerate(xs))

    def plate(p):
        return "\n".join(f'            <Beam Name="Plate {p} {k + 1}" Model="Plate Segment" Position="{mat4(x)}" LampType="LED" PowerConsumption="12.000000" '
                         f'LuminousFlux="160.000000" ColorTemperature="6500.000000" BeamAngle="120.000000" FieldAngle="160.000000" ThrowRatio="1.000000" '
                         f'RectangleRatio="1.777700" BeamRadius="{plate_hw:.6f}" BeamType="Wash" ColorRenderingIndex="80"/>' for k, x in enumerate(xs))

    f.geometries = f"""      <Geometry Name="Housing" Model="Housing" Position="{mat4(0, 0, hz)}">
        <Geometry Name="Tube" Position="{mat4(0, 0, face_z - tube_front - hz)}">
{tube}
        </Geometry>
        <Geometry Name="Plates" Position="{mat4(0, 0, face_z - plate_front - hz)}">
          <Geometry Name="Plate 1" Position="{mat4(0, -plate_off)}">
{plate(1)}
          </Geometry>
          <Geometry Name="Plate 2" Position="{mat4(0, plate_off)}">
{plate(2)}
          </Geometry>
        </Geometry>
      </Geometry>"""
    tube_ch = [simple("Tube", "Dimmer", "1", master="Grand", label="Tube dimmer"), shutter("Tube", "2", 25),
               simple("Tube", "CTC", "3", 6500, 2200, label="Tube colour temperature (6500-2200 K)")]
    standard = tube_ch + [simple("Plates", "Dimmer", "4", label="Plate dimmer")] + rgb("Plates", 5, "Plate ")
    pixel = tube_ch + [simple("Plates", "Dimmer", "4", label="Plate dimmer")] + rgb("Plate 1", 5, "Plate 1 ") + rgb("Plate 2", 8, "Plate 2 ")
    f.modes.append(("Standard 7ch", "Housing", standard, [], 7))
    f.modes.append(("Pixel 10ch", "Housing", pixel, [], 10))
    f.sheet = {"size": f"{L * 1000:.0f} x {2 * hw * 1000:.0f} x {depth * 1000:.0f} mm; the tube stands {(-(face_z - tube_front - tube_h) - depth) * 1000:.0f} mm proud of the face",
               "optics": f"tunable white LED tube, 6500-2200 K, {n} x 2,600 lm, strobe to 25 Hz; two RGB plates either side, 120 deg",
               "cells": f"Plate 1 is the -Y plate, Plate 2 the +Y plate; tube and plates are {n} segments each, left to right in X"}
    f.thumb = lambda: thumb_strobe(housing, c_h, xs, seg, tube_h, plate_hw, plate_off, face_z - tube_front, face_z - plate_front)
    return f


def thumb_strobe(housing, c_h, xs, seg, tube_h, plate_hw, plate_off, tube_z, plate_z):
    U = _facing()
    parts = _place(housing, U @ _T(0, 0, -STROBE_HOUSING[1]))
    for x in xs:
        parts += _place(box_mesh("tube", (seg / 2, tube_h, tube_h)), U @ _T(x, 0, tube_z), "tube")
        for sy in (-1, 1):
            parts += _place(box_mesh("plate", (seg / 2, plate_hw, .001)), U @ _T(x, sy * plate_off, plate_z), "plate")
    emissive = {"tube": (np.array([1.0, .96, .9]) * 5.0).tolist(), "plate": (np.array([1.0, .10, .30]) * 1.1).tolist()}
    eye, target, fov = _frame(parts, (.95, -1.1, .75), margin=1.02)
    return render(_items(parts, emissive), eye, target, fov)


# ---------------------------------------------------------------- Pixel Batten

def pixel_batten(length_mm):
    L = length_mm / 1000
    pixels = int(round(L / BAR_PITCH))
    hw, hd = BAR_SECTION
    sw, proud = BAR_STRIP
    f = Fixture(f"Pixel Batten {length_mm}", f"PixBat{length_mm}", f"Sentinel Pixel Batten {length_mm}",
                f"{L:g} m RGB pixel batten, {pixels} pixels at {BAR_PITCH * 100:g} cm pitch behind a diffuser: the unit PHAGE's "
                "pixel runs are built from, written from the section its renderer draws. A Sentinel example fixture, not a "
                "model of any manufacturer's product.")
    f.attr("Dimmer", "Dim", "Dimmer.Dimmer")
    rgb_attrs(f)
    body = bevel_box("housing", (0, 0, 0), (L / 2, hw, hd), .003)
    c_b = f.mesh_model("Body", body)
    f.model("Pixel", BAR_PITCH * .96, 2 * sw, 0.002, "Cube")
    refs = "\n".join(f'          <GeometryReference Name="Pixel {i + 1}" Geometry="Pixel" Position="{mat4(-L / 2 + BAR_PITCH * (i + .5))}">'
                     f'<Break DMXBreak="1" DMXOffset="{1 + 3 * i}"/></GeometryReference>' for i in range(pixels))
    f.geometries = f"""      <Geometry Name="Body" Model="Body" Position="{mat4(0, 0, -hd)}">
        <Geometry Name="Pixels" Position="{mat4(0, 0, -hd - proud / 2)}">
{refs}
        </Geometry>
      </Geometry>
      <Beam Name="Pixel" Model="Pixel" Position="{mat4()}" LampType="LED" PowerConsumption="0.600000" LuminousFlux="42.000000" ColorTemperature="6500.000000" BeamAngle="110.000000" FieldAngle="150.000000" ThrowRatio="1.000000" RectangleRatio="1.777700" BeamRadius="{sw:.6f}" BeamType="Wash" ColorRenderingIndex="80"/>"""
    pixel = [simple("Pixel", f"ColorAdd_{c}", str(1 + k), extra=f' Emitter="{EMITTER_OF[c]}"', label=f"Pixel {c}") for k, c in enumerate("RGB")]
    bar = [simple("Body", "Dimmer", "1", master="Grand", label="Dimmer")] + rgb("Body", 2)
    f.modes.append((f"Pixel {3 * pixels}ch", "Body", pixel, [], 3 * pixels))
    f.modes.append(("Bar 4ch", "Body", bar, [], 4))
    f.sheet = {"size": f"{L * 1000:.0f} x {2 * hw * 1000:.0f} x {2 * hd * 1000:.0f} mm",
               "optics": f"{pixels} RGB pixels at {BAR_PITCH * 1000:.0f} mm pitch, 110 deg diffused",
               "cells": f"Pixel 1 is at -X (left in the front view); pixels run left to right, three channels each"}
    f.cell_base = {"Pixel": 1}
    f.thumb = lambda: thumb_batten(body, c_b, L, pixels, sw, -2 * hd - proud / 2)
    return f


def thumb_batten(body, c_b, L, pixels, sw, strip_z):
    U = _facing()
    parts = _place(body, U @ _T(0, 0, -BAR_SECTION[1]))
    emissive = {}
    for i in range(pixels):
        t = i / max(1, pixels - 1)
        c = np.array([.1 + .9 * t, .25 * (1 - t) + .05, 1.0 - .55 * t]) * 3.2
        name = f"px{i}"
        parts += _place(box_mesh(name, (BAR_PITCH * .48, sw, .001)), U @ _T(-L / 2 + BAR_PITCH * (i + .5), 0, strip_z), name)
        emissive[name] = c.tolist()
    eye, target, fov = _frame(parts, (.45, -1.4, .5), margin=1.0)
    return render(_items(parts, emissive), eye, target, fov)


# ---------------------------------------------------------------- archive and spec sheet

def write(f: Fixture) -> Path:
    thumb = png_rgba(f.thumb())
    entries = [("description.xml", f.xml()), ("thumbnail.png", thumb)] + f.media
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data)
    path = OUT / f"{MANUFACTURER}@{f.name}.gdtf"
    path.write_bytes(buf.getvalue())
    (OUT / "thumbnails").mkdir(exist_ok=True)
    (OUT / "thumbnails" / f"{f.name}.png").write_bytes(thumb)
    return path


def sheet(fixtures) -> str:
    out = ["# PHAGE fixtures", "",
           "Sentinel's own fixture types, written by `tools/phage_gdtf.py` from the constants PHAGE's renderer draws its",
           "fixtures with. Rerun the script after changing a fixture's shape; it rewrites the GDTFs, their meshes,",
           "thumbnails and this sheet. Photometry is a design figure, not a measurement. GDTF frame: hanging, X right,",
           "Y away from the viewer, Z up, beam along -Z, origin at the mounting face.", ""]
    for f in fixtures:
        out += [f"## {f.long_name}", "", f"![{f.name}](thumbnails/{f.name}.png)", "", f.description, ""]
        for k in ("size", "optics", "motion", "cells"):
            if k in f.sheet:
                out.append(f"- **{k.capitalize()}:** {f.sheet[k]}")
        for mname, _, channels, _, count in f.modes:
            out += ["", f"### {mname}", "", "| Ch | Geometry | Function | DMX |", "|---|---|---|---|"]
            for offset, geometry, label, functions in (c[1] for c in channels):
                spans = []
                for i, (name, attr, dmx_from, pf, pt, _) in enumerate(functions):
                    if len(functions) == 1:
                        unit = "" if (pf, pt) == (0.0, 1.0) else f" ({pf:g} to {pt:g})"
                        spans.append(f"0-{(1 << (8 * len(offset.split(',')))) - 1}{unit}")
                    else:
                        hi = functions[i + 1][2] - 1 if i + 1 < len(functions) else 255
                        spans.append(f"{dmx_from}-{hi} {name.lower()}" + (f" {pf:g}-{pt:g} Hz" if attr.endswith("Strobe") else ""))
                ch = offset.replace(",", "+")
                if geometry in f.cell_base:
                    ch = f"{f.cell_base[geometry] + int(offset) - 1} + 3(n-1)"
                out.append(f"| {ch} | {geometry} | {label} | {'; '.join(spans)} |")
            out.append(f"\n{count} channels.")
        out.append("")
    return "\n".join(out)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    fixtures = [halo_beam(), linear_strobe(), pixel_batten(1000)]
    for f in fixtures:
        p = write(f)
        print(f"{p.relative_to(ROOT)}: {p.stat().st_size} bytes")
    (OUT / "FIXTURES.md").write_text(sheet(fixtures), encoding="utf-8", newline="\n")
    print(f"{(OUT / 'FIXTURES.md').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
