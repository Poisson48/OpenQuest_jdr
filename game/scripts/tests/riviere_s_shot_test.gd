extends SceneTree

## Captures de la démo « Rivière en S » : vue d'ensemble de la carte et gros
## plan sur le méandre + le pont, avec l'eau CS2 (lit creusé, berges, reflets).
## Non headless : rendu réel (fenêtre cachée via run_tests.ps1).
##
## Lancement direct :
##   godot --path game --script res://scripts/tests/riviere_s_shot_test.gd

const Demo := preload("res://scripts/debug/riviere_s_boot.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  [SKIP] capture d'écran impossible en headless.")
		quit(0)
		return
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = Demo.build_map(md)
	if map.is_empty():
		_fail("map_empty")
		return
	DisplayServer.window_set_title("Rivière en S — démo eau")
	get_root().content_scale_factor = 1.0
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	get_root().size = Vector2i(1600, 1000)

	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(editor)
	await process_frame
	editor.size = editor.get_viewport_rect().size
	editor.load_map(map)
	editor.set_editable(false)
	await process_frame
	Demo.apply_river(editor)
	for _i in range(20):
		await process_frame

	# 1) Vue d'ensemble (carte entière).
	if editor._engine != null:
		editor._engine.request_fit_to_view()
	for _i in range(24):
		await process_frame
	_capture("demo_riviere_s.png")

	# 2) Gros plan sur le pont et le méandre central (caméra basse 3/4).
	if editor._engine != null:
		var engine = editor._engine
		var cam: Camera3D = engine._camera
		var cell := float(engine._cell_size)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 46.0
		var look := Vector3(20.5 * cell + cell * 0.5, 0.35 * cell,
			12.0 * cell + cell * 0.5)
		var pitch := -22.0
		var yaw := -102.0
		var basis := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
		var forward := -basis.z
		var distance := 13.0 * cell
		engine._orbit_enabled = true
		engine._orbit_target = look
		engine._orbit_distance = distance
		engine._orbit_yaw = yaw
		engine._orbit_pitch = pitch
		cam.global_transform = Transform3D(basis, look - forward * distance)
	for _i in range(24):
		await process_frame
	_capture("demo_riviere_s_detail.png")

	if _failed:
		print("riviere_s_shot_test:FAIL")
		quit(1)
		return
	print("riviere_s_shot_test:PASS")
	quit(0)


func _capture(name: String) -> void:
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		_fail("capture_" + name)
		return
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var copy_dir := ProjectSettings.globalize_path("res://..").path_join("docs/screenshots")
	DirAccess.make_dir_recursive_absolute(copy_dir)
	var out := copy_dir.path_join(name)
	img.save_png(out)
	print("  capture: ", out)


func _fail(name: String) -> void:
	_failed = true
	print("  [FAIL] ", name)


func _finish() -> void:
	if _failed:
		print("riviere_s_shot_test:FAIL")
		quit(1)
		return
	print("riviere_s_shot_test:PASS")
	quit(0)

var _failed := false
