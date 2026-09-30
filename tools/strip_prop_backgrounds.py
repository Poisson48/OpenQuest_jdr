#!/usr/bin/env python3
"""Détoure les props Gemini : fond damier / blanc / parchemin → alpha réel.

Usage:
  python scripts/strip_prop_backgrounds.py
  python scripts/strip_prop_backgrounds.py --dry-run
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PROPS = ROOT / "game" / "data" / "props"

# Sols plein cadre : on ne détoure que s'ils ont clairement un fond clair en bordure.
GROUND_CATS = {"ground"}


def _is_light_bg(r: int, g: int, b: int) -> bool:
    mx = max(r, g, b)
    mn = min(r, g, b)
    # Blanc / gris clair / damier
    if mn >= 200 and (mx - mn) <= 40:
        return True
    # Parchemin beige clair
    if r >= 175 and g >= 155 and b >= 130 and (mx - mn) <= 70 and (r + g + b) / 3 >= 175:
        return True
    # Gris moyen clair type damier Gemini (~210-240)
    if mn >= 185 and mx <= 255 and (mx - mn) <= 30:
        return True
    return False


def _near(a: tuple[int, int, int], b: tuple[int, int, int], tol: int) -> bool:
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2]) <= tol


def _edge_palette(im: Image.Image, band: int = 6) -> list[tuple[int, int, int]]:
    w, h = im.size
    samples: list[tuple[int, int, int]] = []
    for y in range(h):
        for x in range(w):
            on_edge = x < band or y < band or x >= w - band or y >= h - band
            if not on_edge:
                continue
            r, g, b, a = im.getpixel((x, y))
            if a < 10:
                continue
            if _is_light_bg(r, g, b):
                samples.append((r, g, b))
    # Déduplique grossièrement
    uniq: list[tuple[int, int, int]] = []
    for s in samples:
        if not any(_near(s, u, 18) for u in uniq):
            uniq.append(s)
        if len(uniq) >= 24:
            break
    return uniq


def _should_knockout(px: tuple[int, int, int, int], palette: list[tuple[int, int, int]]) -> bool:
    r, g, b, a = px
    if a < 10:
        return True
    if _is_light_bg(r, g, b):
        return True
    for s in palette:
        if _near((r, g, b), s, 42):
            # Évite d'avaler du bois/pierre clair trop agressivement : exige aussi
            # une luminance élevée.
            if (r + g + b) / 3 >= 165:
                return True
    return False


def strip_image(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    palette = _edge_palette(im)
    if not palette and not _is_light_bg(*im.getpixel((0, 0))[:3]):
        return im

    visited = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))

    out = im.copy()
    px = out.load()
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        idx = y * w + x
        if visited[idx]:
            continue
        visited[idx] = 1
        cur = px[x, y]
        if not _should_knockout(cur, palette):
            continue
        px[x, y] = (0, 0, 0, 0)
        q.append((x + 1, y))
        q.append((x - 1, y))
        q.append((x, y + 1))
        q.append((x, y - 1))

    # 2e passe : damier gris/blanc resté coincé entre branches / jambages
    # (non relié au bord). On ne touche qu'au gris neutre très clair — pas au
    # crépi beige des maisons.
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 10:
                continue
            mn, mx = min(r, g, b), max(r, g, b)
            if mn >= 205 and (mx - mn) <= 22:
                px[x, y] = (0, 0, 0, 0)

    # Durcit l'alpha (pas de fantome semi-transparent)
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 40:
                px[x, y] = (0, 0, 0, 0)
            elif a < 255:
                px[x, y] = (r, g, b, 255)

    # Crop au contenu
    bbox = out.getbbox()
    if bbox:
        l, t, r, b = bbox
        l = max(0, l - 2)
        t = max(0, t - 2)
        r = min(w, r + 2)
        b = min(h, b + 2)
        out = out.crop((l, t, r, b))
    return out


def _edge_clear_ratio(im: Image.Image, band: int = 4) -> float:
    w, h = im.size
    total = 0
    clear = 0
    for y in range(h):
        for x in range(w):
            if not (x < band or y < band or x >= w - band or y >= h - band):
                continue
            total += 1
            if _is_light_bg(*im.getpixel((x, y))[:3]):
                clear += 1
    return clear / max(total, 1)


def process_file(path: Path, dry_run: bool, force: bool = False) -> str:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = list(im.getdata())
    already = sum(1 for *_, a in px if a < 10) / max(len(px), 1)
    cat = path.parent.name
    if path.stat().st_size < 2048:
        return f"skip tiny {path.relative_to(PROPS)}"
    if not force and already >= 0.08:
        # Relance si du damier gris reste au milieu
        leftover = sum(
            1
            for r, g, b, a in px
            if a >= 10 and min(r, g, b) >= 205 and (max(r, g, b) - min(r, g, b)) <= 22
        )
        if leftover < max(40, int(len(px) * 0.002)):
            return f"skip already-cut {path.relative_to(PROPS)} ({already*100:.0f}% clear)"
    if not force and cat in GROUND_CATS and _edge_clear_ratio(im) < 0.35 and already < 0.02:
        return f"skip solid-ground {path.relative_to(PROPS)}"

    out = strip_image(im)
    opx = list(out.getdata())
    clear = sum(1 for *_, a in opx if a < 10) / max(len(opx), 1)
    if clear < 0.05:
        return f"WARN weak-cut {path.relative_to(PROPS)} ({clear*100:.0f}% clear) — kept original"
    if dry_run:
        return f"would-strip {path.relative_to(PROPS)} {w}x{h} -> {out.size[0]}x{out.size[1]} clear={clear*100:.0f}%"
    # Ecriture atomique (evite OSError si Godot a le fichier ouvert en lecture)
    tmp = path.with_suffix(".png.tmp")
    out.save(tmp, format="PNG", optimize=True)
    tmp.replace(path)
    return f"stripped {path.relative_to(PROPS)} {w}x{h} -> {out.size[0]}x{out.size[1]} clear={clear*100:.0f}%"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true", help="Retraite meme les PNG deja detoures")
    args = ap.parse_args()
    # Restaure arbre depuis arbre_valbois si placeholder minuscule
    arbre = PROPS / "nature" / "arbre.png"
    src = PROPS / "nature" / "arbre_valbois.png"
    if arbre.exists() and src.exists() and arbre.stat().st_size < 2048:
        if not args.dry_run:
            Image.open(src).convert("RGBA").save(arbre, format="PNG")
        print(f"restored {arbre.relative_to(PROPS)} from arbre_valbois")

    results = []
    for path in sorted(PROPS.rglob("*.png")):
        results.append(process_file(path, args.dry_run, force=args.force))
    for line in results:
        print(line)
    ok = sum(1 for r in results if r.startswith("stripped") or r.startswith("would-strip") or r.startswith("restored"))
    print(f"done: {ok} processed / {len(results)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
