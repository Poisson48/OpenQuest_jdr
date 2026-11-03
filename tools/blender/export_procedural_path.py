import bpy
import argparse
import math
import os
import sys

parser = argparse.ArgumentParser()
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
parser.add_argument("--blend", required=True)
parser.add_argument("--output", required=True)
parser.add_argument("--texture", default="")
parser.add_argument("--scale", type=float, default=1.0)
parser.add_argument("--yaw", type=float, default=0.0)
parser.add_argument("--decimate", type=float, default=0.0)
args = parser.parse_args(argv)

bpy.ops.wm.open_mainfile(filepath=args.blend)
scene = bpy.context.scene
path = bpy.data.objects.get("path")
if path is None:
    raise SystemExit("Objet 'path' introuvable dans le blend")

# Isole le chemin et évalue les Geometry Nodes.
for obj in scene.objects:
    obj.select_set(False)
path.select_set(True)
bpy.context.view_layer.objects.active = path
path.scale = (args.scale, args.scale, args.scale)
path.rotation_euler = (0.0, 0.0, math.radians(args.yaw))
scene.frame_set(1)
bpy.context.view_layer.update()

deps = bpy.context.evaluated_depsgraph_get()
ev = path.evaluated_get(deps)
mesh = bpy.data.meshes.new_from_object(ev)
if len(mesh.polygons) == 0:
    raise SystemExit("Chemin vide après évaluation")
mesh_obj = bpy.data.objects.new("ProceduralPath", mesh)
scene.collection.objects.link(mesh_obj)
mesh_obj.matrix_world = path.matrix_world

# Décimation optionnelle du maillage final.
if args.decimate > 0.0 and args.decimate < 1.0:
    dec = mesh_obj.modifiers.new("ExportDecimate", "DECIMATE")
    dec.ratio = args.decimate
    dec.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = mesh_obj
    bpy.ops.object.modifier_apply(modifier=dec.name)

# Matériau simple + texture éventuelle.
mat = bpy.data.materials.new("PathStone")
mat.use_nodes = True
nodes = mat.node_tree.nodes
links = mat.node_tree.links
bsdf = nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.42, 0.38, 0.31, 1.0)
bsdf.inputs["Roughness"].default_value = 0.92
if args.texture and os.path.exists(args.texture):
    img = bpy.data.images.load(os.path.abspath(args.texture), check_existing=True)
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
mesh.materials.clear()
mesh.materials.append(mat)
for poly in mesh.polygons:
    poly.material_index = 0

# UVs : Smart UV Project sur le maillage final.
bpy.ops.object.select_all(action="DESELECT")
mesh_obj.select_set(True)
bpy.context.view_layer.objects.active = mesh_obj
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02)
bpy.ops.object.mode_set(mode="OBJECT")

# Retire le guide courbe pour ne pas l'exporter.
path.hide_set(True)
path.hide_render = True
path.select_set(False)
mesh_obj.select_set(True)
bpy.context.view_layer.objects.active = mesh_obj

out = os.path.abspath(args.output)
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_texcoords=True,
    export_normals=True,
    export_materials="EXPORT",
    export_yup=True,
)
print("PATH_EXPORT verts=%d polys=%d uv=%d" % (
    len(mesh.vertices), len(mesh.polygons), len(mesh.uv_layers)))
print("WROTE", out, os.path.getsize(out))
