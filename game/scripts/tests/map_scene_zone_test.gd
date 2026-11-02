extends SceneTree

## Test « Esquisser une scène » : le procédural complète une zone dessinée.

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test esquisse zone", "general", "local", 26, 18)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	await process_frame
	editor._scene_style = "village"
	editor._scene_seed = 4242
	editor._generate_scene_area_live(Vector2(4, 3), Vector2(14, 13))
	for _i in range(240):
		await process_frame
		if editor._gen_panel != null and not editor._gen_panel.visible:
			break
	_assert("zone_elements", editor.doc.elements_sorted().size() > 5,
		"elements=%d" % editor.doc.elements_sorted().size())
	var wrong := 0
	for elem_variant in editor.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		var x := float(elem.get("x", 0.0))
		var y := float(elem.get("y", 0.0))
		if x < 2.0 or y < 1.0 or x > 16.0 or y > 15.0:
			wrong += 1
	_assert("zone_bounds", wrong == 0, "hors_zone=%d" % wrong)
	if _failed:
		print("map_scene_zone_test:FAIL")
		quit(1)
		return
	print("map_scene_zone_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
