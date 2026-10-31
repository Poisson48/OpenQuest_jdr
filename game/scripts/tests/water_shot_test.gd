extends SceneTree

## Capture rapprochée de l'étang de la forêt (plans d'eau 2.5D).
## Non headless : nécessite un rendu réel.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var copy_dir := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join("docs/screenshots")
	var md = get_root().get_node("MapData")
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = boot.build_demo(md)
	var forest: Dictionary = {}
	for map_variant in demo.get("world_maps", []):
		if str((map_variant as Dictionary).get("title", "")) == "Forêt de l'Ouest":
			forest = map_variant
			break
	if forest.is_empty():
		printerr("  FAIL foret introuvable")
		quit(1)
		return
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	get_root().add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	editor.load_map(forest)
	await process_frame
	if editor._engine != null and editor._engine.has_method("focus_grid_rect"):
		editor._engine.focus_grid_rect(Rect2(0, 5, 6, 7))
	for _i in range(24):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		printerr("  FAIL capture")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var out := copy_dir.path_join("carte_25d_etang.png")
	img.save_png(out)
	print("  capture: ", out, " (", img.get_width(), "x", img.get_height(), ")")
	editor.queue_free()
	await process_frame
	print("water_shot_test:PASS")
	quit(0)
