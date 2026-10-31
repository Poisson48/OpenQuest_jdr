"""Assemble une planche de controle des vignettes d'assets 3D.

Lit ``manifest.json`` (ou les dossiers) et compose une image unique : une
vignette par case, nom + categorie + dimensions, sur un fond parchemin rappelant
la palette Valbois. Pratique pour valider d'un coup d'oeil l'homogeneite de
cadrage/eclairage et la palette avant integration dans l'editeur.

Ce script ne tourne **pas** dans Blender : il lui faut Pillow (``pip install
pillow``, ou le Python fourni par l'environnement de dev).

    python tools/blender/make_contact_sheet.py
    python tools/blender/make_contact_sheet.py --cols 4 --cell 320
    python tools/blender/make_contact_sheet.py --out game/assets/objects3d/_planche_assets.png
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
OBJECTS3D_ROOT = REPO_ROOT / "game" / "assets" / "objects3d"

BACKGROUND = (232, 221, 198, 255)  # parchemin clair, proche des fonds Valbois
HEADER = (52, 43, 34, 255)
TEXT = (74, 60, 44, 255)
MUTED = (120, 103, 82, 255)
ACCENT = (140, 74, 58, 255)


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in ("DejaVuSerif.ttf", "DejaVuSans.ttf", "Arial.ttf"):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow < 10
        return ImageFont.load_default()


def load_assets(root: Path) -> list[dict]:
    manifest_path = root / "manifest.json"
    if manifest_path.is_file():
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
        assets = payload.get("assets", [])
    else:
        assets = []
        for glb in sorted(root.glob("*/*.glb")):
            assets.append(
                {
                    "name": glb.stem,
                    "category": glb.parent.name,
                    "thumb": f"{glb.parent.name}/{glb.stem}_thumb.png",
                    "dimensions_cells": [0, 0, 0],
                    "triangles": 0,
                }
            )
    assets.sort(key=lambda item: (str(item.get("category")), str(item.get("name"))))
    return assets


def _fit_text(
    draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, max_width: int
) -> str:
    """Tronque un texte avec une ellipse pour tenir dans ``max_width``."""
    if draw.textlength(text, font=font) <= max_width:
        return text
    shortened = text
    while shortened and draw.textlength(shortened + "…", font=font) > max_width:
        shortened = shortened[:-1]
    return shortened + "…"


def draw_asset(
    sheet: Image.Image,
    draw: ImageDraw.ImageDraw,
    asset: dict,
    root: Path,
    box: tuple[int, int, int, int],
) -> bool:
    """Dessine une case (vignette + legendes). Renvoie False si absente."""
    x, y, width, height = box
    thumb_path = root / str(asset.get("thumb", ""))
    if not thumb_path.is_file():
        draw.rectangle([x, y, x + width, y + height], outline=ACCENT, width=2)
        draw.text((x + 12, y + 12), "vignette absente", font=load_font(14), fill=ACCENT)
        return False

    label_font = load_font(18)
    meta_font = load_font(12)
    image = Image.open(thumb_path).convert("RGBA")
    image.thumbnail((width - 18, height - 62), Image.LANCZOS)
    sheet.alpha_composite(
        image,
        (x + (width - image.width) // 2, y + 6 + (height - 62 - image.height) // 2),
    )
    name = str(asset.get("name", "?"))
    category = str(asset.get("category", ""))
    dims = asset.get("dimensions_cells") or [0, 0, 0]
    triangles = asset.get("triangles", 0)
    dims_text = " × ".join(f"{value:g}" for value in dims) if any(dims) else ""
    meta = str(asset.get("meta") or "")
    if not meta:
        is_wall = str(asset.get("anchor") or "base") == "wall"
        height_floor = asset.get("height_above_floor")
        if is_wall and height_floor:
            meta = f"{category} · h sol {float(height_floor):g} cases · {triangles} tris"
        else:
            meta = f"{category} · {dims_text} cases · {triangles} tris" if dims_text else category

    label_y = y + height - 46
    draw.text(
        (x + 10, label_y),
        _fit_text(draw, name, label_font, width - 24),
        font=label_font,
        fill=TEXT,
    )
    draw.text(
        (x + 10, label_y + 22),
        _fit_text(draw, meta, meta_font, width - 24),
        font=meta_font,
        fill=MUTED,
    )
    return True


def load_terrain_tiles(root: Path) -> list[dict]:
    """Entrées spéciales pour la rangée de textures de sol."""
    tiles = []
    labels = {
        "grass": "herbe",
        "dirt": "terre / chemin",
        "stone": "pavé de pierre",
    }
    for name, label in labels.items():
        thumb = root / f"{name}_thumb.png"
        if thumb.is_file():
            tiles.append(
                {
                    "name": f"sol · {label}",
                    "category": "terrain",
                    "thumb": thumb.name,
                    "kind": "tile",
                    "dimensions_cells": [0, 0, 0],
                    "triangles": 0,
                    "meta": f"terrain · {name}.png 512² · tuilable",
                }
            )
    return tiles


def main() -> int:
    parser = argparse.ArgumentParser(description="Planche de controle des vignettes 3D.")
    parser.add_argument("--root", default=str(OBJECTS3D_ROOT))
    parser.add_argument("--out", default=None)
    parser.add_argument("--cols", type=int, default=5)
    parser.add_argument("--cell", type=int, default=280)
    parser.add_argument("--terrain", action="store_true", help="Ajoute les textures de sol.")
    parser.add_argument("--terrain-root", default=None)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    assets = load_assets(root)
    if args.terrain:
        terrain_root = Path(args.terrain_root).resolve() if args.terrain_root else REPO_ROOT / "game" / "assets" / "terrain"
        tiles = load_terrain_tiles(terrain_root)
        if not tiles:
            print(f"[warn] aucune vignette terrain dans {terrain_root}")
        assets = tiles + assets
        # Les tuiles de sol sont cherchées à part : on expose leur racine.
        terrain_thumb_root = terrain_root
    else:
        terrain_thumb_root = None
    if not assets:
        print(f"[ERREUR] aucun asset dans {root}")
        return 2

    cols = max(1, args.cols)
    rows = (len(assets) + cols - 1) // cols
    cell = max(160, args.cell)
    margin = 28
    header_h = 74
    footer_h = 30
    width = margin * 2 + cols * cell
    height = margin + header_h + rows * cell + footer_h

    sheet = Image.new("RGBA", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    draw.rectangle([8, 8, width - 9, height - 9], outline=(186, 171, 145, 255), width=2)

    draw.text(
        (margin, 22),
        "OpenQuest — objets 3D de la carte 2.5D",
        font=load_font(30),
        fill=HEADER,
    )
    draw.text(
        (margin, 58),
        "Prototypes Blender · 1 unité = 1 case · origine au pied · contour encre · AO + mottling en vertex colors",
        font=load_font(14),
        fill=MUTED,
    )

    missing = 0
    for index, asset in enumerate(assets):
        row, col = divmod(index, cols)
        x = margin + col * cell
        y = margin + header_h + row * cell
        box = (x + 6, y + 6, cell - 12, cell - 12)
        if col > 0:
            draw.line([(x, y + 10), (x, y + cell - 14)], fill=(200, 189, 166, 120), width=1)
        asset_root = terrain_thumb_root if asset.get("kind") == "tile" and terrain_thumb_root else root
        if not draw_asset(sheet, draw, asset, asset_root, box):
            missing += 1

    draw.text(
        (margin, height - 24),
        f"{len(assets)} assets · {sum(int(a.get('triangles', 0)) for a in assets)} triangles au total · "
        "planche générée par tools/blender/make_contact_sheet.py",
        font=load_font(12),
        fill=MUTED,
    )

    out_path = (
        Path(args.out)
        if args.out
        else root / "_planche_assets.png"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"[OK] planche: {out_path} ({out_path.stat().st_size / 1024.0:.1f} Ko, {len(assets)} assets)")
    return 0 if missing == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
