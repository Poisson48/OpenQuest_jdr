"""Rendus de revue avant/apres des rochers Tripo3D integres au jeu.

Usage :
  blender --background --python-exit-code 1 --python tools/blender/render_tripo_rocks_review.py -- \
      [--source DIR] [--final DIR] [--out DIR] [--samples 48]

Produit dans ``artifacts/tripo-review/rock-kit/renders_final/`` :
  01_avant_rochers_bruts.png   : les GLB sources recolorés, à l'échelle d'arrivée
  02_apres_rochers_livres.png  : les GLB livrés (palette, AO, mousse, facettes)
  03_apres_echelle_kit.png     : comparaison avec le kit Valbois (rocher,
                                 gros_rocher, falaise, cailloux)
  04_apres_affleurement.png    : mise en scène décorative avec cailloux

Les rendus « après » activent le preview vertex color (``COLOR_0``), comme le
fait le moteur au chargement (map_meshes_3d.gd).
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
import render_rock_kit_review as review  # noqa: E402

SOURCE_NAMES = ("rocher_socle", "rocher_bloc", "rocher_coin", "rocher_couronne")
FINAL_NAMES = (
    "bloc_rocheux_socle",
    "bloc_rocheux_bloc",
    "bloc_rocheux_coin",
    "bloc_rocheux_couronne",
)
## Facteur d'echelle pour que l'« avant » occupe la meme place que le livré.
SOURCE_SCALE = 2.0


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="artifacts/tripo-review/rock-kit/recolored_1024")
    parser.add_argument("--final", default="game/assets/objects3d/terrain")
    parser.add_argument("--pebbles", default="game/assets/objects3d/terrain")
    parser.add_argument("--out", default="artifacts/tripo-review/rock-kit/renders_final")
    parser.add_argument("--samples", type=int, default=48)
    return parser.parse_args(argv)


def _scene(samples: int) -> None:
    review.clear_scene()
    review.setup_render(bpy.context.scene, samples)
    review.setup_lights()
    review.make_ground()


def _place(root: Path, names: tuple[str, ...], origin_x: float, spacing: float,
           scale: float, yaw: float = 14.0,
           vertex_colors: bool = False) -> list[bpy.types.Object]:
    placed: list[bpy.types.Object] = []
    for index, name in enumerate(names):
        path = root / f"{name}.glb"
        if not path.is_file():
            raise FileNotFoundError(path)
        objs = review.import_asset(
            path, name, (origin_x + index * spacing, 0.0, 0.0), scale, yaw + index * 9.0
        )
        if vertex_colors:
            oq.enable_vertex_color_preview(objs)
        review.place_on(objs, 0.0)
        placed.extend(objs)
    return placed


def render_before(source: Path, out: Path, samples: int) -> None:
    _scene(samples)
    _place(source, SOURCE_NAMES, -3.75, 2.5, SOURCE_SCALE)
    review.render(
        out / "01_avant_rochers_bruts.png", (5.2, -9.8, 3.4), (0.2, 0.35, 0.0), 50.0
    )


def render_after(final: Path, out: Path, samples: int) -> None:
    _scene(samples)
    _place(final, FINAL_NAMES, -3.75, 2.5, 1.0, vertex_colors=True)
    review.render(
        out / "02_apres_rochers_livres.png", (5.2, -9.8, 3.4), (0.2, 0.35, 0.0), 50.0
    )


def render_scale_vs_kit(final: Path, out: Path, samples: int) -> None:
    _scene(samples)
    # Rochers Tripo (livrés) au premier plan.
    _place(final, FINAL_NAMES[:2], -4.2, 2.5, 1.0, vertex_colors=True)
    # Kit Valbois en arrière-plan, pour juger l'échelle et le style.
    kit = (
        ("rocher", -3.4, 0.0),
        ("gros_rocher", -1.1, 0.3),
        ("galets_de_rive", 1.3, -0.1),
        ("falaise", 3.6, 0.4),
    )
    for name, x, z in kit:
        path = final / f"{name}.glb"
        if not path.is_file():
            continue
        objs = review.import_asset(path, name, (x, 0.0, z), 1.0, 0.0)
        oq.enable_vertex_color_preview(objs)
        review.place_on(objs, 0.0)
    review.render(
        out / "03_apres_echelle_kit.png", (6.4, -11.4, 4.0), (0.2, 0.5, 0.2), 50.0
    )


def render_decor(final: Path, out: Path, samples: int) -> None:
    _scene(samples)
    layout = (
        ("bloc_rocheux_socle", -2.0, 0.6, 1.0, -18.0),
        ("bloc_rocheux_bloc", 0.4, -0.4, 1.0, 26.0),
        ("bloc_rocheux_coin", 2.6, 0.7, 1.0, 212.0),
        ("bloc_rocheux_couronne", 4.4, -0.9, 1.0, 118.0),
        ("caillou_galet_ovale", -0.9, 1.5, 1.0, 60.0),
        ("caillou_galet_rond", 1.5, 1.3, 0.9, 140.0),
        ("caillou_eclat_plat", 3.6, 1.1, 1.0, 30.0),
        ("caillou_gravier", 0.1, 1.8, 1.0, 200.0),
    )
    for index, (name, x, z, scale, yaw) in enumerate(layout):
        path = final / f"{name}.glb"
        if not path.is_file():
            raise FileNotFoundError(path)
        objs = review.import_asset(path, f"decor{index}", (x, 0.0, z), scale, yaw)
        oq.enable_vertex_color_preview(objs)
        review.place_on(objs, 0.0)
    review.render(
        out / "04_apres_affleurement.png", (7.2, -10.2, 3.6), (0.9, 0.4, 0.3), 52.0
    )


def main() -> int:
    args = parse_args()
    source = Path(args.source).resolve()
    final = Path(args.final).resolve()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    render_before(source, out, args.samples)
    render_after(final, out, args.samples)
    render_scale_vs_kit(final, out, args.samples)
    render_decor(final, out, args.samples)
    print("TRIPO_ROCKS_REVIEW:PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
