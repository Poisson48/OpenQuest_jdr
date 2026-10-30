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
            mats = material_palette(variant.palette, prefix=f"{name}_")
            parts = spec.builder(mats)
            obj = finalize_asset(parts, name)
            if variant.scale != 1.0:
                obj.scale = (variant.scale, variant.scale, variant.scale)
                apply_transforms(obj)
                normalize_asset(obj, name)

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
                    "triangles": triangles,
                    "triangles_base": triangles_base,
                    "vertices": vertices,
                    "vertex_colors": "AO + mottling (COLOR_0)",
                    "outline": not args.no_outline,
                }
            )
            dims_text = " x ".join(f"{d:.2f}" for d in dims)
            log(
                f"[OK] {spec.category}/{name}.glb  "
                f"{triangles} tris ({triangles_base} mesh + contour)  "
                f"{dims_text} cases  "
                f"({glb_path.stat().st_size / 1024.0:.1f} Ko)"
                + (
                    ""
                    if args.no_thumbs
                    else f"  vignette {thumb_path.stat().st_size / 1024.0:.1f} Ko"
                )
            )
        except Exception as exc:  # noqa: BLE001 - on continue les autres assets
            failures.append(f"{spec.category}/{name}: {exc}")
            log(f"[ECHEC] {spec.category}/{name}: {exc}")

    # Manifeste informatif (l'editeur peut scanner les dossiers sans lui).
    if not args.no_manifest and not args.no_export and manifest:
        manifest_path = out_root / "manifest.json"
        payload = {
            "generated_by": "tools/blender/build_prototypes.py",
            "blender_version": bpy.app.version_string,
            "unit": "1 unite = 1 case de carte",
            "forward_axis_gltf": "+Z",
            "assets": sorted(manifest, key=lambda item: (str(item["category"]), str(item["name"]))),
        }
        manifest_path.write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        log(f"[OK] manifeste: {manifest_path}")

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


