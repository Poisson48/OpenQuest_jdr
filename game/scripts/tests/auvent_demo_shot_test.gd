extends SceneTree

## Capture de la démo auvent (maison + auvent de façade).
## Lancer SANS --headless :
##   godot --path game --script res://scripts/tests/auvent_demo_shot_test.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	get_root().size = Vector2i(1600, 1000)
	var demo: Node = (load("res://scenes/debug/auvent_demo.tscn") as PackedScene).instantiate()
	get_root().add_child(demo)
	for _i in range(60):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		printerr("auvent_demo_shot_test:FAIL")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var out := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join("docs/screenshots/auvent_demo.png")
	img.save_png(out)
	print("  capture: ", out)
	print("auvent_demo_shot_test:PASS")
	quit(0)
