"""Genere les prototypes low-poly de la carte 2.5D (GLB + vignettes).

Tout est procedural et offline : aucune texture, aucun telechargement, aucun
asset externe. Chaque objet est assemble a partir de primitives (boites,
cylindres, cones, ico-spheres, prismes), fusionne en un seul mesh, normalise
selon les conventions du projet puis exporte.

Style 2.5D : palette echantillonnee sur les fonds peints Valbois, materiaux
mats, AO + mottling cuits en vertex colors (COLOR_0), contour "inverted hull"
sombre pour rappeler l'encrage de l'illustration, et jupe de raccord au sol.

Utilisation (Blender 4.5.10 LTS) :

    & "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" `
        --background --python-exit-code 1 `
        --python tools/blender/build_prototypes.py -- [options]

Options (apres ``--``) :

    --only maison tour        Ne generer que ces assets (debug).
    --out-root DIR            Racine de sortie (defaut game/assets/objects3d).
    --engine eevee|cycles     Moteur de rendu des vignettes (defaut eevee).
    --samples N               Echantillons de rendu (defaut 32).
    --thumb-size N            Taille carree des vignettes (defaut 512).
    --no-thumbs               Exporte les GLB sans vignettes.
    --no-export               Rend les vignettes sans exporter les GLB.
    --no-outline              Desactive le contour encre (debug).
    --no-manifest             Ne pas ecrire objects3d/manifest.json.

Sortie : ``game/assets/objects3d/<categorie>/<nom>.glb`` et
``<nom>_thumb.png`` (512x512, RGBA transparent), plus un manifeste JSON
informatif listant les assets, leurs dimensions en cases et leur budget poly.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

# Permet d'importer oq_common quand le script est lance par
# `blender --python tools/blender/build_prototypes.py`.
sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402

import oq_common as oq  # noqa: E402
from oq_common import (  # noqa: E402
    DEFAULT_PALETTE,
    OUTLINE_THICKNESS,
    THUMB_SIZE,
    TRIANGLE_BUDGET,
    add_box,
    add_cone,
    add_cylinder,
    add_ground_skirt,
    add_ico_sphere,
    add_mesh,
    add_torus,
    apply_transforms,
    bake_vertex_colors,
    build_outline,
    enable_vertex_color_preview,
    export_glb,
    finalize_asset,
    log,
    make_material,
    material_palette,
    normalize_asset,
    object_dimensions,
    render_thumbnail,
    reset_scene,
    subdivide_long_edges,
    triangulate_mesh,
    triangle_count,
)

Mats = dict[str, bpy.types.Material]


# --------------------------------------------------------------------------- #
# Geometrie specifique aux prototypes
# --------------------------------------------------------------------------- #


def gable_roof(
    name: str,
    *,
    width: float,
    depth: float,
    height: float,
    base_z: float,
    material: bpy.types.Material,
    ridge_shift: float = 0.0,
) -> bpy.types.Object:
    """Toit a deux pans (prisme triangulaire), faitiere selon l'axe X."""
    w = width * 0.5
    d = depth * 0.5
    ridge_y = ridge_shift
    vertices = [
        (-w, -d, base_z),  # 0 avant gauche
        (-w, d, base_z),  # 1 arriere gauche
        (-w, ridge_y, base_z + height),  # 2 faitiere gauche
        (w, -d, base_z),  # 3 avant droit
        (w, d, base_z),  # 4 arriere droit
        (w, ridge_y, base_z + height),  # 5 faitiere droite
    ]
    faces = [
        (0, 2, 1),  # pan gauche (-X)
        (3, 4, 5),  # pan droit (+X)
        (0, 3, 5, 2),  # pan avant (-Y)
        (1, 2, 5, 4),  # pan arriere (+Y)
        (0, 1, 4, 3),  # dessous
    ]
    return add_mesh(name, vertices, faces, material)


# --------------------------------------------------------------------------- #
# Constructeurs d'assets (chaque fonction renvoie les parties non fusionnees)
# --------------------------------------------------------------------------- #


def build_maison(mats: Mats) -> list[bpy.types.Object]:
    """Maison de village : socle pierre, colombages, toit a deux pans, cheminee."""
    parts: list[bpy.types.Object] = []
    # Jupe de raccord au sol : evite la coupure nette avec le decor peint.
    parts.append(add_ground_skirt("grass_skirt", (1.98, 1.72), mats["grass"], seed=1))
    parts.append(add_box("plinth", (1.70, 1.45, 0.14), (0, 0, 0.07), mats["stone"]))
    parts.append(add_box("walls", (1.60, 1.35, 0.95), (0, 0, 0.14 + 0.475), mats["plaster"]))

    # Colombages : poteaux d'angle + ceinture horizontale.
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(
                add_box(
                    "post",
                    (0.09, 0.09, 0.95),
                    (sx * 0.755, sy * 0.63, 0.14 + 0.475),
                    mats["wood_dark"],
                )
            )
    parts.append(
        add_box("belt", (1.63, 1.38, 0.10), (0, 0, 0.14 + 0.52), mats["wood_dark"])
    )

    # Toit (leger debord), poutres de rive/faitiere et rangÃƒÂ©es de tuiles.
    parts.append(
        gable_roof(
            "roof",
            width=1.82,
            depth=1.58,
            height=0.58,
            base_z=1.09,
            material=mats["roof"],
        )
    )
    parts.append(add_box("eave_front", (1.90, 0.10, 0.10), (0, -0.79, 1.05), mats["wood_dark"]))
    parts.append(add_box("eave_back", (1.90, 0.10, 0.10), (0, 0.79, 1.05), mats["wood_dark"]))
    parts.append(add_box("ridge_beam", (1.86, 0.12, 0.09), (0, 0, 1.69), mats["wood_dark"]))
    # RangÃƒÂ©es de tuiles suggÃƒÂ©rÃƒÂ©es par des liteaux poses sur les pans.
    for y in (-0.56, -0.24):
        slope_z = 1.09 + (y + 0.79) * (0.58 / 0.79)
        parts.append(
            add_box(
                "tile_batten",
                (1.84, 0.055, 0.035),
                (0, y, slope_z + 0.012),
                mats["roof_dark"],
                rotation=(0.633, 0.0, 0.0),
            )
        )
    for y in (0.56, 0.24):
        slope_z = 1.09 + (0.79 - y) * (0.58 / 0.79)
        parts.append(
            add_box(
                "tile_batten",
                (1.84, 0.055, 0.035),
                (0, y, slope_z + 0.012),
                mats["roof_dark"],
                rotation=(-0.633, 0.0, 0.0),
            )
        )
    parts.append(add_box("chimney", (0.18, 0.18, 0.58), (0.44, 0.22, 1.50), mats["stone"]))
    parts.append(add_box("chimney_cap", (0.24, 0.24, 0.07), (0.44, 0.22, 1.82), mats["stone_dark"]))

    # Porte + marche, fenetres (face avant = -Y).
    parts.append(add_box("door", (0.30, 0.09, 0.55), (0, -0.70, 0.14 + 0.275), mats["wood_dark"]))
    parts.append(add_box("door_step", (0.48, 0.24, 0.06), (0, -0.80, 0.03), mats["stone_dark"]))
    parts.append(add_box("door_handle", (0.05, 0.04, 0.05), (0.10, -0.755, 0.46), mats["metal"]))
    for x in (-0.45, 0.45):
        parts.append(add_box("window_front", (0.26, 0.07, 0.24), (x, -0.705, 0.80), mats["glow"]))
        parts.append(add_box("shutter", (0.07, 0.06, 0.28), (x - 0.19, -0.71, 0.80), mats["wood"]))
        parts.append(add_box("shutter", (0.07, 0.06, 0.28), (x + 0.19, -0.71, 0.80), mats["wood"]))
    parts.append(add_box("window_side", (0.07, 0.26, 0.24), (0.81, 0.10, 0.80), mats["glow"]))
    return parts


def build_tour(mats: Mats) -> list[bpy.types.Object]:
    """Tour de guet ronde (~1,4 case de large) : socle, assises, creneaux."""
    parts: list[bpy.types.Object] = []
    parts.append(add_ground_skirt("grass_skirt", (1.34, 1.34), mats["grass"], seed=2))
    parts.append(add_cylinder("plinth", 0.62, 0.18, (0, 0, 0.09), mats["stone_dark"], vertices=12))
    parts.append(add_cylinder("body", 0.52, 1.80, (0, 0, 0.18 + 0.90), mats["stone"], vertices=12))
    # Assises de maconnerie : cassent la surface lisse du fut.
    for z, material in ((0.55, "stone_light"), (1.10, "stone_dark"), (1.65, "stone_light")):
        parts.append(
            add_cylinder("band", 0.545, 0.055, (0, 0, z), mats[material], vertices=12)
        )
    parts.append(add_cylinder("rim", 0.58, 0.12, (0, 0, 2.04), mats["stone_light"], vertices=12))

    # 8 creneaux repartis sur le pourtour.
    import math

    for i in range(8):
        angle = math.tau * i / 8.0
        parts.append(
            add_box(
                "merlon",
                (0.18, 0.16, 0.26),
                (0.47 * math.cos(angle), 0.47 * math.sin(angle), 2.22),
                mats["stone"],
                rotation=(0.0, 0.0, angle),
            )
        )

    # Porte (face avant -Y) et linteau.
    parts.append(add_box("door", (0.34, 0.12, 0.60), (0, -0.48, 0.18 + 0.30), mats["wood_dark"]))
    parts.append(add_box("lintel", (0.46, 0.14, 0.12), (0, -0.48, 0.85), mats["stone_light"]))
    parts.append(add_box("door_step", (0.52, 0.24, 0.06), (0, -0.57, 0.03), mats["stone_dark"]))

    # Meurtrieres.
    parts.append(add_box("slit_front", (0.07, 0.10, 0.24), (0, -0.50, 1.30), mats["stone_dark"]))
    parts.append(add_box("slit_side", (0.10, 0.07, 0.24), (0.50, 0.0, 1.30), mats["stone_dark"]))
    return parts


def build_pont(mats: Mats) -> list[bpy.types.Object]:
    """Pont de pierre et bois, tablier sureleve, garde-corps, poutres."""
    parts: list[bpy.types.Object] = []
    # Culees en pierre elargies (pas de jupe : le pont enjambe l'eau).
    for x in (-1.0, 1.0):
        parts.append(add_box("pier", (0.42, 1.12, 0.52), (x, 0, 0.26), mats["stone"]))
        parts.append(add_box("pier_base", (0.62, 1.28, 0.07), (x, 0, 0.035), mats["stone_dark"]))
        parts.append(add_box("pier_cap", (0.50, 1.18, 0.09), (x, 0, 0.54), mats["stone_light"]))
    # Tablier.
    parts.append(add_box("deck", (2.30, 1.00, 0.14), (0, 0, 0.52), mats["wood_dark"]))
    for i in range(7):
        x = -0.99 + i * 0.33
        material = mats["wood"] if i % 2 == 0 else mats["wood_light"]
        parts.append(add_box("plank", (0.26, 1.02, 0.04), (x, 0, 0.61), material))
    # Poutres de soutien (legerement inclinees).
    for x in (-0.55, 0.55):
        parts.append(
            add_box(
                "brace",
                (0.14, 1.02, 0.14),
                (x, 0, 0.43),
                mats["wood_dark"],
                rotation=(0.0, 0.5 if x > 0 else -0.5, 0.0),
            )
        )
    # Garde-corps.
    for y in (-0.46, 0.46):
        for x in (-0.90, -0.45, 0.0, 0.45, 0.90):
            parts.append(add_box("rail_post", (0.09, 0.09, 0.48), (x, y, 0.83), mats["wood_dark"]))
        parts.append(add_box("rail_top", (1.94, 0.08, 0.10), (0, y, 1.02), mats["wood"]))
        parts.append(add_box("rail_mid", (1.94, 0.06, 0.07), (0, y, 0.78), mats["wood_light"]))
    return parts


def build_arbre(mats: Mats) -> list[bpy.types.Object]:
    """Arbre feuillu (~1 case) : tronc et trois houppes irregulieres imbriquees."""
    parts: list[bpy.types.Object] = []
    parts.append(add_ground_skirt("grass_skirt", (1.04, 1.04), mats["grass"], seed=8))
    parts.append(add_cylinder("trunk", 0.13, 0.95, (0, 0, 0.475), mats["wood_dark"], vertices=7))
    parts.append(add_cylinder("trunk_base", 0.20, 0.10, (0, 0, 0.05), mats["wood"], vertices=7))
    parts.append(
        add_ico_sphere(
            "canopy_low",
            0.52,
            (0, 0, 1.12),
            mats["leaf_dark"],
            subdivisions=1,
            scale=(1.0, 1.0, 0.82),
            jitter=0.06,
            seed=81,
        )
    )
    parts.append(
        add_ico_sphere(
            "canopy_mid",
            0.40,
            (0.10, -0.03, 1.50),
            mats["leaf"],
            subdivisions=1,
            scale=(1.05, 1.0, 0.90),
            jitter=0.05,
            seed=82,
        )
    )
    parts.append(
        add_ico_sphere(
            "canopy_top",
            0.28,
            (-0.06, 0.05, 1.83),
            mats["leaf_light"],
            subdivisions=1,
            scale=(1.0, 1.0, 0.88),
            jitter=0.03,
            seed=83,
        )
    )
    return parts


def build_rocher(mats: Mats) -> list[bpy.types.Object]:
    """Rocher : trois blocs d'ico-spheres deformer + taches de mousse."""
    parts: list[bpy.types.Object] = []
    parts.append(add_ground_skirt("grass_skirt", (1.30, 1.16), mats["dirt"], seed=9))
    parts.append(
        add_ico_sphere(
            "rock_main",
            0.55,
            (0, 0, 0.38),
            mats["stone"],
            subdivisions=1,
            scale=(1.15, 0.95, 0.75),
            jitter=0.07,
            seed=11,
        )
    )
    parts.append(
        add_ico_sphere(
            "rock_side",
            0.36,
            (0.44, 0.16, 0.24),
            mats["stone_light"],
            subdivisions=1,
            scale=(1.10, 0.95, 0.80),
            jitter=0.05,
            seed=23,
        )
    )
    parts.append(
        add_ico_sphere(
            "rock_small",
            0.24,
            (-0.38, -0.20, 0.17),
            mats["stone_dark"],
            subdivisions=1,
            scale=(1.0, 1.0, 0.85),
            jitter=0.04,
            seed=37,
        )
    )
    # Touffes de mousse : calottes opaques enfoncees dans le rocher (pas de
    # feuilles alpha, elles se trieraient mal avec les decoupes 2D).
    for i, (x, y, z, sx, sy) in enumerate(
        [(0.02, -0.02, 0.73, 0.32, 0.26), (-0.20, 0.18, 0.58, 0.22, 0.18)]
    ):
        parts.append(
            add_ico_sphere(
                f"moss_{i}",
                0.15,
                (x, y, z),
                mats["leaf_dark"],
                subdivisions=1,
                scale=(sx / 0.15, sy / 0.15, 0.55),
                jitter=0.02,
                seed=50 + i,
            )
        )
    return parts


def build_caisse(mats: Mats) -> list[bpy.types.Object]:
    """Caisse en bois : corps, renforts d'angle, rails, planche diagonale."""
    parts: list[bpy.types.Object] = []
    parts.append(add_ground_skirt("dirt_skirt", (0.98, 0.98), mats["dirt"], seed=5))
    parts.append(add_box("crate_body", (0.70, 0.70, 0.70), (0, 0, 0.35), mats["wood_light"]))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(
                add_box(
                    "corner_post",
                    (0.10, 0.10, 0.74),
                    (sx * 0.315, sy * 0.315, 0.37),
                    mats["wood_dark"],
                )
            )
    for y in (-0.345, 0.345):
        parts.append(add_box("rail_h", (0.60, 0.06, 0.10), (0, y, 0.10), mats["wood_dark"]))
        parts.append(add_box("rail_h", (0.60, 0.06, 0.10), (0, y, 0.62), mats["wood_dark"]))
    for x in (-0.345, 0.345):
        parts.append(add_box("rail_v", (0.06, 0.60, 0.10), (x, 0, 0.10), mats["wood_dark"]))
        parts.append(add_box("rail_v", (0.06, 0.60, 0.10), (x, 0, 0.62), mats["wood_dark"]))
    parts.append(
        add_box(
            "diagonal",
            (0.07, 0.05, 0.86),
            (0, -0.365, 0.35),
            mats["wood_dark"],
            rotation=(0.0, 0.72, 0.0),
        )
    )
    return parts


def build_palissade(mats: Mats) -> list[bpy.types.Object]:
    """Palissade (module 2 cases) : planches pointees et deux traverses arriere."""
    parts: list[bpy.types.Object] = []
    parts.append(add_ground_skirt("grass_skirt", (2.06, 0.50), mats["grass"], seed=6))
    for i in range(7):
        x = -0.84 + i * 0.28
        material = mats["wood"] if i % 2 == 0 else mats["wood_light"]
        parts.append(add_box("plank", (0.24, 0.10, 1.00), (x, 0, 0.50), material))
        parts.append(
            add_cone(
                "plank_tip",
                0.17,
                0.22,
                (x, 0, 1.11),
                material,
                vertices=4,
                rotation=(0.0, 0.0, 0.785398),
            )
        )
    for z in (0.34, 0.80):
        parts.append(add_box("rail", (1.86, 0.07, 0.13), (0, 0.09, z), mats["wood_dark"]))
    return parts


def build_puits(mats: Mats) -> list[bpy.types.Object]:
    """Puits (~1 case) : margelle de pierre, eau, poteaux, toit, seau et corde."""
    parts: list[bpy.types.Object] = []
    parts.append(add_ground_skirt("dirt_skirt", (1.22, 0.98), mats["dirt"], seed=7))
    # Margelle basse et large : base massive, lisible de dessus.
    parts.append(add_cylinder("curb", 0.46, 0.46, (0, 0, 0.23), mats["stone"], vertices=10))
    parts.append(
        add_cylinder("curb_rim", 0.50, 0.09, (0, 0, 0.50), mats["stone_light"], vertices=10)
    )
    parts.append(add_cylinder("water", 0.35, 0.05, (0, 0, 0.55), mats["water"], vertices=10))
    # Poteaux hauts et toit etroit : le toit ne masque ni la margelle ni le seau.
    for x in (-0.43, 0.43):
        parts.append(add_box("post", (0.09, 0.09, 1.18), (x, 0, 0.59), mats["wood_dark"]))
        parts.append(add_box("post_foot", (0.16, 0.16, 0.08), (x, 0, 0.04), mats["stone_dark"]))
    parts.append(
        gable_roof(
            "roof",
            width=1.14,
            depth=0.68,
            height=0.24,
            base_z=1.18,
            material=mats["roof"],
        )
    )
    parts.append(
        add_cylinder(
            "crossbar",
            0.045,
            0.98,
            (0, 0, 1.02),
            mats["wood"],
            vertices=8,
            rotation=(0.0, 1.5707963, 0.0),
        )
    )
    parts.append(add_box("crank", (0.05, 0.20, 0.05), (0.51, 0.07, 1.02), mats["metal"]))
    # Corde + seau suspendus, visibles sous le toit.
    parts.append(add_cylinder("rope", 0.014, 0.36, (0, -0.08, 0.82), mats["wood_dark"], vertices=6))
    parts.append(add_cylinder("bucket", 0.10, 0.17, (0, -0.08, 0.55), mats["wood"], vertices=8))
    parts.append(add_cylinder("bucket_band", 0.105, 0.03, (0, -0.08, 0.61), mats["metal"], vertices=8))
    return parts


# --------------------------------------------------------------------------- #
# Kit enrichi v2 : murs, mobilier urbain, marche, charrette, foin
# --------------------------------------------------------------------------- #


def _arrow_board(
    name: str,
    *,
    length: float,
    height: float,
    thickness: float,
    material: bpy.types.Material,
    origin: tuple[float, float, float],
    rotation_z: float = 0.0,
) -> bpy.types.Object:
    """Panneau en forme de flèche (prisme fermé), orienté dans le plan XZ local."""
    import bmesh

    shape = [
        (-length * 0.5, -height * 0.5),
        (length * 0.5 - height * 0.75, -height * 0.5),
        (length * 0.5, 0.0),
        (length * 0.5 - height * 0.75, height * 0.5),
        (-length * 0.5, height * 0.5),
    ]
    cos_a = math.cos(rotation_z)
    sin_a = math.sin(rotation_z)
    half_t = thickness * 0.5
    vertices: list[tuple[float, float, float]] = []
    for local_y in (-half_t, half_t):
        for local_x, local_z in shape:
            vertices.append(
                (
                    origin[0] + local_x * cos_a - local_y * sin_a,
                    origin[1] + local_x * sin_a + local_y * cos_a,
                    origin[2] + local_z,
                )
            )
    count = len(shape)
    faces: list[tuple[int, ...]] = [tuple(range(count)), tuple(range(count, 2 * count))[::-1]]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    board = add_mesh(name, vertices, faces, material)
    bm = bmesh.new()
    bm.from_mesh(board.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(board.data)
    bm.free()
    return board


def _stone_wall_parts(
    mats: Mats,
    *,
    length: float,
    location: tuple[float, float],
    rotation_z: float = 0.0,
) -> list[bpy.types.Object]:
    """Tronçon de mur en pierre : socle, assises décalées, dalles de couronnement."""
    parts: list[bpy.types.Object] = []
    cos_a = math.cos(rotation_z)
    sin_a = math.sin(rotation_z)
    depth = 0.46

    def place(dx: float, z: float, size: tuple[float, float, float], material):
        x = location[0] + dx * cos_a
        y = location[1] + dx * sin_a
        return add_box(
            "wall_block", size, (x, y, z), material, rotation=(0.0, 0.0, rotation_z)
        )

    parts.append(
        add_box(
            "wall_plinth",
            (length + 0.10, depth + 0.12, 0.16),
            (location[0], location[1], 0.08),
            mats["stone_dark"],
            rotation=(0.0, 0.0, rotation_z),
        )
    )

    course_patterns = [
        (0.16, 0.38, [0.55, 0.48, 0.52, 0.45, 0.50]),
        (0.54, 0.34, [0.42, 0.58, 0.46, 0.55, 0.49]),
        (0.88, 0.28, [0.60, 0.44, 0.52, 0.47, 0.47]),
    ]
    for course_index, (z_base, block_height, pattern) in enumerate(course_patterns):
        total = sum(pattern)
        widths = [w / total * length for w in pattern]
        offset = -length * 0.5 + (0.0 if course_index % 2 == 0 else length * 0.09)
        materials = [mats["stone"], mats["stone_light"], mats["stone_dark"]]
        for block_index, width in enumerate(widths):
            remaining = length * 0.5 - offset
            if remaining <= 0.05:
                break
            width = min(width, remaining)
            if width < 0.07:
                break
            x_center = offset + width * 0.5
            material = materials[(course_index + block_index) % 3]
            parts.append(
                place(
                    x_center,
                    z_base + block_height * 0.5,
                    (width - 0.018, depth, block_height),
                    material,
                )
            )
            offset += width

    # Dalles de couronnement.
    cap_count = 3
    cap_width = length / cap_count
    for index in range(cap_count):
        dx = -length * 0.5 + cap_width * (index + 0.5)
        parts.append(
            place(
                dx,
                1.16 + 0.055,
                (cap_width - 0.02, depth + 0.14, 0.11),
                mats["stone_light"],
            )
        )
    return parts


def build_mur(mats: Mats) -> list[bpy.types.Object]:
    """Mur de pierre droit (~2 cases) : assises, socle et dalles de couronnement."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.32, 0.66), mats["grass"], seed=41)
    ]
    parts.extend(_stone_wall_parts(mats, length=2.10, location=(0.0, 0.0)))
    return parts


def build_mur_coin(mats: Mats) -> list[bpy.types.Object]:
    """Coin de mur en L (~1,8 case d'emprise) : deux tronçons à 90°."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (1.98, 1.82), mats["grass"], seed=42)
    ]
    parts.extend(
        _stone_wall_parts(mats, length=1.55, location=(-0.02, -0.52), rotation_z=0.0)
    )
    parts.extend(
        _stone_wall_parts(
            mats, length=1.25, location=(0.75, 0.10), rotation_z=math.pi * 0.5
        )
    )
    return parts


def build_barriere(mats: Mats) -> list[bpy.types.Object]:
    """Barrière en bois (module 2 cases) : poteaux, deux lisses et jambe de force."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.10, 0.44), mats["grass"], seed=43)
    ]
    for x in (-0.80, 0.0, 0.80):
        parts.append(add_box("post", (0.13, 0.13, 0.86), (x, 0, 0.43), mats["wood_dark"]))
        parts.append(add_box("post_cap", (0.18, 0.18, 0.06), (x, 0, 0.89), mats["wood"]))
    parts.append(add_box("rail_low", (1.92, 0.09, 0.14), (0, 0, 0.32), mats["wood"]))
    parts.append(add_box("rail_high", (1.92, 0.09, 0.14), (0, 0, 0.64), mats["wood_light"]))
    parts.append(
        add_box(
            "brace",
            (0.76, 0.06, 0.10),
            (0.40, 0.055, 0.48),
            mats["wood_dark"],
            rotation=(0.0, 0.0, 0.32),
        )
    )
    return parts


def build_etal_marche(mats: Mats) -> list[bpy.types.Object]:
    """Étal de marché (~2 cases) : comptoir, auvent à rayures, marchandises."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.02, 1.58), mats["dirt"], seed=44)
    ]
    for x in (-0.72, 0.72):
        for y in (-0.52, 0.52):
            parts.append(add_box("post", (0.10, 0.10, 1.92), (x, y, 0.96), mats["wood_dark"]))
    # Comptoir.
    parts.append(add_box("counter_top", (1.58, 0.92, 0.09), (0, 0, 0.80), mats["wood_light"]))
    parts.append(add_box("counter_front", (1.58, 0.06, 0.62), (0, -0.46, 0.38), mats["wood"]))
    parts.append(add_box("counter_back", (1.58, 0.06, 0.62), (0, 0.46, 0.38), mats["wood_dark"]))
    for x in (-0.60, 0.60):
        parts.append(add_box("counter_leg", (0.10, 0.78, 0.70), (x, 0, 0.35), mats["wood_dark"]))
    # Auvent à rayures incliné vers l'avant (-Y).
    stripe_materials = [mats["cloth"], mats["plaster_light"]]
    stripe_width = 0.24
    for index in range(8):
        x = -0.84 + index * stripe_width
        parts.append(
            add_box(
                "awning_stripe",
                (stripe_width - 0.012, 1.20, 0.04),
                (x, -0.03, 1.84),
                stripe_materials[index % 2],
                rotation=(0.21, 0.0, 0.0),
            )
        )
        parts.append(
            add_box(
                "awning_valance",
                (stripe_width - 0.012, 0.03, 0.17),
                (x, -0.66, 1.70),
                stripe_materials[index % 2],
            )
        )
    # Marchandises sur le comptoir.
    goods = [
        (-0.44, 0.10, 0.24, mats["glow"]),
        (-0.10, 0.04, 0.18, mats["leaf"]),
        (0.18, -0.12, 0.22, mats["wood"]),
        (0.46, 0.06, 0.20, mats["roof_dark"]),
    ]
    for gx, gy, size, material in goods:
        parts.append(add_box("goods", (size, size, size), (gx, gy, 0.85 + size * 0.5), material))
    parts.append(
        add_cylinder("barrel_small", 0.10, 0.19, (0.28, -0.30, 0.92), mats["wood_dark"], vertices=8)
    )
    return parts


def build_tonneau(mats: Mats) -> list[bpy.types.Object]:
    """Tonneau en bois cerclé de métal (~0,8 case)."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("dirt_skirt", (0.98, 0.98), mats["dirt"], seed=45)
    ]
    parts.append(add_cylinder("barrel_body", 0.36, 0.78, (0, 0, 0.39), mats["wood"], vertices=12))
    for z in (0.10, 0.39, 0.68):
        parts.append(add_cylinder("barrel_band", 0.378, 0.055, (0, 0, z), mats["metal"], vertices=12))
    parts.append(add_cylinder("barrel_lid", 0.33, 0.05, (0, 0, 0.80), mats["wood_light"], vertices=12))
    parts.append(add_cylinder("barrel_rim", 0.362, 0.035, (0, 0, 0.775), mats["wood_dark"], vertices=12))
    return parts


def build_lanterne(mats: Mats) -> list[bpy.types.Object]:
    """Lanterne sur poteau (~2,3 cases de haut) : socle, mât, fanal à vitres."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("dirt_skirt", (0.78, 0.78), mats["dirt"], seed=46)
    ]
    parts.append(add_box("base", (0.34, 0.34, 0.14), (0, 0, 0.07), mats["stone_dark"]))
    parts.append(add_box("base_step", (0.26, 0.26, 0.08), (0, 0, 0.17), mats["stone"]))
    parts.append(add_box("post", (0.10, 0.10, 2.05), (0, 0, 1.19), mats["wood_dark"]))
    parts.append(add_box("bracket", (0.34, 0.08, 0.08), (0.12, 0, 2.18), mats["metal"]))
    # Fanal suspendu.
    parts.append(add_box("lantern_top", (0.28, 0.28, 0.06), (0.26, 0, 2.10), mats["metal"]))
    parts.append(add_box("lantern_bottom", (0.28, 0.28, 0.06), (0.26, 0, 1.78), mats["metal"]))
    for dx in (-0.11, 0.11):
        for dy in (-0.11, 0.11):
            parts.append(
                add_box("lantern_post", (0.035, 0.035, 0.30), (0.26 + dx, dy, 1.94), mats["metal"])
            )
    parts.append(add_box("lantern_glass", (0.20, 0.20, 0.24), (0.26, 0, 1.94), mats["lamp"]))
    parts.append(
        add_cone(
            "lantern_cap",
            0.20,
            0.15,
            (0.26, 0, 2.205),
            mats["metal"],
            vertices=4,
            rotation=(0.0, 0.0, math.pi * 0.25),
        )
    )
    return parts


def build_banc(mats: Mats) -> list[bpy.types.Object]:
    """Banc en bois (~1,1 case) : assise, dossier et pieds."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (1.34, 0.70), mats["grass"], seed=47)
    ]
    for y in (-0.09, 0.09):
        parts.append(add_box("seat_plank", (1.10, 0.16, 0.06), (0, y, 0.45), mats["wood_light"]))
    for x in (-0.42, 0.42):
        parts.append(add_box("leg", (0.12, 0.42, 0.45), (x, 0, 0.225), mats["wood_dark"]))
        parts.append(add_box("back_post", (0.09, 0.09, 0.52), (x, 0.17, 0.70), mats["wood_dark"]))
    for z in (0.68, 0.86):
        parts.append(add_box("back_slat", (1.06, 0.05, 0.10), (0, 0.19, z), mats["wood_light"]))
    return parts


def build_panneau(mats: Mats) -> list[bpy.types.Object]:
    """Panneau indicateur (~1,9 case de haut) : mât et deux flèches de bois."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("dirt_skirt", (0.74, 0.74), mats["dirt"], seed=48)
    ]
    parts.append(add_cylinder("post", 0.075, 1.86, (0, 0, 0.93), mats["wood"], vertices=7))
    parts.append(add_cylinder("post_base", 0.13, 0.10, (0, 0, 0.05), mats["stone_dark"], vertices=7))
    parts.append(
        add_cone(
            "post_cap",
            0.12,
            0.14,
            (0, 0, 1.92),
            mats["wood_dark"],
            vertices=4,
            rotation=(0.0, 0.0, math.pi * 0.25),
        )
    )
    parts.append(
        _arrow_board(
            "arrow_high",
            length=0.72,
            height=0.20,
            thickness=0.06,
            material=mats["wood_light"],
            origin=(0.10, 0.0, 1.52),
            rotation_z=-0.20,
        )
    )
    parts.append(
        _arrow_board(
            "arrow_low",
            length=0.60,
            height=0.17,
            thickness=0.06,
            material=mats["wood_light"],
            origin=(-0.08, -0.015, 1.16),
            rotation_z=math.pi + 0.18,
        )
    )
    return parts


def build_charrette(mats: Mats) -> list[bpy.types.Object]:
    """Charrette en bois (~1,5 case) : caisse, roues, essieu et brancards."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("dirt_skirt", (1.72, 1.34), mats["dirt"], seed=49)
    ]
    # Caisse.
    parts.append(add_box("bed", (1.25, 0.80, 0.10), (0, 0, 0.62), mats["wood_light"]))
    for y in (-0.37, 0.37):
        parts.append(add_box("side_panel", (1.25, 0.06, 0.28), (0, y, 0.78), mats["wood"]))
    for x in (-0.60, 0.60):
        parts.append(add_box("end_panel", (0.06, 0.80, 0.28), (x, 0, 0.78), mats["wood"]))
    parts.append(add_box("underframe", (1.15, 0.12, 0.10), (0, 0, 0.52), mats["wood_dark"]))
    # Essieu + roues (axe X).
    parts.append(
        add_cylinder(
            "axle", 0.055, 1.50, (0, 0.02, 0.40), mats["wood_dark"], vertices=8,
            rotation=(0.0, math.pi * 0.5, 0.0),
        )
    )
    for x in (-0.72, 0.72):
        parts.append(
            add_cylinder(
                "wheel", 0.40, 0.10, (x, 0.02, 0.42), mats["wood"], vertices=12,
                rotation=(0.0, math.pi * 0.5, 0.0),
            )
        )
        parts.append(
            add_cylinder(
                "wheel_rim", 0.415, 0.045, (x, 0.02, 0.42), mats["metal"], vertices=12,
                rotation=(0.0, math.pi * 0.5, 0.0),
            )
        )
        parts.append(
            add_cylinder(
                "wheel_hub", 0.12, 0.15, (x, 0.02, 0.42), mats["wood_dark"], vertices=8,
                rotation=(0.0, math.pi * 0.5, 0.0),
            )
        )
    # Brancards vers l'avant (-Y).
    for x in (-0.36, 0.36):
        parts.append(add_box("shaft", (0.08, 0.66, 0.08), (x, -0.72, 0.55), mats["wood"]))
    return parts


def build_botte_foin(mats: Mats) -> list[bpy.types.Object]:
    """Botte de foin (~0,9 case) : botte rectangulaire, liens et brins qui dépassent."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (1.02, 0.84), mats["grass"], seed=50)
    ]
    parts.append(add_box("bale", (0.84, 0.58, 0.52), (0, 0, 0.26), mats["hay"]))
    parts.append(add_box("bale_top", (0.78, 0.52, 0.10), (0, 0, 0.56), mats["hay_light"]))
    parts.append(add_box("bale_base", (0.86, 0.60, 0.06), (0, 0, 0.03), mats["hay_dark"]))
    for x in (-0.24, 0.02, 0.26):
        parts.append(add_box("bale_cord", (0.045, 0.60, 0.54), (x, 0, 0.27), mats["wood_dark"]))
    # Brins qui dépassent, courts et inclinés (pas des clous).
    straws = [
        (-0.34, -0.18, 0.45, 0.30),
        (-0.20, 0.20, -0.35, 0.50),
        (0.08, -0.22, 0.30, -0.45),
        (0.22, 0.16, -0.50, -0.25),
        (0.36, -0.05, 0.20, 0.55),
    ]
    for index, (x, y, tilt_x, tilt_y) in enumerate(straws):
        parts.append(
            add_cone(
                f"straw_{index}",
                0.020,
                0.13,
                (x, y, 0.585),
                mats["hay_light"] if index % 2 == 0 else mats["hay_dark"],
                vertices=4,
                rotation=(tilt_x, tilt_y, index * 0.4),
            )
        )
    return parts



# --------------------------------------------------------------------------- #
# Kit v3 : intérieur taverne, donjon, petits décors
# --------------------------------------------------------------------------- #


def _floor_patch(
    name: str,
    size: tuple[float, float],
    location: tuple[float, float],
    material: bpy.types.Material,
    height: float = 0.03,
) -> bpy.types.Object:
    """Dalle plate de raccord au sol (bois de taverne, pierre de donjon).

    Même rôle que la jupe herbe/terre des extérieurs, mais avec la matière du
    sol intérieur : évite la coupure nette entre l'objet et le sol peint.
    """
    return add_box(
        name,
        (size[0], size[1], height),
        (location[0], location[1], height * 0.5),
        material,
    )


def build_table_tabourets(mats: Mats) -> list[bpy.types.Object]:
    """Table ronde de taverne + trois tabourets + chope et bouteille (~1,7 case)."""
    parts: list[bpy.types.Object] = [
        _floor_patch("floor", (1.72, 1.72), (0, 0), mats["wood_dark"])
    ]
    # Table ronde : piètement central, plateau, ceinture.
    parts.append(add_cylinder("table_foot", 0.28, 0.06, (0, 0, 0.045), mats["wood_dark"], vertices=10))
    parts.append(add_cylinder("table_leg", 0.09, 0.68, (0, 0, 0.38), mats["wood"], vertices=8))
    parts.append(add_cylinder("table_top", 0.46, 0.09, (0, 0, 0.76), mats["wood_light"], vertices=12))
    parts.append(add_cylinder("table_rim", 0.40, 0.025, (0, 0, 0.815), mats["wood_dark"], vertices=12))
    # Tabourets autour.
    for x, y in (
        (0.0, 0.70),
        (-0.61, -0.35),
        (0.61, -0.35),
    ):
        parts.append(add_cylinder("stool_seat", 0.18, 0.07, (x, y, 0.53), mats["wood"], vertices=10))
        parts.append(add_cylinder("stool_leg", 0.07, 0.50, (x, y, 0.25), mats["wood_dark"], vertices=8))
        parts.append(add_cylinder("stool_foot", 0.15, 0.05, (x, y, 0.025), mats["wood_dark"], vertices=8))
    # Chope et bouteille sur la table.
    parts.append(add_cylinder("mug", 0.06, 0.13, (0.17, 0.12, 0.87), mats["plaster_light"], vertices=8))
    parts.append(
        add_torus(
            "mug_handle",
            0.045,
            0.014,
            (0.235, 0.12, 0.87),
            mats["plaster_light"],
            major_segments=6,
            minor_segments=4,
            rotation=(0.0, math.pi * 0.5, 0.0),
        )
    )
    parts.append(add_cylinder("bottle", 0.05, 0.30, (-0.18, -0.06, 0.945), mats["roof_slate"], vertices=8))
    parts.append(
        add_cylinder("bottle_neck", 0.022, 0.15, (-0.18, -0.06, 1.165), mats["roof_slate"], vertices=8)
    )
    parts.append(add_cylinder("bottle_cork", 0.026, 0.04, (-0.18, -0.06, 1.245), mats["wood"], vertices=8))
    return parts


def build_comptoir(mats: Mats) -> list[bpy.types.Object]:
    """Comptoir de taverne + arrière-bar à étagères et bouteilles (~2,3 cases)."""
    parts: list[bpy.types.Object] = [
        _floor_patch("floor", (2.32, 1.24), (0, 0), mats["wood_dark"])
    ]
    # Comptoir.
    parts.append(add_box("counter_body", (2.02, 0.60, 0.92), (0, 0, 0.46), mats["wood_dark"]))
    parts.append(add_box("counter_top", (2.16, 0.78, 0.10), (0, 0, 0.97), mats["wood_light"]))
    for index, x in enumerate((-0.66, 0.0, 0.66)):
        material = mats["wood"] if index % 2 == 0 else mats["wood_light"]
        parts.append(add_box("counter_panel", (0.60, 0.05, 0.78), (x, -0.325, 0.46), material))
    parts.append(
        add_cylinder(
            "foot_rail",
            0.035,
            1.96,
            (0, -0.40, 0.16),
            mats["metal"],
            vertices=8,
            rotation=(0.0, math.pi * 0.5, 0.0),
        )
    )
    parts.append(add_box("counter_edge", (2.18, 0.10, 0.07), (0, -0.40, 1.03), mats["wood_dark"]))
    # Arrière-bar.
    for x in (-0.95, 0.95):
        parts.append(add_box("shelf_post", (0.08, 0.08, 1.78), (x, 0.50, 0.89), mats["wood_dark"]))
    parts.append(add_box("shelf_back", (1.95, 0.05, 1.68), (0, 0.61, 0.94), mats["wood_dark"]))
    for z in (1.16, 1.54):
        parts.append(add_box("shelf", (1.95, 0.30, 0.05), (0, 0.44, z), mats["wood"]))
    bottle_materials = [mats["roof_slate"], mats["leaf"], mats["glow"], mats["roof"], mats["water"]]
    for index in range(9):
        x = -0.80 + index * 0.20
        z = 1.16 if index % 2 == 0 else 1.54
        material = bottle_materials[index % len(bottle_materials)]
        parts.append(add_cylinder("bottle", 0.035, 0.20, (x, 0.44, z + 0.125), material, vertices=8))
        parts.append(add_cylinder("bottle_neck", 0.016, 0.09, (x, 0.44, z + 0.265), material, vertices=8))
    # Chopes sur le comptoir.
    for x in (-0.52, 0.38):
        parts.append(add_cylinder("bar_mug", 0.06, 0.13, (x, -0.10, 1.085), mats["plaster_light"], vertices=8))
    parts.append(add_cylinder("bar_bottle", 0.05, 0.28, (0.72, -0.12, 1.16), mats["roof_slate"], vertices=8))
    return parts


def build_tonneau_couche(mats: Mats) -> list[bpy.types.Object]:
    """Tonneau couché sur cales, robinet au front (~1 case)."""
    parts: list[bpy.types.Object] = [
        _floor_patch("floor", (1.16, 0.88), (0, 0), mats["wood_dark"])
    ]
    parts.append(
        add_cylinder(
            "barrel",
            0.34,
            0.82,
            (0, 0, 0.37),
            mats["wood"],
            vertices=12,
            rotation=(0.0, math.pi * 0.5, 0.0),
        )
    )
    for x in (-0.26, 0.0, 0.26):
        parts.append(
            add_cylinder(
                "hoop",
                0.352,
                0.05,
                (x, 0, 0.37),
                mats["metal"],
                vertices=12,
                rotation=(0.0, math.pi * 0.5, 0.0),
            )
        )
    for x in (-0.415, 0.415):
        parts.append(
            add_cylinder(
                "lid",
                0.315,
                0.035,
                (x, 0, 0.37),
                mats["wood_light"],
                vertices=12,
                rotation=(0.0, math.pi * 0.5, 0.0),
            )
        )
    parts.append(add_box("chock", (0.72, 0.10, 0.10), (0, -0.36, 0.05), mats["wood_dark"]))
    parts.append(
        add_cylinder(
            "tap",
            0.035,
            0.16,
            (0.0, -0.44, 0.24),
            mats["metal"],
            vertices=8,
            rotation=(math.pi * 0.5, 0.0, 0.0),
        )
    )
    return parts


def build_tapis(mats: Mats) -> list[bpy.types.Object]:
    """Tapis de taverne (~1,9 x 1,2 case), plaque plate décorative opaque."""
    parts: list[bpy.types.Object] = [
        add_box("rug_back", (1.96, 1.24, 0.016), (0, 0, 0.008), mats["wood_dark"]),
        add_box("rug_base", (1.86, 1.14, 0.026), (0, 0, 0.029), mats["cloth"]),
    ]
    # Frise extérieure.
    for y in (-0.47, 0.47):
        parts.append(add_box("border", (1.86, 0.10, 0.010), (0, y, 0.045), mats["plaster_light"]))
    for x in (-0.82, 0.82):
        parts.append(add_box("border", (0.10, 0.94, 0.010), (x, 0, 0.045), mats["plaster_light"]))
    # Frise intérieure.
    for y in (-0.36, 0.36):
        parts.append(add_box("inner_border", (1.60, 0.035, 0.008), (0, y, 0.049), mats["roof_dark"]))
    for x in (-0.70, 0.70):
        parts.append(add_box("inner_border", (0.035, 0.72, 0.008), (x, 0, 0.049), mats["roof_dark"]))
    # Motif central en losange.
    parts.append(
        add_box("motif", (0.52, 0.52, 0.008), (0, 0, 0.050), mats["glow"], rotation=(0.0, 0.0, math.pi * 0.25))
    )
    parts.append(
        add_box(
            "motif_core",
            (0.26, 0.26, 0.008),
            (0, 0, 0.054),
            mats["cloth"],
            rotation=(0.0, 0.0, math.pi * 0.25),
        )
    )
    for x in (-0.60, 0.60):
        for y in (-0.32, 0.32):
            parts.append(
                add_box(
                    "corner",
                    (0.10, 0.10, 0.008),
                    (x, y, 0.050),
                    mats["plaster_light"],
                    rotation=(0.0, 0.0, math.pi * 0.25),
                )
            )
    # Franges aux extrémités.
    for x in (-0.985, 0.985):
        for index in range(7):
            y = -0.48 + index * 0.16
            parts.append(add_box("fringe", (0.035, 0.09, 0.006), (x, y, 0.020), mats["plaster_light"]))
    return parts


def build_lit(mats: Mats) -> list[bpy.types.Object]:
    """Lit simple de taverne (~1,4 x 2 cases) : bois, matelas, couverture, oreiller."""
    parts: list[bpy.types.Object] = [
        _floor_patch("floor", (1.46, 2.02), (0, 0), mats["wood_dark"])
    ]
    parts.append(add_box("frame", (1.00, 1.80, 0.20), (0, 0, 0.20), mats["wood"]))
    parts.append(add_box("headboard", (1.08, 0.10, 0.66), (0, 0.92, 0.43), mats["wood_dark"]))
    parts.append(add_box("footboard", (1.08, 0.08, 0.34), (0, -0.92, 0.27), mats["wood_dark"]))
    for x in (-0.44, 0.44):
        for y in (-0.86, 0.86):
            parts.append(add_box("leg", (0.08, 0.08, 0.22), (x, y, 0.11), mats["wood_dark"]))
    parts.append(add_box("mattress", (0.92, 1.64, 0.16), (0, 0, 0.38), mats["plaster_light"]))
    parts.append(add_box("blanket", (0.94, 1.04, 0.06), (0, -0.30, 0.475), mats["cloth"]))
    parts.append(add_box("blanket_fold", (0.94, 0.16, 0.075), (0, 0.18, 0.48), mats["plaster_light"]))
    parts.append(add_box("pillow", (0.56, 0.30, 0.12), (0, 0.64, 0.50), mats["plaster_light"]))
    return parts


def build_torche_murale(mats: Mats) -> list[bpy.types.Object]:
    """Torche murale émissive (~2,4 cases de haut), accrochée au mur (+Y)."""
    parts: list[bpy.types.Object] = []
    parts.append(add_box("wall_plate", (0.18, 0.06, 0.30), (0, 0.09, 1.92), mats["iron_dark"]))
    parts.append(add_box("arm", (0.10, 0.32, 0.08), (0, -0.03, 1.96), mats["iron_dark"]))
    parts.append(
        add_cylinder(
            "handle",
            0.045,
            0.55,
            (0, -0.18, 1.78),
            mats["wood_dark"],
            vertices=8,
            rotation=(-0.35, 0.0, 0.0),
        )
    )
    parts.append(
        add_cylinder(
            "collar",
            0.07,
            0.06,
            (0, -0.22, 1.99),
            mats["metal"],
            vertices=8,
            rotation=(-0.35, 0.0, 0.0),
        )
    )
    parts.append(
        add_ico_sphere("ember", 0.075, (0, -0.275, 2.04), mats["ember"], subdivisions=1, scale=(1.2, 1.0, 0.7))
    )
    parts.append(add_cone("flame_base", 0.10, 0.18, (0, -0.275, 2.12), mats["flame"], vertices=7))
    parts.append(
        add_cone("flame_mid", 0.070, 0.22, (0, -0.270, 2.18), mats["flame_core"], vertices=6,
                 rotation=(0.10, 0.0, 0.0))
    )
    parts.append(
        add_cone("flame_tip", 0.036, 0.18, (0.01, -0.255, 2.28), mats["flame"], vertices=5,
                 rotation=(-0.18, 0.0, 0.0))
    )
    parts.append(
        add_cone("flame_side", 0.045, 0.14, (0.065, -0.245, 2.10), mats["flame"], vertices=5,
                 rotation=(0.0, 0.45, 0.0))
    )
    return parts


def build_chaine_murale(mats: Mats) -> list[bpy.types.Object]:
    """Chaîne murale et anneau (~1,7 case de haut), fixée au mur (+Y)."""
    parts: list[bpy.types.Object] = []
    parts.append(add_box("wall_plate", (0.16, 0.05, 0.22), (0, 0.06, 1.62), mats["iron_dark"]))
    parts.append(
        add_torus(
            "top_ring",
            0.085,
            0.022,
            (0, 0.02, 1.51),
            mats["metal"],
            major_segments=8,
            minor_segments=4,
            rotation=(math.pi * 0.5, 0.0, 0.0),
        )
    )
    for index in range(9):
        z = 1.40 - index * 0.115
        rotation = (math.pi * 0.5, 0.0, 0.0) if index % 2 == 0 else (0.0, math.pi * 0.5, 0.0)
        parts.append(
            add_torus(
                "link",
                0.075,
                0.020,
                (0, 0.02, z),
                mats["iron_dark"],
                major_segments=6,
                minor_segments=4,
                rotation=rotation,
            )
        )
    parts.append(
        add_torus(
            "shackle",
            0.105,
            0.026,
            (0, 0.02, 0.24),
            mats["metal"],
            major_segments=8,
            minor_segments=4,
            rotation=(math.pi * 0.5, 0.0, 0.0),
        )
    )
    return parts


def build_sarcophage(mats: Mats) -> list[bpy.types.Object]:
    """Sarcophage de pierre avec gisant (~1,3 x 0,8 case)."""
    parts: list[bpy.types.Object] = [
        _floor_patch("floor", (1.42, 0.94), (0, 0), mats["stone_dark"])
    ]
    parts.append(add_box("plinth", (1.16, 0.62, 0.10), (0, 0, 0.08), mats["stone_dark"]))
    parts.append(add_box("base", (1.04, 0.52, 0.50), (0, 0, 0.38), mats["stone"]))
    # Bandeaux sculptés.
    for y in (-0.27, 0.27):
        parts.append(add_box("band", (1.05, 0.025, 0.06), (0, y, 0.55), mats["stone_light"]))
    parts.append(add_box("lid", (1.12, 0.58, 0.16), (0, 0, 0.71), mats["stone_light"]))
    parts.append(add_box("lid_ridge", (1.00, 0.34, 0.08), (0, 0, 0.82), mats["stone"]))
    # Gisant : tête + corps + mains.
    parts.append(
        add_ico_sphere(
            "effigy_head", 0.10, (0, 0.16, 0.90), mats["stone_light"], subdivisions=1, scale=(0.9, 1.0, 0.9)
        )
    )
    parts.append(add_box("effigy_body", (0.22, 0.52, 0.07), (0, -0.06, 0.88), mats["stone_light"]))
    for x in (-0.14, 0.14):
        parts.append(add_box("effigy_arm", (0.07, 0.30, 0.05), (x, -0.02, 0.905), mats["stone"]))
    return parts


def build_pile_os(mats: Mats) -> list[bpy.types.Object]:
    """Pile d'os et de crânes (~1,3 x 1 case)."""
    parts: list[bpy.types.Object] = [
        _floor_patch("floor", (1.30, 1.00), (0, 0), mats["stone_dark"])
    ]
    bones = [
        (-0.26, -0.10, 0.10, 0.55, 0.35),
        (0.06, 0.12, 0.09, 0.62, -0.55),
        (0.30, -0.20, 0.15, 0.48, 1.05),
        (-0.06, -0.28, 0.20, 0.44, 0.15),
        (0.12, 0.24, 0.26, 0.36, 1.35),
    ]
    for index, (x, y, z, length, angle) in enumerate(bones):
        parts.append(
            add_cylinder(
                "bone",
                0.034,
                length,
                (x, y, z),
                mats["bone"],
                vertices=6,
                rotation=(math.pi * 0.5, 0.0, angle),
            )
        )
        for sign in (-0.5, 0.5):
            ex = x + math.sin(angle) * length * sign
            ey = y - math.cos(angle) * length * sign
            parts.append(
                add_ico_sphere(
                    "bone_end", 0.052, (ex, ey, z), mats["bone"], subdivisions=1, seed=70 + index
                )
            )
    for index, (x, y, z) in enumerate(((-0.08, 0.08, 0.26), (0.22, -0.04, 0.22))):
        parts.append(
            add_ico_sphere(
                "skull",
                0.13,
                (x, y, z),
                mats["bone"],
                subdivisions=1,
                scale=(1.0, 0.86, 0.92),
                jitter=0.012,
                seed=90 + index,
            )
        )
        parts.append(add_box("jaw", (0.14, 0.10, 0.06), (x, y - 0.10, z - 0.10), mats["bone_dark"]))
        for dx in (-0.045, 0.045):
            parts.append(
                add_box("socket", (0.04, 0.03, 0.035), (x + dx, y - 0.10, z + 0.02), mats["iron_dark"])
            )
    return parts


def build_herse(mats: Mats) -> list[bpy.types.Object]:
    """Herse / grille en fer relevable (~2,2 cases de large, 2,4 de haut)."""
    parts: list[bpy.types.Object] = [
        add_box("threshold", (2.20, 0.42, 0.06), (0, 0, 0.03), mats["stone_dark"])
    ]
    parts.append(add_box("top_beam", (2.05, 0.20, 0.20), (0, 0, 2.32), mats["iron_dark"]))
    parts.append(add_box("mid_beam", (1.98, 0.12, 0.09), (0, 0, 0.98), mats["metal"]))
    for index in range(6):
        x = -0.85 + index * 0.34
        parts.append(add_cylinder("bar", 0.042, 1.96, (x, 0, 1.27), mats["iron_dark"], vertices=6))
        parts.append(
            add_cone(
                "spike",
                0.07,
                0.24,
                (x, 0, 0.23),
                mats["metal"],
                vertices=6,
                rotation=(math.pi, 0.0, 0.0),
            )
        )
        parts.append(add_box("bar_cap", (0.10, 0.10, 0.06), (x, 0, 2.20), mats["metal"]))
    return parts


def build_buisson(mats: Mats) -> list[bpy.types.Object]:
    """Buisson touffu (~1,1 case) avec quelques fleurs."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (1.18, 1.08), mats["grass"], seed=61)
    ]
    clusters = [
        (0.0, 0.0, 0.30, 0.42, "leaf"),
        (0.24, -0.10, 0.24, 0.30, "leaf_light"),
        (-0.24, 0.12, 0.23, 0.28, "leaf_dark"),
        (0.02, 0.22, 0.22, 0.24, "leaf"),
    ]
    for index, (x, y, z, radius, material_key) in enumerate(clusters):
        parts.append(
            add_ico_sphere(
                "bush",
                radius,
                (x, y, z),
                mats[material_key],
                subdivisions=1,
                scale=(1.08, 1.0, 0.88),
                jitter=0.06,
                seed=120 + index,
            )
        )
    flower_positions = [
        (-0.16, -0.22, 0.52),
        (0.14, -0.16, 0.60),
        (0.28, 0.08, 0.42),
        (-0.28, 0.18, 0.42),
        (0.02, 0.25, 0.50),
        (-0.06, 0.02, 0.68),
    ]
    for index, (x, y, z) in enumerate(flower_positions):
        parts.append(
            add_ico_sphere(
                "flower",
                0.038,
                (x, y, z),
                mats["plaster_light"] if index % 2 == 0 else mats["glow"],
                subdivisions=1,
                seed=140 + index,
            )
        )
    return parts


def build_enseigne(mats: Mats) -> list[bpy.types.Object]:
    """Enseigne de taverne suspendue (~2,6 cases de haut), fixée au mur (+Y)."""
    parts: list[bpy.types.Object] = []
    parts.append(add_box("wall_plate", (0.18, 0.08, 0.62), (0, 0.14, 2.22), mats["iron_dark"]))
    parts.append(add_box("arm", (0.10, 0.98, 0.10), (0, -0.26, 2.46), mats["iron_dark"]))
    parts.append(
        add_box("brace", (0.08, 0.42, 0.08), (0, 0.02, 2.34), mats["metal"], rotation=(0.7, 0.0, 0.0))
    )
    # Deux courtes chaînes.
    for x in (-0.28, 0.28):
        for index in range(3):
            z = 2.36 - index * 0.10
            rotation = (math.pi * 0.5, 0.0, 0.0) if index % 2 == 0 else (0.0, math.pi * 0.5, 0.0)
            parts.append(
                add_torus(
                    "link",
                    0.045,
                    0.014,
                    (x, -0.62, z),
                    mats["metal"],
                    major_segments=6,
                    minor_segments=4,
                    rotation=rotation,
                )
            )
    # Panneau et cadre.
    parts.append(add_box("board", (0.95, 0.09, 0.62), (0, -0.62, 1.82), mats["wood_light"]))
    for z in (2.14, 1.50):
        parts.append(add_box("board_frame", (1.00, 0.11, 0.07), (0, -0.62, z), mats["wood_dark"]))
    for x in (-0.475, 0.475):
        parts.append(add_box("board_frame", (0.07, 0.11, 0.62), (x, -0.62, 1.82), mats["wood_dark"]))
    # Emblème peint : chope mousseuse.
    parts.append(add_box("emblem_mug", (0.24, 0.02, 0.22), (0, -0.665, 1.80), mats["glow"]))
    parts.append(
        add_torus(
            "emblem_handle",
            0.065,
            0.018,
            (0.17, -0.665, 1.78),
            mats["glow"],
            major_segments=8,
            minor_segments=4,
            rotation=(math.pi * 0.5, 0.0, 0.0),
        )
    )
    parts.append(add_box("emblem_foam", (0.27, 0.02, 0.07), (0, -0.665, 1.94), mats["plaster_light"]))
    return parts


# --------------------------------------------------------------------------- #
# Declarations des assets
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Variant:
    """Variante peu couteuse d'un asset : echelle et/ou teintes retouchees.

    ``suffix`` vide = asset de base. Les variantes evitent au MJ de regler une
    echelle a la main : petite/moyenne/grande maison, arbre d'automne, etc.
    """

    suffix: str = ""
    scale: float = 1.0
    palette: dict[str, str] = field(default_factory=dict)
    description: str = ""


@dataclass(frozen=True)
class AssetSpec:
    name: str
    category: str
    builder: Callable[[Mats], list[bpy.types.Object]]
    description: str
    tags: tuple[str, ...] = field(default_factory=tuple)
    variants: tuple[Variant, ...] = field(default_factory=tuple)
    anchor: str = "base"  # "base" (defaut) ou "wall" (objet mural)


def asset_name(spec: AssetSpec, variant: Variant) -> str:
    return spec.name if not variant.suffix else f"{spec.name}_{variant.suffix}"


def iter_jobs(specs: list[AssetSpec]) -> list[tuple[AssetSpec, Variant, str]]:
    """Developpe les specs en taches concretes (spec, variante, nom final)."""
    jobs: list[tuple[AssetSpec, Variant, str]] = []
    for spec in specs:
        for variant in spec.variants or (Variant(),):
            jobs.append((spec, variant, asset_name(spec, variant)))
    return jobs


ASSETS: list[AssetSpec] = [
    AssetSpec(
        "maison",
        "buildings",
        build_maison,
        "Maison de village a colombages, toit a deux pans, cheminee.",
        ("habitation", "village", "toit"),
        variants=(
            Variant(
                "petite",
                0.82,
                {
                    "plaster": "#cdbb98",
                    "plaster_light": "#dcccaa",
                    "roof": "#4c5a66",
                    "roof_dark": "#3b4650",
                },
                "Petite maison de village, toit d'ardoise bleu-gris.",
            ),
            Variant(
                "",
                1.0,
                {},
                "Maison de village (taille standard), toit terre cuite.",
            ),
            Variant(
                "grande",
                1.16,
                {"plaster": "#e2d4b4", "roof": "#9a5a45", "roof_dark": "#7a4536"},
                "Grande maison / auberge, toit terre cuite.",
            ),
        ),
    ),
    AssetSpec(
        "tour",
        "buildings",
        build_tour,
        "Tour de guet ronde crenelee, porte et meurtrieres.",
        ("defense", "guet", "village"),
        variants=(
            Variant("", 1.0, {}, "Tour de guet standard."),
            Variant(
                "grande",
                1.16,
                {"stone": "#8f8a7f", "stone_light": "#a49e92"},
                "Tour de guet haute.",
            ),
        ),
    ),
    AssetSpec(
        "pont",
        "props",
        build_pont,
        "Pont de pierre et bois, tablier sureleve et garde-corps.",
        ("passage", "riviere", "elevation"),
    ),
    AssetSpec(
        "caisse",
        "props",
        build_caisse,
        "Caisse en bois renforcee, planche diagonale.",
        ("mobilier", "marchandise", "village"),
        variants=(
            Variant("", 1.0, {}, "Caisse standard."),
            Variant(
                "grande",
                1.26,
                {"wood_light": "#96704a"},
                "Grande caisse / caisse de cargaison.",
            ),
        ),
    ),
    AssetSpec(
        "palissade",
        "props",
        build_palissade,
        "Palissade de planches pointees, deux traverses (module 2 cases).",
        ("defense", "cloture", "camp"),
    ),
    AssetSpec(
        "puits",
        "props",
        build_puits,
        "Puits de village en pierre, toit, seau et manivelle.",
        ("eau", "village", "point d'interet"),
    ),
    AssetSpec(
        "arbre",
        "vegetation",
        build_arbre,
        "Arbre feuillu a houppes irregulieres, tronc cylindrique.",
        ("nature", "foret", "decor"),
        variants=(
            Variant("", 1.0, {}, "Arbre vert (standard)."),
            Variant(
                "automne",
                1.0,
                {
                    "leaf": "#8a6a44",
                    "leaf_light": "#9a784c",
                    "leaf_dark": "#6f5538",
                },
                "Arbre d'automne (teintes ocre).",
            ),
        ),
    ),
    AssetSpec(
        "rocher",
        "terrain",
        build_rocher,
        "Rocher basse-poly en trois blocs, taches de mousse.",
        ("nature", "obstacle", "decor"),
    ),
    AssetSpec(
        "mur",
        "buildings",
        build_mur,
        "Mur de pierre droit (~2 cases) : assises decalees et dalles de couronnement.",
        ("defense", "enceinte", "village"),
    ),
    AssetSpec(
        "mur_coin",
        "buildings",
        build_mur_coin,
        "Coin de mur en L (~1,8 case) pour fermer une enceinte.",
        ("defense", "enceinte", "angle"),
    ),
    AssetSpec(
        "barriere",
        "props",
        build_barriere,
        "Barriere en bois (module 2 cases) : poteaux, lisses et jambe de force.",
        ("cloture", "chemin", "campagne"),
    ),
    AssetSpec(
        "etal_marche",
        "props",
        build_etal_marche,
        "Etal de marche (~2 cases) : comptoir, auvent a rayures et marchandises.",
        ("commerce", "marche", "village"),
    ),
    AssetSpec(
        "tonneau",
        "props",
        build_tonneau,
        "Tonneau en bois cercle de metal (~0,8 case).",
        ("mobilier", "marchandise", "village"),
    ),
    AssetSpec(
        "lanterne",
        "props",
        build_lanterne,
        "Lanterne sur poteau (~2,3 cases de haut), fanal a vitres chaudes.",
        ("eclairage", "rue", "village"),
    ),
    AssetSpec(
        "banc",
        "props",
        build_banc,
        "Banc en bois (~1,1 case) pour place ou jardin.",
        ("mobilier", "village", "repos"),
    ),
    AssetSpec(
        "panneau",
        "props",
        build_panneau,
        "Panneau indicateur en bois (~1,9 case de haut), deux fleches.",
        ("signalisation", "chemin", "village"),
    ),
    AssetSpec(
        "charrette",
        "props",
        build_charrette,
        "Charrette en bois (~1,5 case) : caisse, roues, essieu et brancards.",
        ("transport", "marchandise", "village"),
    ),
    AssetSpec(
        "botte_foin",
        "props",
        build_botte_foin,
        "Botte de foin liee (~0,9 case), brins qui depassent.",
        ("campagne", "ferme", "decor"),
    ),
    AssetSpec(
        "table_tabourets",
        "props",
        build_table_tabourets,
        "Table ronde de taverne avec trois tabourets, chope et bouteille (~1,7 case).",
        ("taverne", "mobilier", "interieur"),
    ),
    AssetSpec(
        "comptoir",
        "props",
        build_comptoir,
        "Comptoir de taverne et arriere-bar a etageres, bouteilles et chopes (~2,3 cases).",
        ("taverne", "commerce", "interieur"),
    ),
    AssetSpec(
        "tonneau_couche",
        "props",
        build_tonneau_couche,
        "Tonneau couche sur cales avec robinet (~1 case).",
        ("taverne", "marchandise", "interieur"),
    ),
    AssetSpec(
        "tapis",
        "props",
        build_tapis,
        "Tapis de taverne a motif losange (~1,9 x 1,2 case), plaque plate opaque.",
        ("taverne", "textile", "interieur"),
    ),
    AssetSpec(
        "lit",
        "props",
        build_lit,
        "Lit simple de taverne : bois, matelas, couverture et oreiller (~1,4 x 2 cases).",
        ("taverne", "mobilier", "interieur"),
    ),
    AssetSpec(
        "torche_murale",
        "props",
        build_torche_murale,
        "Torche murale emissive : support fer, manche bois et flamme (~2,4 cases de haut).",
        ("donjon", "eclairage", "interieur"),
        anchor="wall",
    ),
    AssetSpec(
        "chaine_murale",
        "props",
        build_chaine_murale,
        "Chaine murale a maillons et anneau, accrochee au mur (~1,7 case de haut).",
        ("donjon", "mobilier", "interieur"),
        anchor="wall",
    ),
    AssetSpec(
        "sarcophage",
        "props",
        build_sarcophage,
        "Sarcophage de pierre avec gisant et bandeaux sculptes (~1,3 x 0,8 case).",
        ("donjon", "funeraire", "interieur"),
    ),
    AssetSpec(
        "pile_os",
        "props",
        build_pile_os,
        "Pile d'os et de cranes low-poly (~1,3 x 1 case).",
        ("donjon", "funeraire", "interieur"),
    ),
    AssetSpec(
        "herse",
        "buildings",
        build_herse,
        "Herse / grille en fer relevable, pointes vers le bas (~2,2 cases de large).",
        ("donjon", "defense", "passage"),
    ),
    AssetSpec(
        "buisson",
        "vegetation",
        build_buisson,
        "Buisson touffu avec quelques fleurs (~1,1 case).",
        ("nature", "decor", "exterieur"),
    ),
    AssetSpec(
        "enseigne",
        "props",
        build_enseigne,
        "Enseigne de taverne suspendue, potence fer et panneau peint (~2,6 cases de haut).",
        ("taverne", "signalisation", "exterieur"),
        anchor="wall",
    ),
]


# --------------------------------------------------------------------------- #
# CLI / execution
# --------------------------------------------------------------------------- #


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="build_prototypes.py",
        description="Genere les prototypes low-poly 2.5D (GLB + vignettes).",
    )
    parser.add_argument("--only", nargs="+", default=None, metavar="NOM")
    parser.add_argument("--out-root", default=str(oq.OBJECTS3D_ROOT))
    parser.add_argument("--engine", choices=["eevee", "cycles"], default="eevee")
    parser.add_argument("--samples", type=int, default=32)
    parser.add_argument("--thumb-size", type=int, default=THUMB_SIZE)
    parser.add_argument("--no-thumbs", action="store_true")
    parser.add_argument("--no-export", action="store_true")
    parser.add_argument("--no-outline", action="store_true")
    parser.add_argument("--no-manifest", action="store_true")
    return parser.parse_args(argv)


def _detail_seed(name: str) -> int:
    """Graine stable (build reproductible) derivee du nom d'asset."""
    return sum((index + 1) * ord(char) for index, char in enumerate(name)) % 9973


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    out_root = Path(args.out_root).resolve()

    jobs = iter_jobs(ASSETS)
    if args.only:
        wanted = {oq.slugify(n) for n in args.only}
        jobs = [
            (spec, variant, name)
            for spec, variant, name in jobs
            if spec.name in wanted or name in wanted
        ]
        known = {spec.name for spec in ASSETS} | {job[2] for job in iter_jobs(ASSETS)}
        missing = wanted - known
        if missing:
            log(f"[ERREUR] assets inconnus: {', '.join(sorted(missing))}")
            log(f"         disponibles: {', '.join(sorted(known))}")
            return 2
        if not jobs:
            log("[ERREUR] aucun asset a generer")
            return 2

    log("=" * 78)
    log("OpenQuest / Blender - generation des prototypes 2.5D")
    log(f"Blender {bpy.app.version_string} - sortie: {out_root}")
    log(
        f"Assets: {len(jobs)} (variantes incluses) - moteur vignettes: {args.engine} "
        f"({args.samples} samples, {args.thumb_size}px)"
    )
    log("=" * 78)

    manifest: list[dict[str, object]] = []
    failures: list[str] = []
    engine_used: str | None = None

    for spec, variant, name in jobs:
        try:
            reset_scene()
            mats = material_palette(
                variant.palette, prefix=f"{name}_", emissive={"lamp": 1.1, "flame": 0.9, "flame_core": 1.6}
            )
            parts = spec.builder(mats)
            obj = finalize_asset(parts, name, anchor=spec.anchor)
            if variant.scale != 1.0:
                obj.scale = (variant.scale, variant.scale, variant.scale)
                apply_transforms(obj)
                normalize_asset(obj, name, anchor=spec.anchor)

            # Detail 2.5D : subdivision legere (place pour les vertex colors),
            # AO + mottling cuits, contour encre "inverted hull".
            subdivide_long_edges(obj, max_length=0.5, max_passes=2)
            triangulate_mesh(obj)
            bake_vertex_colors(
                obj,
                seed=_detail_seed(name),
                ao_distance=0.32,
                ao_samples=28,
                ao_strength=0.55,
                mottle_strength=0.09,
                min_value=0.55,
            )
            objects: list[bpy.types.Object] = [obj]
            if not args.no_outline:
                ink = make_material(
                    f"{name}_ink", DEFAULT_PALETTE["ink"], roughness=1.0
                )
                objects.append(
                    build_outline(obj, ink, thickness=OUTLINE_THICKNESS)
                )

            triangles_base = triangle_count(obj)
            triangles = triangles_base + sum(
                triangle_count(extra) for extra in objects[1:]
            )
            if triangles > TRIANGLE_BUDGET:
                raise ValueError(
                    f"{name}: {triangles} triangles (contour inclus) > budget "
                    f"{TRIANGLE_BUDGET}"
                )
            dims = object_dimensions(objects)
            mins, maxs = oq.object_bounds(objects)
            height_above_floor = round(maxs.z, 3) if spec.anchor == "wall" else round(dims[2], 3)
            vertices = sum(len(item.data.vertices) for item in objects)

            category_dir_path = out_root / spec.category
            glb_path = category_dir_path / f"{name}.glb"
            thumb_path = category_dir_path / f"{name}{oq.THUMB_SUFFIX}"

            if not args.no_export:
                export_glb(glb_path, objects)
            # A brancher APRES l'export : l'exporteur deduit baseColorFactor du
            # noeud Base Color, la multiplication vertex color n'est que pour
            # les vignettes Blender.
            enable_vertex_color_preview([obj])
            if not args.no_thumbs:
                _, engine_used = render_thumbnail(
                    thumb_path,
                    objects,
                    engine=args.engine,
                    samples=args.samples,
                    size=args.thumb_size,
                )

            manifest.append(
                {
                    "name": name,
                    "base": spec.name,
                    "variant": variant.suffix or "base",
                    "category": spec.category,
                    "glb": f"{spec.category}/{name}.glb",
                    "thumb": f"{spec.category}/{name}{oq.THUMB_SUFFIX}",
                    "description": " ".join(
                        part for part in (spec.description, variant.description) if part
                    ),
                    "tags": list(spec.tags),
                    "dimensions_cells": [round(d, 3) for d in dims],
                    "height_above_floor": height_above_floor,
                    "anchor": spec.anchor,
                    "triangles": triangles,
                    "triangles_base": triangles_base,
                    "vertices": vertices,
                    "vertex_colors": "AO + mottling (COLOR_0)",
                    "outline": not args.no_outline,
                }
            )
            dims_text = " x ".join(f"{d:.2f}" for d in dims)
            glb_size = glb_path.stat().st_size / 1024.0 if glb_path.is_file() else 0.0
            thumb_size = (
                thumb_path.stat().st_size / 1024.0 if thumb_path.is_file() else 0.0
            )
            log(
                f"[OK] {spec.category}/{name}.glb  "
                f"{triangles} tris ({triangles_base} mesh + contour)  "
                f"{dims_text} cases  "
                f"({glb_size:.1f} Ko)"
                + (
                    ""
                    if args.no_thumbs
                    else f"  vignette {thumb_size:.1f} Ko"
                )
            )
        except Exception as exc:  # noqa: BLE001 - on continue les autres assets
            failures.append(f"{spec.category}/{name}: {exc}")
            log(f"[ECHEC] {spec.category}/{name}: {exc}")

    # Manifeste informatif (l'editeur peut scanner les dossiers sans lui).
    if not args.no_manifest and not args.no_export and manifest:
        manifest_path = out_root / "manifest.json"
        # Un build partiel (--only) ne doit pas ecraser le manifeste complet :
        # on fusionne avec les entrees deja presentes sur le disque.
        existing: dict[str, dict[str, object]] = {}
        if args.only and manifest_path.is_file():
            try:
                previous = json.loads(manifest_path.read_text(encoding="utf-8"))
                for item in previous.get("assets", []):
                    if isinstance(item, dict) and item.get("name"):
                        existing[str(item["name"])] = item
            except (json.JSONDecodeError, OSError):
                existing = {}
        for item in manifest:
            existing[str(item["name"])] = item
        merged = sorted(
            existing.values(),
            key=lambda item: (str(item.get("category")), str(item.get("name"))),
        )
        payload = {
            "generated_by": "tools/blender/build_prototypes.py",
            "blender_version": bpy.app.version_string,
            "unit": "1 unite = 1 case de carte",
            "forward_axis_gltf": "+Z",
            "assets": merged,
        }
        manifest_path.write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        log(f"[OK] manifeste: {manifest_path} ({len(merged)} assets)")

    log("-" * 78)
    if engine_used:
        log(f"Moteur de vignette effectif: {engine_used}")
    log(
        f"BUILD_RESULT ok={len(manifest)} echecs={len(failures)}"
        + ("" if not failures else f" -> {', '.join(failures)}")
    )
    log("=" * 78)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main(oq.cli_argv()))


