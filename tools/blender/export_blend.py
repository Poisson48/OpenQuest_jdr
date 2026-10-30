"""Exporte un fichier .blend fourni par un artiste en GLB + vignette.

CLI generique, a lancer avec Blender (le .blend peut etre ouvert par l'option
``--input`` ou par la ligne de commande Blender classique) :

    & "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" `
        --background --python-exit-code 1 `
        --python tools/blender/export_blend.py -- `
        --input "D:\\3d\\maison.blend" --name maison --category buildings

    # ou, si le .blend est deja charge par Blender :
    blender --background "D:\\3d\\maison.blend" --python tools/blender/export_blend.py -- --name maison

Options (apres ``--``) :

    --input PATH          .blend a ouvrir (sinon on utilise le fichier courant).
    --name NOM            Nom de l'asset (defaut : nom du fichier .blend).
    --category CAT        buildings | props | vegetation | terrain (defaut props).
    --out-root DIR        Racine de sortie (defaut game/assets/objects3d).
    --engine eevee|cycles Moteur de la vignette (defaut eevee).
    --samples N           Echantillons (defaut 32).
    --thumb-size N        Taille de la vignette (defaut 512).
    --thumb-margin F      Marge de cadrage (defaut 1.14).
    --selected            N'exporte que les objets selectionnes.
    --apply-transforms    Applique rotation/scale des meshes avant export.
    --origin-base         Recentre l'origine au pied (un seul mesh uniquement).
    --no-thumb            Pas de vignette.
    --no-export           Pas de GLB (vignette seule).
    --outline             Ajoute le contour encre "inverted hull" (comme les prototypes).
    --outline-thickness F Epaisseur du contour, en cases (defaut 0.014).
    --strict              Echec si budget poly depasse / transforms non propres.

L'export ne contient que les meshes : les cameras et lumieres du .blend sont
ignorees (et masquees pendant le rendu de la vignette). Si le mesh possede des
vertex colors (nom libre), elles sont activees pour la vignette. Les
conventions (1 unite = 1 case, origine au pied, avant vers +Z glTF, < 5000 tris,
materiaux mats, une seule face) sont rappelees dans docs/BLENDER_PIPELINE.md.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402

import oq_common as oq  # noqa: E402
from oq_common import (  # noqa: E402
    CATEGORIES,
    DEFAULT_PALETTE,
    THUMB_SIZE,
    TRIANGLE_BUDGET,
    apply_transforms,
    build_outline,
    enable_vertex_color_preview,
    export_glb,
    log,
    make_material,
    normalize_asset,
    object_dimensions,
    render_thumbnail,
    slugify,
    triangle_count,
)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="export_blend.py",
        description="Exporte un .blend d'artiste en GLB + vignette 512x512.",
    )
    parser.add_argument("--input", default=None)
    parser.add_argument("--name", default=None)
    parser.add_argument("--category", default="props", choices=list(CATEGORIES))
    parser.add_argument("--out-root", default=str(oq.OBJECTS3D_ROOT))
    parser.add_argument("--engine", choices=["eevee", "cycles"], default="eevee")
    parser.add_argument("--samples", type=int, default=32)
    parser.add_argument("--thumb-size", type=int, default=THUMB_SIZE)
    parser.add_argument("--thumb-margin", type=float, default=1.14)
    parser.add_argument("--selected", action="store_true")
    parser.add_argument("--apply-transforms", action="store_true")
    parser.add_argument("--origin-base", action="store_true")
    parser.add_argument("--no-thumb", action="store_true")
    parser.add_argument("--no-export", action="store_true")
    parser.add_argument("--outline", action="store_true")
    parser.add_argument("--outline-thickness", type=float, default=oq.OUTLINE_THICKNESS)
    parser.add_argument("--strict", action="store_true")
    return parser.parse_args(argv)


def collect_mesh_objects(only_selected: bool) -> list[bpy.types.Object]:
    scene = bpy.context.scene
    if only_selected:
        objects = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    else:
        objects = [o for o in scene.objects if o.type == "MESH"]
    # On ignore les meshes caches a l'export (sauf selection explicite).
    if not only_selected:
        objects = [o for o in objects if not o.hide_render and not o.hide_viewport]
    return sorted(objects, key=lambda o: o.name)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    log("=" * 78)
    log("OpenQuest / Blender - export d'un .blend d'artiste")

    if args.input:
        blend_path = Path(args.input).resolve()
        if not blend_path.is_file():
            log(f"[ERREUR] .blend introuvable: {blend_path}")
            return 2
        bpy.ops.wm.open_mainfile(filepath=str(blend_path))
        default_name = blend_path.stem
    else:
        if not bpy.data.filepath:
            log("[ERREUR] aucun .blend charge (utilise --input PATH)")
            return 2
        default_name = Path(bpy.data.filepath).stem

    scene = bpy.context.scene
    name = slugify(args.name or default_name)
    out_root = Path(args.out_root).resolve()
    category = oq.slugify(args.category)
    if category not in CATEGORIES:
        log(f"[ERREUR] categorie invalide: {category} ({', '.join(CATEGORIES)})")
        return 2

    meshes = collect_mesh_objects(args.selected)
    if not meshes:
        log("[ERREUR] aucun mesh a exporter (selection vide ?).")
        return 2

    log(f"fichier : {bpy.data.filepath or '(charge en memoire)'}")
    log(f"asset   : {category}/{name} - {len(meshes)} mesh(s)")

    if args.apply_transforms:
        for obj in meshes:
            apply_transforms(obj)
        log("[info] rotation/scale appliquees aux meshes")

    if args.origin_base:
        if len(meshes) != 1:
            log("[ERREUR] --origin-base exige un seul mesh fusionne.")
            return 2
        normalize_asset(meshes[0], name)
        log("[info] origine replacee au centre de la base (z=0)")

    triangle_total = sum(triangle_count(obj) for obj in meshes)

    # Contour encre optionnel (meme technique que les prototypes).
    outline_objects: list[bpy.types.Object] = []
    if args.outline:
        ink = make_material(f"{name}_ink", DEFAULT_PALETTE["ink"], roughness=1.0)
        for obj in meshes:
            outline_objects.append(
                build_outline(obj, ink, thickness=args.outline_thickness)
            )
        log(f"[info] contour encre ajoute ({len(outline_objects)} coque(s))")

    render_objects = meshes + outline_objects
    triangle_total += sum(triangle_count(obj) for obj in outline_objects)
    dims = object_dimensions(render_objects)
    if triangle_total > TRIANGLE_BUDGET:
        message = f"{triangle_total} triangles > budget low-poly {TRIANGLE_BUDGET}"
        if args.strict:
            log(f"[ERREUR] {message}")
            return 3
        log(f"[warn] {message} (export quand meme, voir --strict)")

    # Masque temporairement cameras/lumieres (et vides) du .blend : elles ne
    # doivent ni s'exporter ni eclairer le rendu de la vignette.
    hidden: list[tuple[bpy.types.Object, bool]] = []
    for obj in scene.objects:
        if obj.type != "MESH":
            hidden.append((obj, obj.hide_render))
            obj.hide_render = True
            obj.hide_viewport = True

    glb_path = out_root / category / f"{name}.glb"
    thumb_path = out_root / category / f"{name}{oq.THUMB_SUFFIX}"
    status = 0
    try:
        if not args.no_export:
            export_glb(glb_path, render_objects)
            log(
                f"[OK] GLB: {glb_path} "
                f"({glb_path.stat().st_size / 1024.0:.1f} Ko, {triangle_total} tris)"
            )
        # A brancher apres l'export : la multiplication vertex color ne sert
        # qu'a la vignette (l'exporteur deduit baseColorFactor du materiau).
        if any(len(obj.data.color_attributes) for obj in meshes):
            layer = meshes[0].data.color_attributes[0].name
            enable_vertex_color_preview(meshes, layer_name=layer)
            log(f"[info] vertex colors '{layer}' activees pour le rendu")
        if not args.no_thumb:
            _, engine = render_thumbnail(
                thumb_path,
                render_objects,
                engine=args.engine,
                samples=args.samples,
                size=args.thumb_size,
                margin=args.thumb_margin,
            )
            log(
                f"[OK] vignette: {thumb_path} "
                f"({thumb_path.stat().st_size / 1024.0:.1f} Ko, {engine})"
            )
    except Exception as exc:  # noqa: BLE001
        log(f"[ECHEC] {exc}")
        status = 1
    finally:
        for obj, was_hidden in hidden:
            if obj.name in bpy.data.objects:
                obj.hide_render = was_hidden
                obj.hide_viewport = False

    dims_text = " x ".join(f"{d:.2f}" for d in dims)
    log(f"RESUME {category}/{name}: {triangle_total} tris, {dims_text} cases")
    if status == 0:
        log("[resume] placer l'objet dans la bibliotheque de l'editeur 2.5D.")
    log("=" * 78)
    return status


if __name__ == "__main__":
    raise SystemExit(main(oq.cli_argv()))
