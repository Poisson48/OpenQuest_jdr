extends SceneTree

## Capture du dialogue de création de zone (nom + thème + description).
## Lancer SANS --headless :
##   godot --path game --script res://scripts/tests/zone_theme_shot_test.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = boot.build_demo(md)
	if demo.is_empty():
		printerr("zone_theme_shot_test:FAIL (démo vide)")
		quit(1)
		return
	var copy_dir := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join("docs/screenshots")
	DirAccess.make_dir_recursive_absolute(copy_dir)
	DisplayServer.window_set_title("Carte 2.5D — thème de zone")
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	get_root().size = Vector2i(1600, 1000)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(editor)
	await process_frame
	editor.size = editor.get_viewport_rect().size
	editor.load_map(demo["map"])
	await process_frame
	var world_tab: int = editor._right_tabs.get_tab_idx_from_control(editor._world_panel)
	if world_tab >= 0:
		editor._right_tabs.current_tab = world_tab
	editor._world_panel._ensure_dialogs()
	editor._world_panel._open_create_zone()
	await process_frame
	if editor._world_panel._zone_theme_opt != null:
		editor._world_panel._zone_theme_opt.select(4)
		editor._world_panel._update_zone_theme_hint(4)
	for _i in range(12):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		printerr("zone_theme_shot_test:FAIL (capture nulle)")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var out := copy_dir.path_join("carte_25d_zone_theme.png")
	img.save_png(out)
	print("  capture: ", out, " (", img.get_width(), "x", img.get_height(), ")")
	print("zone_theme_shot_test:PASS")
	quit(0)
