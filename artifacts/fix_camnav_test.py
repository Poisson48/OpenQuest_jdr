from pathlib import Path

p = Path('game/scripts/tests/camera_navigation_test.gd')
s = p.read_text(encoding='utf-8')
old = '''	# Pan au clic droit.
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
	engine._editor_gui_input(release)'''
new = '''	# Pan au clic droit. Le pan s'ancre au franchissement du seuil (8 px) : on
	# simule donc un premier motion de seuil, puis le vrai déplacement.
	var before_pan: Vector3 = engine._camera.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = Vector2(500, 350)
	engine._editor_gui_input(press)
	var threshold_motion := InputEventMouseMotion.new()
	threshold_motion.position = Vector2(512, 350)
	threshold_motion.relative = Vector2(12, 0)
	engine._editor_gui_input(threshold_motion)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(620, 350)
	motion.relative = Vector2(108, 0)
	engine._editor_gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = Vector2(620, 350)
	engine._editor_gui_input(release)'''
assert old in s, 'bloc pan duo introuvable'
p.write_text(s.replace(old, new, 1), encoding='utf-8')
print('camera_navigation_test : motion de seuil ajouté avant le vrai pan')
