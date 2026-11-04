import bpy
import argparse
import json
import os
import sys

parser = argparse.ArgumentParser()
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
parser.add_argument("--blend", default=r"D:\git\OpenQuest_jdr\_tmp_path_asset\Geometry nodes- Path through grass\GeoNodesStonePath_End.blend")
parser.add_argument("--out", default=r"D:\git\OpenQuest_jdr\game\assets\objects3d\terrain\path_generated.glb")
parser.add_argument("--points", default="")
parser.add_argument("--points-file", default="")
parser.add_argument("--scale", type=float, default=0.55)
parser.add_argument("--grass-decimate", type=float, default=0.18)
parser.add_argument("--path-decimate", type=float, default=0.28)
args = parser.parse_args(argv)

points = []
if args.points:
    points = json.loads(args.points)
elif args.points_file:
    with open(args.points_file, "r", encoding="utf-8") as f:
        points = json.load(f)

bpy.ops.wm.open_mainfile(filepath=args.blend)
scene = bpy.context.scene

for obj in scene.objects:
    obj.select_set(False)

# Remplace la courbe du chemin par le tracé fourni.
path_obj = bpy.data.objects.get("path")
if path_obj is None:
    raise SystemExit("Objet 'path' introuvable")
if points:
    path_obj.data.splines.clear()
    spline = path_obj.data.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for i, p in enumerate(points):
        bp = spline.bezier_points[i]
        bp.co = (float(p[0]), float(p[1]), 0.0)
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
        bp.handle_left = bp.co
        bp.handle_right = bp.co
    path_obj.data.resolution_u = 24

# Réalise les instances du Grass System.
grass_src = bpy.data.objects.get("Grass System")
ng = grass_src.modifiers[0].node_group
out_node = next(n for n in ng.nodes if n.bl_idname == "NodeGroupOutput")
for link in list(ng.links):
    if link.to_node == out_node and link.to_socket.name == "Geometry":
        source = link.from_socket
        ng.links.remove(link)
        realize = ng.nodes.new("GeometryNodeRealizeInstances")
        ng.links.new(source, realize.inputs[0])
        ng.links.new(realize.outputs[0], out_node.inputs["Geometry"])
        break

def material(name, color, roughness=0.95):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
    return mat

def mesh_from(obj, name):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    mesh = bpy.data.meshes.new_from_object(ev)
    out = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(out)
    out.matrix_world = obj.matrix_world
    out.scale = (args.scale, args.scale, args.scale)
    return out

def decimate(obj, ratio):
    mod = obj.modifiers.new("ExportDecimate", "DECIMATE")
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)

GRASS_IMG = r"D:\git\OpenQuest_jdr\game\assets\terrain\grass.png"
STONE_IMG = r"D:\git\OpenQuest_jdr\game\assets\terrain\stone.png"

ground = mesh_from(bpy.data.objects.get("Ground"), "PathPatchGround")
decimate(ground, 0.025)
ground.data.materials.clear()
ground.data.materials.append(material("PathPatchGround", (0.16, 0.30, 0.10)))
if os.path.exists(GRASS_IMG):
    gimg = bpy.data.images.load(GRASS_IMG, check_existing=True)
    gmat = ground.data.materials[0]
    gtex = gmat.node_tree.nodes.new("ShaderNodeTexImage")
    gtex.image = gimg
    gmat.node_tree.links.new(gtex.outputs["Color"], gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])

grass = mesh_from(grass_src, "PathPatchGrass")
decimate(grass, args.grass_decimate)
grass.data.materials.clear()
grass.data.materials.append(material("PathPatchGrass", (0.22, 0.42, 0.12), 0.9))

path = mesh_from(path_obj, "PathPatchStones")
decimate(path, args.path_decimate)
bpy.ops.object.select_all(action="DESELECT")
path.select_set(True)
bpy.context.view_layer.objects.active = path
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02)
bpy.ops.object.mode_set(mode="OBJECT")
path.data.materials.clear()
path.data.materials.append(material("PathPatchStone", (0.42, 0.38, 0.31), 0.92))
if os.path.exists(STONE_IMG):
    simg = bpy.data.images.load(STONE_IMG, check_existing=True)
    smat = path.data.materials[0]
    stex = smat.node_tree.nodes.new("ShaderNodeTexImage")
    stex.image = simg
    smat.node_tree.links.new(stex.outputs["Color"], smat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])

for name in ["PathPatchGrass", "PathPatchStones"]:
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_set(False)
        obj.hide_render = False
        obj.select_set(True)

bpy.context.view_layer.update()
os.makedirs(os.path.dirname(args.out), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=args.out, export_format="GLB", use_selection=True,
    export_apply=True, export_texcoords=True, export_normals=True,
    export_materials="EXPORT", export_yup=True,
)
print("PARTS", [(o.name, len(o.data.vertices), len(o.data.polygons)) for o in bpy.context.selected_objects])
print("WROTE", args.out, os.path.getsize(args.out))
