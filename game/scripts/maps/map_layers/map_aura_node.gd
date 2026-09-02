extends Node2D

## Aura pulsante pour zones de sort / pièges (effet animé 2D).

var preset_id: String = "magic"
var radius: float = 48.0
var _pulse: float = 0.0
var _active: bool = false

func setup(p_id: String) -> void:
	preset_id = p_id

func set_radius(r: float) -> void:
	radius = maxf(8.0, r)

func set_active(active: bool) -> void:
	_active = active
	set_process(active)

func _process(delta: float) -> void:
	if not _active:
		return
	_pulse += delta * 2.5
	queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var col := Color(0.9, 0.4, 0.15, 0.35)
	match preset_id:
		"fire":
			col = Color(1.0, 0.35, 0.05, 0.4)
		"smoke":
			col = Color(0.5, 0.5, 0.5, 0.25)
		"magic":
			col = Color(0.5, 0.3, 1.0, 0.38)
		"rain":
			col = Color(0.4, 0.55, 0.9, 0.22)
	var pulse := 0.85 + sin(_pulse) * 0.15
	var r := radius * pulse
	draw_circle(Vector2.ZERO, r, col)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, col.lightened(0.3), 2.0, true)
