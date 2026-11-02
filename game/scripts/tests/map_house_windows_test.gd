extends SceneTree

## Test de la maison rapide avec fenêtres automatiques.

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test maison fenêtres", "general", "local", 18, 14)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(960, 540)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	await process_frame
	editor._wall_height = 2.6
	editor._roof_height = 1.5
	editor._house_auto_windows = true
	editor._house_auto_interior = false
	editor._create_mesh_house(Vector2(3.0, 4.0), Vector2(9.0, 8.0))
	await process_frame
	var windows := 0
	for elem_variant in editor.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("asset", "")).contains("fenetre"):
			windows += 1
	_assert("house_auto_windows", windows > 0, "count=%d" % windows)

	if _failed:
		print("map_house_windows_test:FAIL")
		quit(1)
		return
	print("map_house_windows_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
