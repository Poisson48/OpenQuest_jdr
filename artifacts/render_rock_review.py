"""Rend des comparaisons avant/après des rochers (vue Blender, même cadrage).

Usage :
  blender -b --python artifacts/render_rock_review.py -- \
      --old artifacts/rock_review/old --new artifacts/rock_review/new \
      --out artifacts/rock_review/renders [--size 800] [--samples 24]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools" / "blender"))
import oq_common as oq  # noqa: E402


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--old", required=True)
    parser.add_argument("--new", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--size", type=int, default=800)
    parser.add_argument("--samples", type=int, default=24)
    return parser.parse_args(argv)


def render_glb(glb: Path, out_png: Path, size: int, samples: int) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(glb))
    objects = [obj for obj in bpy.data.objects if obj not in before and obj.type == "MESH"]
    if not objects:
        raise RuntimeError(f"aucun mesh dans {glb}")
    # Échelle de revue : le pipeline dimensionne ses lumières sur la taille de
    # l'objet ; les petits rochers seraient surgonflés → on garde l'échelle réelle
    # et on agrandit juste le cadrage via size.
    oq.render_thumbnail(str(out_png), objects, samples=samples, size=size,
                        transparent=True, margin=1.16)


def main() -> None:
    args = parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for folder, prefix in ((args.old, "avant"), (args.new, "apres")):
        for glb in sorted(Path(folder).glob("*.glb")):
            name = glb.stem.replace("bloc_rocheux_", "")
            target = out / f"{prefix}_{name}.png"
            render_glb(glb, target, args.size, args.samples)
            print(f"[OK] {target}")
    print("ROCK_REVIEW_RESULT ok")


if __name__ == "__main__":
    main()
