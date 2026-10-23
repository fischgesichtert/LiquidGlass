"""Liquid Glass texture generators (rims, shadows, glow, resize grip, checkerboard)."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 4  # supersampling for analytic shapes
RIM_SCALE = 2  # rims are rendered at 2x and drawn with SliceScale 0.5


def rrect_sdf(w, h, r, ss=SS, ox=0.0, oy=0.0, inset=0.0):
    """Signed distance (px, negative inside) and outward normal of a rounded rect.

    The rect fills the w x h canvas minus `inset` on each side, shifted by (ox, oy).
    """
    ys, xs = np.mgrid[0:h * ss, 0:w * ss].astype(np.float64)
    xs = (xs + 0.5) / ss - ox
    ys = (ys + 0.5) / ss - oy
    cx, cy = w / 2, h / 2
    hw, hh = w / 2 - inset, h / 2 - inset
    qx = np.abs(xs - cx) - (hw - r)
    qy = np.abs(ys - cy) - (hh - r)
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    inside = np.minimum(np.maximum(qx, qy), 0)
    d = outside + inside - r
    sx, sy = np.sign(xs - cx), np.sign(ys - cy)
    corner = (qx > 0) & (qy > 0)
    nx = np.where(corner, qx * sx, np.where(qx > qy, sx, 0.0))
    ny = np.where(corner, qy * sy, np.where(qx > qy, 0.0, sy))
    ln = np.hypot(nx, ny)
    ln[ln == 0] = 1
    return d, nx / ln, ny / ln


def downsample(arr, ss=SS):
    h, w = arr.shape[0] // ss, arr.shape[1] // ss
    return arr.reshape(h, ss, w, ss).mean(axis=(1, 3))


def save_rgba(path, rgb, alpha):
    a = np.clip(alpha, 0, 1)
    img = np.zeros(a.shape + (4,), dtype=np.uint8)
    for i in range(3):
        img[..., i] = np.clip(np.asarray(rgb[i]) * 255, 0, 255)
    img[..., 3] = np.round(a * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(path, optimize=True)


DROP_LIGHT = np.array([-0.7, -0.72])
DROP_LIGHT = DROP_LIGHT / np.linalg.norm(DROP_LIGHT)


def rim(r, path):
    """9-slice rim light for corner radius r (GUI px), rendered at RIM_SCALE.

    Canvas side = 2r+4 GUI px; corners are r, center slice 4 GUI px.
    Lit like a water drop: a crisp specular rim that pools on the curved corners
    facing the light, a dark refraction ring just inside it, a soft glow band, and
    a caustic glow set inside the opposite (bottom-right) rim.
    """
    s = RIM_SCALE
    R = r * s
    size = (2 * r + 4) * s
    d, nx, ny = rrect_sdf(size, size, R)
    cover = np.clip(0.5 - d, 0, 1)
    dist = np.maximum(-d, 0) / s  # GUI px inward from the edge
    facing = nx * DROP_LIGHT[0] + ny * DROP_LIGHT[1]
    front = np.clip(facing, 0, 1) ** 3.0
    back = np.clip(-facing, 0, 1) ** 3.0
    lit = 0.12 + 0.88 * np.maximum(front, 0.8 * back)

    spec = np.exp(-((dist - 0.6) / 0.62) ** 2) * (0.2 + 0.8 * lit)
    gw = min(max(2.5, r * 0.34), 10.0)
    glow = np.exp(-dist / gw) * 0.16 * (0.3 + 0.7 * lit)
    cw = min(max(1.6, r * 0.12), 5.0)
    caustic = np.exp(-((dist - min(max(2.2, r * 0.17), 7.0)) / cw) ** 2) * 0.26 * back
    white = np.clip(spec + glow + caustic, 0, 1)
    dark = np.exp(-((dist - 2.4) / 1.3) ** 2) * 0.13 * (0.35 + 0.65 * front) * (1 - white)

    a = (white + dark * (1 - white)) * cover
    lum = np.where(a > 1e-4, white * cover / np.maximum(a, 1e-4), 1.0)
    a, lum = downsample(a), downsample(lum * a) / np.maximum(downsample(a), 1e-4)
    save_rgba(path, (lum, lum, lum), a)


def shadow(r, path, blur, pad, oy, cut=True, peak=1.0):
    """Soft drop shadow for corner radius r; shape inset by pad, shadow offset oy.

    With cut=True the area under the shape itself is transparent so the shadow never
    darkens the translucent glass above it.
    """
    core = 2 * r + 4
    size = core + 2 * pad
    img = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(img).rounded_rectangle(
        [pad * SS, (pad + oy) * SS, (pad + core) * SS - 1, (pad + core + oy) * SS - 1], radius=r * SS, fill=255)
    img = img.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(blur))
    a = np.asarray(img, dtype=np.float64) / 255.0 * peak
    if cut:
        d, _, _ = rrect_sdf(size, size, r, inset=pad)
        a = a * np.clip(downsample(d) + 0.5, 0, 1)
    save_rgba(path, (0, 0, 0), a)


def radial(path, size=128):
    """Soft round glow used for the pointer light inside glass."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    rr = np.hypot(xs - size / 2 + 0.5, ys - size / 2 + 0.5) / (size / 2)
    a = np.exp(-(rr / 0.5) ** 2) * (rr < 1)
    save_rgba(path, (1, 1, 1), a)


def grip(path, radius=30, inset=5, width=3.0, sweep=62):
    """Resize handle: an arc that hugs a window's bottom-right corner (iPadOS style).

    Canvas is radius x radius; the arc is centered on the corner's circle center,
    offset inward by `inset`, sweeping `sweep` degrees around the 45 degree diagonal.
    """
    s = 8
    n = radius * s
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64) / s
    cx = cy = 0.0  # corner circle center sits at the canvas' top-left
    rr = np.hypot(xs - cx, ys - cy)
    ring = radius - inset
    ang = np.degrees(np.arctan2(ys - cy, xs - cx))
    half = sweep / 2
    # distance to the arc, rounded caps at the ends
    t = np.clip(ang, 45 - half, 45 + half)
    px = cx + ring * np.cos(np.radians(t))
    py = cy + ring * np.sin(np.radians(t))
    dist = np.hypot(xs - px, ys - py)
    a = np.clip(width / 2 - dist + 0.5, 0, 1)
    img = Image.fromarray((a * 255).astype(np.uint8), "L").resize((radius * 2, radius * 2), Image.LANCZOS)
    a = np.asarray(img, dtype=np.float64) / 255.0
    save_rgba(path, (1, 1, 1), a)


def checker(path, cell=6, cells=4):
    """Transparency checkerboard tile for color swatches."""
    size = cell * cells
    ys, xs = np.mgrid[0:size, 0:size]
    on = ((xs // cell) + (ys // cell)) % 2 == 0
    v = np.where(on, 1.0, 0.78)
    save_rgba(path, (v, v, v), np.ones((size, size)))


def squircle_mask(path, size=128, n=5.0):
    """Superellipse (iOS app icon) mask, white."""
    s = SS
    ys, xs = np.mgrid[0:size * s, 0:size * s].astype(np.float64)
    u = (xs + 0.5) / (size * s) * 2 - 1
    v = (ys + 0.5) / (size * s) * 2 - 1
    f = np.abs(u) ** n + np.abs(v) ** n
    a = downsample(np.clip((1 - f) * size * 0.6, 0, 1), s)
    save_rgba(path, (1, 1, 1), a)
