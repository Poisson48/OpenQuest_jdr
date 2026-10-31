"""Controle qualite des assets 3D generes : GLB + vignettes.

Deux verifications independantes :

1. **Lecture directe du conteneur GLB** (sans Blender) : pas de camera, pas de
   lumiere, pas de materiau transparent, comptage des triangles via les
   accessors glTF, transformations de noeuds.
2. **Reimport dans une scene Blender vide** : nombre d'objets/vertices/
   triangles, bounding box et respect des conventions (origine au pied, base
   centree sur 0, 1 unite = 1 case).

Les vignettes sont aussi controlees (512x512, alpha transparent autour de
l'objet, objet visible au centre).

Utilisation :

    & "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" `
        --background --python-exit-code 1 `
        --python tools/blender/verify_glb.py -- [--root DIR] [--only nom ...]

Sortie : une ligne par asset (``[OK]`` / ``[ECHEC]``) et un recapitulatif.
Code de sortie 1 si au moins un asset est en echec.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402
import numpy as np  # noqa: E402 (fourni avec Blender)

import oq_common as oq  # noqa: E402
from oq_common import (  # noqa: E402
    THUMB_SIZE,
    TRIANGLE_BUDGET,
    log,
    object_bounds,
    object_dimensions,
    reset_scene,
    triangle_count,
)

GLB_MAGIC = 0x46546C67
GLB_JSON_CHUNK = 0x4E4F534A
MAX_ORIGIN_TOLERANCE = 0.02  # en cases
MAX_CENTER_TOLERANCE = 0.02
MAX_GROUND_TOLERANCE = 0.02


# --------------------------------------------------------------------------- #
# Lecture directe du GLB (JSON chunk)
# --------------------------------------------------------------------------- #


def read_glb_json(path: Path) -> tuple[dict, int]:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError("fichier GLB trop court")
    magic, version, _total = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError("magic GLB invalide")
    offset = 12
    while offset + 8 <= len(data):
        length, chunk_type = struct.unpack_from("<II", data, offset)
        payload = data[offset + 8 : offset + 8 + length]
        if chunk_type == GLB_JSON_CHUNK:
            return json.loads(payload.decode("utf-8")), version
        offset += 8 + length
    raise ValueError("chunk JSON absent")


def glb_triangle_count(document: dict) -> int:
    """Compte les triangles declares par les primitives glTF."""
    accessors = document.get("accessors", [])
    total = 0
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            indices = primitive.get("indices")
            if indices is not None:
                total += int(accessors[indices].get("count", 0)) // 3
            else:
                position = primitive.get("attributes", {}).get("POSITION")
                if position is not None:
                    total += int(accessors[position].get("count", 0)) // 3
    return total


def audit_glb_container(path: Path) -> dict[str, object]:
    """Verite terrain sur le conteneur : cameras, lumieres, transparence, style."""
    document, version = read_glb_json(path)
    issues: list[str] = []
    warnings: list[str] = []

    if document.get("cameras"):
        issues.append(f"{len(document['cameras'])} camera(s) exportee(s)")
    extensions_used = [e for e in document.get("extensionsUsed", []) if isinstance(e, str)]
    if "KHR_lights_punctual" in extensions_used:
        issues.append("lumiere exportee (KHR_lights_punctual)")

    materials = document.get("materials", [])
    transparent = [
        mat.get("name", f"material_{i}")
        for i, mat in enumerate(materials)
        if mat.get("alphaMode", "OPAQUE") != "OPAQUE"
    ]
    if transparent:
        issues.append("materiaux non opaques: " + ", ".join(transparent))
    double_sided = [
        mat.get("name", f"material_{i}")
        for i, mat in enumerate(materials)
        if mat.get("doubleSided", False)
    ]
    if double_sided:
        warnings.append("materiaux double face (attendu: culling): " + ", ".join(double_sided))
    if document.get("images"):
        warnings.append(f"{len(document['images'])} image(s) embarquee(s)")

    primitives_without_color = 0
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if "COLOR_0" not in primitive.get("attributes", {}):
                primitives_without_color += 1
    if primitives_without_color:
        warnings.append(f"{primitives_without_color} primitive(s) sans COLOR_0")

    nodes = document.get("nodes", [])
    outline_nodes = [
        node.get("name", "node") for node in nodes if str(node.get("name", "")).endswith("_outline")
    ]
    dirty_nodes: list[str] = []
    for node in nodes:
        if "matrix" in node:
            dirty_nodes.append(node.get("name", "node"))
            continue
        translation = node.get("translation", [0.0, 0.0, 0.0])
        rotation = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
        scale = node.get("scale", [1.0, 1.0, 1.0])
        if (
            any(abs(t) > 1e-5 for t in translation)
            or any(abs(r - default) > 1e-5 for r, default in zip(rotation, (0.0, 0.0, 0.0, 1.0)))
            or any(abs(s - 1.0) > 1e-5 for s in scale)
        ):
            dirty_nodes.append(node.get("name", "node"))
    if dirty_nodes:
        warnings.append("transforms non neutres: " + ", ".join(dirty_nodes[:4]))

    return {
        "version": version,
        "nodes": len(nodes),
        "meshes": len(document.get("meshes", [])),
        "materials": len(materials),
        "triangles": glb_triangle_count(document),
        "outline_nodes": outline_nodes,
        "issues": issues,
        "warnings": warnings,
    }


# --------------------------------------------------------------------------- #
# Reimport Blender
# --------------------------------------------------------------------------- #


def import_and_measure(path: Path) -> dict[str, object]:
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    cameras = [o for o in bpy.context.scene.objects if o.type == "CAMERA"]
    lights = [o for o in bpy.context.scene.objects if o.type == "LIGHT"]
    triangles = sum(triangle_count(obj) for obj in meshes)
    vertices = sum(len(obj.data.vertices) for obj in meshes)
    mins, maxs = object_bounds(meshes) if meshes else (None, None)
    dims = object_dimensions(meshes) if meshes else (0.0, 0.0, 0.0)
    center_x = (mins.x + maxs.x) * 0.5 if mins else 0.0
    center_y = (mins.y + maxs.y) * 0.5 if mins else 0.0
    node_transforms_neutral = all(
        max(abs(value) for value in obj.matrix_local.to_translation()) < 1e-4
        and max(abs(value) for value in obj.matrix_local.to_euler()) < 1e-4
        and max(abs(s - 1.0) for s in obj.matrix_local.to_scale()) < 1e-4
        for obj in meshes
    )
    return {
        "meshes": len(meshes),
        "vertices": vertices,
        "triangles": triangles,
        "cameras": len(cameras),
        "lights": len(lights),
        "dims": dims,
        "min_z": mins.z if mins else 0.0,
        "center_x": center_x,
        "center_y": center_y,
        "node_transforms_neutral": node_transforms_neutral,
    }


# --------------------------------------------------------------------------- #
# Vignettes
# --------------------------------------------------------------------------- #


def audit_thumbnail(path: Path, expected_size: int) -> tuple[bool, list[str], dict[str, float]]:
    issues: list[str] = []
    metrics: dict[str, float] = {}
    if not path.is_file():
        return False, ["vignette absente"], metrics
    if path.stat().st_size == 0:
        return False, ["vignette vide"], metrics
    image = bpy.data.images.load(str(path), check_existing=False)
    try:
        width, height = image.size
        metrics["width"] = float(width)
        metrics["height"] = float(height)
        if (width, height) != (expected_size, expected_size):
            issues.append(f"taille {width}x{height} != {expected_size}x{expected_size}")
        buffer = np.empty(width * height * 4, dtype=np.float32)
        image.pixels.foreach_get(buffer)
        pixels = buffer.reshape(height, width, 4)
        alpha = pixels[..., 3]
        corners = [alpha[0, 0], alpha[0, -1], alpha[-1, 0], alpha[-1, -1]]
        metrics["corner_alpha_max"] = float(max(corners))
        if max(corners) > 0.05:
            issues.append("fond non transparent (coins opaques)")
        coverage = float((alpha > 0.5).mean())
        metrics["coverage"] = coverage
        if coverage < 0.03:
            issues.append(f"objet trop petit/absent (couverture {coverage:.1%})")
        if coverage > 0.98:
            issues.append("vignette entierement opaque (fond opaque ?)")
        center_y, center_x = height // 2, width // 2
        # Certains objets sont ajoures (herse, chaine) : le pixel central peut
        # etre transparent alors que l'objet occupe bien le centre. On mesure
        # donc la couverture opaque de la zone centrale (1/4 de l'image).
        half = max(8, min(width, height) // 8)
        central = alpha[center_y - half : center_y + half, center_x - half : center_x + half]
        central_coverage = float((central > 0.5).mean())
        metrics["central_coverage"] = central_coverage
        if central_coverage < 0.01:
            issues.append("objet absent du centre du cadrage")
    finally:
        bpy.data.images.remove(image)
    return not issues, issues, metrics


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="verify_glb.py", description="Verifie les GLB + vignettes produces."
    )
    parser.add_argument("--root", default=str(oq.OBJECTS3D_ROOT))
    parser.add_argument("--only", nargs="+", default=None, metavar="NOM")
    parser.add_argument("--thumb-size", type=int, default=THUMB_SIZE)
    parser.add_argument("--skip-thumbs", action="store_true")
    parser.add_argument("--strict", action="store_true", help="Echoue aussi sur les warnings")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    root = Path(args.root).resolve()
    if not root.is_dir():
        log(f"[ERREUR] dossier introuvable: {root}")
        return 2

    glb_paths = sorted(root.glob("*/*.glb"))
    if not glb_paths:
        log(f"[ERREUR] aucun .glb dans {root}")
        return 2
    if args.only:
        wanted = {oq.slugify(item) for item in args.only}
        selected = []
        for path in glb_paths:
            relative = f"{path.parent.name}/{path.stem}"
            if path.stem in wanted or relative in wanted or f"{path.parent.name}/{path.stem}" in wanted:
                selected.append(path)
        glb_paths = selected
        if not glb_paths:
            log(f"[ERREUR] --only ne correspond a aucun GLB ({', '.join(sorted(wanted))})")
            return 2

    log("=" * 96)
    log(f"OpenQuest / verification des assets 3D - {len(glb_paths)} GLB dans {root}")
    log("=" * 96)

    # Ancres declarees par le manifeste (les objets muraux ont une origine au
    # pied du mur : leur geometrie commence au-dessus du sol, ce n'est pas une
    # erreur de placement).
    manifest_path = root / "manifest.json"
    anchors: dict[str, str] = {}
    if manifest_path.is_file():
        try:
            manifest_data = json.loads(manifest_path.read_text(encoding="utf-8"))
            for asset in manifest_data.get("assets", []):
                if isinstance(asset, dict) and asset.get("name"):
                    anchors[str(asset["name"])] = str(asset.get("anchor") or "base")
        except (json.JSONDecodeError, OSError):
            anchors = {}

    failures = 0
    warnings_total = 0
    budget_max = 0
    total_triangles = 0

    for glb_path in glb_paths:
        issues: list[str] = []
        warnings: list[str] = []
        relative = f"{glb_path.parent.name}/{glb_path.name}"
        try:
            container = audit_glb_container(glb_path)
            imported = import_and_measure(glb_path)
        except Exception as exc:  # noqa: BLE001 - on continue les autres assets
            log(f"[ECHEC] {relative}: lecture impossible ({exc})")
            failures += 1
            continue

        issues.extend(container["issues"])
        warnings.extend(container["warnings"])
        if imported["cameras"] or imported["lights"]:
            issues.append(
                f"camera/lumiere reimportee ({imported['cameras']} cam, {imported['lights']} lum)"
            )
        if imported["meshes"] == 0:
            issues.append("aucun mesh reimporte")
        if container["triangles"] != imported["triangles"]:
            issues.append(
                f"triangles incohérents (glTF {container['triangles']} vs Blender {imported['triangles']})"
            )
        if imported["triangles"] > TRIANGLE_BUDGET:
            issues.append(f"budget depasse ({imported['triangles']} > {TRIANGLE_BUDGET})")
        min_z = float(imported["min_z"])
        anchor = anchors.get(glb_path.stem, "base")
        if anchor == "wall":
            # Origine au pied du mur : la geometrie est suspendue au-dessus du sol.
            # Certains objets muraux descendent bas (chaîne) : on verifie
            # seulement qu'ils ne passent pas sous le sol.
            if min_z < -MAX_GROUND_TOLERANCE:
                issues.append(f"objet mural sous le sol (min_z={min_z:.3f})")
        else:
            if not (-MAX_GROUND_TOLERANCE <= min_z <= MAX_ORIGIN_TOLERANCE):
                issues.append(f"base pas au sol (min_z={min_z:.3f})")
            if abs(float(imported["center_x"])) > MAX_CENTER_TOLERANCE or abs(
                float(imported["center_y"])
            ) > MAX_CENTER_TOLERANCE:
                issues.append(
                    f"base non centree (x={imported['center_x']:.3f}, y={imported['center_y']:.3f})"
                )
        if not imported["node_transforms_neutral"]:
            warnings.append("transforms de noeuds non neutres")
        if imported["vertices"] == 0:
            issues.append("aucun vertex")

        thumb_ok = True
        thumb_metrics: dict[str, float] = {}
        if not args.skip_thumbs:
            thumb_path = glb_path.with_name(f"{glb_path.stem}{oq.THUMB_SUFFIX}")
            thumb_ok, thumb_issues, thumb_metrics = audit_thumbnail(
                thumb_path, args.thumb_size
            )
            issues.extend(thumb_issues)
            if not thumb_ok:
                warnings = [w for w in warnings if "transforms" not in w]

        if args.strict and warnings:
            issues.extend(warnings)
            warnings = []
        warnings_total += len(warnings)
        total_triangles += int(imported["triangles"])
        budget_max = max(budget_max, int(imported["triangles"]))

        dims = imported["dims"]
        dims_text = " x ".join(f"{d:.2f}" for d in dims)
        status = "OK" if not issues else "ECHEC"
        if issues:
            failures += 1
        coverage = thumb_metrics.get("coverage", 0.0)
        outline = container["outline_nodes"]
        log(
            f"[{status}] {relative}  meshes={imported['meshes']} "
            f"verts={imported['vertices']} tris={imported['triangles']} "
            f"dims={dims_text} anchor={anchor} nodes={container['nodes']} "
            f"outline={'oui' if outline else 'non'} "
            + (
                f"thumb={int(thumb_metrics.get('width', 0))}px cov={coverage:.0%} "
                if not args.skip_thumbs
                else ""
            )
            + ("| " + "; ".join(issues) if issues else "")
            + (" | warn: " + "; ".join(warnings) if warnings else "")
        )

    # Coherence du manifeste (informatif).
    if manifest_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            listed = {asset.get("glb") for asset in manifest.get("assets", [])}
            on_disk = {f"{p.parent.name}/{p.name}" for p in root.glob("*/*.glb")}
            if listed != on_disk:
                missing = sorted(on_disk - listed)
                extra = sorted(listed - on_disk)
                log(
                    "[warn] manifest.json desynchronise"
                    + (f" (non listes: {missing})" if missing else "")
                    + (f" (listes absents: {extra})" if extra else "")
                )
        except (json.JSONDecodeError, OSError):
            log("[warn] manifest.json illisible")

    log("-" * 96)
    log(
        f"VERIFY_RESULT assets={len(glb_paths)} ok={len(glb_paths) - failures} "
        f"echecs={failures} warnings={warnings_total} "
        f"tris_total={total_triangles} tris_max={budget_max}"
    )
    log("=" * 96)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(oq.cli_argv()))
