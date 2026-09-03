extends SceneTree

## Verrouille la géométrie de caméra diorama / VTT (audit P1).
## Mesure pan, rectangle visible et hauteur de recadrage — pas seulement les données.

const StyleScript := preload("res://scripts/maps/map_render_style.gd")

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var Engine3DScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd") as GDScript
	_assert("engine_script", Engine3DScript != null)
	if _failed:
		quit(1)
		return

	await _test_diorama_pan_and_visible(Engine3DScript, md)
	await _test_fit_scales_with_map_size(Engine3DScript, md)
	await _test_vtt_is_orthographic(Engine3DScript, md)
	await _test_create_defaults(md)

	if _failed:
		printerr("map_camera_test:FAIL")
		quit(1)
		return
	print("map_camera_test:PASS")
	quit(0)

func _make_engine(Engine3DScript: GDScript, size: Vector2 = Vector2(1000, 700)) -> Control:
	var engine: Control = Engine3DScript.new()
	engine.size = size
	get_root().add_child(engine)
	return engine

func _wait_frames(n: int = 8) -> void:
	for _i in range(n):
		await process_frame

func _test_diorama_pan_and_visible(Engine3DScript: GDScript, md) -> void:
	var map: Dictionary = md.create_complex_map("Caméra diorama 40x30", "general", "local", 40, 30)
	map["renderStyle"] = "diorama"
	map["fogEnabled"] = false
	md.update_map(map)
	map = md.get_by_id(str(map.get("id", "")))

	var engine: Control = _make_engine(Engine3DScript)
	engine.configure(map, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	await _wait_frames(12)
	if engine.has_method("reset_zoom"):
		engine.reset_zoom()
	await _wait_frames(6)

	_assert("dio_perspective", engine._camera.projection == Camera3D.PROJECTION_PERSPECTIVE)

	var span: Vector2 = engine._ground_span_per_pixel()
	_assert("dio_span_positive", span.x > 0.0001 and span.y > 0.0001)
	# Ancien bug : span dérivé de size=1 → ~0.002 u/px. Attendu ~0.02–0.05 u/px
	# pour une carte cadrée (100 px ≈ quelques cases).
	var pan_100_world: float = span.x * 100.0
	var pan_100_cells: float = pan_100_world / engine.get_cell_size()
	print("  pan_100_cells=", pan_100_cells, " span=", span)
	_assert("dio_pan_not_tiny", pan_100_cells > 1.0)
	_assert("dio_pan_not_huge", pan_100_cells < 20.0)

	var visible: Rect2 = engine.visible_grid_rect()
	print("  visible_grid=", visible)
	_assert("dio_visible_w", visible.size.x > 15.0)
	_assert("dio_visible_h", visible.size.y > 10.0)
	# Ancien bug : ~4×3 cases. Doit couvrir une bonne part de 40×30.
	_assert("dio_visible_covers_map", visible.size.x > 20.0 or visible.size.y > 15.0)

	# Zoomer pour que le clamp n'annule pas le pan (carte entière visible → pan verrouillé).
	engine._apply_zoom(2.5, Vector2(500, 350))
	await _wait_frames(2)
	span = engine._ground_span_per_pixel()
	var before: Vector3 = engine._camera.position
	engine.begin_view_pan(Vector2(200, 200))
	engine.update_view_pan(Vector2(300, 200))  # +100 px en X
	var after: Vector3 = engine._camera.position
	var moved: float = absf(after.x - before.x)
	var expected: float = span.x * 100.0
	print("  pan_moved=", moved, " expected≈", expected)
	_assert("dio_pan_matches_span", moved > expected * 0.5 and moved < expected * 1.5)

	engine.queue_free()
	await _wait_frames(2)

func _test_fit_scales_with_map_size(Engine3DScript: GDScript, md) -> void:
	var small: Dictionary = md.create_complex_map("Caméra small", "general", "local", 20, 14)
	small["renderStyle"] = "diorama"
	small["fogEnabled"] = false
	md.update_map(small)
	var big: Dictionary = md.create_complex_map("Caméra big", "general", "local", 96, 72)
	big["renderStyle"] = "diorama"
	big["fogEnabled"] = false
	md.update_map(big)

	var eng_s: Control = _make_engine(Engine3DScript)
	eng_s.configure(md.get_by_id(str(small.get("id", ""))), [], [], [], [], [], false, true, {}, {}, "")
	await _wait_frames(10)
	eng_s.reset_zoom()
	await _wait_frames(4)
	var y_small: float = eng_s._camera.position.y

	var eng_b: Control = _make_engine(Engine3DScript)
	eng_b.configure(md.get_by_id(str(big.get("id", ""))), [], [], [], [], [], false, true, {}, {}, "")
	await _wait_frames(10)
	eng_b.reset_zoom()
	await _wait_frames(4)
	var y_big: float = eng_b._camera.position.y

	print("  fit_y_small=", y_small, " fit_y_big=", y_big)
	# Ancien bug : y=48 pour les deux. La grande carte doit être nettement plus haute.
	_assert("fit_big_taller", y_big > y_small * 1.5)
	_assert("fit_small_positive", y_small > 1.0)

	eng_s.queue_free()
	eng_b.queue_free()
	await _wait_frames(2)

func _test_vtt_is_orthographic(Engine3DScript: GDScript, md) -> void:
	var map: Dictionary = md.create_complex_map("Caméra VTT", "general", "local", 24, 18)
	# Même si une carte porte encore le tilt historique…
	map["renderStyle"] = "vtt"
	map["perspective"] = "perspective"
	map["fogEnabled"] = false
	md.update_map(map)

	var engine: Control = _make_engine(Engine3DScript)
	engine.configure(md.get_by_id(str(map.get("id", ""))), [], [], [], [], [], false, true, {}, {}, "")
	await _wait_frames(10)
	engine.reset_zoom()
	await _wait_frames(4)

	_assert("vtt_ortho", engine._camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	_assert("vtt_topdown", is_equal_approx(engine._camera.rotation_degrees.x, -90.0))
	_assert("vtt_not_diorama", not StyleScript.is_diorama(engine.map_data))

	var span: Vector2 = engine._ground_span_per_pixel()
	var pan_100_cells: float = (span.x * 100.0) / engine.get_cell_size()
	print("  vtt_pan_100_cells=", pan_100_cells)
	_assert("vtt_pan_sane", pan_100_cells > 1.0 and pan_100_cells < 25.0)

	engine.queue_free()
	await _wait_frames(2)

func _test_create_defaults(md) -> void:
	var map: Dictionary = md.create_complex_map("Defaults cam", "general", "local", 16, 12)
	_assert("default_diorama", str(map.get("renderStyle", "")) == "diorama")
	_assert("default_topdown", str(map.get("perspective", "")) == "topdown")

func _assert(name: String, cond: bool) -> void:
	if cond:
		print("  OK  ", name)
	else:
		printerr("FAIL  ", name)
		_failed = true
