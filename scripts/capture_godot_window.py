import ctypes
import sys
import time
from ctypes import wintypes
from pathlib import Path

from PIL import ImageGrab

user32 = ctypes.windll.user32
WNDENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
matches: list[tuple[int, str]] = []


def callback(hwnd, _):
    if user32.IsWindowVisible(hwnd):
        length = user32.GetWindowTextLengthW(hwnd)
        buf = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buf, length + 1)
        title = buf.value
        if title and any(k in title for k in ("Godot", "OpenQuest", "Kharak", "Sables")):
            matches.append((hwnd, title))
    return True


def main() -> int:
    user32.EnumWindows(WNDENUMPROC(callback), 0)
    if not matches:
        print("NO_WINDOW", file=sys.stderr)
        return 1

    hwnd, title = matches[0]
    SW_MAXIMIZE = 3
    user32.ShowWindow(hwnd, SW_MAXIMIZE)
    user32.SetForegroundWindow(hwnd)
    time.sleep(1.5)

    rect = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    bbox = (rect.left, rect.top, rect.right, rect.bottom)
    img = ImageGrab.grab(bbox=bbox)

    out = Path(__file__).resolve().parents[1] / "mj-interface-screenshot.png"
    img.save(out)
    print(f"SAVED {out} title={title!r} size={img.size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
