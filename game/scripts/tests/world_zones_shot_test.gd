extends SceneTree

## Captures des zones de la démo monde (taverne, donjon) dans l'éditeur 2.5D.
## Non headless : nécessite un rendu réel pour sauvegarder les PNG.

var _failed := false
var _copy_dir := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_copy_dir = ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join("docs/screenshots")
	var md = get_root().get_node("MapData")
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = boot.build_demo(md)
	_assert("demo_built", not demo.is_empty())

	var wanted := {
		"Taverne du Corbeau": "carte_25d_taverne.png",
		"Donjon de Valbois": "carte_25d_donjon.png",
		"Forêt de l'Ouest": "carte_25d_foret.png",
	}
	var world_maps: Array = demo.get("world_maps", [])
	for title in wanted:
		var map: Dictionary = {}
		for map_variant in world_maps:
			if map_variant is Dictionary and str((map_variant as Dictionary).get("title", "")) == str(title):
				map = map_variant
				break
		if map.is_empty():
			map = _find_map(md, str(title))
		if map.is_empty():
			_assert("map_" + str(title), false)
			continue
		var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
		get_root().add_child(editor)
		editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		editor.load_map(map)
		editor._apply_responsive_layout()
		for _i in range(24):
			await process_frame
		var img: Image = get_root().get_texture().get_image()
		if img == null:
			_assert("capture_" + str(title), false)
		else:
			img.convert(Image.FORMAT_RGBA8)
			var out := _copy_dir.path_join(str(wanted[title]))
			img.save_png(out)
			print("  capture: ", out, " (", img.get_width(), "x", img.get_height(), ")")
			_assert("capture_" + str(title), true)
		editor.queue_free()
		await process_frame

	if _failed:
		print("world_zones_shot_test:FAIL")
		quit(1)
		return
	print("world_zones_shot_test:PASS")
	quit(0)

func _find_map(md, title: String) -> Dictionary:
	for map_variant in md.maps:
		if map_variant is Dictionary and str((map_variant as Dictionary).get("title", "")) == title:
			return map_variant
	return {}

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
