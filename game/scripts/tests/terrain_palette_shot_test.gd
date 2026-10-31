extends SceneTree

## Capture de la palette de sols : herbe, terre, pierre, neige et sable peints
## sur la carte de démonstration. Lancer SANS --headless :
##   godot --path game --script res://scripts/tests/terrain_palette_shot_test.gd

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var BootScript: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = BootScript.build_demo(md)
	if demo.is_empty():
		printerr("terrain_palette_shot_test:FAIL (démo vide)")
		quit(1)
		return
	var copy_dir := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join("docs/screenshots")
	DirAccess.make_dir_recursive_absolute(copy_dir)
	DisplayServer.window_set_title("Carte 2.5D — palette de sols")
	get_root().content_scale_factor = 1.0
	DisplayServer.window_set_size(Vector2i(1920, 1200))
	get_root().size = Vector2i(1920, 1200)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(editor)
	await process_frame
	editor.size = editor.get_viewport_rect().size
	editor.load_map(demo["map"])
	await process_frame
	editor._layout_force = true
	editor._apply_responsive_layout()
	await process_frame
	# Patchs de neige (nord-ouest) et de sable (sud-est) pour documenter la palette.
	for step in range(4):
		editor.doc.paint_terrain_material_brush(Vector2(3.0 + step * 1.6, 3.0), 2.2,
			MapData.MATERIAL_SNOW, "Neige")
		editor.doc.paint_terrain_material_brush(Vector2(19.0 + step * 1.2, 12.0), 2.0,
			MapData.MATERIAL_SAND, "Sable")
	editor._sync_engine()
	await _wait(12)
	if editor._engine.has_method("request_fit_to_view"):
		editor._engine.request_fit_to_view()
	await _wait(24)
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		_failed = true
		printerr("  FAIL capture nulle")
	else:
		img.convert(Image.FORMAT_RGBA8)
		var out := copy_dir.path_join("carte_25d_sols.png")
		img.save_png(out)
		print("  capture: ", out, " (", img.get_width(), "x", img.get_height(), ")")
	editor.queue_free()
	await _wait(4)
	if _failed:
		printerr("terrain_palette_shot_test:FAIL")
		quit(1)
		return
	print("terrain_palette_shot_test:PASS")
	quit(0)

func _wait(n: int) -> void:
	for _i in range(n):
		await process_frame
