extends SceneTree

## Pan « suivi de souris » : le décor saisi au clic droit doit rester collé au
## curseur pendant le glisser, y compris en caméra perspective inclinée.
##
## Avant le correctif, la caméra se déplaçait en coordonnées monde XYZ avec une
## échelle fixe (span mesurée au centre) : le point saisi ne suivait pas la
## souris (dérive d'autant plus forte qu'on est loin du centre / en perspective).
##
## Vérifie aussi le pan au clic milieu (Maj+clic milieu = déplacer la vue) et
## que l'orbite (Maj + clic droit) ne déclenche PAS le suivi de souris.

const TOLERANCE_WORLD := 0.18

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test pan suivi", "general", "local", 30, 20)
	var heights: Array = []
	heights.resize(30 * 20)
	heights.fill(0.0)
	map["terrainHeights"] = heights
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	md.update_map(map)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1280, 720)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(md.get_by_id(str(map.get("id", ""))))
	for _i in range(3):
		await process_frame
	var engine = editor._engine
	engine.center_on_grid(15.0, 10.0)
	for _i in range(3):
		await process_frame

	# --- 1) Pan au clic droit : le point saisi suit le curseur -----------------
	# Le pan démarre au franchissement du seuil de 8 px : c'est le point de sol
	# sous le curseur À CE MOMENT-LÀ qui est saisi (pas celui du press, sinon la
	# vue sautait des 8 px du seuil au premier mouvement).
	var press_pos := Vector2(500.0, 300.0)
	var threshold_pos := Vector2(512.0, 300.0)
	var move_pos := Vector2(700.0, 420.0)
	var press_button := InputEventMouseButton.new()
	press_button.button_index = MOUSE_BUTTON_RIGHT
	press_button.pressed = true
	press_button.position = press_pos
	engine._editor_gui_input(press_button)
	var threshold_event := InputEventMouseMotion.new()
	threshold_event.position = threshold_pos
	threshold_event.relative = threshold_pos - press_pos
	engine._editor_gui_input(threshold_event)
	var anchor: Vector3 = engine._raycast_ground(engine._control_to_viewport(threshold_pos))
	_assert("anchor_found", anchor != Vector3.INF, str(anchor))
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.position = move_pos
	drag_motion.relative = move_pos - threshold_pos
	engine._editor_gui_input(drag_motion)
	var drag_release := InputEventMouseButton.new()
	drag_release.button_index = MOUSE_BUTTON_RIGHT
	drag_release.pressed = false
	drag_release.position = move_pos
	engine._editor_gui_input(drag_release)
	await process_frame
	var under_cursor: Vector3 = engine._raycast_ground(engine._control_to_viewport(move_pos))
	_assert("pan_keeps_ground_under_cursor",
		under_cursor != Vector3.INF and under_cursor.distance_to(anchor) < TOLERANCE_WORLD,
		"anchor=%s under=%s" % [str(anchor), str(under_cursor)])

	# --- 2) Pan CONTINU : deltas réguliers, pas de tremblement -----------------
	# Ancien bug : la projection du curseur utilisait la caméra courante (qui
	# bougeait), `move = ancre - point(caméra)` bouclait sur elle-même → la
	# caméra alternait entre deux positions (tremblement « changement de vue »).
	engine.center_on_grid(15.0, 10.0)
	for _i in range(3):
		await process_frame
	var smooth_press := InputEventMouseButton.new()
	smooth_press.button_index = MOUSE_BUTTON_RIGHT
	smooth_press.pressed = true
	smooth_press.position = Vector2(620.0, 380.0)
	engine._editor_gui_input(smooth_press)
	var previous: Vector3 = engine._camera.position
	var deltas: Array = []
	for i in range(9):
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(620.0 + float(i + 1) * 7.0, 380.0)
		motion.relative = Vector2(7.0, 0.0)
		engine._editor_gui_input(motion)
		await process_frame
		var current: Vector3 = engine._camera.position
		deltas.append((current - previous).length())
		previous = current
	var smooth_release := InputEventMouseButton.new()
	smooth_release.button_index = MOUSE_BUTTON_RIGHT
	smooth_release.pressed = false
	smooth_release.position = Vector2(620.0 + 63.0, 380.0)
	engine._editor_gui_input(smooth_release)
	var moving: Array = []
	for d in deltas:
		if float(d) > 0.0005:
			moving.append(float(d))
	var ratio := 1.0
	if moving.size() >= 2:
		var lo: float = moving[0]
		var hi: float = moving[0]
		for d in moving:
			lo = minf(lo, d)
			hi = maxf(hi, d)
		ratio = hi / maxf(lo, 0.000001)
	_assert("pan_continuous_regular", moving.size() >= 5 and ratio < 1.8,
		"deltas=%s ratio=%.2f" % [str(moving), ratio])

	# --- 3) Pan au clic milieu : même suivi -----------------------------------
	engine.center_on_grid(15.0, 10.0)
	for _i in range(3):
		await process_frame
	var press2 := Vector2(620.0, 260.0)
	var move2 := Vector2(760.0, 380.0)
	var anchor2: Vector3 = engine._raycast_ground(engine._control_to_viewport(press2))
	_middle_drag(engine, press2, move2)
	await process_frame
	var under2: Vector3 = engine._raycast_ground(engine._control_to_viewport(move2))
	_assert("middle_pan_keeps_ground_under_cursor",
		under2 != Vector3.INF and under2.distance_to(anchor2) < TOLERANCE_WORLD,
		"anchor=%s under=%s" % [str(anchor2), str(under2)])

	# --- 4) Orbite (Maj + clic droit) : ce n'est PAS un pan --------------------
	engine.center_on_grid(15.0, 10.0)
	engine._camera.position = Vector3(10.0, 20.0, 16.0)
	engine._camera.rotation_degrees = Vector3(-50.0, 0.0, 0.0)
	for _i in range(3):
		await process_frame
	var rot_before: Vector3 = engine._camera.rotation
	var focus_before: Vector2 = engine._ground_focus()
	var shift_press := InputEventMouseButton.new()
	shift_press.button_index = MOUSE_BUTTON_RIGHT
	shift_press.pressed = true
	shift_press.shift_pressed = true
	shift_press.position = Vector2(640.0, 360.0)
	engine._editor_gui_input(shift_press)
	var shift_move := InputEventMouseMotion.new()
	shift_move.position = Vector2(760.0, 360.0)
	shift_move.relative = Vector2(120.0, 0.0)
	engine._editor_gui_input(shift_move)
	var shift_release := InputEventMouseButton.new()
	shift_release.button_index = MOUSE_BUTTON_RIGHT
	shift_release.pressed = false
	shift_release.shift_pressed = true
	shift_release.position = Vector2(760.0, 360.0)
	engine._editor_gui_input(shift_release)
	await process_frame
	# Une orbite TOURNE autour du point visé : la rotation change, le point visé
	# reste globalement en place, et le pan « suivi de souris » n'est pas armé.
	_assert("shift_right_orbits_not_pans",
		not engine._pan_anchor_valid
		and (engine._camera.rotation - rot_before).length() > 0.02
		and engine._ground_focus().distance_to(focus_before) < 1.5,
		"anchor_valid=%s rot_delta=%.3f focus_delta=%.2f" % [
			str(engine._pan_anchor_valid),
			(engine._camera.rotation - rot_before).length(),
			engine._ground_focus().distance_to(focus_before)])

	editor.queue_free()
	await process_frame
	_finish()


func _right_drag(engine, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = from
	engine._editor_gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	engine._editor_gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = to
	engine._editor_gui_input(release)


func _middle_drag(engine, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.shift_pressed = true
	press.position = from
	engine._editor_gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	engine._editor_gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	release.pressed = false
	release.shift_pressed = true
	release.position = to
	engine._editor_gui_input(release)


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)


func _finish() -> void:
	if _failed:
		print("pan_cursor_tracking_test:FAIL")
		quit(1)
		return
	print("pan_cursor_tracking_test:PASS")
	quit(0)
