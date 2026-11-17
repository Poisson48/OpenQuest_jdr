from pathlib import Path

# 1) Le pan démarre à la position RÉELLE du motion de seuil (pas au press) :
#    plus de saut initial équivalent aux 8 px de seuil.
p = Path('game/scripts/maps/complex_map_engine_3d.gd')
s = p.read_text(encoding='utf-8')
old = '''				else:
					# Clic droit glissé : déplacer la vue (pan).
					_pan_dragging = true
					_orbit_dragging = false
					_begin_view_drag(_right_nav_start, true)'''
new = '''				else:
					# Clic droit glissé : déplacer la vue (pan). On ancre le pan
					# sur la position COURANTE du curseur (et non sur le press) :
					# les pixels du seuil de 8 px ne font plus sauter la vue.
					_pan_dragging = true
					_orbit_dragging = false
					_begin_view_drag(motion.position, true)'''
assert old in s, 'bloc pan clic droit introuvable'
s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')
print('pan : ancre au motion de seuil, plus de saut initial')

# 2) Test : pan continu régulier (pas d'oscillation), verrouillé par assertion.
p = Path('game/scripts/tests/pan_cursor_tracking_test.gd')
s = p.read_text(encoding='utf-8')
anchor = '''	# --- 2) Pan au clic milieu : même suivi -----------------------------------'''
test = '''	# --- 2) Pan CONTINU : deltas réguliers, pas de tremblement -----------------
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

	# --- 3) Pan au clic milieu : même suivi -----------------------------------'''
assert anchor in s, 'ancre test milieu introuvable'
s = s.replace(anchor, test, 1)

# La fin du fichier teste le pan milieu : on garde l'ordre, seules les
# numéros de sections changent (commentaires).
s = s.replace('	# --- 2) Pan au clic milieu : même suivi',
              '	# --- 3) Pan au clic milieu : même suivi', 1) if '	# --- 2) Pan au clic milieu : même suivi' in s else s
s = s.replace('	# --- 3) Orbite (Maj + clic droit) : ce n\'est PAS un pan --------------------',
              '	# --- 4) Orbite (Maj + clic droit) : ce n\'est PAS un pan --------------------', 1)
p.write_text(s, encoding='utf-8')
print('pan_cursor_tracking_test : assertion pan_continuous_regular ajoutée')
