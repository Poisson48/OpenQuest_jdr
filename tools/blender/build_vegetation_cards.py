"""Construit des assets végétaux « cartes alpha » à partir des planches de
référence IA (3 vues peintes, fond transparent).

Pourquoi : le pipeline historique (`reference_hull.py`) reconstruit un VOLUME
d'intersection de silhouettes sur une grille 64³ puis le décime (~2 000 tris) et
cuit la texture par îlots de 18 px par face. Les feuilles fines, les plumes et
les fleurs ne peuvent pas survivre à ce traitement : roseaux, buissons, haies et
nénuphars deviennent des tas de facettes. La méthode des jeux (Cities: Skylines
II, Valheim…) est celle des **cartouches découpés par l'alpha** : 2–3 quads
croisés, double face, alpha testé, texture peinte de la référence.

Le script ne dépend ni de Blender ni du reste du pipeline : il lit la planche,
nettoie le halo de détourage, packe les vues dans un atlas et écrit un GLB
autonome (texture PNG embarquée). Il met aussi à jour le manifeste de la
bibliothèque (triangle/vertices/source) et la vignette.

Config par défaut : `tools/blender/vegetation_cards.json`.

Usage :
    python tools/blender/build_vegetation_cards.py --all
    python tools/blender/build_vegetation_cards.py --only roseaux buisson
    python tools/blender/build_vegetation_cards.py --reference tools/blender/references/haie.png \
        --name haie --out /tmp/haie.glb --width 2.46 --depth 0.90 --height 0.95 \
        --layout hedge --texture-size 1024
"""

from __future__ import annotations

import argparse
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# Largeur du halo de détourage : les planches IA ont des pixels colorés
# (rouge/jaune) sous l'alpha faible, qui bavent sur les bords une fois la
# texture échantillonnée en mipmaps. On remplit la couleur sous l'alpha, puis on
# rogne l'alpha d'un demi-texel.
FRINGE_BLEED_PX = 4
THUMB_SIZE = 512
MANIFEST_PATH = Path("game/assets/objects3d/manifest.json")


def load_views(reference: Path) -> list[Image.Image]:
    """Découpe la planche en 3 vues et recadre chacune sur son alpha."""
    sheet = Image.open(reference).convert("RGBA")
    w = sheet.width // 3
    views: list[Image.Image] = []
    for i in range(3):
        view = sheet.crop((i * w, 0, (i + 1) * w, sheet.height))
        alpha = np.array(view)[..., 3]
        cols = np.where(alpha.max(axis=0) > 16)[0]
        rows = np.where(alpha.max(axis=1) > 16)[0]
        if len(cols) == 0 or len(rows) == 0:
            continue
        views.append(view.crop(
            (int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1)))
    if not views:
        raise SystemExit(f"{reference}: aucune vue exploitable")
    return views


def bleed_edge_colors(rgba: np.ndarray, steps: int = FRINGE_BLEED_PX) -> np.ndarray:
    """Étale la couleur des pixels opaques sous les pixels transparents."""
    out = rgba.astype(np.float32, copy=True)
    opaque = out[..., 3] > 0.9 * 255.0
    for _ in range(steps):
        if opaque.all():
            break
        colors = np.zeros_like(out[..., :3])
        weights = np.zeros(out.shape[:2], dtype=np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shifted = np.roll(np.roll(out[..., :3], dy, axis=0), dx, axis=1)
            shifted_opaque = np.roll(np.roll(opaque, dy, axis=0), dx, axis=1)
            colors += shifted * shifted_opaque[..., None]
            weights += shifted_opaque.astype(np.float32)
        fill = (~opaque) & (weights > 0)
        if not fill.any():
            break
        out[..., :3][fill] = colors[fill] / weights[fill][..., None]
        opaque = opaque | fill
    return np.clip(out, 0, 255).astype(np.uint8)


def prepare_view(view: Image.Image, size: int) -> Image.Image:
    """Carré `size`, alpha rogné, couleurs du bord étalées, mipmaps propres."""
    side = max(view.width, view.height)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(view, ((side - view.width) // 2, (side - view.height) // 2))
    rgba = bleed_edge_colors(np.array(canvas).astype(np.uint8))
    alpha = rgba[..., 3].astype(np.float32)
    rgba[..., 3] = np.clip((alpha - 10.0) * 255.0 / 245.0, 0, 255).astype(np.uint8)
    return Image.fromarray(rgba).resize((size, size), Image.LANCZOS)


def build_atlas(views: dict[str, Image.Image], size: int) -> tuple[Image.Image, dict[str, tuple[float, float]]]:
    """Atlas horizontal (une case carrée par vue) et bornes UV par vue."""
    keys = list(views.keys())
    atlas = Image.new("RGBA", (size * len(keys), size), (0, 0, 0, 0))
    ranges: dict[str, tuple[float, float]] = {}
    for i, key in enumerate(keys):
        atlas.paste(prepare_view(views[key], size), (i * size, 0))
        ranges[key] = (i / len(keys), (i + 1) / len(keys))
    return atlas, ranges


def _append_vertical(positions, normals, uvs, indices, yaw: float, width: float,
                     height: float, uv: tuple[float, float], flip: bool) -> None:
    cos_y, sin_y = float(np.cos(yaw)), float(np.sin(yaw))
    side = np.array([cos_y, 0.0, sin_y], dtype=np.float64)
    normal = np.array([-sin_y, 0.0, cos_y], dtype=np.float64)
    half = width * 0.5
    u0, u1 = (uv[1], uv[0]) if flip else uv
    base = len(positions)
    for sx, sy in ((-half, 0.0), (half, 0.0), (-half, height), (half, height)):
        positions.append((float(side[0] * sx), float(sy), float(side[2] * sx)))
        normals.append((float(normal[0]), float(normal[1]), float(normal[2])))
    # V=0 en haut de l'image (origine UV glTF en haut à gauche).
    uvs.extend([(u0, 1.0), (u1, 1.0), (u0, 0.0), (u1, 0.0)])
    indices.extend([base, base + 2, base + 1, base + 1, base + 2, base + 3])


def _append_flat(positions, normals, uvs, indices, yaw: float, width: float,
                 depth: float, y: float, uv: tuple[float, float]) -> None:
    cos_y, sin_y = float(np.cos(yaw)), float(np.sin(yaw))
    ax = np.array([cos_y, 0.0, sin_y], dtype=np.float64)
    az = np.array([-sin_y, 0.0, cos_y], dtype=np.float64)
    hw, hd = width * 0.5, depth * 0.5
    base = len(positions)
    for sx, sz in ((-hw, -hd), (hw, -hd), (-hw, hd), (hw, hd)):
        positions.append((float(ax[0] * sx + az[0] * sz), y, float(ax[2] * sx + az[2] * sz)))
        normals.append((0.0, 1.0, 0.0))
    uvs.extend([(uv[0], 0.0), (uv[1], 0.0), (uv[0], 1.0), (uv[1], 1.0)])
    indices.extend([base, base + 1, base + 2, base + 2, base + 1, base + 3])


def card_geometry(width: float, depth: float, height: float, layout: str,
                  planes: int, ranges: dict[str, tuple[float, float]]):
    """Géométrie des cartouches selon le gabarit de la plante."""
    fronts = ranges.get("front", ranges.get("top", (0.0, 1.0)))
    sides = ranges.get("side", fronts)
    tops = ranges.get("top", fronts)
    positions: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    indices: list[int] = []

    if layout == "flat":
        # Nénuphars : raquettes horizontales posées au ras de l'eau.
        y = max(0.01, height * 0.5)
        _append_flat(positions, normals, uvs, indices, 0.0, width, depth, y, tops)
        if planes >= 2:
            _append_flat(positions, normals, uvs, indices, np.pi / 5.0,
                         width * 0.82, depth * 0.82, y + 0.006, tops)
        return positions, normals, uvs, indices

    if layout == "hedge":
        # Haie : une face longiligne + une extrémité, pas de « croix » aux mêmes
        # dimensions (sinon la haie devient un panneau dans l'autre axe).
        _append_vertical(positions, normals, uvs, indices, 0.0, width, height, fronts, False)
        _append_vertical(positions, normals, uvs, indices, np.pi * 0.5, depth, height, sides, False)
        return positions, normals, uvs, indices

    # Buisson / bosquet / roseaux : croix de plans verticaux, miroir pour varier.
    _append_vertical(positions, normals, uvs, indices, 0.0, width, height, fronts, False)
    _append_vertical(positions, normals, uvs, indices, np.pi * 0.5, depth, height, sides, False)
    if planes >= 3:
        _append_vertical(positions, normals, uvs, indices, np.pi / 3.0, width, height, fronts, True)
    if planes >= 4:
        _append_vertical(positions, normals, uvs, indices, 2.0 * np.pi / 3.0, width, height, fronts, True)
    return positions, normals, uvs, indices


def _align4(data: bytes) -> bytes:
    return data + b"\x00" * ((4 - len(data) % 4) % 4)


def write_glb(path: Path, positions, normals, uvs, indices, atlas: Image.Image) -> None:
    """Écrit un GLB 2.0 minimal (1 primitive, texture PNG embarquée)."""
    pos = np.asarray(positions, dtype=np.float32)
    nor = np.asarray(normals, dtype=np.float32)
    uv = np.asarray(uvs, dtype=np.float32)
    idx = np.asarray(indices, dtype=np.uint16)
    png = Path(path).with_suffix(".tmp.png")
    atlas.save(png, optimize=True)
    image_bytes = _align4(png.read_bytes())
    png.unlink()

    pos_bytes = _align4(pos.tobytes())
    nor_bytes = _align4(nor.tobytes())
    uv_bytes = _align4(uv.tobytes())
    idx_bytes = _align4(idx.tobytes())
    chunks = [pos_bytes, nor_bytes, uv_bytes, idx_bytes, image_bytes]
    offsets: list[int] = []
    cursor = 0
    for chunk in chunks:
        offsets.append(cursor)
        cursor += len(chunk)

    def accessor(view: int, count: int, type_: str, extra: dict | None = None) -> dict:
        data = {"bufferView": view, "componentType": 5126, "count": count, "type": type_}
        if extra:
            data.update(extra)
        return data

    gltf = {
        "asset": {"version": "2.0", "generator": "OpenQuest vegetation cards"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": path.stem}],
        "meshes": [{
            "name": path.stem,
            "primitives": [{
                "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                "indices": 3,
                "material": 0,
            }],
        }],
        "materials": [{
            "name": f"{path.stem}_cards",
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0},
                "metallicFactor": 0.0,
                "roughnessFactor": 0.92,
            },
            "alphaMode": "MASK",
            "alphaCutoff": 0.5,
            "doubleSided": True,
        }],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987,
                      "wrapS": 33071, "wrapT": 33071}],
        "images": [{"mimeType": "image/png", "bufferView": 4}],
        "accessors": [
            accessor(0, len(positions), "VEC3", {
                "min": [float(min(p[i] for p in positions)) for i in range(3)],
                "max": [float(max(p[i] for p in positions)) for i in range(3)],
            }),
            accessor(1, len(normals), "VEC3"),
            accessor(2, len(uvs), "VEC2"),
            {"bufferView": 3, "componentType": 5123, "count": len(indices), "type": "SCALAR"},
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": offsets[0], "byteLength": len(pos.tobytes())},
            {"buffer": 0, "byteOffset": offsets[1], "byteLength": len(nor.tobytes())},
            {"buffer": 0, "byteOffset": offsets[2], "byteLength": len(uv.tobytes())},
            {"buffer": 0, "byteOffset": offsets[3], "byteLength": len(idx.tobytes())},
            {"buffer": 0, "byteOffset": offsets[4], "byteLength": len(image_bytes)},
        ],
        "buffers": [{"byteLength": cursor}],
    }

    bin_blob = b"".join(chunks)
    json_blob = _align4(json.dumps(gltf, separators=(",", ":")).encode("utf-8"))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as fh:
        fh.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_blob) + 8 + len(bin_blob)))
        fh.write(struct.pack("<II", len(json_blob), 0x4E4F534A))
        fh.write(json_blob)
        fh.write(struct.pack("<II", len(bin_blob), 0x004E4942))
        fh.write(bin_blob)


def write_thumb(view: Image.Image, path: Path) -> None:
    """Vignette de bibliothèque : la vue de face peinte, pied au sol."""
    canvas = Image.new("RGBA", (THUMB_SIZE, THUMB_SIZE), (0, 0, 0, 0))
    ratio = min((THUMB_SIZE - 40) / view.width, (THUMB_SIZE - 24) / view.height)
    resized = view.resize((max(1, int(view.width * ratio)), max(1, int(view.height * ratio))),
                          Image.LANCZOS)
    x = (THUMB_SIZE - resized.width) // 2
    y = THUMB_SIZE - 12 - resized.height
    shadow = Image.new("RGBA", (THUMB_SIZE, THUMB_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    draw.ellipse((x + resized.width * 0.08, y + resized.height - 18,
                  x + resized.width * 0.92, y + resized.height + 14),
                 fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(6))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(resized, (x, y), resized)
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path, optimize=True)


def update_manifest(manifest_path: Path, name: str, glb_rel: str, thumb_rel: str,
                    triangles: int, vertices: int) -> None:
    """Met à jour l'entrée du manifeste (compteurs + source géométrique)."""
    if not manifest_path.exists():
        return
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for asset in manifest.get("assets", []):
        if asset.get("name") != name:
            continue
        asset["glb"] = glb_rel
        asset["thumb"] = thumb_rel
        asset["triangles"] = triangles
        asset["triangles_base"] = triangles
        asset["vertices"] = vertices
        asset["vertex_colors"] = "aucune (cartes alpha de la référence)"
        asset["outline"] = False
        asset["geometry_source"] = "cartes alpha croisées depuis la planche de référence"
        asset["description"] = asset.get("description", "") + " — cartes alpha."
        break
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")


def build_one(cfg: dict, manifest_path: Path | None, only_thumb: bool = False) -> None:
    reference = Path(cfg["reference"])
    views = load_views(reference)
    layout = cfg.get("layout", "cross")
    texture_size = int(cfg.get("texture_size", 1024))

    wanted: dict[str, Image.Image] = {"front": views[0]}
    if layout == "flat":
        wanted = {"top": views[2] if len(views) > 2 else views[0]}
    elif layout == "hedge":
        wanted = {"front": views[0], "side": views[1] if len(views) > 1 else views[0]}
    elif len(views) > 1:
        wanted = {"front": views[0], "side": views[1]}

    out = Path(cfg["out"])
    if not only_thumb:
        atlas, ranges = build_atlas(wanted, texture_size)
        planes = int(cfg.get("planes", 3))
        positions, normals, uvs, indices = card_geometry(
            float(cfg["width"]), float(cfg["depth"]), float(cfg["height"]),
            layout, planes, ranges)
        write_glb(out, positions, normals, uvs, indices, atlas)
        kb = out.stat().st_size / 1024
        print(f"[OK] {out} ({kb:.0f} Ko) — {len(indices) // 3} tris, "
              f"atlas {atlas.width}x{atlas.height}, gabarit {layout}, "
              f"{len(indices) // 6} cartouches")

    thumb = cfg.get("thumb")
    if thumb:
        write_thumb(views[0], Path(thumb))
        print(f"  vignette : {thumb}")

    if manifest_path and not only_thumb:
        update_manifest(manifest_path, cfg["name"], cfg["glb"], cfg.get("thumb", ""),
                        len(indices) // 3, len(positions))
        print(f"  manifeste mis à jour : {cfg['name']}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path,
                        default=Path("tools/blender/vegetation_cards.json"))
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--only", nargs="+")
    parser.add_argument("--manifest", type=Path, default=MANIFEST_PATH)
    parser.add_argument("--reference", type=Path)
    parser.add_argument("--name")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--width", type=float)
    parser.add_argument("--depth", type=float)
    parser.add_argument("--height", type=float)
    parser.add_argument("--layout", choices=["cross", "hedge", "flat"], default="cross")
    parser.add_argument("--planes", type=int, default=3, choices=[1, 2, 3, 4])
    parser.add_argument("--texture-size", type=int, default=1024)
    args = parser.parse_args()

    if args.reference and args.name and args.out:
        cfg = {
            "name": args.name, "reference": str(args.reference), "out": str(args.out),
            "glb": str(args.out), "width": args.width, "depth": args.depth,
            "height": args.height, "layout": args.layout, "planes": args.planes,
            "texture_size": args.texture_size,
        }
        build_one(cfg, args.manifest)
        return

    config = json.loads(args.config.read_text(encoding="utf-8"))
    selected = [args.only] if isinstance(args.only, str) else (args.only or [])
    names = selected or (list(config.keys()) if args.all else [])
    if not names:
        parser.error("préciser --all, --only, ou --reference/--name/--out")
    for name in names:
        cfg = dict(config[name])
        cfg.setdefault("name", name)
        build_one(cfg, args.manifest)


if __name__ == "__main__":
    main()
