"""Genere des cailloux/gabets low-poly procéduraux pour la carte 2.5D.

Usage :
  blender --background --python tools/blender/build_pebbles.py -- \
      --out artifacts/tripo-review/rock-kit/pebbles

Chaque caillou est un icosphère déformé par bruit déterministe, aplati,
avec un dessous plat, un enroulement de galet et des vertex colors (AO +
mottling) conformes au pipeline Blender du projet. Aucun service externe,
aucun crédit consommé : tout est calculé localement.
"""
from __future__ import annotations

import argparse
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector, noise

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import oq_common as oq  # noqa: E402

## Largeur visée de chaque caillou, en cases. Du plus gros galet au gravier.
SIZES = (0.40, 0.29, 0.20, 0.14)
## Aplatissement vertical : un galet est plus large que haut.
FLATTEN = (0.46, 0.52, 0.56, 0.62)
## Elongation horizontale (galets ovales plutôt que ronds).
ELONGATION = (1.0, 1.18, 0.92, 1.06)
SUBDIVISIONS = 3
## Ratio de décimation : des facettes larges de pierre, pas une sphère lisse.
DECIMATE_RATIO = (0.42, 0.46, 0.52, 0.58)
# Palette pierre du projet : gris chaud, jamais gris pur.
STONE_COLORS = ("#686b6a", "#71736d", "#5b5e5d", "#7b7d78")


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--seed", type=int, default=20261111)
    parser.add_argument("--no-thumbs", action="store_true")
    return parser.parse_args(argv)


def deform_pebble(obj: bpy.types.Object, seed: int, flatten: float, elongation: float) -> None:
    """Deforme l'icosphère : volume irrégulier, dessous plat, galet bombé."""
    mesh = obj.data
    rng = random.Random(seed)
    offset = Vector((rng.random() * 10.0, rng.random() * 10.0, rng.random() * 10.0))
    for vertex in mesh.vertices:
        direction = vertex.co.normalized()
        # Bruit fractal : grosses bosses + petits éclats.
        sample = direction * 2.1 + offset
        coarse = noise.noise(sample)
        fine = noise.noise(sample * 4.7)
        chipped = noise.noise(sample * 9.3 + offset)
        radius = 0.5 * (1.0 + 0.17 * coarse + 0.06 * fine + 0.03 * chipped)
        vertex.co = direction * radius
        vertex.co.x *= elongation
        vertex.co.y *= 1.0 / max(0.6, elongation) ** 0.5
        vertex.co.z *= flatten
        # Dessous plat : tout ce qui descend sous la limite est plaqué.
        floor = -0.30 * flatten * 2.0
        if vertex.co.z < floor:
            vertex.co.z = floor
    mesh.update()


def decimate(obj: bpy.types.Object, ratio: float) -> None:
    """Fusionne les faces quasi coplanaires : facettes de pierre, pas de sphère."""
    modifier = obj.modifiers.new("chunky", "DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def build_pebble(index: int, name: str, seed: int) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=SUBDIVISIONS, radius=0.5)
    obj = bpy.context.object
    deform_pebble(obj, seed, FLATTEN[index], ELONGATION[index])
    decimate(obj, DECIMATE_RATIO[index])
    # Taille finale : le plus grand galet mesure SIZES[0] de large.
    mesh = obj.data
    width = max(
        max(v.co.x for v in mesh.vertices) - min(v.co.x for v in mesh.vertices),
        1e-4,
    )
    factor = SIZES[index] / width
    for vertex in mesh.vertices:
        vertex.co *= factor
    mesh.update()

    oq.normalize_asset(obj, name)
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    oq.bake_vertex_colors(obj, seed=seed, ao_strength=0.45, mottle_strength=0.05)
    material = oq.make_material(
        f"{name}_stone", STONE_COLORS[index % len(STONE_COLORS)], roughness=0.95
    )
    obj.data.materials.append(material)
    return obj


def main() -> int:
    args = parse_args()
    out_root = Path(args.out).resolve()
    out_root.mkdir(parents=True, exist_ok=True)
    palette = ["galet_rond", "galet_ovale", "eclat_plat", "gravier"]
    reports = []
    for index, base_name in enumerate(palette):
        name = f"caillou_{base_name}"
        bpy.ops.wm.read_factory_settings(use_empty=True)
        seed = args.seed + index * 131
        obj = build_pebble(index, name, seed)
        glb = oq.export_glb(out_root / f"{name}.glb", [obj])
        triangles = oq.triangle_count(obj)
        dims = oq.object_dimensions([obj])
        if not args.no_thumbs:
            # L'aperçu vertex color se branche APRÈS l'export, sinon le
            # baseColorFactor glTF serait remplacé par du blanc.
            oq.enable_vertex_color_preview([obj])
            # Le pipeline de vignette dimensionne son éclairage sur la taille de
            # l'objet : un caillou de 0,4 case y est surexposé. On rend une copie
            # agrandie, l'asset exporté garde sa taille réelle.
            proxy = obj.copy()
            proxy.data = obj.data.copy()
            proxy.name = f"{name}_thumbproxy"
            proxy.scale = (2.6, 2.6, 2.6)
            bpy.context.scene.collection.objects.link(proxy)
            oq.render_thumbnail(
                out_root / f"{name}{oq.THUMB_SUFFIX}", [proxy], engine="eevee", samples=24
            )
            bpy.data.objects.remove(proxy, do_unlink=True)
        reports.append(
            {
                "name": name,
                "triangles": triangles,
                "width": round(dims[0], 3),
                "height": round(dims[2], 3),
                "bytes": glb.stat().st_size,
            }
        )
        print(
            "[OK] {name}: {triangles} tris, {width} x {height} cases, {bytes} o".format(
                **reports[-1]
            )
        )
    print("PEBBLES_BUILD:PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
