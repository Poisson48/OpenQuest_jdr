from pathlib import Path

p = Path('game/scripts/maps/complex_map_engine_3d.gd')
s = p.read_text(encoding='utf-8')

# 1) état : transform caméra de référence du drag (pan sans rétroaction).
old_state = '''var _pan_anchor_world: Vector3 = Vector3.INF
var _pan_anchor_plane_y: float = 0.0
var _pan_anchor_valid: bool = false'''
new_state = '''var _pan_anchor_world: Vector3 = Vector3.INF
var _pan_anchor_plane_y: float = 0.0
var _pan_anchor_valid: bool = false
## Transform caméra AU DÉBUT du pan : la projection du curseur sur le plan de
## l'ancre doit être calculée avec cette référence FIXE. Avec la caméra courante
## (qui bouge), `move = ancre - point(caméra)` boucle sur elle-même et oscille :
## la caméra « tremblait » d'une frame à l'autre pendant le clic droit.
var _pan_camera_xform: Transform3D = Transform3D.IDENTITY'''
assert old_state in s, 'état pan introuvable'
s = s.replace(old_state, new_state, 1)

# 2) helper de projection sur un plan avec une transform de référence.
old_helper = '''## Point monde du plan horizontal `plane_y` sous une position écran. Sert au'''
new_helper = '''## Point du plan `plane_y` sous une position écran, calculé avec une transform
## caméra de RÉFÉRENCE (celle du début du pan). Indispensable : projeter avec
## la caméra courante pendant qu'elle se déplace crée une boucle de rétroaction
## (le point « fuit » et la caméra oscille entre deux positions).
func _screen_point_on_plane_fixed(screen_pos: Vector2, plane_y: float,
		camera_xform: Transform3D) -> Vector3:
	if _camera == null:
		return Vector3.INF
	var saved := _camera.global_transform
	_camera.global_transform = camera_xform
	var point := _screen_point_on_plane(screen_pos, plane_y)
	_camera.global_transform = saved
	return point


## Point monde du plan horizontal `plane_y` sous une position écran. Sert au'''
assert old_helper in s, 'helper plan introuvable'
s = s.replace(old_helper, new_helper, 1)

# 3) pan ancré : projection avec la transform de référence (pas la caméra mouvante).
old_move = '''	if _pan_anchor_valid:
		var current := _screen_point_on_plane(motion.position, _pan_anchor_plane_y)
		if current != Vector3.INF:'''
new_move = '''	if _pan_anchor_valid:
		var current := _screen_point_on_plane_fixed(
			motion.position, _pan_anchor_plane_y, _pan_camera_xform)
		if current != Vector3.INF:'''
assert old_move in s, 'pan ancré introuvable'
s = s.replace(old_move, new_move, 1)

# 4) begin drag : mémorise la transform de référence.
old_begin = '''	_pan_anchor_valid = false
	if pan_mode and not table_view and _camera != null:
		var hit := _raycast_ground(_control_to_viewport(screen_pos))'''
new_begin = '''	_pan_anchor_valid = false
	if pan_mode and not table_view and _camera != null:
		_pan_camera_xform = _camera.global_transform
		var hit := _raycast_ground(_control_to_viewport(screen_pos))'''
assert old_begin in s, 'begin drag pan introuvable'
s = s.replace(old_begin, new_begin, 1)

p.write_text(s, encoding='utf-8')
print('pan ancré : projection sur transform de référence (fin du tremblement)')
