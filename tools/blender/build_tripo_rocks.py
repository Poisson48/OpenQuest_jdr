"""Integre les rochers Tripo3D dans la bibliotheque 3D du jeu.

Les quatre prototypes generes par le service Tripo3D (rocher_socle, rocher_bloc,
rocher_coin, rocher_couronne) ont ete juges **trop plats pour etre empiles** en
kit de mur. Ils restent utiles comme **rochers decoratifs / affleurements** :
ce script les prepare a la qualite du kit Valbois et les exporte dans
``game/assets/objects3d/terrain/``.

Usage :
  blender --background --python-exit-code 1 --python tools/blender/build_tripo_rocks.py -- \
      [--source DIR] [--out DIR] [--only nom ...] [--no-thumbs] [--no-manifest] \
      [--texture-size 512] [--tris-budget 1500] [--smooth] [--no-moss] [--samples 32]

Pipeline par asset :
  1. chargement du GLB deja recoloré (``recolored_1024``, textures 1024) ;
  2. fusion en un seul mesh, budget triangles (decimation COLLAPSE si depasse) ;
  3. orientation + echelle uniforme (emprise ~1,7-2,2 cases), pivot au centre
     de la base (z=0), face avant vers +Z (convention glTF/Godot) ;
  4. palette Valbois : albedo Tripo desature/remonte/teinte chaude (sRGB),
     materiau mat (metallic 0, roughness 0.92), normale conservee (detail de
     surface), ORM photographique abandonne (le kit est mat) ;
  5. AO + mottling en vertex colors (COLOR_0), comme le kit existant ;
  6. export GLB autonome (textures JPEG embarquees, pas de transparence),
     vignette 512x512 fond transparent, rapport JSON de mesures.

Les noms de livraison sont ``bloc_rocheux_{socle,bloc,coin,couronne}``.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector, noise

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import oq_common as oq  # noqa: E402

DEFAULT_SOURCE = oq.REPO_ROOT / "artifacts" / "tripo-review" / "rock-kit" / "recolored_1024"
DEFAULT_OUT = oq.OBJECTS3D_ROOT / "terrain"
DEFAULT_REPORT = oq.REPO_ROOT / "artifacts" / "tripo-review" / "rock-kit" / "build_report.json"

## Budget de triangles par asset (kit Valbois : < 5000, contrainte de cette
## integration : < 1500, la source Tripo en compte ~1000).
TRIANGLE_BUDGET = 1500
## Taille des textures embarquees (albedo + normale). 512 suffit pour des
## rochers de ~2 cases et divise le poids du GLB.
TEXTURE_SIZE = 512
JPEG_QUALITY = 88

## Correction de palette appliquee a l'albedo Tripo (valeurs sRGB, comme
## tools/blender/recolor_glb.py) : albedos deja desatures par le recolor, on
## les remonte de ~30 % (le kit Valbois est plus clair que la roche Tripo) et
## on les rechauffe legerement pour coller a la pierre chaude du projet.
PALETTE_SATURATION = 0.92
PALETTE_VALUE = 1.26
PALETTE_TINT = (1.08, 1.00, 0.88)
## AO/mottling en vertex colors, valeurs du kit (0.45 / 0.05).
AO_STRENGTH = 0.50
MOTTLE_STRENGTH = 0.07
AO_MIN_VALUE = 0.55
## Mousse/lichen : tache de teinte verte multipliee sur les faces tournees vers
## le ciel, comme la mousse des rochers peints du kit Valbois. Les taches sont
## eparses (bruit seuille) pour laisser la pierre dominer.
MOSS_STRENGTH = 0.52
MOSS_TINT = (0.72, 0.96, 0.56)
MOSS_SCALE = 3.4

## Une entree par rocher. ``footprint_cells`` est la plus grande dimension
## horizontale visee (en cases) : les rochers deviennent des affleurements de
## ~2 cases, coherents avec gros_rocher (2.1) et falaise (2.3).
## ``yaw_deg`` oriente la face la plus lisible vers +Z (avant glTF).
SPECS: tuple[dict[str, object], ...] = (
    {
        "source": "rocher_socle",
        "name": "bloc_rocheux_socle",
        "role": "socle",
        "footprint_cells": 2.05,
        "yaw_deg": 0.0,
        "description": (
            "Affleurement bas à deux assises, large et stable : rocher décoratif "
            "posé au sol, bord de chemin ou socle d'un petit relief. Rocher "
            "Tripo3D retravaillé (non empilable)."
        ),
        "tags": ["rocher", "affleurement", "decor", "tripo", "bas"],
    },
    {
        "source": "rocher_bloc",
        "name": "bloc_rocheux_bloc",
        "role": "bloc",
        "footprint_cells": 1.95,
        "yaw_deg": 0.0,
        "description": (
            "Dalle rocheuse compacte et fissurée, affleurant du sol : décor "
            "minéral, obstacle bas, bord de sentier. Rocher Tripo3D retravaillé "
            "(non empilable)."
        ),
        "tags": ["rocher", "affleurement", "decor", "tripo", "dalle"],
    },
    {
        "source": "rocher_coin",
        "name": "bloc_rocheux_coin",
        "role": "coin",
        "footprint_cells": 1.75,
        "yaw_deg": 0.0,
        "description": (
            "Rocher incliné en arête, haut sur un côté : décor d'affleurement "
            "vertical, entrée de grotte ou pierre levée. Rocher Tripo3D "
            "retravaillé (non empilable)."
        ),
        "tags": ["rocher", "affleurement", "decor", "tripo", "arete"],
    },
    {
        "source": "rocher_couronne",
        "name": "bloc_rocheux_couronne",
        "role": "couronne",
        "footprint_cells": 2.0,
        "yaw_deg": 0.0,
        "description": (
            "Dalle plate basse, comme une pierre affleurante : dalle de sol, "
            "pas japonais, support de décor. Rocher Tripo3D retravaillé (non "
            "empilable)."
        ),
        "tags": ["rocher", "affleurement", "decor", "tripo", "dalle"],
    },
)

CATEGORY = "terrain"


# --------------------------------------------------------------------------- #
# Arguments / petites aides
# --------------------------------------------------------------------------- #


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default=str(DEFAULT_SOURCE))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--report", default=str(DEFAULT_REPORT))
    parser.add_argument("--only", nargs="+", default=None,
                        help="noms de livraison (bloc_rocheux_*) a construire")
    parser.add_argument("--no-thumbs", action="store_true")
    parser.add_argument("--no-manifest", action="store_true")
    parser.add_argument("--manifest-only", action="store_true",
                        help="ne reconstruit rien : reinjecte --report dans le manifeste")
    parser.add_argument("--texture-size", type=int, default=TEXTURE_SIZE)
    parser.add_argument("--tris-budget", type=int, default=TRIANGLE_BUDGET)
    parser.add_argument("--no-moss", action="store_true",
                        help="pas de teinte mousse (pierre nue)")
    parser.add_argument("--smooth", action="store_true",
                        help="ombrage lisse (defaut : facettes low-poly du kit)")
    parser.add_argument("--samples", type=int, default=32)
    return parser.parse_args(argv)


def _upstream_image(socket: bpy.types.NodeSocket) -> bpy.types.Image | None:
    """Premiere image trouvee en remontant le graphe de noeuds depuis un socket."""
    seen: set[str] = set()
    stack = [socket]
    while stack:
        current = stack.pop()
        for link in current.links:
            node = link.from_node
            if node.name in seen:
                continue
            seen.add(node.name)
            if node.type == "TEX_IMAGE" and node.image is not None:
                return node.image
            for node_input in node.inputs:
                if node_input.is_linked:
                    stack.append(node_input)
    return None


def material_images(obj: bpy.types.Object) -> tuple[bpy.types.Image | None, bpy.types.Image | None]:
    """Renvoie (albedo, normale) du materiau importe depuis Tripo."""
    if not obj.material_slots:
        return None, None
    material = obj.material_slots[0].material
    if material is None or not material.use_nodes:
        return None, None
    bsdf = next(
        (node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"),
        None,
    )
    if bsdf is None:
        return None, None
    albedo = _upstream_image(bsdf.inputs["Base Color"])
    normal = _upstream_image(bsdf.inputs["Normal"])
    return albedo, normal


def load_mesh(source: Path) -> bpy.types.Object:
    """Importe le GLB Tripo et fusionne ses meshes en un objet unique."""
    oq.reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError(f"{source.name}: aucun mesh importe")
    obj = oq.join_objects(meshes, source.stem)
    oq.apply_transforms(obj)
    return obj


def decimate_to_budget(obj: bpy.types.Object, budget: int) -> tuple[int, bool]:
    """Decime le mesh si necessaire. Renvoie (tris avant, decime?)."""
    before = oq.triangle_count(obj)
    if before <= budget:
        return before, False
    # Marge de securite : viser 92 % du budget, le COLLAPSE peut varier.
    ratio = max(0.05, min(1.0, (budget * 0.92) / float(before)))
    modifier = obj.modifiers.new("tripo_budget", "DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    return before, True


def orient_and_scale(obj: bpy.types.Object, footprint_cells: float, yaw_deg: float) -> dict[str, float]:
    """Echelle uniforme vers l'emprise visee puis rotation autour de Z.

    Les transforms passent par l'objet (et non par les vertices) pour que
    Blender repercute correctement les normales personnalisees importees.
    """
    dims_before = oq.object_dimensions([obj])
    footprint_before = max(dims_before[0], dims_before[1])
    factor = footprint_cells / max(footprint_before, 1e-6)
    obj.scale = (factor, factor, factor)
    obj.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    oq.apply_transforms(obj)
    dims_after = oq.object_dimensions([obj])
    return {
        "footprint_before_cells": footprint_before,
        "scale_factor": factor,
        "height_before_cells": dims_before[2],
        "height_after_cells": dims_after[2],
    }


def resize_image(source: bpy.types.Image, size: int, name: str,
                 colorspace: str) -> bpy.types.Image:
    """Redimensionne une image importee et la remplace par une image generee.

    L'exporteur glTF re-encode de facon fiable les images ``GENERATED`` (alors
    qu'une image packee non modifiee est recopiee telle quelle, sans tenir
    compte d'un ``scale()``), ce qui garantit la taille et le poids annonces.
    Les pixels sont manipules dans l'espace de l'image (sRGB pour l'albedo,
    Non-Color pour la normale), comme le fait ``recolor_glb.py``.
    """
    source.scale(size, size)
    width, height = source.size
    if (width, height) != (size, size):  # pragma: no cover - garde-fou API
        raise RuntimeError(f"{name}: redimensionnement impossible ({width}x{height})")
    buffer = np.empty(width * height * 4, dtype=np.float32)
    source.pixels.foreach_get(buffer)
    image = bpy.data.images.new(name, width=width, height=height, alpha=True)
    image.colorspace_settings.name = colorspace
    image.pixels.foreach_set(buffer)
    image.update()
    return image


def apply_palette(image: bpy.types.Image) -> None:
    """Desature, eclaire et teinte l'albedo dans l'espace sRGB (in-place)."""
    width, height = image.size
    buffer = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(buffer)
    pixels = buffer.reshape(-1, 4)
    rgb = pixels[:, :3]
    luminance = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    corrected = (
        (luminance[:, None] + (rgb - luminance[:, None]) * PALETTE_SATURATION)
        * PALETTE_VALUE
        * np.array(PALETTE_TINT, dtype=np.float32)
    )
    np.clip(corrected, 0.0, 1.0, out=corrected)
    rgb[:] = corrected
    image.pixels.foreach_set(buffer)
    image.update()


def rebuild_matte_material(obj: bpy.types.Object, albedo: bpy.types.Image,
                           normal: bpy.types.Image | None) -> bpy.types.Material:
    """Materiau mat du kit : albedo + normale, metallic 0, roughness 0.92.

    L'ORM photographique de Tripo est abandonne : le kit Valbois n'utilise pas
    de metallic/roughness map et les rochers doivent rester mats. Les images
    inutilisees sont purgees pour ne pas etre embarquees dans le GLB.
    """
    previous_materials = [slot.material for slot in obj.material_slots if slot.material]
    material = bpy.data.materials.new(f"{obj.name}_stone")
    material.use_nodes = True
    material.use_backface_culling = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:  # pragma: no cover - Blender 4.x a toujours ce noeud
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.92
    for input_name in ("Specular IOR Level", "Specular"):
        if input_name in bsdf.inputs:
            bsdf.inputs[input_name].default_value = 0.15
            break

    albedo_node = nodes.new("ShaderNodeTexImage")
    albedo_node.name = "OQ_Albedo"
    albedo_node.image = albedo
    albedo_node.location = (-620.0, 320.0)
    links.new(albedo_node.outputs["Color"], bsdf.inputs["Base Color"])

    if normal is not None:
        normal_node = nodes.new("ShaderNodeTexImage")
        normal_node.name = "OQ_Normal"
        normal_node.image = normal
        normal_node.location = (-760.0, -220.0)
        normal_map = nodes.new("ShaderNodeNormalMap")
        normal_map.location = (-420.0, -220.0)
        links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
        links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])

    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
    # L'ancien materiau Tripo n'est plus utilise : on le libere pour que ses
    # images (ORM photographique) ne trainent pas dans le fichier.
    for old_material in previous_materials:
        if old_material.users == 0:
            bpy.data.materials.remove(old_material)
    return material


def _smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge1 <= edge0:  # pragma: no cover - garde-fou
        return 1.0 if value >= edge1 else 0.0
    t = min(1.0, max(0.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def add_moss(obj: bpy.types.Object, seed: int) -> None:
    """Teinte de mousse/lichen sur les faces tournees vers le ciel.

    Modifie les vertex colors (COLOR_0) deja cuits par ``bake_vertex_colors`` :
    un bruit deterministe decoupe des taches, ponderees par la normale montante.
    Le materiau reste sans texture de mousse : c'est le meme multiplie-color que
    le reste du kit, donc lisible sans transparence ni second materiau.
    """
    mesh = obj.data
    attribute = mesh.color_attributes.active_color
    if attribute is None:  # pragma: no cover - bake_vertex_colors en cree une
        raise RuntimeError(f"{obj.name}: vertex colors absentes")
    offset = Vector(
        (
            1.7 + (seed % 97) * 0.113,
            3.1 + (seed % 89) * 0.071,
            0.9 + (seed % 83) * 0.053,
        )
    )
    for index, vertex in enumerate(mesh.vertices):
        normal = vertex.normal.normalized()
        up = max(0.0, normal.z)
        patch = noise.noise(vertex.co * MOSS_SCALE + offset)
        # Deux seuils : la face doit regarder le ciel ET tomber dans une tache
        # de bruit. Sans le second, tout le dessus du rocher verdit.
        up_factor = _smoothstep(0.22, 0.80, up)
        patch_factor = _smoothstep(0.48, 0.82, 0.5 + 0.5 * patch)
        moss = up_factor * patch_factor * MOSS_STRENGTH
        if moss <= 0.0:
            continue
        color = attribute.data[index].color
        attribute.data[index].color = (
            color[0] * (1.0 + (MOSS_TINT[0] - 1.0) * moss),
            color[1] * (1.0 + (MOSS_TINT[1] - 1.0) * moss),
            color[2] * (1.0 + (MOSS_TINT[2] - 1.0) * moss),
            1.0,
        )


def purge_unused_images() -> None:
    for image in list(bpy.data.images):
        if image.users == 0:
            bpy.data.images.remove(image)


def verify_asset(obj: bpy.types.Object) -> None:
    """Controles de la convention du kit (pivot, centrage, transforms)."""
    mins, maxs = oq.object_bounds([obj])
    if abs(mins.z) > 0.005:
        raise RuntimeError(f"{obj.name}: base pas au sol (min_z={mins.z:.4f})")
    center_x = (mins.x + maxs.x) * 0.5
    center_y = (mins.y + maxs.y) * 0.5
    if abs(center_x) > 0.01 or abs(center_y) > 0.01:
        raise RuntimeError(
            f"{obj.name}: base non centree (x={center_x:.4f}, y={center_y:.4f})"
        )
    triangles = oq.triangle_count(obj)
    if triangles > TRIANGLE_BUDGET:
        raise RuntimeError(f"{obj.name}: {triangles} tris > budget {TRIANGLE_BUDGET}")


# --------------------------------------------------------------------------- #
# Construction d'un asset
# --------------------------------------------------------------------------- #


def build_asset(spec: dict[str, object], source_root: Path, out_root: Path,
                args: argparse.Namespace) -> dict[str, object]:
    name = str(spec["name"])
    source_path = source_root / f"{spec['source']}.glb"
    if not source_path.is_file():
        raise FileNotFoundError(f"source absente : {source_path}")

    obj = load_mesh(source_path)
    albedo_source, normal_source = material_images(obj)
    if albedo_source is None:
        raise RuntimeError(f"{name}: aucune texture d'albedo dans le GLB source")

    triangles_before, decimated = decimate_to_budget(obj, args.tris_budget)
    scale_report = orient_and_scale(obj, float(spec["footprint_cells"]), float(spec["yaw_deg"]))
    oq.normalize_asset(obj, name)

    # Textures : albedo retravaille en 512, normale en 512 (jachere si absente).
    albedo = resize_image(albedo_source, args.texture_size, f"{name}_albedo", "sRGB")
    apply_palette(albedo)
    normal = None
    if normal_source is not None:
        normal = resize_image(normal_source, args.texture_size, f"{name}_normale", "Non-Color")
    rebuild_matte_material(obj, albedo, normal)
    purge_unused_images()

    # AO + mottling en vertex colors, comme le kit (COLOR_0).
    seed = 20261112 + int(SPECS.index(spec)) * 131
    oq.bake_vertex_colors(
        obj, seed=seed, ao_strength=AO_STRENGTH,
        mottle_strength=MOTTLE_STRENGTH, min_value=AO_MIN_VALUE,
    )
    if not args.no_moss:
        add_moss(obj, seed)
    if args.smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    else:
        # Les normales personnalisees du GLB Tripo priment sur use_smooth :
        # il faut les effacer pour obtenir de vraies facettes low-poly.
        oq.select_only([obj], obj)
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
        for polygon in obj.data.polygons:
            polygon.use_smooth = False

    verify_asset(obj)
    triangles = oq.triangle_count(obj)
    dimensions = oq.object_dimensions([obj])
    vertices = len(obj.data.vertices)

    glb_path = out_root / f"{name}.glb"
    oq.export_glb(
        glb_path, [obj], image_format="JPEG", image_quality=JPEG_QUALITY,
    )

    thumb_path = out_root / f"{name}{oq.THUMB_SUFFIX}"
    engine = ""
    if not args.no_thumbs:
        # Le preview vertex color se branche APRES l'export (sinon le
        # baseColorFactor glTF serait remplace par du blanc).
        oq.enable_vertex_color_preview([obj])
        _, engine = oq.render_thumbnail(
            thumb_path, [obj], engine="eevee", samples=args.samples
        )

    report: dict[str, object] = {
        "name": name,
        "source": _display_path(source_path),
        "role": spec["role"],
        "description": spec["description"],
        "tags": list(spec["tags"]),
        "glb": _display_path(glb_path),
        "thumb": _display_path(thumb_path),
        "glb_bytes": glb_path.stat().st_size,
        "thumb_bytes": thumb_path.stat().st_size if thumb_path.is_file() else 0,
        "triangles": triangles,
        "triangles_before_decimation": triangles_before,
        "decimated": decimated,
        "vertices": vertices,
        "dimensions_cells": [round(value, 3) for value in dimensions],
        "height_above_floor": round(dimensions[2], 3),
        "scale_factor": round(float(scale_report["scale_factor"]), 4),
        "footprint_before_cells": round(float(scale_report["footprint_before_cells"]), 3),
        "height_before_cells": round(float(scale_report["height_before_cells"]), 3),
        "yaw_deg": float(spec["yaw_deg"]),
        "textures": {
            "albedo": {"size": args.texture_size, "format": "JPEG", "quality": JPEG_QUALITY},
            "normal": {"size": args.texture_size} if normal is not None else None,
            "orm": "abandonnee (materiau mat)",
        },
        "vertex_colors": "COLOR_0 : AO + mottling + teinte mousse (gris/vert)",
        "material": "mat : metallic 0, roughness 0.92, specular 0.15",
        "shading": "smooth" if args.smooth else "flat (facettes low-poly du kit)",
        "moss": not args.no_moss,
        "thumbnail_engine": engine,
    }
    oq.log(
        "[OK] {name}: {triangles} tris, {dims} cases, {glb_kb:.0f} Ko GLB, "
        "{thumb_kb:.0f} Ko vignette".format(
            name=name,
            triangles=triangles,
            dims=" x ".join(f"{value:.2f}" for value in dimensions),
            glb_kb=report["glb_bytes"] / 1024.0,
            thumb_kb=report["thumb_bytes"] / 1024.0,
        )
    )
    return report


# --------------------------------------------------------------------------- #
# Manifeste
# --------------------------------------------------------------------------- #


def _display_path(path: Path) -> str:
    """Chemin relatif au depot si possible (lisible dans le rapport)."""
    try:
        return str(path.resolve().relative_to(oq.REPO_ROOT)).replace("\\", "/")
    except ValueError:
        return str(path).replace("\\", "/")


def manifest_entry(report: dict[str, object]) -> dict[str, object]:
    name = str(report["name"])
    dimensions = [float(value) for value in report["dimensions_cells"]]
    return {
        "name": name,
        "base": name,
        "variant": "base",
        "category": CATEGORY,
        "glb": f"{CATEGORY}/{name}.glb",
        "thumb": f"{CATEGORY}/{name}_thumb.png",
        "description": report["description"],
        "tags": list(report["tags"]),
        "dimensions_cells": dimensions,
        "height_above_floor": float(report["height_above_floor"]),
        "anchor": "base",
        "triangles": int(report["triangles"]),
        "triangles_base": int(report["triangles"]),
        "vertices": int(report["vertices"]),
        "vertex_colors": report["vertex_colors"],
        "outline": False,
        "source_glb": report["source"],
        "source_service": "Tripo3D P1-20260311",
        "textures": "albedo + normale 512 JPEG embarquees, aucune transparence",
        "material": report["material"],
        "generator": "tools/blender/build_tripo_rocks.py",
    }


def update_manifest(out_root: Path, reports: list[dict[str, object]], only: list[str] | None) -> None:
    candidates = (out_root / "manifest.json", out_root.parent / "manifest.json")
    manifest_path = next((path for path in candidates if path.is_file()), None)
    if manifest_path is None:
        raise FileNotFoundError(f"manifeste introuvable (essaye {', '.join(map(str, candidates))})")
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    assets = [item for item in payload.get("assets", []) if isinstance(item, dict)]
    # Conservation du reste du catalogue (build partiel) : on ne remplace que
    # les entrees construites cette fois-ci, plus celles deja sur le disque.
    known = set(only or [str(report["name"]) for report in reports])
    merged: dict[str, dict[str, object]] = {}
    for item in assets:
        item_name = str(item.get("name", ""))
        if item_name and item_name not in known:
            merged[item_name] = item
    for report in reports:
        merged[str(report["name"])] = manifest_entry(report)
    payload["assets"] = sorted(
        merged.values(), key=lambda item: (str(item.get("category")), str(item.get("name")))
    )
    manifest_path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    oq.log(f"[OK] manifeste: {manifest_path} ({len(payload['assets'])} assets)")


# --------------------------------------------------------------------------- #
# Entree
# --------------------------------------------------------------------------- #


def main() -> int:
    args = parse_args()
    source_root = Path(args.source).resolve()
    out_root = Path(args.out).resolve()
    out_root.mkdir(parents=True, exist_ok=True)
    specs = list(SPECS)
    if args.only:
        wanted = {name.lower() for name in args.only}
        specs = [spec for spec in specs if str(spec["name"]).lower() in wanted]
        if not specs:
            missing = ", ".join(sorted(wanted))
            oq.log(f"[ERREUR] --only ne correspond a aucun rocher ({missing})")
            return 2

    reports: list[dict[str, object]] = []
    failures: list[str] = []
    if args.manifest_only:
        # Reprise rapide : on reinjecte le dernier rapport sans reconstruire
        # les GLB (utile si seul le manifeste a echoue).
        previous = json.loads(Path(args.report).read_text(encoding="utf-8"))
        reports = [item for item in previous.get("assets", []) if isinstance(item, dict)]
        if not reports:
            oq.log(f"[ERREUR] rapport vide ou illisible : {args.report}")
            return 2
        update_manifest(Path(args.out).resolve(), reports, args.only)
        oq.log(f"TRIPO_ROCKS_RESULT manifest_only={len(reports)}")
        return 0
    for spec in specs:
        try:
            reports.append(build_asset(spec, source_root, out_root, args))
        except Exception as exc:  # noqa: BLE001 - on continue les autres assets
            failures.append(f"{spec['name']}: {exc}")
            oq.log(f"[ECHEC] {spec['name']}: {exc}")

    if reports:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            json.dumps(
                {
                    "generated_by": "tools/blender/build_tripo_rocks.py",
                    "blender_version": bpy.app.version_string,
                    "source_root": _display_path(source_root),
                    "triangle_budget": args.tris_budget,
                    "texture_size": args.texture_size,
                    "jpeg_quality": JPEG_QUALITY,
                    "palette": {
                        "saturation": PALETTE_SATURATION,
                        "value": PALETTE_VALUE,
                        "tint_srgb": list(PALETTE_TINT),
                        "ao_strength": AO_STRENGTH,
                        "mottle_strength": MOTTLE_STRENGTH,
                        "ao_min_value": AO_MIN_VALUE,
                        "moss_strength": 0.0 if args.no_moss else MOSS_STRENGTH,
                        "moss_tint": list(MOSS_TINT),
                    },
                    "assets": reports,
                },
                indent=2,
                ensure_ascii=False,
            )
            + "\n",
            encoding="utf-8",
        )
        oq.log(f"[OK] rapport: {report_path}")

    if reports and not args.no_manifest:
        try:
            update_manifest(out_root, reports, args.only)
        except Exception as exc:  # noqa: BLE001 - le GLB reste livre
            failures.append(f"manifeste: {exc}")
            oq.log(f"[ECHEC] manifeste: {exc}")

    oq.log("-" * 78)
    oq.log(
        f"TRIPO_ROCKS_RESULT ok={len(reports)} echecs={len(failures)}"
        + ("" if not failures else " -> " + ", ".join(failures))
    )
    oq.log("=" * 78)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
