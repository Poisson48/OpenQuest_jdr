extends SceneTree

## Végétation en cartouches alpha : les 5 plants (roseaux, buisson, haie,
## nénuphars, bosquet) sont générés par `tools/blender/build_vegetation_cards.py`.
## Vérifie : matériau alpha-scissor importé, texture 1024² avec mipmaps, très
## peu de triangles, et — en jeu — application du shader de végétation (vent,
## double face) au lieu du matériau standard qui forcerait le cull back.

const ASSETS := {
	"roseaux": "res://assets/objects3d/vegetation/roseaux.glb",
	"buisson": "res://assets/objects3d/vegetation/buisson.glb",
	"haie": "res://assets/objects3d/vegetation/haie.glb",
	"nenuphars": "res://assets/objects3d/vegetation/nenuphars.glb",
	"bosquet": "res://assets/objects3d/vegetation/bosquet.glb",
}
const CARD_SHADER := "res://shaders/vegetation_card.gdshader"
const CARD_UNSHADED_SHADER := "res://shaders/vegetation_card_unshaded.gdshader"
const MAX_TRIANGLES := 24

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	# --- 1) Assets : matériau alpha + texture + budget de triangles -----------
	for name in ASSETS:
		var packed := load(ASSETS[name]) as PackedScene
		_assert("load_%s" % name, packed != null)
		if packed == null:
			continue
		var scene := packed.instantiate()
		var mesh_instance := _first_mesh_instance(scene)
		_assert("mesh_%s" % name, mesh_instance != null and mesh_instance.mesh != null)
		if mesh_instance == null or mesh_instance.mesh == null:
			scene.free()
			continue
		var tris := 0
		var mesh: Mesh = mesh_instance.mesh
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var indices = arrays[Mesh.ARRAY_INDEX]
			tris += (indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
		_assert("triangles_%s" % name, tris <= MAX_TRIANGLES, "tris=%d" % tris)
		var material := mesh_instance.get_active_material(0)
		_assert("material_%s" % name, material is StandardMaterial3D)
		if material is StandardMaterial3D:
			var standard := material as StandardMaterial3D
			_assert("alpha_%s" % name,
				standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,
				"transparency=%d" % standard.transparency)
			_assert("texture_%s" % name, standard.albedo_texture != null)
			if standard.albedo_texture != null:
				var image := standard.albedo_texture.get_image()
				_assert("texture_size_%s" % name,
					standard.albedo_texture.get_width() >= 1024,
					"w=%d" % standard.albedo_texture.get_width())
				_assert("texture_mips_%s" % name, image != null and image.has_mipmaps())
		scene.free()

	# --- 2) En jeu : le shader de végétation remplace le matériau standard ----
	var md = get_root().get_node("MapData")
	var demo := preload("res://scripts/debug/riviere_s_boot.gd")
	var map: Dictionary = demo.build_map(md)
	_assert("demo_map", not map.is_empty())
	# Ajoute les plants du kit sur une bande pour vérifier l'application moteur.
	var y := 2.0
	for name in ASSETS:
		map["elements"] = map.get("elements", [])
		(map["elements"] as Array).append({
			"kind": "mesh", "id": "cards_%s" % name, "asset": ASSETS[name],
			"x": 4.0 + float(map["elements"].size()) * 2.0, "y": y,
			"w": 2.0, "h": 2.0, "scale": 1.0, "rotation": 0.0,
		})
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1280, 720)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	for _i in range(4):
		await process_frame
	var card_materials := 0
	var standard_bleed := 0
	var stack: Array = [editor._engine]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null:
				for surface in range(mesh_instance.mesh.get_surface_count()):
					var material = mesh_instance.get_active_material(surface)
					if material is ShaderMaterial:
						var shader_path := (material as ShaderMaterial).shader.resource_path
						if shader_path == CARD_SHADER or shader_path == CARD_UNSHADED_SHADER:
							card_materials += 1
		for child in node.get_children():
			stack.push_back(child)
	_assert("card_shader_applied", card_materials >= ASSETS.size(),
		"materials=%d" % card_materials)
	editor.queue_free()
	await process_frame
	_finish()


func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh_instance(child)
		if found != null:
			return found
	return null


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)


func _finish() -> void:
	if _failed:
		print("vegetation_cards_test:FAIL")
		quit(1)
		return
	print("vegetation_cards_test:PASS")
	quit(0)
