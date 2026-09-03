extends Node3D
class_name MapFog3D

## Brouillard de guerre.
## - **VTT** : dalles 3D semi-transparentes.
## - **Diorama** : voile plat (quads au sol), plus léger et cohérent avec le style peint.

var _tiles: Dictionary = {}
var _cell_size: float = 1.0
var _map_width: int = 16
var _map_height: int = 12
var _fog_enabled: bool = true
var _is_gm: bool = false
var _revealed_set: Dictionary = {}
var _flat: bool = false

func configure(width: int, height: int, cell_size: float, revealed: Array, gm: bool, enabled: bool, flat: bool = false) -> void:
	_map_width = width
	_map_height = height
	_cell_size = cell_size
	_fog_enabled = enabled
	_is_gm = gm
	_flat = flat
	_revealed_set.clear()
	for key in revealed:
		_revealed_set[str(key)] = true
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_tiles.clear()
	if not _fog_enabled or _is_gm:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.04, 0.08, 0.82 if _flat else 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = 40
	for y in range(_map_height):
		for x in range(_map_width):
			var key := "%d,%d" % [x, y]
			if _revealed_set.has(key):
				continue
			var mi := MeshInstance3D.new()
			if _flat:
				var quad := QuadMesh.new()
				quad.size = Vector2(_cell_size * 0.98, _cell_size * 0.98)
				mi.mesh = quad
				mi.rotation_degrees = Vector3(-90, 0, 0)
				mi.position = Vector3(
					x * _cell_size + _cell_size * 0.5,
					0.03,
					y * _cell_size + _cell_size * 0.5
				)
			else:
				var box := BoxMesh.new()
				box.size = Vector3(_cell_size * 0.98, 0.08, _cell_size * 0.98)
				mi.mesh = box
				mi.position = Vector3(
					x * _cell_size + _cell_size * 0.5,
					0.06,
					y * _cell_size + _cell_size * 0.5
				)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_tiles[key] = mi
