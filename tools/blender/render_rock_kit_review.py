"""Rendus de revue Blender du kit de rochers et de cailloux.

Usage :
  blender --background --python tools/blender/render_rock_kit_review.py -- \
      --rocks artifacts/tripo-review/rock-kit/recolored \
      --pebbles artifacts/tripo-review/rock-kit/pebbles \
      --out artifacts/tripo-review/rock-kit/renders

Les GLB restent hors du jeu : ce script ne sert qu'à produire des images de
validation (palette, mur empilé, cairn de cailloux, décor).

Repère : Blender est Z-up, Godot est Y-up. Les points de pose sont exprimés
dans le repère Godot puis convertis, pour éviter des objets couchés.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

PEBBLE_NAMES = ("caillou_galet_rond", "caillou_galet_ovale", "caillou_eclat_plat", "caillou_gravier")
ROCK_NAMES = ("rocher_socle", "rocher_coin", "rocher_bloc", "rocher_couronne")


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--rocks", required=True)
    parser.add_argument("--pebbles", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--samples", type=int, default=64)
    return parser.parse_args(argv)


def godot_to_blender(point: tuple[float, float, float]) -> Vector:
    return Vector((point[0], point[2], point[1]))


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(datablocks):
            datablocks.remove(item)


def point_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def setup_render(scene: bpy.types.Scene, samples: int) -> None:
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.eevee.taa_render_samples = samples
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 820
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    # AgX délave les albédos mats : pour juger une palette de pierre, il faut
    # une transformée neutre, sinon les gris chauds virent au blanc.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.35
    scene.world = bpy.data.worlds.new("RockReviewWorld")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.055, 0.072, 0.085, 1.0)
    background.inputs["Strength"].default_value = 0.34


def add_light(name: str, location: tuple[float, float, float], energy: float,
              size: float, color: tuple[float, float, float]) -> None:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    lamp = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(lamp)
    lamp.location = location
    point_at(lamp, Vector((0.0, 0.0, 0.5)))


def setup_lights() -> None:
    add_light("Key", (3.6, -3.8, 5.4), 640.0, 3.6, (1.0, 0.94, 0.86))
    add_light("Fill", (-4.2, -1.6, 2.6), 300.0, 5.5, (0.55, 0.70, 1.0))
    add_light("Rim", (0.8, 4.2, 4.2), 380.0, 3.0, (0.70, 0.82, 1.0))


def make_ground(radius: float = 18.0) -> None:
    bpy.ops.mesh.primitive_plane_add(size=radius * 2.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground.name = "MossyGround"
    mat = bpy.data.materials.new("GroundMat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    principled = nodes.get("Principled BSDF")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3.4
    noise.inputs["Detail"].default_value = 6.0
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.045, 0.058, 0.034, 1.0)
    ramp.color_ramp.elements[1].color = (0.150, 0.190, 0.100, 1.0)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], principled.inputs["Base Color"])
    principled.inputs["Roughness"].default_value = 0.97
    ground.data.materials.append(mat)
    return ground


def import_asset(path: Path, name: str, location: tuple[float, float, float],
                 scale: float | tuple[float, float, float] = 1.0,
                 yaw: float = 0.0) -> list[bpy.types.Object]:
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
    if isinstance(scale, (int, float)):
        factor = Vector((scale, scale, scale))
    else:
        # Échelle exprimée dans le repère Godot (x, y=hauteur, z=profondeur).
        factor = Vector((scale[0], scale[2], scale[1]))
    for obj in imported:
        obj.name = name
        obj.location += godot_to_blender(location)
        obj.rotation_euler[2] += math.radians(yaw)
        obj.scale = Vector((obj.scale.x * factor.x, obj.scale.y * factor.y,
                            obj.scale.z * factor.z))
    return imported


def world_bounds(objs: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    mins = Vector((math.inf, math.inf, math.inf))
    maxs = Vector((-math.inf, -math.inf, -math.inf))
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in objs:
        evaluated = obj.evaluated_get(depsgraph)
        for corner in evaluated.bound_box:
            point = evaluated.matrix_world @ Vector(corner)
            mins = Vector((min(mins.x, point.x), min(mins.y, point.y), min(mins.z, point.z)))
            maxs = Vector((max(maxs.x, point.x), max(maxs.y, point.y), max(maxs.z, point.z)))
    return mins, maxs


def place_on(objs: list[bpy.types.Object], base_z: float) -> float:
    """Pose le groupe sur ``base_z`` et renvoie son sommet."""
    mins, maxs = world_bounds(objs)
    delta = base_z - mins.z
    for obj in objs:
        obj.location.z += delta
    return maxs.z + delta


def setup_camera(location: tuple[float, float, float],
                 target: tuple[float, float, float], lens: float = 52.0) -> None:
    data = bpy.data.cameras.new("ReviewCamera")
    data.lens = lens
    camera = bpy.data.objects.new("ReviewCamera", data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = location
    point_at(camera, godot_to_blender(target))
    bpy.context.scene.camera = camera


def render(out: Path, camera_location: tuple[float, float, float],
           target: tuple[float, float, float], lens: float = 52.0) -> None:
    setup_camera(camera_location, target, lens)
    bpy.context.scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)


# --------------------------------------------------------------------------- #
# Scenes
# --------------------------------------------------------------------------- #


def scene_palette(rocks: Path, pebbles: Path, out: Path, samples: int) -> None:
    clear_scene()
    setup_render(bpy.context.scene, samples)
    setup_lights()
    make_ground()
    spacing = 0.0
    positions: list[float] = []
    for name, width in zip(ROCK_NAMES, (0.92, 0.84, 0.88, 0.76)):
        objs = import_asset(rocks / f"{name}.glb", name, (spacing, 0.0, 0.0), 1.15, 14.0)
        place_on(objs, 0.0)
        positions.append(spacing)
        spacing += width * 1.15 + 0.14
    center = (positions[0] + positions[-1]) * 0.5
    render(out / "01_palette_rochers.png", (center + 2.4, -4.6, 2.5),
           (center, 0.24, 0.0), 46.0)


def scene_wall(rocks: Path, pebbles: Path, out: Path, samples: int) -> None:
    clear_scene()
    setup_render(bpy.context.scene, samples)
    setup_lights()
    make_ground()

    def build_course(specs: list[tuple[str, float, tuple[float, float, float], float]],
                     supports: list[tuple[float, float]], base: float) -> list[tuple[float, float]]:
        placed: list[tuple[float, float]] = []
        for name, x, scale, yaw in specs:
            if supports:
                nearest = min(supports, key=lambda item: abs(item[0] - x))
                bottom = nearest[1] - 0.07
            else:
                bottom = base
            objs = import_asset(rocks / f"{name}.glb", name, (x, 0.0, 0.0), scale, yaw)
            placed.append((x, place_on(objs, bottom)))
        return placed

    # Mur de 4,4 cases : trois assises décalées + une couronne continue.
    # Chaque pierre est étirée verticalement et posée sur la pierre la plus
    # proche en dessous : les surplombs restent inférieurs à un demi-bloc.
    course0 = build_course(
        [("rocher_socle", -1.95, (0.85, 1.30, 0.95), -8.0),
         ("rocher_bloc", -1.05, (0.92, 1.70, 1.0), 6.0),
         ("rocher_bloc", -0.10, (0.90, 1.75, 1.0), -7.0),
         ("rocher_bloc", 0.82, (0.85, 1.65, 0.95), 9.0),
         ("rocher_coin", 1.72, (0.72, 1.05, 0.85), 178.0)],
        [], 0.0,
    )
    course1 = build_course(
        [("rocher_bloc", -1.50, (0.92, 1.55, 1.0), 178.0),
         ("rocher_bloc", -0.58, (0.88, 1.60, 1.0), 4.0),
         ("rocher_bloc", 0.36, (0.90, 1.58, 1.0), 180.0),
         ("rocher_bloc", 1.28, (0.78, 1.35, 0.9), -4.0)],
        course0, 0.0,
    )
    build_course(
        [("rocher_couronne", -1.20, (0.90, 1.05, 0.95), 8.0),
         ("rocher_couronne", 0.0, (0.92, 1.08, 0.95), -6.0),
         ("rocher_couronne", 1.15, (0.82, 0.95, 0.9), 177.0)],
        course1, 0.0,
    )
    # Cailloux au pied du mur, pour l'échelle et le naturel.
    for index, (x, z, name, scale, yaw) in enumerate(
        [(-2.45, 0.42, "caillou_galet_rond", 1.0, 12.0),
         (-2.15, -0.42, "caillou_gravier", 1.0, 70.0),
         (2.42, 0.34, "caillou_galet_ovale", 1.0, 210.0),
         (2.10, -0.52, "caillou_eclat_plat", 0.9, 33.0),
         (0.30, 0.62, "caillou_gravier", 0.85, 155.0)]
    ):
        objs = import_asset(pebbles / f"{name}.glb", f"foot{index}", (x, 0.0, z), scale, yaw)
        place_on(objs, 0.0)
    render(out / "02_mur_empile.png", (1.15, -5.4, 2.55), (0.0, 0.52, 0.0), 46.0)


def scene_cairn(pebbles: Path, out: Path, samples: int) -> None:
    """Petit cairn : les cailloux s'empilent sans flotter, du plus gros au plus petit."""
    clear_scene()
    setup_render(bpy.context.scene, samples)
    setup_lights()
    make_ground()
    layout = [
        ("caillou_galet_ovale", 0.0, 0.0, 0.0, 1.15, 8.0),
        ("caillou_galet_rond", 0.02, 0.0, 0.0, 1.05, -22.0),
        ("caillou_galet_ovale", 0.06, 0.0, 0.0, 0.80, 41.0),
        ("caillou_eclat_plat", 0.10, 0.0, 0.0, 0.95, 96.0),
        ("caillou_gravier", 0.12, 0.0, 0.0, 1.0, 12.0),
    ]
    # Ordre de pose : les 3 gros puis les petits sur le dessus.
    order = [1, 0, 2, 3, 4]
    base = 0.0
    for rank, index in enumerate(order):
        name, x, _y, _z, scale, yaw = layout[index]
        objs = import_asset(pebbles / f"{name}.glb", f"cairn{index}",
                            (x, 0.0, 0.0), scale, yaw + rank * 26.0)
        top = place_on(objs, base)
        base = top - 0.035
    # Cailloux satellites posés au sol, jamais flottants.
    satellites = [
        ("caillou_galet_rond", -0.62, 0.34, 45.0),
        ("caillou_eclat_plat", 0.58, -0.22, 130.0),
        ("caillou_gravier", 0.42, 0.46, 12.0),
        ("caillou_galet_ovale", -0.38, -0.45, 210.0),
    ]
    for index, (name, x, y, yaw) in enumerate(satellites):
        objs = import_asset(pebbles / f"{name}.glb", f"sat{index}", (x, 0.0, y), 1.0, yaw)
        place_on(objs, 0.0)
    render(out / "03_cairn_cailloux.png", (1.05, -1.55, 0.72), (0.02, 0.14, 0.04), 58.0)


def scene_pebbles_closeup(pebbles: Path, out: Path, samples: int) -> None:
    """Gros plan au sol : on voit la matière, les facettes et la taille relative."""
    clear_scene()
    setup_render(bpy.context.scene, samples)
    setup_lights()
    make_ground()
    lineup = [
        ("caillou_galet_rond", -0.52, 0.16, 1.0, 8.0),
        ("caillou_galet_ovale", -0.16, -0.10, 1.0, 64.0),
        ("caillou_eclat_plat", 0.20, 0.14, 1.0, 128.0),
        ("caillou_gravier", 0.44, -0.16, 1.0, 200.0),
    ]
    for index, (name, x, z, scale, yaw) in enumerate(lineup):
        objs = import_asset(pebbles / f"{name}.glb", f"lineup{index}", (x, 0.0, z), scale, yaw)
        place_on(objs, 0.0)
    # Petit amas pour montrer qu'ils s'assemblent sans flotter.
    cluster = [("caillou_galet_ovale", 0.86, 0.30, 0.95, 20.0),
               ("caillou_galet_rond", 1.02, 0.02, 0.80, 95.0),
               ("caillou_eclat_plat", 0.92, 0.18, 0.75, 260.0)]
    base = 0.0
    for index, (name, x, z, scale, yaw) in enumerate(cluster):
        objs = import_asset(pebbles / f"{name}.glb", f"cluster{index}", (x, 0.0, z), scale, yaw)
        base = place_on(objs, 0.0 if index == 0 else base - 0.02)
    render(out / "05_cailloux_gros_plan.png", (0.55, -1.42, 0.46), (0.02, 0.04, 0.0), 46.0)


def scene_terrain(rocks: Path, pebbles: Path, out: Path, samples: int) -> None:
    clear_scene()
    setup_render(bpy.context.scene, samples)
    setup_lights()
    make_ground()
    boulders = [
        ("rocher_bloc", -0.55, 0.35, 1.75, -22.0),
        ("rocher_coin", 1.45, 0.75, 1.05, 212.0),
        ("rocher_couronne", 1.15, -1.05, 1.05, 34.0),
    ]
    for index, (name, x, z, scale, yaw) in enumerate(boulders):
        objs = import_asset(rocks / f"{name}.glb", f"boulder{index}", (x, 0.0, z), scale, yaw)
        place_on(objs, 0.0)
    scatter = [
        ("caillou_galet_rond", -1.95, -0.75, 1.05, 12.0),
        ("caillou_galet_ovale", -1.55, 0.62, 0.90, 76.0),
        ("caillou_eclat_plat", -1.10, -1.45, 1.10, 133.0),
        ("caillou_gravier", -1.35, 0.05, 1.0, 220.0),
        ("caillou_galet_ovale", 2.25, -0.30, 0.85, 45.0),
        ("caillou_galet_rond", 2.05, 1.30, 0.80, 95.0),
        ("caillou_gravier", 0.55, 1.55, 1.0, 3.0),
        ("caillou_eclat_plat", 0.05, 1.10, 0.70, 160.0),
        ("caillou_gravier", -0.35, 1.35, 0.9, 240.0),
        ("caillou_galet_rond", 1.05, 0.95, 0.65, 18.0),
    ]
    for index, (name, x, z, scale, yaw) in enumerate(scatter):
        objs = import_asset(pebbles / f"{name}.glb", f"pebble{index}", (x, 0.0, z), scale, yaw)
        place_on(objs, 0.0)
    render(out / "04_rochers_et_cailloux_decor.png", (5.6, -6.6, 3.6), (0.35, 0.30, 0.0), 46.0)


def main() -> int:
    args = parse_args()
    rocks = Path(args.rocks).resolve()
    pebbles = Path(args.pebbles).resolve()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    required = [rocks / f"{name}.glb" for name in ROCK_NAMES]
    required += [pebbles / f"{name}.glb" for name in PEBBLE_NAMES]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("assets manquants : " + ", ".join(missing))
    scene_palette(rocks, pebbles, out, args.samples)
    scene_wall(rocks, pebbles, out, args.samples)
    scene_cairn(pebbles, out, args.samples)
    scene_pebbles_closeup(pebbles, out, args.samples)
    scene_terrain(rocks, pebbles, out, args.samples)
    print("ROCK_REVIEW_RENDER:PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
