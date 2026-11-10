"""Export Blender des volumes et textures calculés par reference_hull.py."""

import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import oq_common as oq
from reference_detail_models import DETAIL_BUILDERS


def build_mesh(name, input_dir, entry):
    with np.load(input_dir / f"{name}.npz") as hull:
        vertices = hull["vertices"]
        triangles = hull["triangles"]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices.tolist(), [], triangles.tolist())
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    oq.select_only([obj], obj)

    # Simplifie la géométrie avant de projeter la matière. Le contour utilise
    # la même topologie et compte dans le budget du modèle.
    target = max(700, min(2150, int(entry["triangles_base"] * 1.5)))
    if len(mesh.polygons) > target:
        decimate = obj.modifiers.new("Silhouette", "DECIMATE")
        decimate.ratio = target / len(mesh.polygons)
        decimate.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=decimate.name)
        mesh = obj.data

    mesh.validate()
    texture_atlas, glow_atlas = bake_projection(mesh, name, input_dir / f"{name}_atlas.png")
    for poly in mesh.polygons:
        poly.use_smooth = True

    material = oq.make_material(f"{name}_projection", "#ffffff")
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = texture_atlas
    texture.extension = "EXTEND"
    material.node_tree.links.new(
        texture.outputs["Color"], material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"]
    )
    if glow_atlas is not None:
        glow = material.node_tree.nodes.new("ShaderNodeTexImage")
        glow.image = glow_atlas
        bsdf = material.node_tree.nodes.get("Principled BSDF")
        material.node_tree.links.new(glow.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.1
    mesh.materials.append(material)
    return obj


def finish_mesh(obj, entry):
    bounds = entry.get("reference_bounds", entry["dimensions_cells"])
    thickness = min(oq.OUTLINE_THICKNESS, min(bounds) * 0.07)
    target_size = Vector([max(d - 2 * thickness, d * 0.90) for d in bounds])
    low, high = oq.object_bounds([obj])
    span = high - low
    floor = float(entry.get("reference_floor", 0.0))
    for vertex in obj.data.vertices:
        v = vertex.co
        v.x = ((v.x - low.x) / span.x - 0.5) * target_size.x
        v.y = ((v.y - low.y) / span.y - 0.5) * target_size.y
        v.z = (v.z - low.z) / span.z * target_size.z + floor
    obj.data.update()
    oq.bake_vertex_colors(obj, ao_distance=0.19, ao_samples=14, ao_strength=0.24,
                          mottle_strength=0.0, min_value=0.76)
    outline = oq.build_outline(obj, oq.make_material(f"{obj.name}_ink", "#29231d"), thickness=thickness)
    outline.data.validate()
    return outline, bounds, floor


def read_projection(path):
    source = bpy.data.images.load(str(path))
    width, height = source.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    source.pixels.foreach_get(pixels)
    bpy.data.images.remove(source)
    return pixels.reshape(height, width, 4)[..., :3].copy()


def sample_view(image, view, u, v):
    tile = image.shape[1] // 3
    px = np.clip(u, 0, 1) * (tile - 1) + view * tile
    py = np.clip(v, 0, 1) * (image.shape[0] - 1)
    x0, y0 = px.astype(int), py.astype(int)
    x1 = np.minimum(x0 + 1, (view + 1) * tile - 1)
    y1 = np.minimum(y0 + 1, image.shape[0] - 1)
    tx, ty = (px - x0)[..., None], (py - y0)[..., None]
    lower = image[y0, x0] * (1 - tx) + image[y0, x1] * tx
    upper = image[y1, x0] * (1 - tx) + image[y1, x1] * tx
    return lower * (1 - ty) + upper * ty


def bake_projection(mesh, name, source_path):
    """Cuit les vues mélangées sur une texture UV opaque, avec marge par face."""
    source = read_projection(source_path)
    mesh.update()
    uv = mesh.uv_layers.new(name="Reference")
    tile = 18
    columns = int(np.ceil(np.sqrt(len(mesh.polygons))))
    size = tile * columns
    pixels = np.ones((size, size, 4), dtype=np.float32)
    pixels[..., :3] = np.median(source.reshape(-1, 3), axis=0)
    glow = None
    if name == "torche_murale":
        glow = np.zeros_like(pixels)
        glow[..., 3] = 1
    axis = np.clip((np.arange(tile, dtype=np.float32) - 2) / (tile - 5), 0, 1)
    s, t = np.meshgrid(axis, axis)
    total = np.maximum(1.0, s + t)
    # Étend la couleur des bords dans les marges de l'îlot UV.
    s, t = s / total, t / total
    bary = np.stack([1 - s - t, s, t], axis=-1)
    corners = np.asarray([tuple(v.co) for v in mesh.vertices], dtype=np.float32)
    normals = np.asarray([tuple(v.normal) for v in mesh.vertices], dtype=np.float32)
    for poly in mesh.polygons:
        indices = list(poly.vertices)
        point = bary @ corners[indices]
        n = bary @ normals[indices]
        n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 0.001)
        x, y, z = point.transpose(2, 0, 1)
        front = sample_view(source, 0, x, z)
        side = sample_view(source, 1, y, z)
        top = sample_view(source, 2, x, y)
        weights = np.stack([
            np.abs(n[..., 1]) ** 2.6,
            np.abs(n[..., 0]) ** 2.6,
            np.maximum(n[..., 2], 0.0) ** 1.7 * 1.7,
        ], axis=-1) + 0.012
        weights /= weights.sum(axis=-1, keepdims=True)
        color = (front * weights[..., 0, None] + side * weights[..., 1, None]
                 + top * weights[..., 2, None])
        ox, oy = (poly.index % columns) * tile, (poly.index // columns) * tile
        pixels[oy:oy + tile, ox:ox + tile, :3] = color
        if glow is not None:
            red, green, blue = color.transpose(2, 0, 1)
            flame = np.clip((red - 0.65) * 4, 0, 1) * np.clip((green - blue - 0.09) * 5, 0, 1)
            flame *= np.clip((z - 0.65) * 9, 0, 1)
            glow[oy:oy + tile, ox:ox + tile, :3] = color * flame[..., None]
        for i, (u, v) in zip(poly.loop_indices, ((2.5, 2.5), (tile - 2.5, 2.5), (2.5, tile - 2.5))):
            uv.data[i].uv = ((ox + u) / size, (oy + v) / size)
    surface = pack_atlas(f"{name}_surface", pixels)
    return surface, pack_atlas(f"{name}_lueur", glow) if glow is not None else None


def pack_atlas(name, pixels):
    image = bpy.data.images.new(name, width=pixels.shape[1], height=pixels.shape[0], alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    image.pack()
    return image


def export_asset(entry, args):
    name = entry["name"]
    oq.reset_scene()
    if "reference_floor" not in entry and entry["anchor"] == "wall":
        entry["reference_floor"] = max(0.0, entry["height_above_floor"] - entry["dimensions_cells"][2])
    detail = DETAIL_BUILDERS.get(name)
    if detail:
        obj = oq.join_objects(detail(), name)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        oq.triangulate_mesh(obj)
    else:
        obj = build_mesh(name, args.input, entry)
    outline, bounds, floor = finish_mesh(obj, entry)
    nodes = [obj, outline]
    triangles_base = oq.triangle_count(obj)
    triangles_total = triangles_base + oq.triangle_count(outline)
    if triangles_total > oq.TRIANGLE_BUDGET:
        raise ValueError(f"{triangles_total} triangles dépassent le budget.")

    glb = args.out / entry["glb"]
    oq.export_glb(glb, nodes)
    thumb = args.out / entry["thumb"]
    oq.render_thumbnail(thumb, nodes, samples=args.samples)
    low, high = oq.object_bounds(nodes)
    sha256 = hashlib.sha256((args.references / f"{name}.png").read_bytes()).hexdigest()
    return {
        **entry,
        "dimensions_cells": [round(v, 3) for v in (high - low)],
        "height_above_floor": round(high.z, 3),
        "triangles": triangles_total,
        "triangles_base": triangles_base,
        "vertices": sum(len(node.data.vertices) for node in nodes),
        "vertex_colors": "AO léger" if detail else "AO léger + atlas UV de référence",
        "reference_image": f"tools/blender/references/{name}.png",
        "reference_sha256": sha256,
        "reference_bounds": bounds,
        "reference_floor": floor,
        "geometry_source": "modelage d'après la référence" if detail else "intersection des silhouettes avant/droite/dessus",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--references", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--only", nargs="+", required=True)
    parser.add_argument("--samples", type=int, default=12)
    args = parser.parse_args(oq.cli_argv())
    args.input = args.input.resolve()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    base = json.loads(args.manifest.read_text(encoding="utf-8"))
    staged = args.out / "manifest.json"
    if staged.is_file():
        prior = json.loads(staged.read_text(encoding="utf-8"))
        previous = {entry["name"]: entry for entry in prior["assets"]}
        base["assets"] = [previous.get(entry["name"], entry) for entry in base["assets"]]
    names = set(args.only)
    selected = [a for a in base["assets"] if a["name"] in names]
    failures = names.difference(a["name"] for a in selected)
    updated = {}
    for entry in selected:
        name = entry["name"]
        try:
            updated[name] = export_asset(entry, args)
            oq.log(f"[OK] {name}: {updated[name]['triangles']} triangles")
        except Exception as exc:
            failures.add(name)
            oq.log(f"[ECHEC] {name}: {exc}")
    base["assets"] = [updated.get(entry["name"], entry) for entry in base["assets"]]
    base["generated_by"] = "tools/blender/build_reference_volumes.py + tools/blender/build_prototypes.py"
    base["blender_version"] = bpy.app.version_string
    staged.write_text(json.dumps(base, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    oq.log(f"VOLUMES_RESULT ok={len(updated)} echecs={len(failures)}")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
