extends SceneTree

## Test d'application du générateur de scène à une vraie carte : chemins peints,
## maisons construites et décor posé.

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test scène appliquée", "general", "local", 30, 20)
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["lighting"] = {"enabled": false, "preset": "tiny_glade", "sources": []}
	md.update_map(map)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1280, 720)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(md.get_by_id(str(map.get("id", ""))))
	await process_frame
	editor._scene_style = "village"
	editor._scene_seed = 42
	editor._scene_density = 1.0
	editor._construction._generate_scene(Vector2(15.0, 10.0))
	await process_frame
	var meshes: Array = editor.doc.elements_of_kind("mesh")
	var walls := 0
	var doors := 0
	var decor := 0
	for elem_variant in meshes:
		var elem: Dictionary = elem_variant
		var asset := str(elem.get("asset", ""))
		if asset.contains("mur"):
			walls += 1
		elif asset.contains("porte"):
			doors += 1
		elif str(elem.get("label", "")) == "Décor de scène":
			decor += 1
	_assert("scene_walls", walls > 0, "walls=%d" % walls)
	_assert("scene_doors", doors > 0, "doors=%d" % doors)
	_assert("scene_decor", decor > 0, "decor=%d" % decor)
	var materials: Array = editor.doc.map_data.get("terrainMaterials", [])
	var path_cells := 0
	for value in materials:
		if int(value) == 1:
			path_cells += 1
	_assert("scene_path", path_cells > 0, "cells=%d" % path_cells)

	if _failed:
		print("map_scene_apply_test:FAIL")
		quit(1)
		return
	print("map_scene_apply_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
