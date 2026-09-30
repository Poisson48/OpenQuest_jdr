"""Tile the 4 Valbois LAN Godot windows 2x2 and capture each one to a PNG.

Each window is restored, moved to its quadrant and raised to the top of the
z-order just before its own screen grab, so an editor window covering the
desktop cannot leak into the capture.
"""
import ctypes
import sys
import time
from ctypes import wintypes
from pathlib import Path

from PIL import ImageGrab

user32 = ctypes.windll.user32
user32.SetProcessDPIAware()

WNDENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

SW_SHOWNORMAL = 1
SW_SHOW = 5
SW_RESTORE = 9
HWND_TOP = 0
HWND_TOPMOST = -1
HWND_NOTOPMOST = -2
SWP_NOACTIVATE = 0x0010
SWP_SHOWWINDOW = 0x0040
GWL_EXSTYLE = -20
WS_EX_TOPMOST = 0x8

ORDER = ["MJ", "P1", "P2", "P3"]


def find_windows():
    found = {}

    def cb(hwnd, _):
        n = user32.GetWindowTextLengthW(hwnd)
        buf = ctypes.create_unicode_buffer(n + 1)
        user32.GetWindowTextW(hwnd, buf, n + 1)
        for key in ORDER:
            if f"RealLan_{key}" in buf.value:
                found[key] = (hwnd, buf.value)
        return True

    user32.EnumWindows(WNDENUMPROC(cb), 0)
    return found


def main() -> int:
    suffix = sys.argv[1] if len(sys.argv) > 1 else "ux-break"
    wins = find_windows()
    missing = [k for k in ORDER if k not in wins]
    if missing:
        print(f"MISSING {missing}", file=sys.stderr)
        return 1

    SPI_GETWORKAREA = 0x0030
    wa = wintypes.RECT()
    user32.SystemParametersInfoW(SPI_GETWORKAREA, 0, ctypes.byref(wa), 0)
    ww = (wa.right - wa.left) // 2
    wh = (wa.bottom - wa.top) // 2
    slots = {
        "MJ": (wa.left, wa.top),
        "P1": (wa.left + ww, wa.top),
        "P2": (wa.left, wa.top + wh),
        "P3": (wa.left + ww, wa.top + wh),
    }

    # Restore + place everything first so no window is left minimized.
    for key in ORDER:
        hwnd, _ = wins[key]
        if user32.IsIconic(hwnd):
            user32.ShowWindow(hwnd, SW_RESTORE)
            time.sleep(0.5)
        user32.ShowWindow(hwnd, SW_SHOW)
        x, y = slots[key]
        user32.MoveWindow(hwnd, x, y, ww, wh, True)
        time.sleep(0.3)

    time.sleep(2.5)

    root = Path(__file__).resolve().parents[1]
    rc = 0
    for key in ORDER:
        hwnd, title = wins[key]
        # Raise just this window, capture it, then drop it back.
        user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, 0x1 | 0x2 | SWP_SHOWWINDOW)
        user32.BringWindowToTop(hwnd)
        time.sleep(1.2)

        r = wintypes.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(r))
        img = ImageGrab.grab(bbox=(r.left, r.top, r.right, r.bottom), all_screens=True)
        path = root / f"valbois-{suffix}-{key.lower()}.png"
        img.save(path)

        ex = user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
        print(
            f"SAVED {path.name} title={title!r} "
            f"rect=({r.left},{r.top},{r.right},{r.bottom}) size={img.size} "
            f"topmost={bool(ex & WS_EX_TOPMOST)}"
        )
        if user32.IsIconic(hwnd):
            print(f"  WARN {key} is minimized", file=sys.stderr)
            rc = 2

    for key in ORDER:
        hwnd, _ = wins[key]
        user32.SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, 0x1 | 0x2 | SWP_NOACTIVATE)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
