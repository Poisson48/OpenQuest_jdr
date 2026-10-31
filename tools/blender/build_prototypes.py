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
# Kit v4 : bâtiments varies, détails de toit, figurines PNJ
# --------------------------------------------------------------------------- #


def _npc_base(mats: Mats, seed: int, radius: float = 0.34) -> list[bpy.types.Object]:
    """Socle rond discret (sans jupe) : utilisable en intérieur comme en extérieur."""
    parts: list[bpy.types.Object] = []
    parts.append(add_cylinder("socle", radius, 0.06, (0, 0, 0.03), mats["stone_dark"], vertices=12))
    parts.append(
        add_cylinder("socle_top", radius - 0.035, 0.02, (0, 0, 0.07), mats["stone_light"], vertices=12)
    )
    return parts


def _npc_face(parts: list[bpy.types.Object], mats: Mats, z: float) -> None:
    """Yeux et nez peints pour donner un visage aux figurines."""
    for x in (-0.055, 0.055):
        parts.append(add_box("eye", (0.028, 0.018, 0.028), (x, -0.125, z + 0.01), mats["iron_dark"]))
    parts.append(add_box("nose", (0.028, 0.035, 0.025), (0, -0.145, z - 0.02), mats["skin_dark"]))


def build_forge(mats: Mats) -> list[bpy.types.Object]:
    """Forge de forgeron (~2,3 cases) : pierre, toit, grosse cheminée, enclume."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.50, 2.25), mats["grass"], seed=201)
    ]
    parts.append(add_box("plinth", (1.95, 1.70, 0.16), (0, 0, 0.08), mats["stone_dark"]))
    parts.append(add_box("walls", (1.80, 1.55, 1.05), (0, 0, 0.16 + 0.525), mats["stone"]))
    for x in (-0.85, 0.85):
        for y in (-0.72, 0.72):
            parts.append(add_box("post", (0.10, 0.10, 1.05), (x, y, 0.685), mats["wood_dark"]))
    parts.append(add_box("belt", (1.86, 1.62, 0.09), (0, 0, 0.92), mats["wood_dark"]))
    parts.append(
        gable_roof("roof", width=2.00, depth=1.85, height=0.62, base_z=1.21, material=mats["roof_slate"])
    )
    parts.append(add_box("eave", (2.06, 0.10, 0.10), (0, -0.78, 1.17), mats["wood_dark"]))
    parts.append(add_box("ridge", (1.94, 0.11, 0.08), (0, 0, 1.81), mats["iron_dark"]))
    # Grosse cheminée de forge.
    parts.append(add_box("chimney", (0.42, 0.42, 1.25), (0.55, 0.30, 1.85), mats["stone"]))
    parts.append(add_box("chimney_cap", (0.50, 0.50, 0.08), (0.55, 0.30, 2.51), mats["stone_dark"]))
    # Gueule de forge chaude et linteau.
    parts.append(add_box("forge_mouth", (0.55, 0.10, 0.45), (0, -0.80, 0.58), mats["ember"]))
    parts.append(add_box("lintel", (0.66, 0.12, 0.10), (0, -0.80, 0.86), mats["stone_light"]))
    parts.append(add_box("door", (0.34, 0.08, 0.62), (0.60, -0.80, 0.47), mats["wood_dark"]))
    # Enclume sur billot + tonnelet de trempe.
    parts.append(add_cylinder("stump", 0.16, 0.28, (-0.58, -0.92, 0.14), mats["wood_dark"], vertices=8))
    parts.append(add_box("anvil_body", (0.30, 0.16, 0.10), (-0.58, -0.92, 0.33), mats["iron_dark"]))
    parts.append(
        add_cone(
            "anvil_horn", 0.055, 0.16, (-0.40, -0.92, 0.35), mats["metal"], vertices=6,
            rotation=(0.0, math.pi * 0.5, 0.0),
        )
    )
    parts.append(add_cylinder("quench", 0.13, 0.26, (0.72, -0.86, 0.13), mats["wood"], vertices=10))
    parts.append(add_cylinder("quench_water", 0.11, 0.03, (0.72, -0.86, 0.265), mats["water"], vertices=10))
    return parts


def build_chapelle(mats: Mats) -> list[bpy.types.Object]:
    """Petite chapelle de village (~2,3 cases) : clocher, flèche, vitraux."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.35, 2.65), mats["grass"], seed=202)
    ]
    parts.append(add_box("plinth", (1.90, 2.20, 0.16), (0, 0, 0.08), mats["stone_dark"]))
    parts.append(add_box("nave", (1.55, 1.95, 1.45), (0, 0, 0.16 + 0.725), mats["stone"]))
    parts.append(
        gable_roof("roof", width=1.85, depth=2.25, height=0.58, base_z=1.61, material=mats["roof_slate"])
    )
    parts.append(add_box("ridge", (1.70, 0.10, 0.07), (0, 0, 2.17), mats["iron_dark"]))
    # Clocher sur l'angle avant gauche.
    parts.append(add_box("tower", (0.62, 0.62, 2.10), (-0.55, -0.80, 1.21), mats["stone"]))
    parts.append(add_box("tower_rim", (0.70, 0.70, 0.10), (-0.55, -0.80, 2.31), mats["stone_light"]))
    parts.append(add_box("bell_arch", (0.22, 0.06, 0.32), (-0.55, -1.12, 2.03), mats["iron_dark"]))
    parts.append(add_box("bell", (0.13, 0.09, 0.20), (-0.55, -1.13, 1.98), mats["metal"]))
    parts.append(
        add_cone(
            "spire", 0.46, 0.72, (-0.55, -0.80, 2.72), mats["roof_slate"], vertices=4,
            rotation=(0.0, 0.0, math.pi * 0.25),
        )
    )
    parts.append(add_box("cross_v", (0.04, 0.04, 0.30), (-0.55, -0.80, 3.23), mats["metal"]))
    parts.append(add_box("cross_h", (0.18, 0.04, 0.04), (-0.55, -0.80, 3.31), mats["metal"]))
    # Entrée, marches, vitraux.
    parts.append(add_box("door", (0.34, 0.08, 0.62), (0.28, -1.01, 0.47), mats["wood_dark"]))
    parts.append(add_box("door_frame", (0.42, 0.10, 0.07), (0.28, -1.01, 0.82), mats["stone_light"]))
    parts.append(add_box("step", (0.52, 0.30, 0.07), (0.28, -1.13, 0.035), mats["stone_dark"]))
    for x in (-0.18, 0.52):
        parts.append(add_box("stained_glass", (0.16, 0.06, 0.32), (x, -1.01, 0.95), mats["glow"]))
        parts.append(add_box("glass_frame", (0.20, 0.08, 0.05), (x, -1.01, 1.13), mats["stone_light"]))
    parts.append(add_box("side_window", (0.06, 0.16, 0.30), (0.79, 0.20, 0.95), mats["glow"]))
    return parts


def build_grange(mats: Mats) -> list[bpy.types.Object]:
    """Grange à colombages (~2,9 x 3,2 cases) : grandes portes, toit de bois."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.95, 3.20), mats["grass"], seed=203)
    ]
    parts.append(add_box("plinth", (2.55, 2.85, 0.22), (0, 0, 0.11), mats["stone_dark"]))
    parts.append(add_box("body", (2.42, 2.70, 1.45), (0, 0, 0.945), mats["wood"]))
    # Bardage : planches verticales sur la façade avant.
    for index in range(9):
        x = -1.04 + index * 0.26
        material = mats["wood_light"] if index % 2 == 0 else mats["wood"]
        parts.append(add_box("plank", (0.24, 0.05, 1.33), (x, -1.37, 0.945), material))
    for x in (-1.20, 1.20):
        for y in (-1.34, 1.34):
            parts.append(add_box("corner_post", (0.12, 0.12, 1.45), (x, y, 0.945), mats["wood_dark"]))
    parts.append(
        gable_roof("roof", width=2.80, depth=3.10, height=0.78, base_z=1.67, material=mats["roof_dark"])
    )
    parts.append(add_box("ridge", (2.66, 0.12, 0.09), (0, 0, 2.41), mats["wood_dark"]))
    # Grande porte à double battant + croisillons.
    parts.append(add_box("door", (1.10, 0.08, 1.15), (0, -1.40, 0.80), mats["wood_dark"]))
    parts.append(add_box("door_beam", (1.16, 0.06, 0.09), (0, -1.44, 1.38), mats["wood"]))
    for rotation in (0.6, -0.6):
        parts.append(
            add_box("door_brace", (1.25, 0.05, 0.08), (0, -1.45, 0.80), mats["wood"], rotation=(0.0, rotation, 0.0))
        )
    # Petite lucarne de fenil côté droit.
    parts.append(add_box("loft_door", (0.34, 0.06, 0.34), (1.21, -0.40, 1.42), mats["wood_light"]))
    return parts


def build_ecurie(mats: Mats) -> list[bpy.types.Object]:
    """Écurie ouverte (~2,9 x 2,4 cases) : stalles, auvent, abreuvoir."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.95, 2.45), mats["grass"], seed=204)
    ]
    parts.append(add_box("plinth", (2.55, 2.10, 0.16), (0, 0, 0.08), mats["stone_dark"]))
    parts.append(add_box("back_wall", (2.45, 0.16, 1.45), (0, 1.00, 0.885), mats["plaster"]))
    for x in (-1.20, 1.20):
        parts.append(add_box("side_wall", (0.14, 1.95, 1.45), (x, -0.05, 0.885), mats["wood"]))
    for x in (-1.05, -0.35, 0.35, 1.05):
        parts.append(add_box("front_post", (0.12, 0.12, 1.55), (x, -0.95, 0.935), mats["wood_dark"]))
    for x in (-0.40, 0.40):
        parts.append(add_box("stall_divider", (0.08, 1.20, 1.10), (x, 0.10, 0.71), mats["wood"]))
    for y in (-0.88, 0.30):
        parts.append(add_box("tie_beam", (2.30, 0.10, 0.12), (0, y, 1.60), mats["wood_dark"]))
    parts.append(
        gable_roof("roof", width=2.75, depth=2.30, height=0.65, base_z=1.66, material=mats["roof"])
    )
    parts.append(add_box("ridge", (2.62, 0.11, 0.08), (0, 0, 2.29), mats["wood_dark"]))
    # Abreuvoir et foin.
    parts.append(add_box("trough", (0.90, 0.28, 0.18), (0.60, -0.65, 0.25), mats["wood_dark"]))
    parts.append(add_box("trough_water", (0.80, 0.20, 0.03), (0.60, -0.65, 0.355), mats["water"]))
    parts.append(add_box("hay", (0.55, 0.35, 0.30), (-0.72, -0.58, 0.31), mats["hay"]))
    parts.append(add_box("hay_top", (0.50, 0.30, 0.08), (-0.72, -0.58, 0.50), mats["hay_light"]))
    return parts


def build_maison_etage(mats: Mats) -> list[bpy.types.Object]:
    """Maison à étage (~2 x 2 cases) : encorbellement, colombages, toit."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.30, 2.10), mats["grass"], seed=205)
    ]
    parts.append(add_box("plinth", (2.00, 1.80, 0.16), (0, 0, 0.08), mats["stone_dark"]))
    parts.append(add_box("ground", (1.75, 1.55, 1.15), (0, 0, 0.735), mats["plaster"]))
    parts.append(add_box("belt", (1.88, 1.68, 0.10), (0, 0, 1.35), mats["wood_dark"]))
    parts.append(add_box("upper", (1.92, 1.72, 0.95), (0, 0, 1.885), mats["plaster_light"]))
    for x in (-0.90, 0.90):
        for y in (-0.81, 0.81):
            parts.append(add_box("upper_post", (0.09, 0.09, 0.95), (x, y, 1.885), mats["wood_dark"]))
    parts.append(
        gable_roof("roof", width=2.12, depth=1.96, height=0.55, base_z=2.36, material=mats["roof"])
    )
    parts.append(add_box("eave", (2.18, 0.10, 0.09), (0, -0.82, 2.32), mats["wood_dark"]))
    parts.append(add_box("ridge", (2.00, 0.11, 0.08), (0, 0, 2.88), mats["wood_dark"]))
    parts.append(add_box("chimney", (0.22, 0.22, 0.75), (0.58, 0.28, 2.72), mats["stone"]))
    parts.append(add_box("chimney_cap", (0.28, 0.28, 0.07), (0.58, 0.28, 3.11), mats["stone_dark"]))
    # Porte et fenêtres (deux niveaux).
    parts.append(add_box("door", (0.32, 0.08, 0.62), (-0.25, -0.80, 0.47), mats["wood_dark"]))
    parts.append(add_box("step", (0.46, 0.24, 0.06), (-0.25, -0.90, 0.03), mats["stone_dark"]))
    for x in (0.20, 0.55):
        parts.append(add_box("window_low", (0.22, 0.06, 0.24), (x, -0.80, 0.98), mats["glow"]))
        parts.append(add_box("shutter", (0.06, 0.05, 0.28), (x - 0.16, -0.81, 0.98), mats["wood"]))
        parts.append(add_box("shutter", (0.06, 0.05, 0.28), (x + 0.16, -0.81, 0.98), mats["wood"]))
    for x in (-0.50, 0.32):
        parts.append(add_box("window_up", (0.22, 0.06, 0.24), (x, -0.89, 1.80), mats["glow"]))
        parts.append(add_box("window_frame", (0.28, 0.07, 0.05), (x, -0.89, 1.95), mats["wood_dark"]))
    parts.append(add_box("side_window", (0.06, 0.22, 0.24), (0.98, 0.10, 1.80), mats["glow"]))
    return parts


def build_manoir(mats: Mats) -> list[bpy.types.Object]:
    """Manoir / petit château (~3,5 x 2,9 cases) : tourelle, aile, porche."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (3.50, 2.95), mats["grass"], seed=206)
    ]
    parts.append(add_box("plinth", (2.65, 2.25, 0.18), (0, 0, 0.09), mats["stone_dark"]))
    parts.append(add_box("ground", (2.30, 1.90, 1.05), (0, 0, 0.705), mats["stone"]))
    parts.append(add_box("upper", (2.20, 1.80, 1.00), (0, 0, 1.73), mats["plaster"]))
    parts.append(
        gable_roof("roof", width=2.55, depth=2.15, height=0.85, base_z=2.23, material=mats["roof_slate"])
    )
    parts.append(add_box("ridge", (2.40, 0.12, 0.09), (0, 0, 3.03), mats["iron_dark"]))
    # Tourelle d'angle.
    parts.append(add_cylinder("turret", 0.44, 2.45, (-1.15, -0.72, 1.405), mats["stone"], vertices=12))
    parts.append(add_cylinder("turret_rim", 0.50, 0.10, (-1.15, -0.72, 2.65), mats["stone_light"], vertices=12))
    parts.append(
        add_cone(
            "turret_roof", 0.53, 0.85, (-1.15, -0.72, 3.10), mats["roof_slate"], vertices=12
        )
    )
    parts.append(
        add_ico_sphere("finial", 0.08, (-1.15, -0.72, 3.55), mats["metal"], subdivisions=1)
    )
    # Aile basse.
    parts.append(add_box("wing", (0.80, 1.45, 1.35), (1.52, 0.25, 0.855), mats["plaster"]))
    parts.append(
        gable_roof("wing_roof", width=1.00, depth=1.65, height=0.45, base_z=1.53, material=mats["roof_slate"])
    )
    parts.append(add_box("wing_ridge", (0.90, 0.10, 0.07), (1.52, 0.25, 1.94), mats["iron_dark"]))
    # Porche d'entrée et marches.
    parts.append(add_box("porch", (0.95, 0.45, 0.95), (0, -1.05, 0.475), mats["stone_light"]))
    parts.append(add_box("porch_roof", (1.10, 0.60, 0.12), (0, -1.05, 1.00), mats["stone"]))
    parts.append(add_box("steps", (1.15, 0.55, 0.10), (0, -1.32, 0.05), mats["stone_dark"]))
    parts.append(add_box("door", (0.40, 0.08, 0.68), (0, -1.29, 0.44), mats["wood_dark"]))
    # Fenêtres, bannières.
    for x in (-0.72, -0.25, 0.32, 0.80):
        parts.append(add_box("window", (0.20, 0.06, 0.30), (x, -0.98, 1.72), mats["glow"]))
        parts.append(add_box("window_frame", (0.26, 0.07, 0.05), (x, -0.98, 1.89), mats["stone_light"]))
    for x in (-0.95, 0.95):
        parts.append(add_box("banner", (0.20, 0.05, 0.60), (x, -0.92, 1.62), mats["cloth"]))
        parts.append(add_box("banner_bar", (0.28, 0.06, 0.05), (x, -0.92, 1.94), mats["metal"]))
    parts.append(add_box("turret_slit", (0.07, 0.10, 0.28), (-1.15, -1.15, 1.55), mats["iron_dark"]))
    return parts


def build_tour_guet_bois(mats: Mats) -> list[bpy.types.Object]:
    """Tour de guet en bois (~1,8 case, 3,6 de haut) : plateforme, garde-corps."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (1.85, 1.85), mats["grass"], seed=207)
    ]
    for x in (-0.55, 0.55):
        for y in (-0.55, 0.55):
            parts.append(add_box("leg", (0.14, 0.14, 2.30), (x, y, 1.15), mats["wood_dark"]))
    # Contreventements en X sur les quatre faces (longue barre verticale inclinee).
    for y in (-0.56, 0.56):
        for angle in (0.8, -0.8):
            parts.append(
                add_box("brace", (0.07, 0.07, 1.45), (0, y, 1.15), mats["wood"], rotation=(0.0, angle, 0.0))
            )
    for x in (-0.56, 0.56):
        for angle in (0.8, -0.8):
            parts.append(
                add_box("brace", (0.07, 0.07, 1.45), (x, 0, 1.15), mats["wood"], rotation=(angle, 0.0, 0.0))
            )
    parts.append(add_box("platform", (1.55, 1.55, 0.14), (0, 0, 2.44), mats["wood"]))
    for x in (-0.62, 0.62):
        for y in (-0.62, 0.62):
            parts.append(add_box("rail_post", (0.07, 0.07, 0.55), (x, y, 2.78), mats["wood_dark"]))
    for x in (-0.62, 0.62):
        parts.append(add_box("rail", (0.06, 1.32, 0.08), (x, 0, 3.02), mats["wood_light"]))
        parts.append(add_box("rail_mid", (0.06, 1.32, 0.06), (x, 0, 2.86), mats["wood_dark"]))
    for y in (-0.62, 0.62):
        parts.append(add_box("rail", (1.32, 0.06, 0.08), (0, y, 3.02), mats["wood_light"]))
        parts.append(add_box("rail_mid", (1.32, 0.06, 0.06), (0, y, 2.86), mats["wood_dark"]))
    parts.append(
        gable_roof("roof", width=1.70, depth=1.70, height=0.42, base_z=3.10, material=mats["roof_slate"])
    )
    # Échelle d'accès.
    for x in (-0.12, 0.12):
        parts.append(add_box("ladder_rail", (0.05, 0.05, 2.30), (x, -0.66, 1.15), mats["wood"]))
    for index in range(6):
        parts.append(add_box("ladder_rung", (0.30, 0.05, 0.05), (0, -0.66, 0.35 + index * 0.35), mats["wood_dark"]))
    return parts


def build_marche_couvert(mats: Mats) -> list[bpy.types.Object]:
    """Marché couvert (~3,2 x 2,7 cases) : poteaux, toit, étals, lanternes."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (3.15, 2.70), mats["dirt"], seed=208)
    ]
    parts.append(add_box("floor", (2.90, 2.45, 0.06), (0, 0, 0.03), mats["stone_dark"]))
    for x in (-1.15, 0.0, 1.15):
        for y in (-1.00, 1.00):
            parts.append(add_box("post", (0.13, 0.13, 2.25), (x, y, 1.125), mats["wood_dark"]))
    for y in (-1.00, 1.00):
        parts.append(add_box("beam", (2.90, 0.12, 0.14), (0, y, 2.28), mats["wood_dark"]))
    parts.append(
        gable_roof("roof", width=3.05, depth=2.60, height=0.62, base_z=2.31, material=mats["roof"])
    )
    parts.append(add_box("ridge", (2.90, 0.12, 0.09), (0, 0, 2.88), mats["wood_dark"]))
    # Deux étals sous le marché.
    for x in (-0.72, 0.72):
        parts.append(add_box("stall_top", (0.95, 0.55, 0.10), (x, -0.52, 0.88), mats["wood_light"]))
        for leg_x in (-0.35, 0.35):
            parts.append(add_box("stall_leg", (0.08, 0.45, 0.85), (x + leg_x, -0.52, 0.425), mats["wood_dark"]))
    goods = [
        (-0.95, -0.45, 0.20, "glow"),
        (-0.55, -0.55, 0.16, "leaf"),
        (0.55, -0.50, 0.18, "roof_dark"),
        (0.95, -0.42, 0.22, "wood"),
    ]
    for gx, gy, size, material_key in goods:
        parts.append(add_box("goods", (size, size, size), (gx, gy, 0.98 + size * 0.5), mats[material_key]))
    # Lanternes suspendues.
    for x in (-0.62, 0.62):
        parts.append(add_cylinder("lamp_rope", 0.012, 0.28, (x, 0, 2.10), mats["wood_dark"], vertices=5))
        parts.append(add_box("lamp", (0.14, 0.14, 0.20), (x, 0, 1.90), mats["lamp"]))
        parts.append(add_box("lamp_cap", (0.18, 0.18, 0.04), (x, 0, 2.02), mats["iron_dark"]))
    return parts


def build_toit_lucarne(mats: Mats) -> list[bpy.types.Object]:
    """Élément de toit à lucarne + cheminée, posable sur un bâtiment (~1,5 case)."""
    parts: list[bpy.types.Object] = []
    parts.append(
        gable_roof("roof", width=1.50, depth=1.10, height=0.55, base_z=0.0, material=mats["roof_slate"])
    )
    parts.append(add_box("ridge", (1.36, 0.10, 0.07), (0, 0, 0.52), mats["iron_dark"]))
    # Lucarne sur le pan avant (-Y).
    parts.append(add_box("dormer", (0.42, 0.30, 0.42), (0.25, -0.20, 0.30), mats["plaster_light"]))
    parts.append(add_box("dormer_window", (0.26, 0.06, 0.26), (0.25, -0.36, 0.32), mats["glow"]))
    parts.append(
        gable_roof("dormer_roof", width=0.55, depth=0.45, height=0.20, base_z=0.50, material=mats["roof_slate"])
    )
    # Cheminée.
    parts.append(add_box("chimney", (0.20, 0.20, 0.60), (-0.42, 0.18, 0.50), mats["stone"]))
    parts.append(add_box("chimney_cap", (0.26, 0.26, 0.06), (-0.42, 0.18, 0.82), mats["stone_dark"]))
    return parts


def build_fontaine(mats: Mats) -> list[bpy.types.Object]:
    """Fontaine de place (~2 cases) : bassin octogonal, colonne, vasque."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.15, 2.15), mats["grass"], seed=209)
    ]
    parts.append(add_cylinder("base", 0.95, 0.10, (0, 0, 0.05), mats["stone_dark"], vertices=8))
    parts.append(add_cylinder("basin", 0.85, 0.30, (0, 0, 0.25), mats["stone"], vertices=8))
    parts.append(add_cylinder("rim", 0.90, 0.10, (0, 0, 0.45), mats["stone_light"], vertices=8))
    parts.append(add_cylinder("water", 0.70, 0.04, (0, 0, 0.44), mats["water"], vertices=8))
    parts.append(add_cylinder("column", 0.16, 0.85, (0, 0, 0.90), mats["stone"], vertices=8))
    parts.append(add_cylinder("bowl", 0.45, 0.10, (0, 0, 1.10), mats["stone_light"], vertices=10))
    parts.append(add_cylinder("bowl_water", 0.34, 0.03, (0, 0, 1.16), mats["water"], vertices=10))
    parts.append(add_ico_sphere("finial", 0.11, (0, 0, 1.28), mats["stone_light"], subdivisions=1))
    # Becs d'eau.
    for index, angle in enumerate((0.0, math.pi * 0.5, math.pi, math.pi * 1.5)):
        x = math.cos(angle) * 0.22
        y = math.sin(angle) * 0.22
        parts.append(
            add_cylinder(
                "spout", 0.03, 0.26, (x, y, 0.62), mats["metal"], vertices=6,
                rotation=(math.pi * 0.5, 0.0, angle),
            )
        )
    return parts


def build_puits_couvert(mats: Mats) -> list[bpy.types.Object]:
    """Puits couvert (~1,8 case) : margelle, quatre poteaux, toit, poulie."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("dirt_skirt", (1.80, 1.80), mats["dirt"], seed=210)
    ]
    parts.append(add_box("plinth", (1.30, 1.30, 0.12), (0, 0, 0.06), mats["stone_dark"]))
    parts.append(add_cylinder("curb", 0.55, 0.60, (0, 0, 0.42), mats["stone"], vertices=8))
    parts.append(add_cylinder("rim", 0.60, 0.08, (0, 0, 0.76), mats["stone_light"], vertices=8))
    parts.append(add_cylinder("water", 0.42, 0.04, (0, 0, 0.73), mats["water"], vertices=8))
    for x in (-0.45, 0.45):
        for y in (-0.45, 0.45):
            parts.append(add_box("post", (0.10, 0.10, 1.05), (x, y, 1.325), mats["wood_dark"]))
    parts.append(
        gable_roof("roof", width=1.45, depth=1.35, height=0.40, base_z=1.85, material=mats["roof"])
    )
    parts.append(add_box("ridge", (1.30, 0.10, 0.07), (0, 0, 2.23), mats["wood_dark"]))
    parts.append(
        add_cylinder(
            "axle", 0.05, 1.05, (0, 0, 1.35), mats["wood"], vertices=8,
            rotation=(0.0, math.pi * 0.5, 0.0),
        )
    )
    parts.append(
        add_cylinder(
            "pulley", 0.16, 0.07, (0.30, 0, 1.35), mats["wood_dark"], vertices=10,
            rotation=(0.0, math.pi * 0.5, 0.0),
        )
    )
    parts.append(add_cylinder("rope", 0.012, 0.42, (0, 0, 1.12), mats["wood_dark"], vertices=5))
    parts.append(add_cylinder("bucket", 0.10, 0.17, (0, 0, 0.86), mats["wood"], vertices=8))
    parts.append(add_box("crank", (0.05, 0.22, 0.05), (0.60, 0.06, 1.35), mats["metal"]))
    return parts


# --------------------------------------------------------------------------- #
# Figurines de personnages v6 (~1 case, socle rond discret, visages peints)
# --------------------------------------------------------------------------- #


def _npc_base(mats: Mats, seed: int, radius: float = 0.34) -> list[bpy.types.Object]:
    """Socle rond discret (sans jupe) : utilisable en intérieur comme en extérieur."""
    parts: list[bpy.types.Object] = []
    parts.append(add_cylinder("socle", radius, 0.06, (0, 0, 0.03), mats["stone_dark"], vertices=12))
    parts.append(
        add_cylinder("socle_top", radius - 0.035, 0.02, (0, 0, 0.07), mats["stone_light"], vertices=12)
    )
    return parts


def _npc_face(parts: list[bpy.types.Object], mats: Mats, z: float) -> None:
    """Yeux et nez peints pour donner un visage aux figurines."""
    for x in (-0.055, 0.055):
        parts.append(add_box("eye", (0.028, 0.018, 0.028), (x, -0.125, z + 0.01), mats["iron_dark"]))
    parts.append(add_box("nose", (0.028, 0.035, 0.025), (0, -0.145, z - 0.02), mats["skin_dark"]))


def build_pnj_aventurier(mats: Mats) -> list[bpy.types.Object]:
    """Aventurier (classe) : épée, bouclier, cape et sac à dos."""
    parts = _npc_base(mats, seed=211)
    for x in (-0.10, 0.10):
        parts.append(add_box("leg", (0.12, 0.15, 0.30), (x, 0, 0.25), mats["roof_slate"]))
        parts.append(add_box("boot", (0.13, 0.22, 0.10), (x, -0.03, 0.13), mats["wood_dark"]))
    parts.append(add_box("torso", (0.36, 0.23, 0.34), (0, 0, 0.57), mats["leaf"]))
    parts.append(add_box("belt", (0.38, 0.25, 0.06), (0, 0, 0.41), mats["wood_dark"]))
    parts.append(add_box("buckle", (0.06, 0.03, 0.05), (0, -0.13, 0.41), mats["glow"]))
    for x in (-0.235, 0.235):
        parts.append(add_box("arm", (0.11, 0.14, 0.30), (x, 0, 0.58), mats["leaf"]))
        parts.append(add_ico_sphere("hand", 0.055, (x, -0.01, 0.42), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("head", 0.135, (0, 0, 0.86), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("hair", 0.14, (0, 0.02, 0.895), mats["hair"], subdivisions=1, scale=(1.0, 0.95, 0.6)))
    parts.append(
        add_ico_sphere("hood", 0.155, (0, 0.04, 0.90), mats["leaf_dark"], subdivisions=1, scale=(1.05, 1.0, 0.75))
    )
    _npc_face(parts, mats, 0.86)
    # Cape et sac à dos.
    parts.append(add_box("cape", (0.32, 0.06, 0.52), (0, 0.17, 0.52), mats["leaf_dark"], rotation=(-0.08, 0.0, 0.0)))
    parts.append(add_box("backpack", (0.20, 0.12, 0.26), (0, 0.19, 0.56), mats["wood"]))
    parts.append(
        add_cylinder("bedroll", 0.06, 0.32, (0, 0.21, 0.73), mats["cloth"], vertices=8,
                     rotation=(0.0, math.pi * 0.5, 0.0))
    )
    # Épée (main droite) et bouclier (main gauche).
    parts.append(
        add_box("sword_blade", (0.05, 0.02, 0.52), (0.31, -0.04, 0.86), mats["metal"],
                rotation=(0.10, 0.0, 0.10))
    )
    parts.append(add_box("sword_guard", (0.14, 0.04, 0.05), (0.29, -0.03, 0.59), mats["wood_dark"]))
    parts.append(add_ico_sphere("sword_pommel", 0.035, (0.28, -0.02, 0.55), mats["glow"], subdivisions=1))
    parts.append(
        add_cylinder("shield", 0.16, 0.05, (-0.33, -0.13, 0.56), mats["wood"], vertices=10,
                     rotation=(math.pi * 0.5, 0.0, 0.0))
    )
    parts.append(
        add_cylinder("shield_boss", 0.055, 0.07, (-0.33, -0.17, 0.56), mats["glow"], vertices=8,
                     rotation=(math.pi * 0.5, 0.0, 0.0))
    )
    return parts


def build_pnj_archere(mats: Mats) -> list[bpy.types.Object]:
    """Archère (classe) : arc, carquois et flèches, capuche."""
    parts = _npc_base(mats, seed=214)
    for x in (-0.10, 0.10):
        parts.append(add_box("leg", (0.12, 0.15, 0.30), (x, 0, 0.25), mats["wood"]))
        parts.append(add_box("boot", (0.13, 0.22, 0.10), (x, -0.03, 0.13), mats["wood_dark"]))
    parts.append(add_box("torso", (0.32, 0.21, 0.33), (0, 0, 0.56), mats["leaf_light"]))
    parts.append(add_box("belt", (0.34, 0.23, 0.06), (0, 0, 0.41), mats["wood_dark"]))
    for x in (-0.22, 0.22):
        parts.append(add_box("arm", (0.10, 0.13, 0.29), (x, 0, 0.57), mats["leaf_light"]))
        parts.append(add_ico_sphere("hand", 0.052, (x, -0.01, 0.42), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("head", 0.13, (0, 0, 0.85), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("hair", 0.14, (0, 0.03, 0.88), mats["hair"], subdivisions=1, scale=(1.0, 0.95, 0.75)))
    parts.append(
        add_ico_sphere("hood", 0.15, (0, 0.05, 0.89), mats["leaf_dark"], subdivisions=1, scale=(1.05, 1.0, 0.8))
    )
    _npc_face(parts, mats, 0.85)
    # Queue de cheval.
    parts.append(add_cylinder("ponytail", 0.05, 0.28, (0, 0.17, 0.72), mats["hair"], vertices=6, rotation=(0.5, 0.0, 0.0)))
    # Arc (grip + deux branches + corde).
    parts.append(add_cylinder("bow_grip", 0.024, 0.24, (-0.32, -0.12, 0.58), mats["wood_dark"], vertices=6))
    parts.append(
        add_cylinder("bow_upper", 0.019, 0.44, (-0.32, -0.17, 0.86), mats["wood"], vertices=6,
                     rotation=(0.35, 0.0, 0.0))
    )
    parts.append(
        add_cylinder("bow_lower", 0.019, 0.44, (-0.32, -0.17, 0.30), mats["wood"], vertices=6,
                     rotation=(-0.35, 0.0, 0.0))
    )
    parts.append(add_box("bow_string", (0.008, 0.008, 0.86), (-0.32, -0.26, 0.58), mats["plaster_light"]))
    # Carquois et flèches dans le dos.
    parts.append(
        add_cylinder("quiver", 0.07, 0.38, (0.18, 0.17, 0.76), mats["wood_dark"], vertices=8,
                     rotation=(0.18, 0.15, 0.0))
    )
    for index in range(4):
        x = 0.12 + index * 0.035
        parts.append(add_cylinder("arrow", 0.008, 0.42, (x, 0.20, 1.00), mats["wood"], vertices=5,
                                  rotation=(0.15, 0.12, 0.0)))
        parts.append(add_cone("fletching", 0.018, 0.06, (x, 0.16, 1.19), mats["cloth"], vertices=4))
    return parts


def build_pnj_mage(mats: Mats) -> list[bpy.types.Object]:
    """Mage (classe) : robe, chapeau pointu, bâton à orbe, barbe."""
    parts = _npc_base(mats, seed=215)
    parts.append(add_cone("robe_skirt", 0.34, 0.55, (0, 0, 0.35), mats["robe_purple"], vertices=10, radius2=0.24))
    parts.append(add_cylinder("robe_body", 0.24, 0.60, (0, 0, 0.85), mats["robe_purple"], vertices=10))
    parts.append(add_cylinder("robe_belt", 0.25, 0.07, (0, 0, 0.62), mats["glow"], vertices=12))
    for x in (-0.26, 0.26):
        parts.append(add_box("sleeve", (0.13, 0.16, 0.32), (x, 0, 0.82), mats["robe_purple"]))
        parts.append(add_ico_sphere("hand", 0.05, (x, -0.02, 0.64), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("head", 0.135, (0, 0, 1.16), mats["skin"], subdivisions=1))
    _npc_face(parts, mats, 1.16)
    # Barbe et cheveux.
    parts.append(
        add_ico_sphere("beard", 0.12, (0, -0.09, 1.03), mats["plaster_light"], subdivisions=1,
                       scale=(0.95, 0.75, 1.35))
    )
    parts.append(
        add_ico_sphere("hair", 0.14, (0, 0.04, 1.20), mats["plaster_light"], subdivisions=1,
                       scale=(1.0, 0.95, 0.6))
    )
    # Chapeau pointu.
    parts.append(add_cylinder("hat_brim", 0.23, 0.04, (0, 0, 1.31), mats["robe_purple"], vertices=12))
    parts.append(add_cone("hat_cone", 0.17, 0.40, (0, 0, 1.53), mats["robe_purple"], vertices=10))
    parts.append(add_ico_sphere("hat_tip", 0.04, (0, 0, 1.74), mats["glow"], subdivisions=1))
    # Bâton à orbe.
    parts.append(add_cylinder("staff", 0.025, 1.55, (0.34, -0.02, 0.86), mats["wood"], vertices=6))
    parts.append(add_ico_sphere("orb", 0.08, (0.34, -0.02, 1.66), mats["glow"], subdivisions=1))
    parts.append(
        add_torus("orb_ring", 0.11, 0.015, (0.34, -0.02, 1.66), mats["metal"], major_segments=10, minor_segments=4,
                  rotation=(math.pi * 0.5, 0.0, 0.0))
    )
    return parts


def build_pnj_voleuse(mats: Mats) -> list[bpy.types.Object]:
    """Voleuse (classe) : capuche, écharpe, deux dagues, sacoches."""
    parts = _npc_base(mats, seed=216)
    for x in (-0.10, 0.10):
        parts.append(add_box("leg", (0.11, 0.15, 0.28), (x, 0, 0.23), mats["roof_slate"]))
        parts.append(add_box("boot", (0.12, 0.21, 0.10), (x, -0.03, 0.11), mats["wood_dark"]))
    parts.append(add_box("torso", (0.30, 0.20, 0.30), (0, 0, 0.52), mats["roof_slate"]))
    parts.append(add_box("belt", (0.32, 0.22, 0.06), (0, 0, 0.38), mats["wood_dark"]))
    for x in (-0.21, 0.21):
        parts.append(add_box("arm", (0.09, 0.12, 0.27), (x, 0, 0.54), mats["roof_slate"]))
        parts.append(add_ico_sphere("hand", 0.05, (x, -0.01, 0.40), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("head", 0.13, (0, 0, 0.80), mats["skin"], subdivisions=1))
    parts.append(
        add_ico_sphere("hood", 0.155, (0, 0.04, 0.84), mats["roof_slate"], subdivisions=1,
                       scale=(1.05, 1.0, 0.85))
    )
    _npc_face(parts, mats, 0.80)
    parts.append(add_box("scarf", (0.26, 0.06, 0.10), (0, -0.12, 0.66), mats["cloth"]))
    parts.append(add_box("scarf_tail", (0.08, 0.04, 0.26), (0.14, -0.04, 0.50), mats["cloth"], rotation=(0.0, 0.0, 0.2)))
    # Dagues jumelles.
    for side in (-1, 1):
        x = side * 0.235
        parts.append(
            add_box("dagger_blade", (0.035, 0.015, 0.26), (x, -0.07, 0.58), mats["metal"],
                    rotation=(0.0, side * 0.35, 0.0))
        )
        parts.append(add_box("dagger_hilt", (0.05, 0.03, 0.07), (x, -0.05, 0.42), mats["wood_dark"]))
    # Sacoches à la ceinture.
    for x in (-0.15, 0.15):
        parts.append(add_box("pouch", (0.09, 0.08, 0.10), (x, -0.10, 0.36), mats["wood"]))
    return parts


def build_pnj_pretresse(mats: Mats) -> list[bpy.types.Object]:
    """Prêtresse (classe) : robe longue, cape, symbole sacré, diadème."""
    parts = _npc_base(mats, seed=217)
    parts.append(add_cone("robe_skirt", 0.30, 0.60, (0, 0, 0.38), mats["plaster_light"], vertices=10, radius2=0.21))
    parts.append(add_cylinder("robe_body", 0.20, 0.55, (0, 0, 0.88), mats["plaster_light"], vertices=10))
    parts.append(add_box("robe_trim", (0.06, 0.04, 0.55), (0, -0.20, 0.86), mats["glow"]))
    parts.append(add_cylinder("robe_belt", 0.21, 0.06, (0, 0, 0.64), mats["glow"], vertices=12))
    for x in (-0.26, 0.26):
        parts.append(add_box("sleeve", (0.11, 0.14, 0.30), (x, 0, 0.86), mats["plaster_light"]))
        parts.append(add_ico_sphere("hand", 0.05, (x, -0.02, 0.68), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("head", 0.13, (0, 0, 1.14), mats["skin"], subdivisions=1))
    parts.append(
        add_ico_sphere("hair", 0.145, (0, 0.06, 1.15), mats["hair"], subdivisions=1,
                       scale=(1.0, 0.85, 1.05))
    )
    _npc_face(parts, mats, 1.14)
    # Cape bleue et diadème doré.
    parts.append(add_box("cape", (0.40, 0.06, 0.72), (0, 0.20, 0.78), mats["robe_blue"], rotation=(-0.06, 0.0, 0.0)))
    parts.append(add_box("cape_trim", (0.42, 0.07, 0.06), (0, 0.20, 1.12), mats["glow"]))
    parts.append(
        add_torus("circlet", 0.14, 0.018, (0, 0, 1.22), mats["glow"], major_segments=10, minor_segments=4,
                  rotation=(math.pi * 0.5, 0.0, 0.0))
    )
    # Symbole sacré porté en sautoir (soleil stylisé).
    parts.append(add_cylinder("amulet_chain", 0.012, 0.28, (0, -0.16, 1.02), mats["metal"], vertices=5,
                              rotation=(math.pi * 0.5, 0.0, 0.0)))
    parts.append(
        add_cylinder("sun_disc", 0.075, 0.03, (0, -0.19, 0.90), mats["glow"], vertices=10,
                     rotation=(math.pi * 0.5, 0.0, 0.0))
    )
    for index, angle in enumerate((0.0, 0.785, 1.57, 2.356)):
        parts.append(
            add_box("sun_ray", (0.02, 0.02, 0.07), (math.cos(angle) * 0.10, -0.19, 0.90 + math.sin(angle) * 0.10),
                    mats["glow"], rotation=(0.0, 0.0, angle))
        )
    return parts


def build_pnj_garde(mats: Mats) -> list[bpy.types.Object]:
    """Garde (classe) : armure, casque à plumet, hallebarde."""
    parts = _npc_base(mats, seed=213)
    for x in (-0.11, 0.11):
        parts.append(add_box("leg", (0.13, 0.14, 0.32), (x, 0, 0.25), mats["roof_slate"]))
        parts.append(add_box("boot", (0.14, 0.21, 0.10), (x, -0.03, 0.09), mats["iron_dark"]))
    parts.append(add_box("torso", (0.38, 0.24, 0.36), (0, 0, 0.60), mats["metal"]))
    parts.append(add_box("tabard", (0.24, 0.04, 0.34), (0, -0.14, 0.58), mats["cloth"]))
    parts.append(add_box("belt", (0.40, 0.26, 0.06), (0, 0, 0.43), mats["wood_dark"]))
    for x in (-0.26, 0.26):
        parts.append(add_box("pauldron", (0.16, 0.20, 0.10), (x, 0, 0.76), mats["metal"]))
        parts.append(add_box("arm", (0.11, 0.14, 0.28), (x, 0, 0.58), mats["metal"]))
        parts.append(add_ico_sphere("hand", 0.055, (x, -0.01, 0.42), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("head", 0.135, (0, 0, 0.94), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("helmet", 0.15, (0, 0, 1.02), mats["metal"], subdivisions=1, scale=(1.05, 0.95, 0.78)))
    parts.append(add_box("nasal", (0.035, 0.05, 0.14), (0, -0.135, 0.94), mats["iron_dark"]))
    parts.append(add_box("plume", (0.05, 0.22, 0.06), (0, 0.02, 1.12), mats["cloth"]))
    _npc_face(parts, mats, 0.94)
    # Hallebarde : hampe, fer, hache et pointe.
    parts.append(add_cylinder("halberd_shaft", 0.026, 1.75, (0.30, -0.02, 0.92), mats["wood"], vertices=6))
    parts.append(add_box("halberd_head", (0.22, 0.05, 0.18), (0.38, -0.02, 1.62), mats["metal"], rotation=(0.0, 0.0, 0.10)))
    parts.append(add_cone("halberd_spike", 0.055, 0.22, (0.30, -0.02, 1.88), mats["metal"], vertices=6))
    parts.append(add_box("halberd_butt", (0.05, 0.05, 0.08), (0.30, -0.02, 0.12), mats["iron_dark"]))
    return parts


def build_pnj_marchand(mats: Mats) -> list[bpy.types.Object]:
    """Marchand (classe) : chapeau large, sac de marchandises, bâton."""
    parts = _npc_base(mats, seed=212)
    for x in (-0.11, 0.11):
        parts.append(add_box("leg", (0.13, 0.15, 0.28), (x, 0, 0.22), mats["wood"]))
        parts.append(add_box("boot", (0.14, 0.21, 0.10), (x, -0.03, 0.09), mats["wood_dark"]))
    parts.append(add_box("torso", (0.42, 0.28, 0.40), (0, 0, 0.55), mats["plaster_light"]))
    parts.append(add_box("vest", (0.44, 0.30, 0.26), (0, 0, 0.64), mats["cloth"]))
    parts.append(add_box("belt", (0.44, 0.30, 0.07), (0, 0, 0.40), mats["wood_dark"]))
    parts.append(add_box("strap", (0.07, 0.30, 0.05), (0.10, 0.01, 0.66), mats["wood_dark"], rotation=(0.0, 0.0, 0.55)))
    for x in (-0.26, 0.26):
        parts.append(add_box("arm", (0.11, 0.14, 0.28), (x, 0, 0.58), mats["plaster_light"]))
        parts.append(add_ico_sphere("hand", 0.055, (x, -0.01, 0.42), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("head", 0.14, (0, 0, 0.88), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("beard", 0.11, (0, -0.08, 0.82), mats["hair"], subdivisions=1, scale=(0.9, 0.75, 0.8)))
    _npc_face(parts, mats, 0.88)
    parts.append(add_cylinder("hat_brim", 0.22, 0.035, (0, 0, 1.07), mats["wood"], vertices=12))
    parts.append(add_cylinder("hat_crown", 0.13, 0.13, (0, 0, 1.15), mats["wood_dark"], vertices=10))
    parts.append(add_cylinder("hat_band", 0.135, 0.03, (0, 0, 1.09), mats["roof_dark"], vertices=10))
    # Bâton de marche et sac de marchandises.
    parts.append(add_cylinder("staff", 0.026, 1.45, (-0.32, -0.02, 0.80), mats["wood"], vertices=6))
    parts.append(add_ico_sphere("staff_knob", 0.05, (-0.32, -0.02, 1.53), mats["wood_dark"], subdivisions=1))
    parts.append(add_box("sack", (0.30, 0.24, 0.30), (0.30, 0.10, 0.43), mats["cloth"]))
    parts.append(add_box("sack_tie", (0.10, 0.10, 0.06), (0.30, 0.10, 0.58), mats["wood_dark"]))
    parts.append(add_ico_sphere("purse", 0.085, (0.16, -0.14, 0.37), mats["glow"], subdivisions=1, scale=(1.0, 0.9, 0.9)))
    return parts


def build_pnj_villageois(mats: Mats) -> list[bpy.types.Object]:
    """Villageois (classe) : tunique, tablier, seau."""
    parts = _npc_base(mats, seed=218)
    for x in (-0.10, 0.10):
        parts.append(add_box("leg", (0.12, 0.14, 0.28), (x, 0, 0.23), mats["wood"]))
        parts.append(add_box("boot", (0.13, 0.21, 0.10), (x, -0.03, 0.10), mats["wood_dark"]))
    parts.append(add_box("torso", (0.36, 0.24, 0.34), (0, 0, 0.55), mats["plaster_light"]))
    parts.append(add_box("apron", (0.28, 0.04, 0.34), (0, -0.13, 0.50), mats["wood_light"]))
    parts.append(add_box("belt", (0.38, 0.26, 0.06), (0, 0, 0.39), mats["wood_dark"]))
    for x in (-0.23, 0.23):
        parts.append(add_box("arm", (0.10, 0.13, 0.28), (x, 0, 0.55), mats["plaster_light"]))
        parts.append(add_ico_sphere("hand", 0.052, (x, -0.01, 0.40), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("head", 0.135, (0, 0, 0.86), mats["skin"], subdivisions=1))
    parts.append(add_ico_sphere("hair", 0.14, (0, 0.02, 0.895), mats["hair"], subdivisions=1, scale=(1.0, 0.95, 0.6)))
    _npc_face(parts, mats, 0.86)
    # Bonnet de paysan.
    parts.append(add_cylinder("cap", 0.15, 0.08, (0, 0, 0.99), mats["wood_dark"], vertices=10))
    parts.append(add_box("cap_brim", (0.20, 0.12, 0.03), (0, -0.14, 0.96), mats["wood"]))
    # Seau.
    parts.append(add_cylinder("bucket", 0.11, 0.18, (0.32, -0.10, 0.30), mats["wood"], vertices=8))
    parts.append(add_cylinder("bucket_rim", 0.115, 0.03, (0.32, -0.10, 0.385), mats["metal"], vertices=8))
    parts.append(
        add_torus("bucket_handle", 0.11, 0.012, (0.32, -0.10, 0.40), mats["metal"], major_segments=8,
                  minor_segments=4, rotation=(math.pi * 0.5, 0.0, 0.0))
    )
    parts.append(add_cylinder("bucket_water", 0.095, 0.03, (0.32, -0.10, 0.37), mats["water"], vertices=8))
    return parts


def build_pnj_gobelin(mats: Mats) -> list[bpy.types.Object]:
    """Gobelin (créature) : petit, vert, grandes oreilles, dague."""
    parts = _npc_base(mats, seed=219, radius=0.30)
    for x in (-0.09, 0.09):
        parts.append(add_box("leg", (0.10, 0.12, 0.20), (x, 0, 0.18), mats["goblin_skin_dark"]))
        parts.append(add_box("foot", (0.11, 0.18, 0.08), (x, -0.03, 0.10), mats["wood_dark"]))
    parts.append(add_box("torso", (0.28, 0.20, 0.28), (0, 0, 0.42), mats["goblin_skin"], rotation=(0.12, 0.0, 0.0)))
    parts.append(add_box("loincloth", (0.24, 0.20, 0.10), (0, 0, 0.31), mats["cloth"]))
    for x in (-0.19, 0.19):
        parts.append(add_box("arm", (0.09, 0.12, 0.26), (x, 0, 0.46), mats["goblin_skin"]))
        parts.append(add_ico_sphere("hand", 0.05, (x, -0.01, 0.32), mats["goblin_skin_dark"], subdivisions=1))
    parts.append(
        add_ico_sphere("head", 0.16, (0, 0, 0.68), mats["goblin_skin"], subdivisions=1,
                       scale=(1.05, 1.0, 0.95))
    )
    # Grandes oreilles pointues.
    for side in (-1, 1):
        parts.append(
            add_cone("ear", 0.055, 0.20, (side * 0.17, 0.02, 0.72), mats["goblin_skin"], vertices=5,
                     rotation=(0.0, side * math.pi * 0.5, 0.0))
        )
    # Yeux jaunes, nez crochu, bouche.
    for x in (-0.055, 0.055):
        parts.append(add_ico_sphere("eye", 0.028, (x, -0.145, 0.70), mats["glow"], subdivisions=1))
    parts.append(add_cone("nose", 0.035, 0.10, (0, -0.18, 0.67), mats["goblin_skin_dark"], vertices=4,
                          rotation=(math.pi * 0.5, 0.0, 0.0)))
    parts.append(add_box("mouth", (0.09, 0.02, 0.02), (0, -0.155, 0.60), mats["iron_dark"]))
    # Dague rudimentaire.
    parts.append(add_box("dagger_blade", (0.04, 0.015, 0.22), (0.25, -0.08, 0.50), mats["metal"],
                         rotation=(0.0, 0.25, 0.0)))
    parts.append(add_box("dagger_hilt", (0.05, 0.03, 0.06), (0.23, -0.06, 0.36), mats["wood_dark"]))
    # Trophée en os à la ceinture.
    parts.append(add_cylinder("bone_trophy", 0.02, 0.18, (-0.15, -0.10, 0.33), mats["bone"], vertices=5,
                              rotation=(0.0, 0.0, 0.7)))
    return parts


def build_pnj_squelette(mats: Mats) -> list[bpy.types.Object]:
    """Squelette (créature) : ossature, crâne, épée rouillée."""
    parts = _npc_base(mats, seed=220, radius=0.32)
    for x in (-0.09, 0.09):
        parts.append(add_cylinder("leg_bone", 0.035, 0.36, (x, 0, 0.27), mats["bone"], vertices=6))
        parts.append(add_ico_sphere("knee", 0.045, (x, 0, 0.45), mats["bone_dark"], subdivisions=1))
        parts.append(add_box("foot", (0.11, 0.18, 0.06), (x, -0.03, 0.10), mats["bone_dark"]))
    parts.append(add_box("pelvis", (0.24, 0.16, 0.10), (0, 0, 0.53), mats["bone_dark"]))
    parts.append(add_cylinder("spine", 0.03, 0.30, (0, 0, 0.72), mats["bone"], vertices=6))
    for index in range(4):
        width = 0.28 - index * 0.02
        parts.append(add_box("rib", (width, 0.15, 0.025), (0, 0, 0.62 + index * 0.06), mats["bone"]))
    parts.append(add_cylinder("shoulders", 0.03, 0.30, (0, 0, 0.90), mats["bone"], vertices=6,
                              rotation=(0.0, math.pi * 0.5, 0.0)))
    for side in (-1, 1):
        x = side * 0.20
        parts.append(add_cylinder("arm_bone", 0.028, 0.28, (x, 0, 0.78), mats["bone"], vertices=6,
                                  rotation=(0.0, side * 0.15, 0.0)))
        parts.append(add_ico_sphere("elbow", 0.035, (x, 0, 0.64), mats["bone_dark"], subdivisions=1))
        parts.append(add_cylinder("forearm", 0.024, 0.24, (x, -0.02, 0.53), mats["bone"], vertices=6))
    # Crâne avec orbites sombres et mâchoire.
    parts.append(
        add_ico_sphere("skull", 0.135, (0, 0, 1.02), mats["bone"], subdivisions=1, scale=(0.95, 0.95, 1.05))
    )
    for x in (-0.05, 0.05):
        parts.append(add_box("eye_socket", (0.045, 0.03, 0.04), (x, -0.115, 1.02), mats["iron_dark"]))
    parts.append(add_box("jaw", (0.14, 0.10, 0.05), (0, -0.06, 0.91), mats["bone_dark"]))
    for x in (-0.035, 0.035):
        parts.append(add_box("tooth", (0.02, 0.02, 0.03), (x, -0.12, 0.93), mats["bone"]))
    # Épée rouillée + fourreau vide à la ceinture.
    parts.append(add_box("sword_blade", (0.05, 0.02, 0.48), (0.29, -0.06, 0.68), mats["roof_dark"],
                         rotation=(0.05, 0.10, 0.12)))
    parts.append(add_box("sword_guard", (0.13, 0.04, 0.05), (0.26, -0.04, 0.44), mats["iron_dark"]))
    parts.append(add_ico_sphere("sword_pommel", 0.03, (0.25, -0.03, 0.40), mats["wood_dark"], subdivisions=1))
    parts.append(add_box("shoulder_pad", (0.12, 0.14, 0.08), (0.20, 0, 0.96), mats["iron_dark"]))
    return parts


# --------------------------------------------------------------------------- #
# Kit v5 : environnement — relief, forêt, berges, eau
# --------------------------------------------------------------------------- #


def build_falaise(mats: Mats) -> list[bpy.types.Object]:
    """Falaise rocheuse (module 2x2 cases) avec plateau herbeux."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.28, 2.28), mats["grass"], seed=301)
    ]
    # Masse rocheuse principale + second étage.
    parts.append(
        add_ico_sphere(
            "rock_base", 1.02, (0, 0, 0.52), mats["stone"], subdivisions=2,
            scale=(1.05, 1.00, 0.72), jitter=0.10, seed=302,
        )
    )
    parts.append(
        add_ico_sphere(
            "rock_upper", 0.80, (0.22, 0.16, 1.12), mats["stone_light"], subdivisions=1,
            scale=(1.02, 0.95, 0.78), jitter=0.07, seed=303,
        )
    )
    parts.append(
        add_ico_sphere(
            "rock_side", 0.52, (-0.72, -0.42, 0.42), mats["stone_dark"], subdivisions=1,
            scale=(1.0, 0.9, 0.85), jitter=0.05, seed=304,
        )
    )
    # Plateaux rocheux et couverture d'herbe.
    parts.append(add_cylinder("plateau", 0.86, 0.16, (0.10, -0.04, 1.42), mats["stone"], vertices=10))
    parts.append(add_cylinder("plateau_grass", 0.84, 0.05, (0.10, -0.04, 1.51), mats["grass"], vertices=10))
    # Dalles rocheuses en saillie sur la face avant.
    parts.append(
        add_ico_sphere(
            "ledge_low", 0.55, (-0.15, -0.72, 0.52), mats["stone_dark"], subdivisions=1,
            scale=(1.65, 0.55, 0.28), jitter=0.03, seed=305,
        )
    )
    parts.append(
        add_ico_sphere(
            "ledge_high", 0.44, (0.34, -0.55, 0.92), mats["stone_light"], subdivisions=1,
            scale=(1.35, 0.60, 0.28), jitter=0.03, seed=306,
        )
    )
    # Touffes d'herbe et petits rochers sur le plateau.
    for index, (x, y, radius, material) in enumerate(
        ((0.38, -0.28, 0.16, "leaf_dark"), (-0.30, 0.10, 0.14, "leaf"), (0.02, -0.52, 0.12, "leaf_light"))
    ):
        parts.append(
            add_ico_sphere(
                f"tuft_{index}", radius, (x, y, 1.56), mats[material], subdivisions=1,
                scale=(1.0, 1.0, 0.55), jitter=0.03, seed=310 + index,
            )
        )
    parts.append(
        add_ico_sphere("top_rock", 0.13, (-0.55, -0.36, 1.58), mats["stone"], subdivisions=1,
                       scale=(1.1, 0.9, 0.7), jitter=0.03, seed=320)
    )
    return parts


def build_gros_rocher(mats: Mats) -> list[bpy.types.Object]:
    """Gros rocher (~1,9 case) en trois blocs avec mousse."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (1.98, 1.78), mats["grass"], seed=331)
    ]
    parts.append(
        add_ico_sphere(
            "rock_main", 0.78, (0, 0, 0.54), mats["stone"], subdivisions=2,
            scale=(1.12, 0.96, 0.82), jitter=0.09, seed=332,
        )
    )
    parts.append(
        add_ico_sphere(
            "rock_side", 0.46, (0.62, 0.16, 0.30), mats["stone_light"], subdivisions=1,
            scale=(1.05, 0.92, 0.80), jitter=0.06, seed=333,
        )
    )
    parts.append(
        add_ico_sphere(
            "rock_small", 0.30, (-0.55, -0.24, 0.22), mats["stone_dark"], subdivisions=1,
            scale=(1.0, 0.95, 0.85), jitter=0.05, seed=334,
        )
    )
    # Mousse sur le sommet.
    for index, (x, y, z, radius, material_key) in enumerate(
        ((0.05, -0.05, 1.02, 0.24, "leaf_dark"), (-0.28, 0.22, 0.86, 0.16, "leaf"))
    ):
        parts.append(
            add_ico_sphere(
                f"moss_{index}", radius, (x, y, z), mats[material_key], subdivisions=1,
                scale=(1.5, 1.2, 0.45), jitter=0.02, seed=340 + index,
            )
        )
    return parts


def build_arbre_majestueux(mats: Mats) -> list[bpy.types.Object]:
    """Grand arbre majestueux (~2,4 cases de large, 4,2 de haut)."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.45, 2.45), mats["grass"], seed=351)
    ]
    parts.append(add_cylinder("trunk", 0.30, 2.00, (0, 0, 1.00), mats["wood_dark"], vertices=8))
    parts.append(
        add_cone("trunk_top", 0.28, 0.85, (0, 0, 2.10), mats["wood_dark"], vertices=8, radius2=0.16)
    )
    # Racines et branches.
    for index, angle in enumerate((0.0, math.pi * 0.5, math.pi, math.pi * 1.5)):
        parts.append(
            add_cone(
                f"root_{index}", 0.12, 0.55,
                (math.cos(angle) * 0.34, math.sin(angle) * 0.34, 0.22),
                mats["wood_dark"], vertices=5,
                rotation=(math.sin(angle) * 0.9, math.cos(angle) * 0.9, 0.0),
            )
        )
    for index, angle in enumerate((0.6, 2.4, 4.2)):
        parts.append(
            add_cylinder(
                f"branch_{index}", 0.09, 0.95,
                (math.cos(angle) * 0.70, math.sin(angle) * 0.70, 2.35),
                mats["wood"], vertices=6,
                rotation=(math.sin(angle) * 0.8, -math.cos(angle) * 0.8, 0.0),
            )
        )
    # Houppier en quatre masses.
    canopies = [
        (0.0, 0.0, 2.95, 0.95, "leaf", (1.10, 1.05, 0.82)),
        (0.62, 0.18, 3.38, 0.72, "leaf_light", (1.05, 1.0, 0.9)),
        (-0.58, -0.12, 3.22, 0.68, "leaf_dark", (1.0, 1.0, 0.88)),
        (0.08, 0.24, 3.85, 0.55, "leaf_light", (1.0, 1.0, 0.9)),
    ]
    for index, (x, y, z, radius, material_key, scale) in enumerate(canopies):
        parts.append(
            add_ico_sphere(
                f"canopy_{index}", radius, (x, y, z), mats[material_key], subdivisions=1,
                scale=scale, jitter=0.05, seed=360 + index,
            )
        )
    return parts


def build_haie(mats: Mats) -> list[bpy.types.Object]:
    """Haie taillée (module 2 cases) en masses de feuillage."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.30, 0.85), mats["grass"], seed=371)
    ]
    for index in range(7):
        x = -0.90 + index * 0.30
        material_key = ("leaf", "leaf_light", "leaf_dark")[index % 3]
        parts.append(
            add_ico_sphere(
                f"hedge_{index}", 0.36, (x, 0.02 * ((-1) ** index), 0.54),
                mats[material_key], subdivisions=1,
                scale=(1.0, 0.88, 0.92), jitter=0.04, seed=380 + index,
            )
        )
    # Petites touches claires au sommet.
    for index, x in enumerate((-0.62, 0.10, 0.70)):
        parts.append(
            add_ico_sphere(
                f"hedge_top_{index}", 0.13, (x, 0.0, 0.84), mats["leaf_light"],
                subdivisions=1, scale=(1.2, 1.0, 0.6), jitter=0.02, seed=390 + index,
            )
        )
    return parts


def build_bosquet(mats: Mats) -> list[bpy.types.Object]:
    """Bosquet / taillis (~2,4 cases) : trois jeunes arbres et sous-bois."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.40, 2.30), mats["grass"], seed=401)
    ]
    trees = [
        (-0.62, -0.18, 1.30, 0.55, "leaf"),
        (0.48, 0.28, 1.55, 0.62, "leaf_light"),
        (0.05, -0.58, 1.15, 0.48, "leaf_dark"),
    ]
    for index, (x, y, trunk_height, radius, material_key) in enumerate(trees):
        parts.append(
            add_cylinder(f"trunk_{index}", 0.10, trunk_height, (x, y, trunk_height * 0.5), mats["wood_dark"], vertices=6)
        )
        parts.append(
            add_ico_sphere(
                f"canopy_{index}", radius, (x, y, trunk_height + radius * 0.55),
                mats[material_key], subdivisions=1, scale=(1.05, 1.0, 0.9), jitter=0.05,
                seed=410 + index,
            )
        )
    for index, (x, y, radius) in enumerate(((-0.05, 0.22, 0.22), (0.32, -0.10, 0.18), (-0.42, 0.38, 0.16))):
        parts.append(
            add_ico_sphere(
                f"undergrowth_{index}", radius, (x, y, radius * 0.7), mats["leaf_dark"],
                subdivisions=1, scale=(1.1, 1.0, 0.75), jitter=0.03, seed=420 + index,
            )
        )
    return parts


def build_roseaux(mats: Mats) -> list[bpy.types.Object]:
    """Roseaux de berge (~1,3 case) sur une plaque de terre humide."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("dirt_skirt", (1.35, 1.15), mats["dirt"], seed=431)
    ]
    stems = [
        (-0.34, -0.18, 1.20, 0.10), (-0.18, 0.10, 1.45, 0.05), (0.02, -0.22, 1.10, -0.08),
        (0.18, 0.16, 1.55, 0.12), (0.32, -0.06, 1.30, -0.05), (-0.28, 0.26, 1.00, 0.06),
        (0.12, -0.12, 1.40, -0.10), (0.40, 0.22, 1.15, 0.04),
    ]
    for index, (x, y, height, lean) in enumerate(stems):
        parts.append(
            add_cylinder(
                f"stem_{index}", 0.018, height, (x, y, height * 0.5),
                mats["reed"], vertices=5, rotation=(lean, -lean * 0.6, 0.0),
            )
        )
        parts.append(
            add_cone(
                f"seed_{index}", 0.045, 0.22, (x + lean * height * 0.4, y - lean * height * 0.2, height + 0.06),
                mats["hay_dark"] if index % 2 == 0 else mats["hay"], vertices=5,
            )
        )
        # Lame de feuille.
        parts.append(
            add_box(
                f"blade_{index}", (0.025, 0.010, 0.45),
                (x - 0.06, y + 0.05, height * 0.45),
                mats["leaf"], rotation=(0.15, 0.25, 0.0),
            )
        )
    return parts


def build_ponton(mats: Mats) -> list[bpy.types.Object]:
    """Ponton / embarcadère en bois (~2,2 x 0,95 case), sur l'eau."""
    parts: list[bpy.types.Object] = []
    # Pilotis dans l'eau.
    for x in (-0.92, 0.0, 0.92):
        for y in (-0.34, 0.34):
            parts.append(add_box("post", (0.13, 0.13, 0.95), (x, y, 0.475), mats["wood_dark"]))
    # Structure et tablier de planches.
    for y in (-0.34, 0.34):
        parts.append(add_box("stringer", (2.20, 0.10, 0.10), (0, y, 0.42), mats["wood_dark"]))
    for index in range(7):
        x = -0.96 + index * 0.32
        material = mats["wood"] if index % 2 == 0 else mats["wood_light"]
        parts.append(add_box("plank", (0.30, 0.88, 0.06), (x, 0, 0.50), material))
    # Poteaux d'amarrage aux extrémités.
    for x in (-1.02, 1.02):
        parts.append(add_box("mooring_post", (0.16, 0.16, 1.20), (x, 0.36, 0.60), mats["wood_dark"]))
        parts.append(add_box("mooring_cap", (0.20, 0.20, 0.07), (x, 0.36, 1.23), mats["wood"]))
    # Rouleau de corde sur le ponton.
    parts.append(
        add_torus(
            "rope_coil", 0.11, 0.035, (-0.62, 0.16, 0.55), mats["hay_dark"],
            major_segments=8, minor_segments=4, rotation=(0.0, 0.0, 0.0),
        )
    )
    return parts


def build_barque(mats: Mats) -> list[bpy.types.Object]:
    """Petite barque creuse (~1,9 x 0,9 case) avec rames, posée sur l'eau."""
    import bmesh

    parts: list[bpy.types.Object] = []
    outline = [
        (-0.90, 0.02),
        (-0.62, -0.30),
        (-0.10, -0.36),
        (0.45, -0.33),
        (0.90, 0.00),
        (0.45, 0.33),
        (-0.10, 0.36),
        (-0.62, 0.30),
    ]

    def ring(scale: float, z: float) -> list[tuple[float, float, float]]:
        return [(x * scale, y * scale, z) for x, y in outline]

    count = len(outline)
    vertices = ring(0.42, 0.08) + ring(1.0, 0.44) + ring(0.82, 0.44) + ring(0.55, 0.16)
    outer_bottom = 0
    outer_top = count
    inner_top = count * 2
    inner_floor = count * 3
    faces: list[tuple[int, ...]] = []
    # Coque extérieure + fond.
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((outer_bottom + index, outer_bottom + nxt, outer_top + nxt, outer_top + index))
    faces.append(tuple(reversed(range(outer_bottom, outer_bottom + count))))
    # Paroi intérieure + plancher.
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((inner_top + index, inner_top + nxt, inner_floor + nxt, inner_floor + index))
    faces.append(tuple(range(inner_floor, inner_floor + count)))
    # Bau (rebord) entre coque et paroi intérieure.
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((outer_top + index, outer_top + nxt, inner_top + nxt, inner_top + index))
    hull = add_mesh("hull", vertices, faces, mats["wood"])
    bm = bmesh.new()
    bm.from_mesh(hull.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(hull.data)
    bm.free()
    parts.append(hull)
    # Plat-bord en bois sombre.
    for index in range(count):
        x0, y0 = outline[index]
        x1, y1 = outline[(index + 1) % count]
        length = math.hypot(x1 - x0, y1 - y0) * 1.04
        angle = math.atan2(y1 - y0, x1 - x0)
        parts.append(
            add_box(
                "gunwale", (length, 0.07, 0.05),
                ((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.455), mats["wood_dark"],
                rotation=(0.0, 0.0, angle),
            )
        )
    # Plancher intérieur et bancs.
    parts.append(add_box("floor", (1.10, 0.50, 0.03), (0, 0, 0.17), mats["wood_dark"]))
    for x in (-0.32, 0.28):
        parts.append(add_box("seat", (0.16, 0.60, 0.05), (x, 0, 0.33), mats["wood_light"]))
    # Deux rames.
    parts.append(
        add_cylinder(
            "oar_long", 0.022, 1.20, (0.05, -0.10, 0.47), mats["wood_light"], vertices=6,
            rotation=(0.0, math.pi * 0.5, 0.20),
        )
    )
    parts.append(add_box("oar_blade", (0.18, 0.10, 0.02), (0.68, -0.22, 0.47), mats["wood"]))
    parts.append(
        add_cylinder(
            "oar_short", 0.022, 0.95, (0.52, 0.0, 0.48), mats["wood_light"], vertices=6,
            rotation=(math.pi * 0.5, 0.0, 0.0),
        )
    )
    parts.append(add_box("oar_blade", (0.02, 0.10, 0.16), (0.52, 0.44, 0.48), mats["wood"]))
    parts.append(
        add_torus("rope", 0.08, 0.022, (0.70, 0.0, 0.47), mats["hay_dark"], major_segments=8, minor_segments=4)
    )
    return parts


def build_nenuphars(mats: Mats) -> list[bpy.types.Object]:
    """Touffe de nénuphars flottants (~1,4 x 1,0 case)."""
    parts: list[bpy.types.Object] = []
    pads = [
        (-0.42, -0.18, 0.24, "leaf"),
        (-0.10, 0.12, 0.20, "leaf_light"),
        (0.24, -0.20, 0.22, "leaf_dark"),
        (0.48, 0.14, 0.17, "leaf"),
        (0.06, -0.34, 0.16, "leaf_light"),
        (-0.34, 0.30, 0.15, "leaf_dark"),
        (0.42, 0.36, 0.13, "leaf"),
    ]
    for index, (x, y, radius, material_key) in enumerate(pads):
        parts.append(
            add_cylinder(f"pad_{index}", radius, 0.016, (x, y, 0.012), mats[material_key], vertices=8)
        )
    flowers = [(-0.16, 0.02, 0.08), (0.28, -0.10, 0.07), (0.50, 0.22, 0.06)]
    for index, (x, y, z) in enumerate(flowers):
        parts.append(add_cylinder("flower_stem", 0.012, 0.06, (x, y, z), mats["leaf_dark"], vertices=5))
        parts.append(
            add_ico_sphere(
                f"flower_{index}", 0.055, (x, y, z + 0.04), mats["blossom"], subdivisions=1,
                scale=(1.0, 1.0, 0.7), jitter=0.01, seed=460 + index,
            )
        )
        parts.append(add_ico_sphere("flower_core", 0.022, (x, y, z + 0.065), mats["glow"], subdivisions=1))
    return parts


def build_banniere(mats: Mats) -> list[bpy.types.Object]:
    """Bannière / étendard sur mât (~1,1 case, 2,9 de haut)."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (1.15, 0.95), mats["grass"], seed=471)
    ]
    parts.append(add_cylinder("base", 0.22, 0.12, (0, 0, 0.06), mats["stone_dark"], vertices=8))
    parts.append(add_cylinder("base_top", 0.17, 0.06, (0, 0, 0.15), mats["stone_light"], vertices=8))
    parts.append(add_cylinder("pole", 0.055, 2.75, (0, 0, 1.45), mats["wood_dark"], vertices=8))
    parts.append(add_box("crossbar", (0.95, 0.07, 0.07), (0.30, 0, 2.62), mats["wood"]))
    parts.append(add_ico_sphere("finial", 0.075, (0, 0, 2.87), mats["metal"], subdivisions=1))
    # Bannière principale (coton rouge sombre) + emblème losange.
    parts.append(add_box("banner", (0.72, 0.03, 1.05), (0.36, 0, 2.05), mats["cloth"]))
    parts.append(add_box("banner_bar", (0.78, 0.04, 0.06), (0.36, 0, 2.56), mats["wood_dark"]))
    parts.append(
        add_box("emblem", (0.26, 0.02, 0.26), (0.36, -0.02, 2.06), mats["glow"], rotation=(0.0, 0.0, math.pi * 0.25))
    )
    for index in range(3):
        parts.append(add_box("fringe", (0.20, 0.02, 0.10), (0.36 + (index - 1) * 0.22, 0, 1.48), mats["glow"]))
    # Fanion secondaire côté opposé.
    parts.append(add_box("pennant", (0.20, 0.03, 0.42), (-0.20, 0, 2.40), mats["plaster_light"]))
    parts.append(add_box("pennant_bar", (0.24, 0.04, 0.05), (-0.20, 0, 2.60), mats["wood_dark"]))
    return parts


def build_cloture_basse(mats: Mats) -> list[bpy.types.Object]:
    """Clôture basse (module 2 cases), plus légère que barrière/palissade."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (2.15, 0.42), mats["grass"], seed=481)
    ]
    for index in range(5):
        x = -0.88 + index * 0.44
        parts.append(add_box("post", (0.10, 0.10, 0.62), (x, 0, 0.31), mats["wood_dark"]))
        parts.append(add_box("post_cap", (0.13, 0.13, 0.05), (x, 0, 0.635), mats["wood_light"]))
    for z in (0.25, 0.47):
        parts.append(add_box("rail", (1.92, 0.07, 0.10), (0, 0, z), mats["wood"]))
    parts.append(
        add_box("brace", (0.62, 0.05, 0.07), (0.46, 0.055, 0.36), mats["wood_dark"], rotation=(0.0, 0.0, 0.42))
    )
    return parts


def build_tas_de_bois(mats: Mats) -> list[bpy.types.Object]:
    """Tas de bois (~1,3 x 0,95 case) : bûches empilées et hache plantée."""
    parts: list[bpy.types.Object] = [
        add_ground_skirt("grass_skirt", (1.35, 0.95), mats["grass"], seed=491)
    ]
    logs = [
        (-0.26, 0.11), (0.0, 0.11), (0.26, 0.11),
        (-0.13, 0.29), (0.13, 0.29),
        (0.0, 0.47),
    ]
    for index, (y, z) in enumerate(logs):
        parts.append(
            add_cylinder(
                f"log_{index}", 0.10, 0.95, (0, y, z), mats["wood_dark"], vertices=8,
                rotation=(0.0, math.pi * 0.5, 0.0),
            )
        )
        for x in (-0.48, 0.48):
            parts.append(
                add_cylinder(
                    "log_end", 0.095, 0.02, (x, y, z), mats["wood_light"], vertices=8,
                    rotation=(0.0, math.pi * 0.5, 0.0),
                )
            )
    # Hache plantée dans la bûche du haut.
    parts.append(
        add_cylinder(
            "axe_handle", 0.022, 0.52, (0.20, 0.0, 0.72), mats["wood"], vertices=6,
            rotation=(0.10, 0.10, 0.18),
        )
    )
    parts.append(
        add_box(
            "axe_head", (0.20, 0.05, 0.10), (0.21, 0.0, 0.96), mats["iron_dark"],
            rotation=(0.10, 0.10, 0.18),
        )
    )
    return parts


# --------------------------------------------------------------------------- #
# Kit v7 : modules de toiture et de facade (ancres roof / wall)
# --------------------------------------------------------------------------- #


def build_toit_2pentes(mats: Mats) -> list[bpy.types.Object]:
    """Toit a deux pentes 2x2 (module de toiture, ancre roof)."""
    parts: list[bpy.types.Object] = []
    parts.append(
        gable_roof("roof", width=2.10, depth=2.00, height=0.85, base_z=0.0, material=mats["roof"])
    )
    parts.append(add_box("ridge", (1.96, 0.12, 0.10), (0, 0, 0.86), mats["roof_dark"]))
    for y in (-1.00, 1.00):
        parts.append(add_box("eave", (2.14, 0.10, 0.10), (0, y, 0.03), mats["wood_dark"]))
    slope_angle = math.atan2(0.85, 1.0)
    for y in (-0.72, -0.42):
        z = (y + 1.0) * 0.85
        parts.append(
            add_box("batten", (2.06, 0.055, 0.035), (0, y, z + 0.02), mats["roof_dark"],
                    rotation=(slope_angle, 0.0, 0.0))
        )
    for y in (0.72, 0.42):
        z = (1.0 - y) * 0.85
        parts.append(
            add_box("batten", (2.06, 0.055, 0.035), (0, y, z + 0.02), mats["roof_dark"],
                    rotation=(-slope_angle, 0.0, 0.0))
        )
    return parts


def build_toit_croupe(mats: Mats) -> list[bpy.types.Object]:
    """Toit a croupe (4 pans) 2x2 (module de toiture, ancre roof)."""
    import bmesh

    parts: list[bpy.types.Object] = []
    half_w, half_d, height, ridge_half = 1.05, 1.00, 0.85, 0.38
    vertices = [
        (-half_w, -half_d, 0.0),
        (half_w, -half_d, 0.0),
        (half_w, half_d, 0.0),
        (-half_w, half_d, 0.0),
        (-ridge_half, 0.0, height),
        (ridge_half, 0.0, height),
    ]
    faces = [
        (0, 1, 5, 4),  # pan avant
        (3, 2, 5, 4),  # pan arriere
        (0, 4, 3),     # croupe gauche
        (1, 2, 5),     # croupe droite
    ]
    roof = add_mesh("roof", vertices, faces, mats["roof"])
    bm = bmesh.new()
    bm.from_mesh(roof.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(roof.data)
    bm.free()
    parts.append(roof)
    parts.append(add_box("ridge", (0.80, 0.10, 0.08), (0, 0, 0.87), mats["roof_dark"]))
    for y in (-half_d, half_d):
        parts.append(add_box("eave", (2.14, 0.09, 0.09), (0, y, 0.03), mats["wood_dark"]))
    for x in (-half_w, half_w):
        parts.append(add_box("eave", (0.09, 2.02, 0.09), (x, 0, 0.03), mats["wood_dark"]))
    return parts


def build_toit_appentis(mats: Mats) -> list[bpy.types.Object]:
    """Toit en appentis 2x1 (module de toiture, ancre roof)."""
    parts: list[bpy.types.Object] = []
    slope_angle = math.atan2(0.55, 1.0)
    parts.append(
        add_box("roof", (2.05, 1.02, 0.07), (0, 0, 0.275), mats["roof"], rotation=(slope_angle, 0.0, 0.0))
    )
    for x in (-0.70, 0.0, 0.70):
        parts.append(
            add_box("rafter", (0.07, 1.04, 0.09), (x, 0, 0.23), mats["wood_dark"],
                    rotation=(slope_angle, 0.0, 0.0))
        )
    parts.append(add_box("eave", (2.10, 0.09, 0.10), (0, -0.50, 0.02), mats["wood_dark"]))
    parts.append(add_box("wall_beam", (2.10, 0.10, 0.12), (0, 0.50, 0.52), mats["wood_dark"]))
    parts.append(
        add_box("roof_batten", (2.02, 0.055, 0.035), (0, -0.10, 0.34), mats["roof_dark"],
                rotation=(slope_angle, 0.0, 0.0))
    )
    return parts


def build_toit_clocheton(mats: Mats) -> list[bpy.types.Object]:
    """Petit clocheton de faitage (module de toiture, ancre roof)."""
    parts: list[bpy.types.Object] = []
    parts.append(add_box("base", (0.55, 0.55, 0.10), (0, 0, 0.05), mats["stone_dark"]))
    parts.append(add_box("tower", (0.50, 0.50, 0.80), (0, 0, 0.50), mats["stone"]))
    parts.append(add_box("opening", (0.22, 0.06, 0.30), (0, -0.25, 0.60), mats["iron_dark"]))
    parts.append(add_box("bell", (0.14, 0.10, 0.16), (0, -0.235, 0.58), mats["metal"]))
    parts.append(add_box("rim", (0.58, 0.58, 0.08), (0, 0, 0.94), mats["stone_light"]))
    parts.append(
        add_cone("roof", 0.44, 0.55, (0, 0, 1.25), mats["roof_slate"], vertices=4,
                 rotation=(0.0, 0.0, math.pi * 0.25))
    )
    parts.append(add_box("cross_v", (0.04, 0.04, 0.28), (0, 0, 1.66), mats["metal"]))
    parts.append(add_box("cross_h", (0.16, 0.04, 0.04), (0, 0, 1.72), mats["metal"]))
    return parts


def build_toit_chaume(mats: Mats) -> list[bpy.types.Object]:
    """Toit en chaume 2x2 (module de toiture, ancre roof)."""
    parts: list[bpy.types.Object] = []
    parts.append(
        gable_roof("roof", width=2.10, depth=2.05, height=0.88, base_z=0.0, material=mats["hay"])
    )
    parts.append(
        add_cylinder("ridge_cap", 0.10, 1.98, (0, 0, 0.92), mats["hay_dark"], vertices=8,
                     rotation=(0.0, math.pi * 0.5, 0.0))
    )
    slope_angle = math.atan2(0.88, 1.025)
    for y in (-1.00, 1.00):
        parts.append(
            add_cylinder("eave_roll", 0.06, 2.10, (0, y, 0.05), mats["hay_dark"], vertices=6,
                         rotation=(0.0, math.pi * 0.5, 0.0))
        )
        parts.append(add_box("eave_board", (2.12, 0.09, 0.08), (0, y, 0.01), mats["wood_dark"]))
    for y in (-0.70, -0.40):
        z = (y + 1.025) / 1.025 * 0.88
        parts.append(
            add_box("straw_band", (2.02, 0.08, 0.05), (0, y, z + 0.02), mats["hay_light"],
                    rotation=(slope_angle, 0.0, 0.0))
        )
    for y in (0.70, 0.40):
        z = (1.025 - y) / 1.025 * 0.88
        parts.append(
            add_box("straw_band", (2.02, 0.08, 0.05), (0, y, z + 0.02), mats["hay_light"],
                    rotation=(-slope_angle, 0.0, 0.0))
        )
    return parts


def build_cheminee_fumante(mats: Mats) -> list[bpy.types.Object]:
    """Cheminee de toit avec fumee stylisee opaque (ancre roof)."""
    parts: list[bpy.types.Object] = []
    parts.append(add_box("base", (0.56, 0.56, 0.14), (0, 0, 0.07), mats["stone_dark"]))
    parts.append(add_box("shaft", (0.46, 0.46, 1.30), (0, 0, 0.79), mats["stone"]))
    for z in (0.35, 0.75, 1.15):
        parts.append(add_box("course", (0.49, 0.49, 0.05), (0, 0, z), mats["stone_dark"]))
    parts.append(add_box("cap", (0.58, 0.58, 0.10), (0, 0, 1.49), mats["stone_light"]))
    parts.append(add_box("cap_top", (0.62, 0.62, 0.05), (0, 0, 1.56), mats["stone_dark"]))
    smoke = [
        (0.00, 0.00, 1.76, 0.14, 1.00),
        (0.05, 0.02, 1.94, 0.18, 1.10),
        (0.14, 0.05, 2.12, 0.22, 1.20),
        (0.25, 0.08, 2.28, 0.18, 1.10),
        (0.36, 0.11, 2.40, 0.13, 1.00),
    ]
    for index, (x, y, z, radius, scale) in enumerate(smoke):
        parts.append(
            add_ico_sphere(
                f"smoke_{index}", radius, (x, y, z),
                mats["smoke"] if index % 2 == 0 else mats["smoke_light"], subdivisions=1,
                scale=(scale, scale * 0.9, scale * 0.75), jitter=0.025, seed=640 + index,
            )
        )
    return parts


def build_colombage_panneau(mats: Mats) -> list[bpy.types.Object]:
    """Panneau de colombage 2x1 (module de facade, ancre wall)."""
    parts: list[bpy.types.Object] = []
    parts.append(add_box("plaster", (1.90, 0.12, 1.66), (0, 0, 0.87), mats["plaster"]))
    for x in (-0.90, 0.90):
        parts.append(add_box("post", (0.12, 0.16, 1.75), (x, 0, 0.875), mats["wood_dark"]))
    for z in (0.10, 0.90, 1.62):
        parts.append(add_box("rail", (1.94, 0.15, 0.11), (0, 0, z), mats["wood_dark"]))
    parts.append(add_box("top_plate", (2.02, 0.15, 0.12), (0, 0, 1.73), mats["wood_dark"]))
    parts.append(
        add_box("brace", (0.10, 0.16, 1.05), (-0.45, 0, 0.85), mats["wood_dark"],
                rotation=(0.0, 0.55, 0.0))
    )
    parts.append(
        add_box("brace", (0.10, 0.16, 1.05), (0.45, 0, 0.85), mats["wood_dark"],
                rotation=(0.0, -0.55, 0.0))
    )
    parts.append(add_box("sill", (2.04, 0.18, 0.08), (0, 0, 0.04), mats["stone_dark"]))
    return parts


def build_porte_auvent(mats: Mats) -> list[bpy.types.Object]:
    """Porte de facade avec auvent (module, ancre wall)."""
    parts: list[bpy.types.Object] = []
    parts.append(add_box("step", (1.10, 0.35, 0.10), (0, -0.10, 0.05), mats["stone_dark"]))
    parts.append(add_box("door", (0.90, 0.12, 1.90), (0, -0.06, 0.95), mats["wood_dark"]))
    for index, x in enumerate((-0.28, 0.0, 0.28)):
        material = mats["wood"] if index % 2 == 0 else mats["wood_light"]
        parts.append(add_box("plank", (0.24, 0.05, 1.78), (x, -0.13, 0.95), material))
    parts.append(add_box("handle", (0.05, 0.05, 0.06), (0.28, -0.17, 1.00), mats["metal"]))
    for x in (-0.52, 0.52):
        parts.append(add_box("jamb", (0.14, 0.18, 1.98), (x, -0.04, 0.99), mats["stone_light"]))
    parts.append(add_box("lintel", (1.24, 0.20, 0.16), (0, -0.04, 2.02), mats["stone_light"]))
    parts.append(
        gable_roof("awning", width=1.35, depth=0.60, height=0.24, base_z=2.10, material=mats["roof"])
    )
    for x in (-0.58, 0.58):
        parts.append(
            add_box("bracket", (0.08, 0.34, 0.08), (x, -0.24, 2.08), mats["wood_dark"],
                    rotation=(-0.4, 0.0, 0.0))
        )
    return parts


def build_fenetre_volets(mats: Mats) -> list[bpy.types.Object]:
    """Fenetre a volets ouverts (module de facade, ancre wall)."""
    parts: list[bpy.types.Object] = []
    z = 1.22
    parts.append(add_box("frame", (0.94, 0.12, 0.94), (0, 0, z), mats["stone_light"]))
    parts.append(add_box("glass", (0.66, 0.07, 0.66), (0, -0.05, z), mats["glow"]))
    parts.append(add_box("mullion_v", (0.05, 0.08, 0.70), (0, -0.07, z), mats["wood_dark"]))
    parts.append(add_box("mullion_h", (0.70, 0.08, 0.05), (0, -0.07, z), mats["wood_dark"]))
    parts.append(add_box("sill", (1.08, 0.20, 0.09), (0, -0.06, z - 0.51), mats["stone"]))
    for side in (-1, 1):
        x = side * 0.63
        parts.append(add_box("shutter", (0.30, 0.05, 0.82), (x, -0.04, z), mats["wood"]))
        for index in range(3):
            parts.append(
                add_box("slat", (0.26, 0.06, 0.04), (x, -0.07, z - 0.22 + index * 0.22), mats["wood_dark"])
            )
        parts.append(add_box("hinge", (0.05, 0.06, 0.05), (side * 0.47, -0.07, z + 0.28), mats["iron_dark"]))
    return parts


def build_balcon_bois(mats: Mats) -> list[bpy.types.Object]:
    """Balcon en bois 1x1 avec garde-corps (module de facade, ancre wall)."""
    parts: list[bpy.types.Object] = []
    parts.append(add_box("platform", (1.02, 0.55, 0.10), (0, -0.18, 1.00), mats["wood"]))
    for x in (-0.45, 0.45):
        parts.append(
            add_box("support", (0.08, 0.40, 0.10), (x, -0.20, 0.86), mats["wood_dark"],
                    rotation=(0.5, 0.0, 0.0))
        )
    for x in (-0.50, 0.50):
        for y in (-0.42, -0.05):
            parts.append(add_box("post", (0.06, 0.06, 0.55), (x, y, 1.32), mats["wood_dark"]))
    for y in (-0.42, -0.05):
        parts.append(add_box("rail", (1.02, 0.05, 0.07), (0, y, 1.57), mats["wood"]))
    for x in (-0.50, -0.17, 0.17, 0.50):
        parts.append(add_box("baluster", (0.03, 0.03, 0.45), (x, -0.42, 1.32), mats["wood_dark"]))
    parts.append(add_box("front_rail_mid", (1.02, 0.04, 0.05), (0, -0.42, 1.38), mats["wood"]))
    return parts


def build_escalier_exterieur(mats: Mats) -> list[bpy.types.Object]:
    """Escalier exterieur en bois 1x2 (module, ancre base)."""
    parts: list[bpy.types.Object] = []
    slope_angle = math.atan2(1.0, 1.7)
    for index in range(6):
        y = -0.85 + index * 0.34
        z = 0.10 + index * 0.20
        parts.append(add_box("step", (0.92, 0.34, 0.12), (0, y, z), mats["wood_light"] if index % 2 else mats["wood"]))
    for x in (-0.47, 0.47):
        parts.append(
            add_box("stringer", (0.10, 2.10, 0.20), (x, 0, 0.62), mats["wood_dark"],
                    rotation=(slope_angle, 0.0, 0.0))
        )
    for x in (-0.40, 0.40):
        parts.append(add_box("support", (0.10, 0.10, 1.10), (x, 0.82, 0.55), mats["wood_dark"]))
    # Garde-corps sur un cote.
    parts.append(add_box("rail_post_low", (0.06, 0.06, 0.80), (0.47, -0.85, 0.55), mats["wood_dark"]))
    parts.append(add_box("rail_post_high", (0.06, 0.06, 0.80), (0.47, 0.85, 1.55), mats["wood_dark"]))
    parts.append(
        add_box("handrail", (0.06, 2.20, 0.08), (0.47, 0, 1.30), mats["wood"],
                rotation=(slope_angle, 0.0, 0.0))
    )
    return parts


def build_auvent_etal(mats: Mats) -> list[bpy.types.Object]:
    """Auvent d'etal a rayures 2x1 (module de facade, ancre wall)."""
    parts: list[bpy.types.Object] = []
    parts.append(add_box("wall_plate", (2.06, 0.10, 0.10), (0, 0.02, 2.52), mats["wood_dark"]))
    stripe_materials = [mats["cloth"], mats["plaster_light"]]
    stripe_width = 0.24
    for index in range(8):
        x = -0.84 + index * stripe_width
        parts.append(
            add_box("awning_stripe", (stripe_width - 0.012, 1.05, 0.04), (x, -0.42, 2.32),
                    stripe_materials[index % 2], rotation=(0.32, 0.0, 0.0))
        )
        parts.append(
            add_box("awning_valance", (stripe_width - 0.012, 0.03, 0.18), (x, -0.92, 2.10),
                    stripe_materials[index % 2])
        )
    for x in (-1.00, 1.00):
        parts.append(
            add_box("arm", (0.06, 1.05, 0.06), (x, -0.42, 2.32), mats["wood_dark"],
                    rotation=(0.32, 0.0, 0.0))
        )
        parts.append(
            add_box("bracket", (0.07, 0.55, 0.07), (x, 0.20, 2.40), mats["wood_dark"],
                    rotation=(0.62, 0.0, 0.0))
        )
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
    AssetSpec(
        "forge",
        "buildings",
        build_forge,
        "Forge de forgeron (~2,3 cases) : pierre, grosse cheminee, enclume et tonnelet.",
        ("forge", "artisan", "village"),
    ),
    AssetSpec(
        "chapelle",
        "buildings",
        build_chapelle,
        "Petite chapelle (~2,3 cases) : clocher, fleche, vitraux et croix.",
        ("culte", "village", "clocher"),
    ),
    AssetSpec(
        "grange",
        "buildings",
        build_grange,
        "Grange a colombages (~2,9 x 3,2 cases) : grandes portes, bardage, toit de bois.",
        ("ferme", "stockage", "village"),
    ),
    AssetSpec(
        "ecurie",
        "buildings",
        build_ecurie,
        "Ecurie ouverte (~2,9 x 2,4 cases) : stalles, auvent, abreuvoir et foin.",
        ("ferme", "chevaux", "village"),
    ),
    AssetSpec(
        "maison_etage",
        "buildings",
        build_maison_etage,
        "Maison a etage (~2 x 2 cases) : encorbellement, colombages, toit et cheminee.",
        ("habitation", "village", "etage"),
    ),
    AssetSpec(
        "manoir",
        "buildings",
        build_manoir,
        "Manoir / petit chateau (~3,5 x 2,9 cases) : tourelle, aile basse, porche, bannieres.",
        ("noble", "chateau", "village"),
    ),
    AssetSpec(
        "tour_guet_bois",
        "buildings",
        build_tour_guet_bois,
        "Tour de guet en bois (~1,8 case, 3,6 de haut) : plateforme, garde-corps, echelle.",
        ("defense", "guet", "bois"),
    ),
    AssetSpec(
        "marche_couvert",
        "buildings",
        build_marche_couvert,
        "Marche couvert (~3,2 x 2,7 cases) : poteaux, toit, deux etals, lanternes.",
        ("commerce", "marche", "village"),
    ),
    AssetSpec(
        "toit_lucarne",
        "buildings",
        build_toit_lucarne,
        "Element de toit a lucarne et cheminee (~1,5 case), posable sur un batiment.",
        ("toit", "detail", "village"),
    ),
    AssetSpec(
        "fontaine",
        "props",
        build_fontaine,
        "Fontaine de place (~2 cases) : bassin octogonal, colonne, vasque et becs d'eau.",
        ("eau", "place", "village"),
    ),
    AssetSpec(
        "puits_couvert",
        "props",
        build_puits_couvert,
        "Puits couvert (~1,8 case) : margelle, quatre poteaux, toit, poulie et seau.",
        ("eau", "cour", "village"),
    ),
    AssetSpec(
        "pnj_aventurier",
        "props",
        build_pnj_aventurier,
        "Aventurier (classe) : epee, bouclier, cape et sac a dos (~1 case).",
        ("figurine", "token", "class:aventurier"),
    ),
    AssetSpec(
        "pnj_marchand",
        "props",
        build_pnj_marchand,
        "Marchand (classe) : chapeau large, sac de marchandises et baton (~1 case).",
        ("figurine", "token", "class:marchand"),
    ),
    AssetSpec(
        "pnj_garde",
        "props",
        build_pnj_garde,
        "Garde (classe) : armure, casque a plumet et hallebarde (~1,8 case de haut).",
        ("figurine", "token", "class:garde"),
    ),
    AssetSpec(
        "pnj_archere",
        "props",
        build_pnj_archere,
        "Archere (classe) : arc, carquois et fleches, capuche (~1 case).",
        ("figurine", "token", "class:archere"),
    ),
    AssetSpec(
        "pnj_mage",
        "props",
        build_pnj_mage,
        "Mage (classe) : robe, chapeau pointu, baton a orbe et barbe (~1,7 case de haut).",
        ("figurine", "token", "class:mage"),
    ),
    AssetSpec(
        "pnj_voleuse",
        "props",
        build_pnj_voleuse,
        "Voleuse (classe) : capuche, echappe et deux dagues (~1 case).",
        ("figurine", "token", "class:voleuse"),
    ),
    AssetSpec(
        "pnj_pretresse",
        "props",
        build_pnj_pretresse,
        "Pretresse (classe) : robe longue, cape, symbole sacre et diademe (~1,3 case).",
        ("figurine", "token", "class:pretresse"),
    ),
    AssetSpec(
        "pnj_villageois",
        "props",
        build_pnj_villageois,
        "Villageois (classe) : tunique, tablier et seau (~1 case).",
        ("figurine", "token", "class:villageois"),
    ),
    AssetSpec(
        "pnj_gobelin",
        "props",
        build_pnj_gobelin,
        "Gobelin (creature) : petit, vert, grandes oreilles et dague (~0,9 case).",
        ("figurine", "token", "creature:gobelin"),
    ),
    AssetSpec(
        "pnj_squelette",
        "props",
        build_pnj_squelette,
        "Squelette (creature) : ossature, crane et epee rouillee (~1,2 case).",
        ("figurine", "token", "creature:squelette"),
    ),
    AssetSpec(
        "falaise",
        "terrain",
        build_falaise,
        "Falaise rocheuse (module 2x2 cases) : masse rocheuse, strates, plateau herbeux.",
        ("relief", "rocher", "bord"),
    ),
    AssetSpec(
        "gros_rocher",
        "terrain",
        build_gros_rocher,
        "Gros rocher (~1,9 case) en trois blocs avec mousse.",
        ("relief", "rocher", "obstacle"),
    ),
    AssetSpec(
        "arbre_majestueux",
        "vegetation",
        build_arbre_majestueux,
        "Grand arbre majestueux (~2,4 cases, 4,2 de haut) : racines, branches, large houppier.",
        ("nature", "arbre", "foret"),
    ),
    AssetSpec(
        "haie",
        "vegetation",
        build_haie,
        "Haie taillee (module 2 cases) en masses de feuillage.",
        ("nature", "cloture", "jardin"),
    ),
    AssetSpec(
        "bosquet",
        "vegetation",
        build_bosquet,
        "Bosquet / taillis (~2,4 cases) : trois jeunes arbres et sous-bois.",
        ("nature", "foret", "decor"),
    ),
    AssetSpec(
        "roseaux",
        "vegetation",
        build_roseaux,
        "Roseaux de berge (~1,3 case) sur terre humide : tiges, epis, feuilles.",
        ("nature", "eau", "berge"),
    ),
    AssetSpec(
        "ponton",
        "props",
        build_ponton,
        "Ponton / embarcadere en bois (~2,2 x 0,95 case), pilotis et corde.",
        ("eau", "passage", "quai"),
    ),
    AssetSpec(
        "barque",
        "props",
        build_barque,
        "Petite barque (~1,9 x 0,9 case) : coque, bancs, rames et corde.",
        ("eau", "embarcation", "etang"),
    ),
    AssetSpec(
        "nenuphars",
        "vegetation",
        build_nenuphars,
        "Touffe de nenuphars flottants (~1,4 x 1,0 case) : feuilles et fleurs.",
        ("eau", "nature", "etang"),
    ),
    AssetSpec(
        "banniere",
        "props",
        build_banniere,
        "Banniere / etendard sur mat (~2,9 de haut) : embleme et fanion.",
        ("village", "decor", "place"),
    ),
    AssetSpec(
        "cloture_basse",
        "props",
        build_cloture_basse,
        "Cloture basse (module 2 cases) : poteaux et deux lisses.",
        ("cloture", "chemin", "campagne"),
    ),
    AssetSpec(
        "tas_de_bois",
        "props",
        build_tas_de_bois,
        "Tas de bois (~1,3 x 0,95 case) : buches empilees et hache plantee.",
        ("campagne", "bois", "decor"),
    ),
    AssetSpec(
        "toit_2pentes",
        "buildings",
        build_toit_2pentes,
        "Toit a deux pentes 2x2 (module de toiture) : tuiles, faitiere, liteaux.",
        ("module", "toit", "batiment"),
        anchor="roof",
    ),
    AssetSpec(
        "toit_croupe",
        "buildings",
        build_toit_croupe,
        "Toit a croupe 2x2 (module de toiture) : quatre pans, aretiers.",
        ("module", "toit", "batiment"),
        anchor="roof",
    ),
    AssetSpec(
        "toit_appentis",
        "buildings",
        build_toit_appentis,
        "Toit en appentis 2x1 (module de toiture) : un pan incline, chevrons.",
        ("module", "toit", "batiment"),
        anchor="roof",
    ),
    AssetSpec(
        "toit_clocheton",
        "buildings",
        build_toit_clocheton,
        "Petit clocheton de faitage (module de toiture) : cloche, fleche, croix.",
        ("module", "toit", "clocher"),
        anchor="roof",
    ),
    AssetSpec(
        "toit_chaume",
        "buildings",
        build_toit_chaume,
        "Toit en chaume 2x2 (module de toiture) : paille, faitiere, rouleaux de rive.",
        ("module", "toit", "chaume"),
        anchor="roof",
    ),
    AssetSpec(
        "cheminee_fumante",
        "buildings",
        build_cheminee_fumante,
        "Cheminee de toit avec fumee stylisee opaque (module, ancre roof).",
        ("module", "toit", "cheminee"),
        anchor="roof",
    ),
    AssetSpec(
        "colombage_panneau",
        "buildings",
        build_colombage_panneau,
        "Panneau de colombage 2x1 (module de facade) : torchis et croisillons.",
        ("module", "facade", "colombage"),
        anchor="wall",
    ),
    AssetSpec(
        "porte_auvent",
        "buildings",
        build_porte_auvent,
        "Porte de facade avec auvent (module, ancre wall) : encadrement, marche, auvent.",
        ("module", "facade", "porte"),
        anchor="wall",
    ),
    AssetSpec(
        "fenetre_volets",
        "buildings",
        build_fenetre_volets,
        "Fenetre a volets ouverts (module de facade) : encadrement, vitre, volets.",
        ("module", "facade", "fenetre"),
        anchor="wall",
    ),
    AssetSpec(
        "balcon_bois",
        "buildings",
        build_balcon_bois,
        "Balcon en bois 1x1 avec garde-corps (module de facade, ancre wall).",
        ("module", "facade", "balcon"),
        anchor="wall",
    ),
    AssetSpec(
        "escalier_exterieur",
        "buildings",
        build_escalier_exterieur,
        "Escalier exterieur en bois 1x2 (module, ancre base) : marches, limons, rampe.",
        ("module", "exterieur", "escalier"),
    ),
    AssetSpec(
        "auvent_etal",
        "buildings",
        build_auvent_etal,
        "Auvent d'etal a rayures 2x1 (module de facade, ancre wall).",
        ("module", "facade", "auvent"),
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
            height_above_floor = round(maxs.z, 3) if spec.anchor in ("wall", "roof") else round(dims[2], 3)
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


