extends Node2D
class_name MapGridLayer

## Grille carrée configurable (taille, opacité, couleur).

var grid_size: int = 70
var map_width: int = 16
var map_height: int = 12
var color: Color = Color(1.0, 1.0, 1.0, 0.22)
var enabled: bool = true

func configure(cfg: Dictionary, width: int, height: int) -> void:
	grid_size = int(cfg.get("size", 70))
	map_width = width
	map_height = height
	color = Color.html(str(cfg.get("color", "#ffffff")))
	color.a = float(cfg.get("opacity", 0.22))
	enabled = bool(cfg.get("enabled", true))
	queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	var w_px := map_width * grid_size
	var h_px := map_height * grid_size
	for x in range(map_width + 1):
		var lx := x * grid_size
		draw_line(Vector2(lx, 0), Vector2(lx, h_px), color, 1.0)
	for y in range(map_height + 1):
		var ly := y * grid_size
		draw_line(Vector2(0, ly), Vector2(w_px, ly), color, 1.0)
