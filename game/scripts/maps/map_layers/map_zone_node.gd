extends Node2D
class_name MapZoneNode

## Marqueur de zone (cercle/rect) — sorts, pièges, objectifs.

var zone_data: Dictionary = {}
var grid_size: int = 70
var _pulse: float = 0.0

func setup(data: Dictionary, g_size: int) -> void:
	zone_data = data.duplicate(true)
	grid_size = g_size
	position = Vector2(float(data.get("x", 0)) * g_size, float(data.get("y", 0)) * g_size)
	set_process(true)

func _process(delta: float) -> void:
	_pulse += delta * 1.8
	queue_redraw()

func _draw() -> void:
	var shape: String = str(zone_data.get("shape", "circle"))
	var col := Color.html(str(zone_data.get("color", "#c9a227")))
	col.a = 0.28 + sin(_pulse) * 0.08
	var label: String = str(zone_data.get("label", ""))

	if shape == "rect":
		var w := float(zone_data.get("width", 2)) * grid_size
		var h := float(zone_data.get("height", 2)) * grid_size
		draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), col)
		draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), col.lightened(0.2), false, 2.0)
	else:
		var r := float(zone_data.get("radius", 1.5)) * grid_size * (0.92 + sin(_pulse) * 0.06)
		draw_circle(Vector2.ZERO, r, col)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, col.lightened(0.25), 2.0, true)

	if not label.is_empty():
		var font := ThemeDB.fallback_font
		var fs := maxi(11, int(grid_size * 0.2))
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, Vector2(-tw.x * 0.5, grid_size * 0.15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.88, 0.65))
