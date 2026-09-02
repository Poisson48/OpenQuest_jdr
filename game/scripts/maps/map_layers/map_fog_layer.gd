extends Node2D
class_name MapFogLayer

## Brouillard de guerre — masque cellulaire ; MJ voit tout.

var grid_size: int = 70
var map_width: int = 16
var map_height: int = 12
var fog_enabled: bool = true
var is_gm: bool = false
var revealed: Array = []
var _revealed_set: Dictionary = {}

func configure(width: int, height: int, g_size: int, revealed_cells: Array, gm: bool, enabled: bool = true) -> void:
	map_width = width
	map_height = height
	grid_size = g_size
	revealed = revealed_cells
	is_gm = gm
	fog_enabled = enabled
	_rebuild_set()
	queue_redraw()

func _rebuild_set() -> void:
	_revealed_set.clear()
	for key in revealed:
		_revealed_set[str(key)] = true

func _draw() -> void:
	if not fog_enabled or is_gm:
		return
	var fog_col := Color(0.04, 0.03, 0.06, 0.88)
	for y in range(map_height):
		for x in range(map_width):
			var key := "%d,%d" % [x, y]
			if _revealed_set.has(key):
				continue
			var rect := Rect2(x * grid_size, y * grid_size, grid_size, grid_size)
			draw_rect(rect, fog_col)
