import bpy
import os

SRC = r"D:\git\OpenQuest_jdr\_tmp_path_asset\Geometry nodes- Path through grass\GeoNodesStonePath_End.blend"
OUT = r"D:\git\OpenQuest_jdr\game\assets\objects3d\terrain\path_through_grass.glb"
SCALE = 0.55
GRASS_IMG = r"D:\git\OpenQuest_jdr\game\assets\terrain\dirt_ai.png"

bpy.ops.wm.open_mainfile(filepath=SRC)
scene = bpy.context.scene
for obj in scene.objects:
    obj.select_set(False)

# Réalise les instances du Grass System dans son node group.
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
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
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
    out.scale = (SCALE, SCALE, SCALE)
    return out

def decimate(obj, ratio):
    mod = obj.modifiers.new("ExportDecimate", "DECIMATE")
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)

# Sol : 30k triangles suffisent sous l'herbe.
ground_obj = bpy.data.objects.get("Ground")
ground = mesh_from(ground_obj, "PathPatchGround")
decimate(ground, 0.025)
ground.data.materials.clear()
ground.data.materials.append(material("PathPatchGround", (0.16, 0.30, 0.10)))

# Herbe : on garde assez de brins pour la densité, puis décimation légère.
grass = mesh_from(grass_src, "PathPatchGrass")
decimate(grass, 0.055)
grass.data.materials.clear()
grass.data.materials.append(material("PathPatchGrass", (0.22, 0.42, 0.12), 0.9))

# Chemin : UV + texture IA.
path_obj = bpy.data.objects.get("path")
path = mesh_from(path_obj, "PathPatchStones")
decimate(path, 0.28)
bpy.ops.object.select_all(action="DESELECT")
path.select_set(True)
bpy.context.view_layer.objects.active = path
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02)
bpy.ops.object.mode_set(mode="OBJECT")
path_mat = material("PathPatchStone", (0.42, 0.38, 0.31), 0.92)
path.data.materials.clear()
path.data.materials.append(path_mat)
if os.path.exists(GRASS_IMG):
    img = bpy.data.images.load(GRASS_IMG, check_existing=True)
    bsdf = path_mat.node_tree.nodes.get("Principled BSDF")
    tex = path_mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    path_mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

for name in ["PathPatchGrass", "PathPatchStones"]:
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_set(False)
        obj.hide_render = False
        obj.select_set(True)

bpy.context.view_layer.update()
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format="GLB", use_selection=True,
    export_apply=True, export_texcoords=True, export_normals=True,
    export_materials="EXPORT", export_yup=True,
)
for name in ["PathPatchGround", "PathPatchGrass", "PathPatchStones"]:
    obj = bpy.data.objects.get(name)
    if obj:
        print("PART", name, len(obj.data.vertices), len(obj.data.polygons))
print("WROTE", OUT, os.path.getsize(OUT))
