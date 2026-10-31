"""Helpers Blender partages du pipeline OpenQuest (carte 2.5D).

Conventions imposees par le projet (documentees dans ``docs/BLENDER_PIPELINE.md``) :

* **1 unite Blender = 1 case de carte** (scene metrique, ``unit_scale = 1.0``).
* **Origine de l'objet au centre de sa base** : apres normalisation, le mesh
  occupe x/y centres sur 0 et z de 0 (sol) a la hauteur de l'objet.
* **+Z = haut dans Blender**. L'export glTF se fait avec ``export_yup=True`` :
  la hauteur devient +Y et la profondeur -Y en Blender devient +Z en glTF.
* **La face avant de l'objet regarde -Y dans Blender**, donc **+Z dans
  glTF/Godot** (convention demandee par le moteur).
* Transforms appliquees (rotation et scale a 1, location a 0).
* Low-poly (< 5000 triangles), pas de camera ni de lumiere exportees.
* Chaque asset produit ``<nom>.glb`` + ``<nom>_thumb.png`` (512x512, alpha).

Les fonctions de ce module sont concues pour tourner en **headless** :

    blender --background --python tools/blender/build_prototypes.py -- ...

Aucune dependance externe : uniquement ``bpy`` / ``mathutils``.
"""

from __future__ import annotations

import math
import os
import random
import re
import sys
import unicodedata
from pathlib import Path
from typing import Iterable, Sequence

import bpy
from mathutils import Vector

# --------------------------------------------------------------------------- #
# Chemins et constantes partagees
# --------------------------------------------------------------------------- #

REPO_ROOT = Path(__file__).resolve().parents[2]
OBJECTS3D_ROOT = REPO_ROOT / "game" / "assets" / "objects3d"

CATEGORIES: tuple[str, ...] = ("buildings", "props", "vegetation", "terrain")

THUMB_SIZE = 512
THUMB_SUFFIX = "_thumb.png"
DEFAULT_FOV_DEG = 38.0
DEFAULT_AZIMUTH_DEG = 35.0
DEFAULT_ELEVATION_DEG = 38.0
TRIANGLE_BUDGET = 5000

# Palette par defaut, partagee par les prototypes (couleurs sRGB -> linear
# plus bas via :func:`hex_to_rgba`). Modifiable par asset.
#
# Guide de style (demande produit) : palette echantillonnee sur les fonds peints
# Valbois - enduits creme/beige chaud, bois brun, toits terre cuite desaturee
# ou ardoise bleu-gris, pierre chaude, vegetation vert desature, encrage sombre.
# Materiaux mats (aucun reflet PBR) pour se fondre dans l'illustration.
DEFAULT_PALETTE: dict[str, str] = {
    # Pierre / maconnerie : gris chaud, jamais gris pur.
    "stone": "#8c887d",
    "stone_dark": "#6e6a61",
    "stone_light": "#a29d92",
    # Bois : brun moyen, brun sombre, brun clair.
    "wood": "#6d4b32",
    "wood_dark": "#4a3222",
    "wood_light": "#8a6242",
    # Toits : terre cuite desaturee et ardoise bleu-gris.
    "roof": "#9a5a45",
    "roof_dark": "#7a4536",
    "roof_slate": "#4c5a66",
    "roof_slate_dark": "#3b4650",
    # Enduits / colombages.
    "plaster": "#d9c7a6",
    "plaster_light": "#e3d4b8",
    "plaster_dark": "#bfa987",
    # Vegetation : verts tres desatures (olive), variante automne ocre.
    "leaf": "#5d6b45",
    "leaf_light": "#6f7d52",
    "leaf_dark": "#475336",
    "leaf_autumn": "#8a6a44",
    "leaf_autumn_light": "#9a784c",
    "leaf_autumn_dark": "#6f5538",
    # Divers.
    "water": "#4a6a70",
    "metal": "#53504a",
    "glow": "#d9b96a",
    "lamp": "#e0b768",
    "cloth": "#8a5248",
    "grass": "#64704a",
    "grass_dark": "#545e3e",
    "dirt": "#8a755c",
    # Encrage : contour "inverted hull" et details sombres.
    "ink": "#241f1a",
    # Foin / paille (botte de foin, toits de chaume eventuels) et osier.
    "hay": "#a98a4f",
    "hay_dark": "#7f6338",
    "hay_light": "#c4a96b",
    "wicker": "#9a7a4e",
    # Kit v3 : os, flamme emissive, fer sombre.
    "bone": "#cfc3a4",
    "bone_dark": "#a89c80",
    "flame": "#cf6f2a",
    "flame_core": "#e8a94e",
    "iron_dark": "#3d4043",
    "ember": "#7a4024",
    # Kit v4 : figurines PNJ (peau, cheveux) et accents.
    "skin": "#c79a6b",
    "skin_dark": "#a87c50",
    "hair": "#4b3626",
}

# Epaisseur (en case) des jupes de raccord au sol posees sous les objets.
GROUND_SKIRT_HEIGHT = 0.04
# Epaisseur (en case) du trait de contour (inverted hull) a l'echelle 1 case.
OUTLINE_THICKNESS = 0.014


# --------------------------------------------------------------------------- #
# Utilitaires generiques
# --------------------------------------------------------------------------- #


def log(message: str) -> None:
    """Print immediatement (utile en headless, Blender bufferise stdout)."""
    print(message, flush=True)


def cli_argv() -> list[str]:
    """Arguments utilisateur passes apres ``--`` a Blender."""
    argv = list(sys.argv)
    if "--" in argv:
        return argv[argv.index("--") + 1 :]
    return []


def slugify(value: str) -> str:
    """Nom de fichier sur : minuscules, ASCII, snake_case."""
    value = unicodedata.normalize("NFKD", value)
    value = value.encode("ascii", "ignore").decode("ascii")
    value = re.sub(r"[^a-zA-Z0-9]+", "_", value).strip("_").lower()
    return value or "asset"


def category_dir(category: str) -> Path:
    category = slugify(category)
    if category not in CATEGORIES:
        raise ValueError(
            f"Categorie inconnue: {category!r} (attendu: {', '.join(CATEGORIES)})"
        )
    return OBJECTS3D_ROOT / category


def asset_paths(category: str, name: str) -> tuple[Path, Path]:
    """(chemin .glb, chemin vignette) pour un asset."""
    base = category_dir(category)
    return base / f"{name}.glb", base / f"{name}{THUMB_SUFFIX}"


def hex_to_rgba(hex_color: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    """Hex sRGB -> RGBA lineaire (ce que Blender attend dans les noeuds)."""
    h = hex_color.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    srgb = [int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]

    def to_linear(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (to_linear(c) for c in srgb)
    return (r, g, b, alpha)


# --------------------------------------------------------------------------- #
# Scene
# --------------------------------------------------------------------------- #


def reset_scene() -> bpy.types.Scene:
    """Reinitialise une scene vide (pas de cube/camera/lumiere par defaut)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    # Unites glTF = metres, 1 unite = 1 case : on garde un scale neutre.
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    return scene


def select_only(
    objects: Sequence[bpy.types.Object],
    active: bpy.types.Object | None = None,
) -> None:
    """Selectionne exactement ``objects`` (et active le premier par defaut)."""
    objects = list(objects)
    if not objects:
        return
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = active or objects[0]


def apply_transforms(obj: bpy.types.Object) -> bpy.types.Object:
    """Applique rotation + scale (location conservee)."""
    select_only([obj], obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


# --------------------------------------------------------------------------- #
# Materiaux
# --------------------------------------------------------------------------- #


def make_material(
    name: str,
    color: str | tuple[float, float, float, float],
    roughness: float = 0.92,
    metallic: float = 0.0,
    emission: str | None = None,
    emission_strength: float = 1.0,
) -> bpy.types.Material:
    """Materiau PBR simple (Principled BSDF), compatible export glTF.

    ``color`` accepte un hex sRGB (``"#8c8880"``) ou un RGBA lineaire.

    Defauts = guide de style 2.5D : mat (roughness 0.92), aucun metal, tres
    peu de speculaire, pas de textures ni de transparence, pour ne pas jurer
    avec les fonds peints. ``use_backface_culling`` est active pour que le
    glTF exporte ``doubleSided: false`` (indispensable au contour "inverted
    hull" et au rendu correct des volumes fermes).
    """
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = True
    rgba = hex_to_rgba(color) if isinstance(color, str) else color
    mat.diffuse_color = rgba
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:  # pragma: no cover - Blender 4.x a toujours ce noeud
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.location = (0, 0)
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    # Specular : "Specular IOR Level" en Blender 4.x -> 0.15 = quasi mat.
    for input_name in ("Specular IOR Level", "Specular"):
        if input_name in bsdf.inputs:
            bsdf.inputs[input_name].default_value = 0.15
            break
    if emission:
        bsdf.inputs["Emission Color"].default_value = hex_to_rgba(emission)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def material_palette(
    palette: dict[str, str] | None = None,
    prefix: str = "",
    emissive: dict[str, float] | None = None,
) -> dict[str, bpy.types.Material]:
    """Construit un dict de materiaux a partir de :data:`DEFAULT_PALETTE`.

    ``emissive`` mappe une clé de palette à une force d'émission (ex.
    ``{"glow": 0.9}`` pour les fenêtres et le fanal de lanterne). L'émission
    est exportée en glTF et reconnue par Godot.
    """
    palette = {**DEFAULT_PALETTE, **(palette or {})}
    emissive = emissive or {}
    materials: dict[str, bpy.types.Material] = {}
    for key, hex_color in palette.items():
        strength = emissive.get(key)
        materials[key] = make_material(
            f"{prefix}{key}".strip("_"),
            hex_color,
            emission=hex_color if strength else None,
            emission_strength=strength or 1.0,
        )
    return materials


# --------------------------------------------------------------------------- #
# Primitives (toutes creees avec un materiau et transforms appliquees)
# --------------------------------------------------------------------------- #


def _finish_part(obj: bpy.types.Object, material: bpy.types.Material | None) -> bpy.types.Object:
    if material is not None:
        obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False  # low-poly : facettes franches
    apply_transforms(obj)
    return obj


def add_box(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
    material: bpy.types.Material | None = None,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Boite de dimensions ``size`` (largeur X, profondeur Y, hauteur Z)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    return _finish_part(obj, material)


def add_cylinder(
    name: str,
    radius: float,
    depth: float,
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
    material: bpy.types.Material | None = None,
    vertices: int = 12,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Cylindre droit (axe Z par defaut)."""
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    return _finish_part(obj, material)


def add_cone(
    name: str,
    radius1: float,
    depth: float,
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
    material: bpy.types.Material | None = None,
    vertices: int = 8,
    radius2: float = 0.0,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Cone / pointe (radius2 = 0 -> pointe)."""
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        end_fill_type="NGON",
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    return _finish_part(obj, material)


def add_ico_sphere(
    name: str,
    radius: float,
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
    material: bpy.types.Material | None = None,
    subdivisions: int = 1,
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
    jitter: float = 0.0,
    seed: int = 0,
) -> bpy.types.Object:
    """Ico-sphere low-poly, avec jitter optionnel (rochers, feuillages)."""
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions, radius=radius, location=location
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    if jitter > 0.0:
        rng = random.Random(seed)
        for vertex in obj.data.vertices:
            vertex.co += Vector(
                (
                    rng.uniform(-jitter, jitter),
                    rng.uniform(-jitter, jitter),
                    rng.uniform(-jitter, jitter),
                )
            )
    return _finish_part(obj, material)


def add_uv_sphere(
    name: str,
    radius: float,
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
    material: bpy.types.Material | None = None,
    segments: int = 12,
    ring_count: int = 8,
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=ring_count, radius=radius, location=location
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    return _finish_part(obj, material)


def add_torus(
    name: str,
    major_radius: float,
    minor_radius: float,
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
    material: bpy.types.Material | None = None,
    major_segments: int = 8,
    minor_segments: int = 4,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Tore low-poly (maillons de chaine, anneaux, poignees)."""
    bpy.ops.mesh.primitive_torus_add(
        major_segments=major_segments,
        minor_segments=minor_segments,
        major_radius=major_radius,
        minor_radius=minor_radius,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    return _finish_part(obj, material)


def add_mesh(
    name: str,
    vertices: Iterable[Sequence[float]],
    faces: Iterable[Sequence[int]],
    material: bpy.types.Material | None = None,
) -> bpy.types.Object:
    """Mesh arbitraire (coordonnees deja en espace monde, z=0 au sol)."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in vertices], [], [tuple(f) for f in faces])
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return _finish_part(obj, material)


def add_ground_skirt(
    name: str,
    size: tuple[float, float],
    material: bpy.types.Material,
    height: float = GROUND_SKIRT_HEIGHT,
    sides: int = 10,
    irregularity: float = 0.12,
    seed: int = 0,
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Jupe de raccord au sol : dalle elliptique irreguliere tres plate.

    Sert a eviter la coupure nette entre le mesh et le decor peint (herbe ou
    terre), et donne une base large aux objets. ``size`` = (largeur X,
    profondeur Y) de la dalle, en cases. L'ombre de contact reste geree par le
    moteur : rien n'est cuit ici.
    """
    rng = random.Random(seed)
    rx, ry = size[0] * 0.5, size[1] * 0.5
    lx, ly, lz = location
    ring: list[tuple[float, float]] = []
    for i in range(sides):
        angle = math.tau * i / sides
        wobble = 1.0 + rng.uniform(-irregularity, irregularity)
        ring.append((lx + math.cos(angle) * rx * wobble, ly + math.sin(angle) * ry * wobble))
    vertices = [(x, y, lz) for x, y in ring] + [(x, y, lz + height) for x, y in ring]
    faces: list[tuple[int, ...]] = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((i, j, sides + j, sides + i))
    faces.append(tuple(range(sides, 2 * sides)))  # dessus (+Z)
    faces.append(tuple(reversed(range(sides))))  # dessous (-Z)
    return add_mesh(name, vertices, faces, material)


# --------------------------------------------------------------------------- #
# Assemblage / normalisation d'un asset
# --------------------------------------------------------------------------- #


def join_objects(
    objects: Sequence[bpy.types.Object], name: str
) -> bpy.types.Object:
    """Fusionne les parties en un seul mesh nomme ``name``."""
    objects = [o for o in objects if o is not None]
    if not objects:
        raise ValueError("join_objects: aucune partie a fusionner")
    select_only(objects, objects[0])
    if len(objects) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    return obj


def _bounds_from_vertices(
    vertices: Iterable[Vector],
) -> tuple[Vector, Vector]:
    points = list(vertices)
    if not points:
        raise ValueError("_bounds_from_vertices: aucun sommet")
    xs = [v.x for v in points]
    ys = [v.y for v in points]
    zs = [v.z for v in points]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def object_bounds(objects: Sequence[bpy.types.Object]) -> tuple[Vector, Vector]:
    """Bounding box monde (evaluated) de plusieurs objets mesh."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mins = Vector((math.inf, math.inf, math.inf))
    maxs = Vector((-math.inf, -math.inf, -math.inf))
    for obj in objects:
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            for vertex in mesh.vertices:
                world = evaluated.matrix_world @ vertex.co
                mins = Vector((min(mins.x, world.x), min(mins.y, world.y), min(mins.z, world.z)))
                maxs = Vector((max(maxs.x, world.x), max(maxs.y, world.y), max(maxs.z, world.z)))
        finally:
            evaluated.to_mesh_clear()
    if math.isinf(mins.x):
        raise ValueError("object_bounds: aucun objet mesh")
    return mins, maxs


def object_dimensions(objects: Sequence[bpy.types.Object]) -> tuple[float, float, float]:
    """Dimensions (X, Y, Z) en cases de carte."""
    mins, maxs = object_bounds(objects)
    size = maxs - mins
    return (size.x, size.y, size.z)


def triangle_count(obj: bpy.types.Object) -> int:
    mesh = obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def normalize_asset(
    obj: bpy.types.Object, name: str, *, anchor: str = "base"
) -> bpy.types.Object:
    """Applique les conventions d'origine, transforms neutres.

    ``anchor="base"`` : origine au centre de la base, z=0, x/y du bbox centres.
    ``anchor="wall"`` : objet mural (torche, chaîne, enseigne) ; l'origine reste
    au **pied du mur** (z=0, x=0, y=0 dans l'espace de conception) sans recentrer
    le bbox ni plaquer le mesh au sol : le point d'ancrage est le bas du mur.
    """
    obj.name = name
    obj.data.name = name
    apply_transforms(obj)

    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    select_only([obj], obj)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

    mesh = obj.data
    if not mesh.vertices:
        raise ValueError(f"{name}: mesh vide")
    mins, maxs = _bounds_from_vertices((v.co for v in mesh.vertices))
    if anchor == "wall":
        # Le mesh est deja construit avec le mur en y=0 et le sol en z=0 :
        # on ne recentre pas, on verifie juste que la geometrie est au-dessus.
        if mins.z < -1e-4:
            raise ValueError(f"{name}: geometrie murale sous le sol (min_z={mins.z:.3f})")
    else:
        center_x = (mins.x + maxs.x) * 0.5
        center_y = (mins.y + maxs.y) * 0.5
        delta = Vector((-center_x, -center_y, -mins.z))
        if delta.length > 1e-9:
            for vertex in mesh.vertices:
                vertex.co += delta
            mesh.update()
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    return obj


def finalize_asset(
    parts: Sequence[bpy.types.Object], name: str, *, anchor: str = "base"
) -> bpy.types.Object:
    """Fusionne, normalise et valide un asset avant export."""
    obj = join_objects(parts, name)
    normalize_asset(obj, name, anchor=anchor)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    triangles = triangle_count(obj)
    if triangles > TRIANGLE_BUDGET:
        raise ValueError(
            f"{name}: {triangles} triangles > budget {TRIANGLE_BUDGET} (low-poly)"
        )
    return obj


# --------------------------------------------------------------------------- #
# Detail procedural : subdivision, AO/mottling en vertex colors, contour encre
# --------------------------------------------------------------------------- #


def subdivide_long_edges(
    obj: bpy.types.Object, *, max_length: float = 0.5, max_passes: int = 2
) -> int:
    """Decoupe les longues aretes pour que les vertex colors aient de la place.

    Les prototypes sont tres basse definition : sans subdivision, l'AO et le
    mottling n'ont que quelques sommets par face et restent invisibles. On
    subdivise uniquement les aretes plus longues que ``max_length`` (en cases)
    pour garder le budget poly bas.
    """
    import bmesh

    for _ in range(max(0, max_passes)):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        long_edges = [edge for edge in bm.edges if edge.calc_length() > max_length]
        if not long_edges:
            bm.free()
            break
        bmesh.ops.subdivide_edges(
            bm, edges=long_edges, cuts=1, use_grid_fill=True, use_only_quads=False
        )
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()

    # Nettoyage : la subdivision d'aretes isolees peut creer des triangles
    # degeneres (arete de longueur nulle) que le reimport glTF supprime, ce
    # qui fausserait le comptage de triangles de verify_glb.py.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()

    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return len(obj.data.vertices)


def triangulate_mesh(obj: bpy.types.Object) -> bpy.types.Object:
    """Triangule le mesh avant export (comptage de tris identique au reimport).

    L'exporteur glTF triangule lui-meme les quads/ngons ; si un ngon contient
    des sommets alignes, le triangle degenere produit peut etre supprime au
    reimport et fausser les verifications. On triangule donc explicitement.
    """
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(
        bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY"
    )
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def _hemisphere_direction(
    normal: Vector, tangent: Vector, bitangent: Vector, rng: random.Random
) -> Vector:
    """Direction d'echantillonnage cosinus-ponderee dans l'hemisphere."""
    r1 = rng.random()
    r2 = rng.random()
    phi = math.tau * r1
    cos_theta = math.sqrt(max(0.0, 1.0 - r2))
    sin_theta = math.sqrt(max(0.0, r2))
    return (
        tangent * (math.cos(phi) * sin_theta)
        + bitangent * (math.sin(phi) * sin_theta)
        + normal * cos_theta
    ).normalized()


def _mottle_noise(co: Vector, seed: int) -> float:
    """Bruit doux deterministe dans [-1, 1] (variation de teinte par sommet)."""
    return (
        math.sin(co.x * 9.1 + seed * 0.73)
        * math.sin(co.y * 8.3 + seed * 1.31)
        * math.sin(co.z * 7.7 + seed * 2.17)
    )


def bake_vertex_colors(
    obj: bpy.types.Object,
    *,
    seed: int = 0,
    ao_distance: float = 0.6,
    ao_samples: int = 20,
    ao_strength: float = 0.5,
    mottle_strength: float = 0.06,
    min_value: float = 0.5,
) -> int:
    """Cuit un AO approximatif + un mottling dans les vertex colors (COLOR_0).

    Les couleurs stockees sont **grises multiplicatrices** : le materiau garde
    sa couleur de palette (baseColorFactor glTF, multiplie par COLOR_0 chez
    Godot). Si un moteur ignore les vertex colors, l'objet garde donc ses
    couleurs plates : pas de casse, juste moins de volume.

    L'AO est calcule par lancer de rayons sur l'hemisphere du sommet (BVH
    locale), sans Cycles ni bake de texture : deterministe, headless, rapide.
    """
    from mathutils.bvhtree import BVHTree

    mesh = obj.data
    mesh.update()
    while mesh.color_attributes:
        mesh.color_attributes.remove(mesh.color_attributes[0])
    attribute = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")

    bvh = BVHTree.FromPolygons(
        [vertex.co.copy() for vertex in mesh.vertices],
        [tuple(polygon.vertices) for polygon in mesh.polygons],
        all_triangles=False,
        epsilon=0.0,
    )
    rng = random.Random(seed * 7919 + 13)
    for index, vertex in enumerate(mesh.vertices):
        normal = vertex.normal.copy()
        if normal.length < 1e-8:  # pragma: no cover - sommet isole
            normal = Vector((0.0, 0.0, 1.0))
        normal.normalize()
        tangent = normal.orthogonal()
        if tangent.length < 1e-8:  # pragma: no cover
            tangent = Vector((1.0, 0.0, 0.0))
        tangent.normalize()
        bitangent = normal.cross(tangent).normalized()
        origin = vertex.co + normal * 0.002
        hits = 0
        for _ in range(ao_samples):
            direction = _hemisphere_direction(normal, tangent, bitangent, rng)
            if bvh.ray_cast(origin, direction, ao_distance)[0] is not None:
                hits += 1
        ao = 1.0 - (hits / float(ao_samples))
        ao_factor = 1.0 - ao_strength * (1.0 - ao)
        noise = _mottle_noise(vertex.co, seed)
        value = ao_factor * (1.0 + mottle_strength * noise)
        value = max(min_value, min(1.0, value))
        attribute.data[index].color = (value, value, value, 1.0)

    mesh.color_attributes.active_color_index = 0
    mesh.color_attributes.render_color_index = 0
    return mesh.color_attributes.active_color_index


def build_outline(
    source: bpy.types.Object,
    material: bpy.types.Material,
    *,
    thickness: float = OUTLINE_THICKNESS,
    name: str | None = None,
) -> bpy.types.Object:
    """Contour "inverted hull" : coque decalee le long des normales, faces inversees.

    Combine avec ``use_backface_culling`` (doubleSided: false dans le glTF), la
    coque ne montre que sa face arriere : un trait sombre fin autour de la
    silhouette, qui rappelle l'encrage du decor peint. La coque est un objet
    separe, exporte dans le meme GLB.
    """
    import bmesh

    source_mesh = source.data
    normals = [vertex.normal.copy() for vertex in source_mesh.vertices]
    mesh = source_mesh.copy()
    for index, normal in enumerate(normals):
        if normal.length < 1e-8:  # pragma: no cover
            normal = Vector((0.0, 0.0, 1.0))
        normal.normalize()
        mesh.vertices[index].co = source_mesh.vertices[index].co + normal * thickness

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    mesh.materials.clear()
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.material_index = 0
        polygon.use_smooth = False

    outline = bpy.data.objects.new(name or f"{source.name}_outline", mesh)
    bpy.context.collection.objects.link(outline)
    outline.location = (0.0, 0.0, 0.0)
    outline.rotation_euler = (0.0, 0.0, 0.0)
    outline.scale = (1.0, 1.0, 1.0)
    # La coque ne doit pas projeter d'ombre ni participer a l'eclairage, sinon
    # elle assombrit tout l'objet (visible en EEVEE/Cycles et dans Godot si le
    # loader laisse cast_shadow actif : cf. docs, nom en *_outline).
    for flag in (
        "visible_shadow",
        "visible_diffuse",
        "visible_glossy",
        "visible_transmission",
        "visible_volume_scatter",
    ):
        if hasattr(outline, flag):
            setattr(outline, flag, False)
    return outline


def enable_vertex_color_preview(
    objects: Sequence[bpy.types.Object], *, layer_name: str = "Col"
) -> int:
    """Branche COLOR_0 en multiplication dans les materiaux, pour les rendus.

    A appeler **apres l'export GLB** : l'exporteur glTF deduit
    ``baseColorFactor`` du noeud Base Color, donc on garde des materiaux a
    couleur constante pendant l'export, puis on ajoute la multiplication
    vertex color pour que EEVEE/Cycles montre l'AO et le mottling dans les
    vignettes.
    """
    touched = 0
    seen: set[str] = set()
    for obj in objects:
        for slot in obj.material_slots:
            material = slot.material
            if material is None or material.name in seen or not material.use_nodes:
                continue
            seen.add(material.name)
            nodes = material.node_tree.nodes
            links = material.node_tree.links
            bsdf = nodes.get("Principled BSDF")
            if bsdf is None or "OQ_VC_Mix" in nodes:
                continue
            vertex_color = nodes.new("ShaderNodeVertexColor")
            vertex_color.name = "OQ_VertexColor"
            vertex_color.layer_name = layer_name
            vertex_color.location = (-620.0, -260.0)
            mix = nodes.new("ShaderNodeMixRGB")
            mix.name = "OQ_VC_Mix"
            mix.blend_type = "MULTIPLY"
            mix.inputs[0].default_value = 1.0
            mix.location = (-380.0, -240.0)
            base_color = bsdf.inputs["Base Color"]
            if base_color.is_linked:
                links.new(base_color.links[0].from_socket, mix.inputs[2])
            else:
                mix.inputs[2].default_value = tuple(base_color.default_value)
            links.new(vertex_color.outputs["Color"], mix.inputs[1])
            links.new(mix.outputs["Color"], base_color)
            touched += 1
    return touched


# --------------------------------------------------------------------------- #
# Export GLB
# --------------------------------------------------------------------------- #


def export_glb(
    filepath: str | Path,
    objects: Sequence[bpy.types.Object],
    *,
    apply_modifiers: bool = True,
    vertex_colors: str = "ACTIVE",
) -> Path:
    """Exporte les objets en GLB (Y-up, sans camera ni lumiere).

    Options verifiees sur Blender 4.5.10 LTS : ``export_apply``,
    ``export_yup``, ``export_cameras``, ``export_lights`` existent bien.
    ``vertex_colors="ACTIVE"`` force l'export du COLOR_0 actif (AO/mottling)
    meme si le materiau n'utilise pas de noeud vertex color : le glTF le
    multiplie alors a ``baseColorFactor``, conformement au spec.
    """
    filepath = Path(filepath)
    filepath.parent.mkdir(parents=True, exist_ok=True)
    meshes = [o for o in objects if o.type == "MESH"]
    if not meshes:
        raise ValueError("export_glb: aucun mesh a exporter")
    select_only(meshes, meshes[0])
    bpy.context.view_layer.update()
    bpy.ops.export_scene.gltf(
        filepath=str(filepath),
        export_format="GLB",
        use_selection=True,
        export_apply=apply_modifiers,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_skins=False,
        export_extras=False,
        export_materials="EXPORT",
        export_normals=True,
        export_texcoords=True,
        export_tangents=False,
        export_vertex_color=vertex_colors,
        export_all_vertex_colors=False,
        export_draco_mesh_compression_enable=False,
    )
    if not filepath.is_file() or filepath.stat().st_size == 0:
        raise RuntimeError(f"export_glb: fichier absent ou vide: {filepath}")
    return filepath


# --------------------------------------------------------------------------- #
# Rendu de vignette (EEVEE par defaut, Cycles CPU en secours)
# --------------------------------------------------------------------------- #


def _remove_object(obj: bpy.types.Object) -> None:
    data = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    try:
        if isinstance(data, bpy.types.Light):
            bpy.data.lights.remove(data)
        elif isinstance(data, bpy.types.Camera):
            bpy.data.cameras.remove(data)
    except (ReferenceError, RuntimeError):  # pragma: no cover - deja libere
        pass


def configure_render(
    scene: bpy.types.Scene,
    *,
    engine: str = "eevee",
    samples: int = 32,
    size: int = THUMB_SIZE,
    transparent: bool = True,
) -> str:
    """Configure le rendu vignette et renvoie le moteur effectivement utilise.

    ``engine`` : ``"eevee"`` (defaut, teste OK en headless sur 4.5.10) ou
    ``"cycles"`` (repli CPU). Si Cycles n'est pas disponible, on revient a
    EEVEE en le signalant.
    """
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = transparent
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.use_file_extension = True
    scene.render.fps = 24
    # Rendu stylise lisible : pas de AgX qui delave les couleurs.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    requested = engine.lower().strip()
    if requested in {"cycles", "cyles"}:
        try:
            bpy.ops.preferences.addon_enable(module="cycles")
        except Exception:  # pragma: no cover - addon absent
            pass
        try:
            scene.render.engine = "CYCLES"
        except (TypeError, ValueError):
            log("[warn] Cycles indisponible en headless, repli sur EEVEE")
            requested = "eevee"
        if scene.render.engine == "CYCLES":
            scene.cycles.device = "CPU"
            scene.cycles.samples = samples
            scene.cycles.use_denoising = True
            scene.cycles.max_bounces = 4
            scene.cycles.use_adaptive_sampling = True
            return "CYCLES"

    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.eevee.taa_render_samples = samples
    scene.eevee.use_shadows = True
    try:
        scene.eevee.use_gtao = True
        scene.eevee.gtao_distance = 0.6
        scene.eevee.gtao_quality = 1.25
    except AttributeError:  # pragma: no cover - variante de version
        pass
    return "BLENDER_EEVEE_NEXT"


def setup_world(
    scene: bpy.types.Scene,
    color: tuple[float, float, float] = (0.32, 0.36, 0.44),
    strength: float = 0.9,
) -> bpy.types.World:
    """Monde d'ambiance (eclaire l'objet meme avec film transparent)."""
    world = bpy.data.worlds.get("OQ_World")
    if world is None:
        world = bpy.data.worlds.new("OQ_World")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background is None:  # pragma: no cover
        background = world.node_tree.nodes.new("ShaderNodeBackground")
    background.inputs["Color"].default_value = (*color, 1.0)
    background.inputs["Strength"].default_value = strength
    scene.world = world
    return world


def _point_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_thumbnail_camera(
    objects: Sequence[bpy.types.Object],
    *,
    azimuth_deg: float = DEFAULT_AZIMUTH_DEG,
    elevation_deg: float = DEFAULT_ELEVATION_DEG,
    fov_deg: float = DEFAULT_FOV_DEG,
    margin: float = 1.14,
) -> bpy.types.Object:
    """Camera 3/4 cadrant l'objet entier (objet centre, marge reguliere).

    Azimut 0 = face avant (-Y en Blender) ; 35 deg de biais vers +X.
    Elevation 38 deg : vue 3/4 haute type carte 2.5D.
    """
    mins, maxs = object_bounds(objects)
    center = (mins + maxs) * 0.5
    radius = (maxs - mins).length * 0.5
    azimuth = math.radians(azimuth_deg)
    elevation = math.radians(elevation_deg)
    direction = Vector(
        (
            math.sin(azimuth) * math.cos(elevation),
            -math.cos(azimuth) * math.cos(elevation),
            math.sin(elevation),
        )
    ).normalized()
    distance = radius / math.tan(math.radians(fov_deg) * 0.5) * margin

    camera_data = bpy.data.cameras.new("OQ_ThumbCam")
    camera_data.angle = math.radians(fov_deg)
    camera_data.clip_start = 0.01
    camera_data.clip_end = 1000.0
    camera = bpy.data.objects.new("OQ_ThumbCam", camera_data)
    scene = bpy.context.scene
    scene.collection.objects.link(camera)
    camera.location = center + direction * distance
    _point_at(camera, center)
    scene.camera = camera
    return camera


def setup_studio_lights(
    objects: Sequence[bpy.types.Object],
) -> list[bpy.types.Object]:
    """Eclairage 3 points (cle soleil, fill froide, rim arriere)."""
    mins, maxs = object_bounds(objects)
    center = (mins + maxs) * 0.5
    radius = max((maxs - mins).length * 0.5, 0.2)
    scene = bpy.context.scene
    lights: list[bpy.types.Object] = []

    key_data = bpy.data.lights.new("OQ_Key", "SUN")
    key_data.energy = 3.2
    key_data.angle = math.radians(7.0)
    key_data.color = (1.0, 0.96, 0.90)
    key = bpy.data.objects.new("OQ_Key", key_data)
    scene.collection.objects.link(key)
    key.location = center + Vector((1.1, -0.9, 1.6)).normalized() * radius * 8.0
    _point_at(key, center)
    lights.append(key)

    fill_data = bpy.data.lights.new("OQ_Fill", "AREA")
    fill_data.energy = 260.0
    fill_data.size = radius * 4.0
    fill_data.color = (0.80, 0.87, 1.0)
    fill = bpy.data.objects.new("OQ_Fill", fill_data)
    scene.collection.objects.link(fill)
    fill.location = center + Vector((-1.5, -0.8, 0.9)).normalized() * radius * 5.0
    _point_at(fill, center)
    lights.append(fill)

    rim_data = bpy.data.lights.new("OQ_Rim", "AREA")
    rim_data.energy = 150.0
    rim_data.size = radius * 3.0
    rim_data.color = (1.0, 0.93, 0.82)
    rim = bpy.data.objects.new("OQ_Rim", rim_data)
    scene.collection.objects.link(rim)
    rim.location = center + Vector((0.4, 1.6, 1.2)).normalized() * radius * 5.0
    _point_at(rim, center)
    lights.append(rim)
    return lights


def render_thumbnail(
    filepath: str | Path,
    objects: Sequence[bpy.types.Object],
    *,
    engine: str = "eevee",
    samples: int = 32,
    size: int = THUMB_SIZE,
    transparent: bool = True,
    azimuth_deg: float = DEFAULT_AZIMUTH_DEG,
    elevation_deg: float = DEFAULT_ELEVATION_DEG,
    fov_deg: float = DEFAULT_FOV_DEG,
    margin: float = 1.14,
    cleanup: bool = True,
) -> tuple[Path, str]:
    """Rend ``<nom>_thumb.png`` et renvoie (chemin, moteur utilise)."""
    filepath = Path(filepath)
    filepath.parent.mkdir(parents=True, exist_ok=True)
    if not objects:
        raise ValueError("render_thumbnail: aucun objet")
    scene = bpy.context.scene
    effective_engine = configure_render(
        scene, engine=engine, samples=samples, size=size, transparent=transparent
    )
    setup_world(scene)
    camera = add_thumbnail_camera(
        objects,
        azimuth_deg=azimuth_deg,
        elevation_deg=elevation_deg,
        fov_deg=fov_deg,
        margin=margin,
    )
    lights = setup_studio_lights(objects)
    scene.render.filepath = str(filepath)
    try:
        bpy.ops.render.render(write_still=True)
    finally:
        if cleanup:
            for light in lights:
                _remove_object(light)
            _remove_object(camera)
            scene.camera = None
    if not filepath.is_file() or filepath.stat().st_size == 0:
        raise RuntimeError(f"render_thumbnail: PNG absent ou vide: {filepath}")
    return filepath, effective_engine


# --------------------------------------------------------------------------- #
# Rapport
# --------------------------------------------------------------------------- #


def asset_report(obj: bpy.types.Object) -> dict[str, object]:
    """Metadonnees d'un asset (triangles, dimensions en cases)."""
    dims = object_dimensions([obj])
    return {
        "name": obj.name,
        "triangles": triangle_count(obj),
        "dimensions_cells": tuple(round(d, 3) for d in dims),
    }


def describe_outputs(
    glb_path: Path,
    thumb_path: Path | None,
    *,
    obj: bpy.types.Object | None = None,
) -> str:
    glb_kb = glb_path.stat().st_size / 1024.0
    parts = [f"{glb_path.parent.name}/{glb_path.name} ({glb_kb:.1f} Ko)"]
    if thumb_path is not None and thumb_path.is_file():
        parts.append(f"{thumb_path.name} ({thumb_path.stat().st_size / 1024.0:.1f} Ko)")
    if obj is not None:
        dims = object_dimensions([obj])
        parts.append(
            f"{triangle_count(obj)} tris, {dims[0]:.2f} x {dims[1]:.2f} x {dims[2]:.2f} cases"
        )
    return " | ".join(parts)

