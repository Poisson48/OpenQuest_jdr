extends SceneTree

## Non-régression caméra : changer d'outil ne doit pas téléporter la caméra,
## et un clic droit glissé doit déplacer la vue.

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test caméra outils", "general", "local", 24, 16)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1280, 720)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	for _i in range(3):
		await process_frame
	var engine = editor._engine
	engine.center_on_grid(12.0, 8.0)
	await process_frame
	var before: Vector3 = engine._camera.position

	for tool_id in ["proc_wall", "proc_fence", "proc_path", "proc_poly_roof", "terrain_height", "select"]:
		editor._set_tool(tool_id)
		await process_frame
		var moved: float = engine._camera.position.distance_to(before)
		_assert("tool_stable_%s" % tool_id, moved < 3.0, "moved=%.2f" % moved)

	# Pan au clic droit.
	var before_pan: Vector3 = engine._camera.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = Vector2(500, 350)
	engine._editor_gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(620, 350)
	engine._editor_gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = Vector2(620, 350)
	engine._editor_gui_input(release)
	await process_frame
	var pan_distance: float = engine._camera.position.distance_to(before_pan)
	_assert("right_drag_pans", pan_distance > 0.2, "moved=%.2f" % pan_distance)

	# Une synchro de l'éditeur (peinture sol, sélection) ne recadre pas.
	var before_sync: Vector3 = engine._camera.position
	editor._sync_engine()
	await process_frame
	var sync_distance: float = engine._camera.position.distance_to(before_sync)
	_assert("sync_stable", sync_distance < 2.0, "moved=%.2f" % sync_distance)

	if _failed:
		print("camera_navigation_test:FAIL")
		quit(1)
		return
	print("camera_navigation_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
