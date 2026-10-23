"""DPI-aware capture of the Roblox window client area (works while occluded via PrintWindow).

usage: python shot.py out.png [x y w h]   (optional crop in Roblox GUI pixels)
"""
import ctypes
import sys
from ctypes import wintypes

from PIL import Image

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
ctypes.windll.shcore.SetProcessDpiAwareness(2)


def find_roblox():
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def cb(hwnd, _):
        if user32.IsWindowVisible(hwnd):
            buf = ctypes.create_unicode_buffer(256)
            user32.GetWindowTextW(hwnd, buf, 256)
            cls = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, cls, 256)
            if buf.value == "Roblox" and "WINDOWSCLIENT" in cls.value.upper():
                found.append(hwnd)
        return True

    user32.EnumWindows(cb, 0)
    if not found:
        # fall back to any window titled Roblox
        hwnd = user32.FindWindowW(None, "Roblox")
        if hwnd:
            found.append(hwnd)
    return found[0]


def capture(hwnd):
    rc = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rc))
    w, h = rc.right - rc.left, rc.bottom - rc.top
    hdc = user32.GetWindowDC(hwnd)
    mdc = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(mdc, bmp)
    user32.PrintWindow(hwnd, mdc, 2)  # PW_RENDERFULLCONTENT

    class BITMAPINFOHEADER(ctypes.Structure):
        _fields_ = [("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG), ("biHeight", wintypes.LONG),
                    ("biPlanes", wintypes.WORD), ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                    ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", wintypes.LONG),
                    ("biYPelsPerMeter", wintypes.LONG), ("biClrUsed", wintypes.DWORD),
                    ("biClrImportant", wintypes.DWORD)]

    bi = BITMAPINFOHEADER()
    bi.biSize = ctypes.sizeof(bi)
    bi.biWidth, bi.biHeight, bi.biPlanes, bi.biBitCount = w, -h, 1, 32
    buf = ctypes.create_string_buffer(w * h * 4)
    gdi32.GetDIBits(mdc, bmp, 0, h, buf, ctypes.byref(bi), 0)
    img = Image.frombuffer("RGBA", (w, h), buf, "raw", "BGRA", 0, 1).convert("RGB")
    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mdc)
    user32.ReleaseDC(hwnd, hdc)

    # crop to client area
    crc = wintypes.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(crc))
    pt = wintypes.POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(pt))
    ox, oy = pt.x - rc.left, pt.y - rc.top
    return img.crop((ox, oy, ox + crc.right, oy + crc.bottom))


if __name__ == "__main__":
    out = sys.argv[1]
    img = capture(find_roblox())
    if len(sys.argv) >= 6:
        # crop given in GUI px; convert using the DPI scale of the client area
        scale = img.width / float(sys.argv[6]) if len(sys.argv) >= 7 else 1.25
        x, y, w, h = (float(v) * scale for v in sys.argv[2:6])
        img = img.crop((int(x), int(y), int(x + w), int(y + h)))
    img.save(out)
    print(out, img.size)
