extends Node3D
class_name MapFog3D

## Brouillard de guerre 3D — dalles semi-transparentes au-dessus du sol.

var _tiles: Dictionary = {}
var _cell_size: float = 1.0
var _map_width: int = 16
var _map_height: int = 12
var _fog_enabled: bool = true
var _is_gm: bool = false
var _revealed_set: Dictionary = {}

func configure(width: int, height: int, cell_size: float, revealed: Array, gm: bool, enabled: bool) -> void:
	_map_width = width
	_map_height = height
	_cell_size = cell_size
	_fog_enabled = enabled
	_is_gm = gm
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
	mat.albedo_color = Color(0.04, 0.03, 0.06, 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for y in range(_map_height):
		for x in range(_map_width):
			var key := "%d,%d" % [x, y]
			if _revealed_set.has(key):
				continue
			var box := BoxMesh.new()
			box.size = Vector3(_cell_size * 0.98, 0.08, _cell_size * 0.98)
			var mi := MeshInstance3D.new()
			mi.mesh = box
			mi.material_override = mat
			mi.position = Vector3(
				x * _cell_size + _cell_size * 0.5,
				0.06,
				y * _cell_size + _cell_size * 0.5
			)
			add_child(mi)
			_tiles[key] = mi
