from pathlib import Path

p = Path('game/scripts/tests/pan_cursor_tracking_test.gd')
s = p.read_text(encoding='utf-8')
old = '''	# --- 1) Pan au clic droit : le point saisi suit le curseur -----------------
	var press_pos := Vector2(500.0, 300.0)
	var move_pos := Vector2(700.0, 420.0)
	var anchor: Vector3 = engine._raycast_ground(engine._control_to_viewport(press_pos))
	_assert("anchor_found", anchor != Vector3.INF, str(anchor))
	_right_drag(engine, press_pos, move_pos)
	await process_frame
	var under_cursor: Vector3 = engine._raycast_ground(engine._control_to_viewport(move_pos))
	_assert("pan_keeps_ground_under_cursor",
		under_cursor != Vector3.INF and under_cursor.distance_to(anchor) < TOLERANCE_WORLD,
		"anchor=%s under=%s" % [str(anchor), str(under_cursor)])'''
new = '''	# --- 1) Pan au clic droit : le point saisi suit le curseur -----------------
	# Le pan démarre au franchissement du seuil de 8 px : c'est le point de sol
	# sous le curseur À CE MOMENT-LÀ qui est saisi (pas celui du press, sinon la
	# vue sautait des 8 px du seuil au premier mouvement).
	var press_pos := Vector2(500.0, 300.0)
	var threshold_pos := Vector2(512.0, 300.0)
	var move_pos := Vector2(700.0, 420.0)
	var smooth_press := InputEventMouseButton.new()
	smooth_press.button_index = MOUSE_BUTTON_RIGHT
	smooth_press.pressed = true
	smooth_press.position = press_pos
	engine._editor_gui_input(smooth_press)
	var threshold_motion := InputEventMouseMotion.new()
	threshold_motion.position = threshold_pos
	threshold_motion.relative = threshold_pos - press_pos
	engine._editor_gui_input(threshold_motion)
	var anchor: Vector3 = engine._raycast_ground(engine._control_to_viewport(threshold_pos))
	_assert("anchor_found", anchor != Vector3.INF, str(anchor))
	var motion := InputEventMouseMotion.new()
	motion.position = move_pos
	motion.relative = move_pos - threshold_pos
	engine._editor_gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = move_pos
	engine._editor_gui_input(release)
	await process_frame
	var under_cursor: Vector3 = engine._raycast_ground(engine._control_to_viewport(move_pos))
	_assert("pan_keeps_ground_under_cursor",
		under_cursor != Vector3.INF and under_cursor.distance_to(anchor) < TOLERANCE_WORLD,
		"anchor=%s under=%s" % [str(anchor), str(under_cursor)])'''
assert old in s, 'section 1 test introuvable'
p.write_text(s.replace(old, new, 1), encoding='utf-8')
print('pan_cursor_tracking_test : ancre au seuil de drag')
