"""Builds dist/LiquidGlass.lua: generates textures and the icon atlas, embeds them
(plus the UI sounds) as base64, and concatenates the library sources.

usage: python build.py [--no-textures] [--install]
  --no-textures  reuse build/assets from the previous run
  --install      also copy the result into the executor workspace for testing
"""
import base64
import hashlib
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "tools"))

import icons  # noqa: E402
import logo3d  # noqa: E402
from PIL import Image  # noqa: E402
import textures  # noqa: E402

ASSETS = os.path.join(HERE, "build", "assets")
SOUNDS = os.path.join(HERE, "assets", "sounds")
SRC = os.path.join(HERE, "src")
DIST = os.path.join(HERE, "dist", "LiquidGlass.lua")
WORKSPACE = os.path.expandvars(r"%LOCALAPPDATA%\Real\workspace\LiquidGlass")

WINDOW_RADIUS = 26  # keep in sync with W_RADIUS in src/04_window.lua
# every small radius, then coarser steps (in-between radii are drawn scaled);
# keep in sync with RIM_SIZES in src/03_glass.lua
RIM_SIZES = list(range(4, 17)) + [18, 20, 22, 24, 26, 28, 30, 33, 36, 40]


def gen_textures():
    if os.path.isdir(ASSETS):
        shutil.rmtree(ASSETS)
    os.makedirs(ASSETS)
    for r in RIM_SIZES:
        textures.rim(r, os.path.join(ASSETS, f"rim_{r}.png"))
    for r in range(4, 41, 4):
        textures.shadow(r, os.path.join(ASSETS, f"shadow_{r}.png"), blur=20, pad=48, oy=10, peak=0.55)
    for r in range(4, 25, 4):
        textures.shadow(r, os.path.join(ASSETS, f"shadowsm_{r}.png"), blur=3.2, pad=12, oy=2, cut=False)
    textures.radial(os.path.join(ASSETS, "radial.png"))
    textures.grip(os.path.join(ASSETS, "grip.png"), radius=WINDOW_RADIUS)
    textures.checker(os.path.join(ASSETS, "checker.png"))
    index = icons.build(os.path.join(ASSETS, "icons.png"))
    to_gray_alpha()
    logo3d.build("Entity", os.path.join(ASSETS, "logo.mesh"))
    with open(os.path.join(ASSETS, "icons.index"), "w", encoding="utf-8") as f:
        for name, i in sorted(index.items(), key=lambda kv: kv[1]):
            f.write(f"{name} {i}\n")


def to_gray_alpha():
    """All textures are single-color + alpha: store them as LA PNGs (~35% smaller)."""
    for name in os.listdir(ASSETS):
        if not name.endswith(".png"):
            continue
        path = os.path.join(ASSETS, name)
        im = Image.open(path).convert("RGBA")
        r, g, b, a = im.split()
        if r.tobytes() == g.tobytes() == b.tobytes():
            Image.merge("LA", (r, a)).save(path, optimize=True)


def read_index():
    out = {}
    with open(os.path.join(ASSETS, "icons.index"), encoding="utf-8") as f:
        for line in f:
            name, i = line.split()
            out[name] = int(i)
    return out


def lua_assets():
    files = {}
    for name in sorted(os.listdir(ASSETS)):
        if name.endswith(".png") or name.endswith(".mesh"):
            files[name] = open(os.path.join(ASSETS, name), "rb").read()
    if os.path.isdir(SOUNDS):
        for name in sorted(os.listdir(SOUNDS)):
            if name.endswith(".ogg"):
                files[name] = open(os.path.join(SOUNDS, name), "rb").read()
    digest = hashlib.sha1()
    for name, data in files.items():
        digest.update(name.encode())
        digest.update(data)
    version = digest.hexdigest()[:10]
    lines = ["local PACK = {"]
    for name, data in files.items():
        lines.append(f'\t["{name}"] = "{base64.b64encode(data).decode()}",')
    lines.append("}")
    lines.append(f'local ASSET_VERSION = "{version}"')
    index = read_index()
    entries = ", ".join(f'["{n}"] = {i}' for n, i in sorted(index.items(), key=lambda kv: kv[1]))
    lines.append(f"local ICON_INDEX = {{ {entries} }}")
    lines.append(f"local ICON_CELL, ICON_COLS = {icons.CELL}, {icons.COLS}")
    total = sum(len(d) for d in files.values())
    return "\n".join(lines), version, len(files), total


def main():
    if "--no-textures" not in sys.argv or not os.path.isdir(ASSETS):
        gen_textures()
    assets_code, version, count, total = lua_assets()
    parts = []
    for name in sorted(os.listdir(SRC)):
        if name.endswith(".lua"):
            parts.append(open(os.path.join(SRC, name), encoding="utf-8").read())
    source = "\n".join(parts)
    marker = "--@ASSETS@--"
    assert source.count(marker) == 1, "asset marker missing"
    source = source.replace(marker, assets_code)
    os.makedirs(os.path.dirname(DIST), exist_ok=True)
    with open(DIST, "w", encoding="utf-8", newline="\n") as f:
        f.write(source)
    size = os.path.getsize(DIST)
    print(f"dist/LiquidGlass.lua  {size / 1024:.0f} KB  ({count} assets, {total / 1024:.0f} KB raw, version {version})")
    if "--install" in sys.argv:
        os.makedirs(WORKSPACE, exist_ok=True)
        shutil.copy(DIST, os.path.join(WORKSPACE, "LiquidGlass.lua"))
        for name in ("example.lua", "demo.lua"):
            path = os.path.join(HERE, name)
            if os.path.isfile(path):
                shutil.copy(path, os.path.join(WORKSPACE, name))
        print("installed to", WORKSPACE)


if __name__ == "__main__":
    main()
