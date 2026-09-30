#!/usr/bin/env python3
"""Génère des placeholders PNG procéduraux (gratuits) pour MapAssetLibrary.

Usage:
  python scripts/generate_prop_placeholders.py
  python scripts/generate_prop_placeholders.py --force
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PROPS = ROOT / "game" / "data" / "props"

# Nouveaux assets (ne remplace pas le pack existant sauf --force).
SPECS: list[tuple[str, str, int, int, str]] = [
    # category, filename, w, h, kind
    ("buildings", "auberge.png", 96, 112, "auberge"),
    ("vehicles", "char_de_guerre.png", 88, 56, "char"),
    ("furniture", "banc.png", 72, 36, "banc"),
    ("nature", "rocher.png", 64, 48, "rocher"),
    ("objects", "puits.png", 56, 72, "puits"),
    ("characters", "garde.png", 40, 64, "garde"),
    ("ground", "pave.png", 80, 80, "pave"),
]


def _rgba(hex_color: str, a: int = 255) -> tuple[int, int, int, int]:
    h = hex_color.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return (r, g, b, a)


def paint(kind: str, w: int, h: int) -> Image.Image:
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = w // 2, h // 2

    if kind == "auberge":
        d.rectangle([12, 40, w - 12, h - 8], fill=_rgba("#6b4a32"))
        d.polygon([(6, 44), (cx, 8), (w - 6, 44)], fill=_rgba("#8b2e2e"))
        d.rectangle([cx - 10, h - 36, cx + 10, h - 8], fill=_rgba("#3d2918"))
        d.rectangle([22, 52, 36, 66], fill=_rgba("#c9a227"))
        d.rectangle([w - 36, 52, w - 22, 66], fill=_rgba("#c9a227"))
        d.ellipse([cx - 6, 28, cx + 6, 40], fill=_rgba("#d4a017"))
    elif kind == "char":
        d.ellipse([10, h - 28, 34, h - 6], fill=_rgba("#3a2a1a"))
        d.ellipse([w - 34, h - 28, w - 10, h - 6], fill=_rgba("#3a2a1a"))
        d.rounded_rectangle([8, 14, w - 8, h - 22], radius=6, fill=_rgba("#5c4030"))
        d.rectangle([14, 8, w - 28, 18], fill=_rgba("#7a5230"))
        d.polygon([(w - 28, 10), (w - 6, 22), (w - 28, 28)], fill=_rgba("#4a3424"))
    elif kind == "banc":
        d.rectangle([6, 10, w - 6, 22], fill=_rgba("#8b6914"))
        d.rectangle([10, 22, 18, h - 4], fill=_rgba("#5c4010"))
        d.rectangle([w - 18, 22, w - 10, h - 4], fill=_rgba("#5c4010"))
        d.rectangle([8, h - 10, w - 8, h - 4], fill=_rgba("#6b5010"))
    elif kind == "rocher":
        d.polygon(
            [(10, h - 8), (18, 18), (cx, 6), (w - 16, 20), (w - 8, h - 8)],
            fill=_rgba("#7a7a72"),
        )
        d.polygon([(22, h - 10), (30, 28), (cx + 4, 16), (w - 22, h - 10)], fill=_rgba("#9a9a90"))
    elif kind == "puits":
        d.ellipse([8, h - 28, w - 8, h - 6], fill=_rgba("#6a6a68"))
        d.ellipse([14, h - 24, w - 14, h - 10], fill=_rgba("#2a4a6a"))
        d.rectangle([cx - 3, 8, cx + 3, h - 24], fill=_rgba("#5c4030"))
        d.rectangle([10, 6, w - 10, 14], fill=_rgba("#8b6914"))
    elif kind == "garde":
        d.ellipse([cx - 10, 4, cx + 10, 24], fill=_rgba("#e8c4a0"))
        d.rectangle([cx - 12, 24, cx + 12, 48], fill=_rgba("#3d5a3d"))
        d.rectangle([cx - 14, 22, cx + 14, 28], fill=_rgba("#6a6a68"))  # gorget
        d.rectangle([cx - 8, 48, cx - 2, h - 4], fill=_rgba("#3a2a1a"))
        d.rectangle([cx + 2, 48, cx + 8, h - 4], fill=_rgba("#3a2a1a"))
        d.polygon([(cx + 10, 28), (w - 4, 36), (cx + 10, 40)], fill=_rgba("#c0c0c0"))
    elif kind == "pave":
        colors = ["#8a8070", "#7a7060", "#9a9080", "#6a6050"]
        tw, th = w // 4, h // 4
        for row in range(4):
            for col in range(4):
                x0, y0 = col * tw, row * th
                d.rectangle(
                    [x0 + 1, y0 + 1, x0 + tw - 2, y0 + th - 2],
                    fill=_rgba(colors[(row + col) % len(colors)]),
                )
    else:
        d.ellipse([4, 4, w - 4, h - 4], fill=_rgba("#888888"))

    # Contour léger pour lisibilité VTT
    outline = im.copy()
    return outline


def main() -> int:
    parser = argparse.ArgumentParser(description="Placeholders PNG gratuits pour props OpenQuest")
    parser.add_argument("--force", action="store_true", help="Écraser les fichiers existants")
    args = parser.parse_args()

    written = 0
    skipped = 0
    for category, name, w, h, kind in SPECS:
        dest_dir = PROPS / category
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / name
        if dest.exists() and not args.force:
            print(f"skip  {category}/{name}")
            skipped += 1
            continue
        paint(kind, w, h).save(dest, "PNG")
        print(f"write {category}/{name} ({w}x{h})")
        written += 1

    print(f"Done: {written} written, {skipped} skipped. Root={PROPS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
