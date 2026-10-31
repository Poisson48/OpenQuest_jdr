extends SceneTree

## Capture rapprochée du bord de carte pour vérifier la jupe de falaise.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var copy_dir := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join("docs/screenshots")
	var md = get_root().get_node("MapData")
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = boot.build_demo(md)
	var village: Dictionary = demo.get("map", {})
	var EngineScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var engine: Control = EngineScript.new()
	get_root().add_child(engine)
	engine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	engine.configure(village, [], [], [], [], [], false, true)
	await process_frame
	if engine.has_method("focus_grid_rect"):
		engine.focus_grid_rect(Rect2(6.0, 8.0, 14.0, 8.0))
	# Caméra volontairement rasant pour contrôler la jupe de falaise.
	if engine._camera != null:
		engine._camera.rotation_degrees = Vector3(-35.0, 0.0, 0.0)
		engine._camera.position = Vector3(engine._camera.position.x, 26.0, 34.0)
	for _i in range(20):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		printerr("  FAIL capture")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var out := copy_dir.path_join("carte_25d_falaise.png")
	img.save_png(out)
	print("  capture: ", out, " (", img.get_width(), "x", img.get_height(), ")")
	engine.queue_free()
	await process_frame
	print("cliff_shot_test:PASS")
	quit(0)
