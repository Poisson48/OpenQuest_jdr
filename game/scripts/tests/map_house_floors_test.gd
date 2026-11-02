extends SceneTree

## Test maison à étage : les murs du niveau supérieur sont surélevés.

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test maison étages", "general", "local", 18, 14)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(960, 540)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	await process_frame
	editor._wall_height = 1.3
	editor._roof_height = 1.1
	editor._house_floors = 2
	editor._house_auto_windows = false
	editor._house_auto_interior = false
	editor._create_mesh_house(Vector2(3.0, 4.0), Vector2(9.0, 8.0))
	await process_frame
	var upper_walls := 0
	var ground_walls := 0
	for elem_variant in editor.doc.elements_of_kind("mesh"):
		var elem: Dictionary = elem_variant
		if not str(elem.get("asset", "")).contains("mur"):
			continue
		if float(elem.get("elevation", 0.0)) > 0.5:
			upper_walls += 1
		else:
			ground_walls += 1
	_assert("house_ground_walls", ground_walls > 0)
	_assert("house_upper_walls", upper_walls > 0, "upper=%d" % upper_walls)

	if _failed:
		print("map_house_floors_test:FAIL")
		quit(1)
		return
	print("map_house_floors_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
