"""Builds the 3D intro word from exact font outlines: a glass slab with a flat,
crisp front face and a small rounded bevel on every edge.

Contours come straight from the font (Segoe UI Variable Display Bold), curves
are flattened adaptively, and the bevel is made of rings offset along each
contour point's corner bisector, so letter shapes stay exact. Sharp corners get
split normals (crisp edges); curves share normals (smooth highlights).

Binary blob read by the library:
    u16 vertexCount, u16 triangleCount, u16 faceTriangleCount
    vertexCount * (i16 x, i16 y, i16 z)      positions / 32767 * halfExtent
    vertexCount * (i16 nx, i16 ny, i16 nz)   normals / 32767
    triangleCount * (u16 a, u16 b, u16 c)    counter-clockwise seen from outside;
                                             the first faceTriangleCount are the flat
                                             front/back faces, the rest the bevels
    f32 halfExtentX, f32 halfExtentY, f32 halfExtentZ
"""
import math
import struct
import sys

import mapbox_earcut as earcut
import numpy as np
from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont

FONT = r"C:\Windows\Fonts\SegUIVar.ttf"
AXES = {"wght": 700, "opsz": 36}


class FlattenPen(BasePen):
    """Collects glyph contours as polylines, flattening curves adaptively."""

    def __init__(self, glyphSet, tolerance=6.0):
        super().__init__(glyphSet)
        self.contours, self.cur, self.tol = [], [], tolerance

    def _moveTo(self, p):
        self.cur = [p]

    def _lineTo(self, p):
        self.cur.append(p)

    def _curveToOne(self, p1, p2, p3):
        p0 = self.cur[-1]
        n = max(2, min(24, int(math.dist(p0, p3) / self.tol / 4) + 2))
        for i in range(1, n + 1):
            t = i / n
            mt = 1 - t
            self.cur.append((mt ** 3 * p0[0] + 3 * mt * mt * t * p1[0] + 3 * mt * t * t * p2[0] + t ** 3 * p3[0],
                             mt ** 3 * p0[1] + 3 * mt * mt * t * p1[1] + 3 * mt * t * t * p2[1] + t ** 3 * p3[1]))

    def _qCurveToOne(self, p1, p2):
        p0 = self.cur[-1]
        n = max(2, min(24, int((math.dist(p0, p1) + math.dist(p1, p2)) / self.tol / 4) + 2))
        for i in range(1, n + 1):
            t = i / n
            mt = 1 - t
            self.cur.append((mt * mt * p0[0] + 2 * mt * t * p1[0] + t * t * p2[0],
                             mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1]))

    def _closePath(self):
        if len(self.cur) > 2:
            self.contours.append(self.cur)
        self.cur = []

    _endPath = _closePath


def signed_area(c):
    x, y = c[:, 0], c[:, 1]
    return 0.5 * np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y)


def point_in_poly(p, c):
    x, y = p
    inside = False
    j = len(c) - 1
    for i in range(len(c)):
        xi, yi = c[i]
        xj, yj = c[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def clean(c, eps=0.5):
    c = np.array(c, dtype=np.float64)
    if np.allclose(c[0], c[-1]):
        c = c[:-1]
    keep = [0]
    for i in range(1, len(c)):
        if np.linalg.norm(c[i] - c[keep[-1]]) > eps:
            keep.append(i)
    c = c[keep]
    if np.linalg.norm(c[0] - c[-1]) <= eps:
        c = c[:-1]
    out = []
    n = len(c)
    for i in range(n):  # drop collinear points
        a, b, d = c[i - 1], c[i], c[(i + 1) % n]
        u, w = b - a, d - b
        if abs(u[0] * w[1] - u[1] * w[0]) > 1e-3 * np.linalg.norm(u) * np.linalg.norm(w) or np.dot(u, w) < 0:
            out.append(b)
    return np.array(out)


def word_contours(text):
    font = TTFont(FONT)
    cmap = font.getBestCmap()
    # outlines and advances interpolated at the chosen weight/optical size
    gs = font.getGlyphSet(location=AXES)
    x = 0.0
    shapes = []  # (outer counter-clockwise, [holes clockwise])
    for ch in text:
        name = cmap[ord(ch)]
        pen = FlattenPen(gs)
        gs[name].draw(pen)
        cs = [clean(c) + np.array([x, 0.0]) for c in pen.contours]
        cs = [c for c in cs if len(c) >= 3]
        # TrueType outer contours are clockwise
        groups = [(c[::-1], []) for c in cs if signed_area(c) < 0]
        for h in (c for c in cs if signed_area(c) >= 0):
            for o, hs in groups:
                if point_in_poly(h[0], o):
                    hs.append(h[::-1])
                    break
        shapes += groups
        x += gs[name].width
    return shapes


def ring_data(c):
    """Per point: outward bisector, miter scale, incoming/outgoing edge normals, sharp corner flag."""
    e_in = c - np.roll(c, 1, axis=0)
    e_out = np.roll(c, -1, axis=0) - c
    e_in /= np.linalg.norm(e_in, axis=1, keepdims=True)
    e_out /= np.linalg.norm(e_out, axis=1, keepdims=True)
    # solid on the left (ccw outer / cw hole): outward normal = edge rotated clockwise
    n_in = np.stack([e_in[:, 1], -e_in[:, 0]], axis=1)
    n_out = np.stack([e_out[:, 1], -e_out[:, 0]], axis=1)
    b = n_in + n_out
    bl = np.linalg.norm(b, axis=1, keepdims=True)
    b = np.where(bl > 1e-6, b / np.maximum(bl, 1e-6), n_out)
    miter = 1.0 / np.maximum(np.sum(b * n_out, axis=1), 0.5)
    sharp = np.degrees(np.arccos(np.clip(np.sum(e_in * e_out, axis=1), -1, 1))) > 32
    return b, miter, n_in, n_out, sharp


def build(text, out_path, bevel=42.0, half_depth=130.0, steps=6):
    shapes = word_contours(text)
    V, N, T, TF = [], [], [], []

    def add(p, n):
        V.append(p)
        N.append(n)
        return len(V) - 1

    # bevel: quarter circle from the front face edge (inset by `bevel`) to the side wall
    prof = []
    for i in range(steps + 1):
        th = (i / steps) * math.pi / 2
        prof.append((bevel * (1 - math.sin(th)), (half_depth - bevel) + bevel * math.cos(th), th))
    levels = prof + [(inset, -z, th) for inset, z, th in reversed(prof)]

    for outer, holes in shapes:
        contours = [outer] + holes
        datas = [ring_data(c) for c in contours]
        # flat front and back faces, triangulated with their holes
        front = [c - d[0] * (bevel * d[1])[:, None] for c, d in zip(contours, datas)]
        flat = np.concatenate(front)
        ends = np.cumsum([len(r) for r in front]).astype(np.uint32)
        tris = np.asarray(earcut.triangulate_float64(flat, ends)).reshape(-1, 3)
        for zs in (1.0, -1.0):
            base = len(V)
            for p in flat:
                add((p[0], p[1], zs * half_depth), (0.0, 0.0, zs))
            for a, b2, cc in tris:
                TF.append((base + a, base + b2, base + cc) if zs > 0 else (base + a, base + cc, base + b2))
        # bevel rings + side wall
        for c, (b, miter, n_in, n_out, sharp) in zip(contours, datas):
            m = len(c)
            cols_in, cols_out = [], []
            for inset, z, th in levels:
                pos = c - b * (inset * miter)[:, None]
                zs = 1.0 if z > 0 else -1.0
                s, co = math.sin(th), math.cos(th)
                ci, cout = [], []
                for j in range(m):
                    p3 = (pos[j, 0], pos[j, 1], z)
                    if sharp[j]:
                        ci.append(add(p3, (n_in[j, 0] * s, n_in[j, 1] * s, zs * co)))
                        cout.append(add(p3, (n_out[j, 0] * s, n_out[j, 1] * s, zs * co)))
                    else:
                        k = add(p3, (b[j, 0] * s, b[j, 1] * s, zs * co))
                        ci.append(k)
                        cout.append(k)
                cols_in.append(ci)
                cols_out.append(cout)
            for L in range(len(levels) - 1):
                if levels[L][1] == levels[L + 1][1]:
                    continue
                for j in range(m):
                    jn = (j + 1) % m
                    a1, b1 = cols_out[L][j], cols_in[L][jn]
                    a2, b2 = cols_out[L + 1][j], cols_in[L + 1][jn]
                    T.append((a1, a2, b1))
                    T.append((b1, a2, b2))

    v = np.array(V, dtype=np.float64)
    n = np.array(N, dtype=np.float64)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    faces_n = len(TF)
    f = np.array(TF + T, dtype=np.int64)
    # every triangle must face the same way as its stored normals
    tri = v[f]
    fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    agree = np.sum(fn * n[f].mean(axis=1), axis=1)
    flipped = agree < 0
    f[flipped] = f[flipped][:, [0, 2, 1]]
    print("triangles re-wound:", int(np.sum(flipped)), "of", len(f))

    lo, hi = v.min(axis=0), v.max(axis=0)
    v -= (lo + hi) / 2
    v /= (hi[1] - lo[1])
    half = np.abs(v).max(axis=0)
    q = np.round(v / half * 32767).astype(np.int16)
    qn = np.round(n * 32767).astype(np.int16)
    assert len(v) < 65536
    blob = struct.pack("<HHH", len(v), len(f), faces_n) + q.tobytes() + qn.tobytes() + f.astype(np.uint16).tobytes() + struct.pack("<fff", *half)
    open(out_path, "wb").write(blob)
    print(len(v), "verts", len(f), "tris; blob", len(blob), "bytes; half extent", half)


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "Entity", sys.argv[2] if len(sys.argv) > 2 else "logo.mesh")
