"""Construit un asset végétal « cartes alpha » à partir d'une planche de
référence IA (3 vues peintes, fond transparent).

Le pipeline historique (`reference_hull.py`) reconstruit un VOLUME d'intersection
de silhouettes sur une grille 64³ puis le décime à ~2 000 tris : les feuilles
fines et les plumes ne peuvent pas survivre, et la texture est cuite par îlots de
18 px par face. Pour la végétation, la bonne méthode est celle des jeux
(Cities: Skylines II, Valheim…) : quelques **quads croisés** découpés par
l'alpha des vues de référence, double face, avec l'alpha testé.

Ce script ne dépend ni de Blender ni du pipeline : il lit la planche PNG,
extrait la vue de face et la vue de 3/4, les nettoie (halo de détourage), les
packs dans un atlas et écrit un GLB autonome (texture PNG embarquée).

Usage :
    python tools/blender/build_vegetation_cards.py --help
    python tools/blender/build_vegetation_cards.py \
        --reference tools/blender/references/roseaux.png \
        --name roseaux_cards --out game/assets/objects3d/vegetation/roseaux_cards.glb \
        --width 1.42 --height 1.74 --planes 3 --texture-size 1024
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image

# Durée de vie du halo de détourage : les planches IA ont des pixels colorés
# (rouge/jaune) sous l'alpha faible, qui bavent sur les bords une fois la
# texture échantillonnée en mipmaps. On les remplace par la couleur opaque la
# plus proche, puis on rogne l'alpha d'un demi-texel.
FRINGE_BLEED_PX = 4


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
        view = view.crop((int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1))
        views.append(view)
    if len(views) < 2:
        raise SystemExit(f"{reference}: impossible d'extraire au moins 2 vues")
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
    rgba = np.array(view).astype(np.uint8)
    # Recadrage carré centré (on garde toute la hauteur du végétal).
    side = max(view.width, view.height)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(view, ((side - view.width) // 2, (side - view.height) // 2))
    rgba = np.array(canvas).astype(np.uint8)
    rgba = bleed_edge_colors(rgba)
    # Rognage de l'alpha : évite le liseré coloré du détourage IA.
    alpha = rgba[..., 3].astype(np.float32)
    rgba[..., 3] = np.clip((alpha - 10.0) * 255.0 / 245.0, 0, 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA").resize((size, size), Image.LANCZOS)


def build_atlas(views: list[Image.Image], size: int) -> tuple[Image.Image, float, float]:
    """Texture des cartes : la vue de FACE seule (la 3/4 est trop étroite : une
    fois plaquée sur un plan de même largeur, elle donne une bande étirée).

    Retourne l'atlas carré et les bornes UV `u0, u1` (0 → 1)."""
    atlas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    atlas.paste(prepare_view(views[0], size), (0, 0))
    return atlas, 0.0, 1.0


def card_geometry(width: float, height: float, planes: int) -> tuple[list, list, list, list, list]:
    """Quads verticaux croisés, base à y=0, centrés ; retourne les tampons.

    Toutes les cartes reprennent la vue de face (miroir horizontal sur une
    carte sur deux pour varier la silhouette) : pas de bande étroite."""

    def corners_for(yaw: float, u0: float, u1: float):
        cos_y, sin_y = float(np.cos(yaw)), float(np.sin(yaw))
        side = np.array([cos_y, 0.0, sin_y], dtype=np.float64)
        normal = np.array([-sin_y, 0.0, cos_y], dtype=np.float64)
        half = width * 0.5
        # V=0 en haut de l'image (origine UV glTF en haut à gauche).
        uv = [(u0, 1.0), (u1, 1.0), (u0, 0.0), (u1, 0.0)]
        return side, normal, half, uv

    patterns = [(0.0, False)]
    if planes >= 2:
        patterns.append((np.pi / 3.0, True))
    if planes >= 3:
        patterns.append((2.0 * np.pi / 3.0, False))

    positions: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    indices: list[int] = []
    for yaw, flip in patterns:
        side, normal, half, uv = corners_for(yaw, 1.0 if flip else 0.0, 0.0 if flip else 1.0)
        base = len(positions)
        for sx, sy in ((-half, 0.0), (half, 0.0), (-half, height), (half, height)):
            positions.append((float(side[0] * sx), float(sy), float(side[2] * sx)))
            normals.append((float(normal[0]), float(normal[1]), float(normal[2])))
        uvs.extend(uv)
        indices.extend([base, base + 2, base + 1, base + 1, base + 2, base + 3])
    return positions, normals, uvs, indices, patterns


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

    chunks: list[bytes] = [pos_bytes, nor_bytes, uv_bytes, idx_bytes, image_bytes]
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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--width", type=float, required=True, help="largeur en cases")
    parser.add_argument("--height", type=float, required=True, help="hauteur en cases")
    parser.add_argument("--planes", type=int, default=3, choices=[1, 2, 3])
    parser.add_argument("--texture-size", type=int, default=1024)
    args = parser.parse_args()

    views = load_views(args.reference)
    atlas, _u0, _u1 = build_atlas(views, args.texture_size)
    positions, normals, uvs, indices, _ = card_geometry(args.width, args.height, args.planes)
    write_glb(args.out, positions, normals, uvs, indices, atlas)
    kb = args.out.stat().st_size / 1024
    print(f"[OK] {args.out} ({kb:.0f} Ko) — {len(indices) // 3} tris, "
          f"atlas {atlas.width}x{atlas.height}, {args.planes} plans alpha")


if __name__ == "__main__":
    main()
