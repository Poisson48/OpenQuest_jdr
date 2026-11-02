extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	get_root().size = Vector2i(1600, 1000)
	var demo: Node = (load("res://scenes/debug/terrain_spline_demo.tscn") as PackedScene).instantiate()
	get_root().add_child(demo)
	for _i in range(8):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		printerr("terrain_spline_demo_shot_test:FAIL")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var out := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join("docs/screenshots/terrain_spline_demo.png")
	img.save_png(out)
	print("  capture: ", out)
	print("terrain_spline_demo_shot_test:PASS")
	quit(0)
