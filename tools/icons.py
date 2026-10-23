"""Builds the icon atlas (white glyphs on transparent cells) from Segoe Fluent Icons."""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONT = r"C:\Windows\Fonts\SegoeIcons.ttf"
CELL = 64
COLS = 16

# name -> code point (Segoe Fluent Icons). Aliases are added by the library.
ICONS = {
    "home": 0xE80F, "home-fill": 0xEA8A, "settings": 0xE713, "search": 0xE721, "user": 0xE77B,
    "users": 0xE716, "user-plus": 0xE8FA, "people-team": 0xE902, "admin": 0xE7EF,
    "close": 0xE711, "check": 0xE73E, "plus": 0xE710, "minus": 0xE738,
    "chevron-right": 0xE76C, "chevron-left": 0xE76B, "chevron-down": 0xE70D, "chevron-up": 0xE70E,
    "arrow-right": 0xE72A, "arrow-left": 0xE72B, "arrow-up": 0xE74A, "arrow-down": 0xE74B,
    "menu": 0xE700, "more": 0xE712, "grid": 0xF0E2, "apps": 0xE71D, "list": 0xEA37,
    "star": 0xE734, "star-fill": 0xE735, "heart": 0xEB51, "heart-fill": 0xEB52, "heart-broken": 0xEA92,
    "bell": 0xEA8F, "info": 0xE946, "help": 0xE897, "warning": 0xE7BA, "error": 0xEA39,
    "check-circle": 0xEC61, "shield": 0xEA18, "lock": 0xE72E, "unlock": 0xE785, "key": 0xE8D7,
    "fingerprint": 0xE928, "eye": 0xE890, "eye-off": 0xED1A,
    "edit": 0xE70F, "trash": 0xE74D, "copy": 0xE8C8, "paste": 0xE77F, "cut": 0xE8C6, "save": 0xE74E,
    "download": 0xE896, "upload": 0xE898, "refresh": 0xE72C, "sync": 0xE895, "undo": 0xE7A7, "redo": 0xE7A6,
    "link": 0xE71B, "share": 0xE72D, "external": 0xE8A7, "filter": 0xE71C, "sort": 0xE8CB, "swap": 0xE8AB,
    "folder": 0xE8B7, "file": 0xE8A5, "page": 0xE7C3, "code": 0xE943, "terminal": 0xE756,
    "bug": 0xEBE8, "wrench": 0xE90F, "tools": 0xEC7A, "puzzle": 0xEA86, "robot": 0xE99A, "cogs": 0xE9F5,
    "gamepad": 0xE7FC, "keyboard": 0xE765, "mouse": 0xE962, "cursor": 0xE8B0, "monitor": 0xE7F4, "phone": 0xE8EA,
    "play": 0xF5B0, "pause": 0xF8AE, "stop": 0xE71A, "next": 0xF8AD, "previous": 0xF8AC,
    "shuffle": 0xE8B1, "repeat": 0xE8EE, "volume": 0xE767, "mute": 0xE74F, "music": 0xEC4F,
    "headphones": 0xE7F6, "mic": 0xE720, "camera": 0xE722, "video": 0xE714, "image": 0xE91B,
    "palette": 0xE790, "brush": 0xE771, "eyedropper": 0xEF3C, "layers": 0xE81E, "contrast": 0xE793,
    "sun": 0xE706, "moon": 0xE708, "bolt": 0xE945, "flash": 0xE754, "cloud": 0xE753, "water": 0xEB42,
    "fire": 0xECAD, "lightbulb": 0xEA80, "smile": 0xED54,
    "wifi": 0xE701, "bluetooth": 0xE702, "airplane": 0xE709, "globe": 0xE774, "location": 0xE81D,
    "map-pin": 0xE707, "compass": 0xE909, "flag": 0xE7C1, "pin": 0xE718, "pin-fill": 0xE841, "tag": 0xE8EC,
    "cart": 0xE7BF, "shop": 0xE719, "card": 0xE8C7, "calendar": 0xE787, "clock": 0xE823,
    "history": 0xE81C, "timer": 0xE916, "mail": 0xE715, "chat": 0xE8BD, "chats": 0xE8F2, "send": 0xE724,
    "attach": 0xE723, "power": 0xE7E8, "logout": 0xF3B1, "target": 0xF272, "speed": 0xEC4A,
    "chart": 0xE9D9, "database": 0xEE94, "network": 0xE968, "cpu": 0xEEA1, "battery": 0xEBA7,
    "zoom-in": 0xE8A3, "zoom-out": 0xE71F, "fullscreen": 0xE740, "collapse": 0xE73F, "minimize": 0xE921,
    "maximize": 0xE922, "sidebar": 0xE89F, "dock": 0xE90C, "sliders": 0xE9E9, "thumbs-up": 0xE8E1,
    "thumbs-down": 0xE8E0, "translate": 0xF2B7, "ruler": 0xED5E, "move": 0xE7C2, "rotate": 0xE7AD,
    "cube": 0xF158, "box": 0xE7B8, "car": 0xE804, "walk": 0xE805, "run": 0xE726, "accessibility": 0xE776,
    "checkbox": 0xE739, "checkbox-checked": 0xE73A, "circle": 0xEA3A, "qr": 0xED14,
}


def build(atlas_path, preview_path=None):
    """Renders the atlas; returns {name: index} for glyphs that actually exist."""
    font = ImageFont.truetype(FONT, int(CELL * 0.74) * 4)
    probe = ImageDraw.Draw(Image.new("L", (8, 8)))
    names, seen = [], {}
    for name, cp in ICONS.items():
        bbox = probe.textbbox((0, 0), chr(cp), font=font)
        if bbox[2] - bbox[0] < 4 or bbox[3] - bbox[1] < 4:
            continue  # glyph missing in this font
        names.append((name, cp))
    rows = math.ceil(len(names) / COLS)
    atlas = Image.new("RGBA", (COLS * CELL, rows * CELL), (255, 255, 255, 0))
    index = {}
    for i, (name, cp) in enumerate(names):
        # render on a roomy canvas, then center by the actual ink: font boxes include
        # line metrics, which leaves glyphs like the minus far above center
        S4 = CELL * 4
        scratch = Image.new("L", (S4 * 2, S4 * 2), 0)
        ImageDraw.Draw(scratch).text((S4 // 2, S4 // 2), chr(cp), font=font, fill=255)
        ink = scratch.getbbox()
        glyph = scratch.crop(ink)
        big = Image.new("L", (S4, S4), 0)
        big.paste(glyph, ((S4 - glyph.width) // 2, (S4 - glyph.height) // 2))
        cell = big.resize((CELL, CELL), Image.LANCZOS)
        rgba = Image.merge("RGBA", (Image.new("L", cell.size, 255),) * 3 + (cell,))
        atlas.alpha_composite(rgba, ((i % COLS) * CELL, (i // COLS) * CELL))
        index[name] = i
    atlas.save(atlas_path, optimize=True)
    if preview_path:
        sheet = Image.new("RGBA", (COLS * 90, rows * 96), (36, 36, 44, 255))
        d = ImageDraw.Draw(sheet)
        for name, i in index.items():
            x, y = (i % COLS) * 90, (i // COLS) * 96
            sheet.alpha_composite(atlas.crop(((i % COLS) * CELL, (i // COLS) * CELL, (i % COLS + 1) * CELL, (i // COLS + 1) * CELL)), (x + 13, y + 6))
            d.text((x + 4, y + 74), name[:14], fill=(220, 220, 220, 255))
        sheet.save(preview_path)
    return index
