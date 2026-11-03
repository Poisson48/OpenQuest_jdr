extends SceneTree

## Test du démarrage rapide : une carte doit devenir agréable en un clic.

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test démarrage rapide", "general", "local", 24, 18)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	await process_frame
	editor._on_quick_start(0)
	for _i in range(240):
		await process_frame
		if editor._gen_panel != null and not editor._gen_panel.visible:
			break
	_assert("village_created", editor.doc.elements_sorted().size() > 10,
		"elements=%d" % editor.doc.elements_sorted().size())
	_assert("terrain_mode", str(editor.doc.map_data.get("groundMode", "")) == "terrain3d")
	_assert("lighting_tiny_glade",
		str(md.get_lighting_config(editor.doc.map_data).get("preset", "")) == "tiny_glade")
	_assert("render_style", str(editor.doc.map_data.get("renderStyle", "")) == "2.5d")

	var before_light := str(md.get_lighting_config(editor.doc.map_data).get("preset", ""))
	editor._on_quick_lighting(0)
	await process_frame
	_assert("lighting_changed",
		str(md.get_lighting_config(editor.doc.map_data).get("preset", "")) != before_light
			or before_light.is_empty())

	if _failed:
		print("map_quick_start_test:FAIL")
		quit(1)
		return
	print("map_quick_start_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
