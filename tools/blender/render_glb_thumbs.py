"""Rend les vignettes 512 px d'une serie de GLB avec le pipeline du projet.

Usage :
  blender --background --python tools/blender/render_glb_thumbs.py -- \
      --input IN --out OUT [--scale 1.6]

Utilise l'eclairage et le cadrage de ``oq_common.render_thumbnail``. Le facteur
``--scale`` agrandit une copie temporaire de l'objet : le pipeline dimensionne
ses lumieres sur la taille de l'objet, donc les petits decors seraient
surexposes s'ils etaient rendus a leur taille reelle. Le GLB n'est pas modifie.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import oq_common as oq  # noqa: E402


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--scale", type=float, default=1.6)
    parser.add_argument("--samples", type=int, default=32)
    parser.add_argument("--brightness", type=float, default=1.0)
    parser.add_argument("--only", nargs="+", default=None)
    return parser.parse_args(argv)


def _brighten_materials(meshes: list[bpy.types.Object], factor: float) -> None:
    """Éclaircit l'albédo pour l'aperçu (texture liée ou couleur constante)."""
    seen: set[str] = set()
    for obj in meshes:
        for slot in obj.material_slots:
            material = slot.material
            if material is None or material.name in seen or not material.use_nodes:
                continue
            seen.add(material.name)
            nodes = material.node_tree.nodes
            links = material.node_tree.links
            for node in nodes:
                if node.type != "BSDF_PRINCIPLED":
                    continue
                base = node.inputs["Base Color"]
                if base.is_linked:
                    source = base.links[0].from_socket
                    links.remove(base.links[0])
                    mix = nodes.new("ShaderNodeMixRGB")
                    mix.blend_type = "MULTIPLY"
                    mix.inputs[0].default_value = 1.0
                    mix.inputs[2].default_value = (factor, factor, factor, 1.0)
                    links.new(source, mix.inputs[1])
                    links.new(mix.outputs[0], base)
                else:
                    color = base.default_value
                    base.default_value = (
                        min(1.0, color[0] * factor),
                        min(1.0, color[1] * factor),
                        min(1.0, color[2] * factor),
                        color[3],
                    )


def main() -> int:
    args = parse_args()
    in_root = Path(args.input).resolve()
    out_root = Path(args.out).resolve()
    out_root.mkdir(parents=True, exist_ok=True)
    files = sorted(in_root.glob("*.glb"))
    if args.only:
        wanted = {name.lower() for name in args.only}
        files = [path for path in files if path.stem.lower() in wanted]
    if not files:
        raise FileNotFoundError(f"aucun GLB dans {in_root}")
    for path in files:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(path))
        meshes = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
        if not meshes:
            raise RuntimeError(f"{path.name}: aucun mesh importe")
        # Les materiaux importes sont mats et sans vignette d'encrage : on force
        # une couleur de base neutre pour que l'apercu reflete l'albedo importe.
        proxy_root = bpy.data.objects.new(f"{path.stem}_proxy", None)
        bpy.context.scene.collection.objects.link(proxy_root)
        for obj in meshes:
            obj.parent = proxy_root
        proxy_root.scale = (args.scale, args.scale, args.scale)
        if args.brightness != 1.0:
            # Albedo tres sombre (pierre ardoise) : on l'eclaircit uniquement
            # pour l'apercu, le GLB garde sa couleur reelle.
            _brighten_materials(meshes, args.brightness)
        target = out_root / f"{path.stem}{oq.THUMB_SUFFIX}"
        _, engine = oq.render_thumbnail(
            target, meshes, engine="eevee", samples=args.samples
        )
        print(f"[OK] {target.name} ({engine}, scale={args.scale})")
    print("GLB_THUMBS:PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
