extends Node2D
class_name MapLightingLayer

## Éclairage directionnel simulé + sources ponctuelles (overlay 2D).

var _config: Dictionary = {}
var _map_size: Vector2 = Vector2.ZERO
var _grid_size: int = 70
var _pulse: float = 0.0

func configure(lighting: Dictionary, map_w: int, map_h: int, grid_size: int) -> void:
	_config = lighting if lighting is Dictionary else {}
	_grid_size = grid_size
	_map_size = Vector2(map_w * grid_size, map_h * grid_size)
	var enabled := bool(_config.get("enabled", false))
	set_process(enabled)
	visible = enabled
	queue_redraw()

func _process(delta: float) -> void:
	if not bool(_config.get("enabled", false)):
		return
	_pulse += delta * 1.2
	queue_redraw()

func _draw() -> void:
	if not bool(_config.get("enabled", false)) or _map_size == Vector2.ZERO:
		return

	var intensity := clampf(float(_config.get("intensity", 0.35)), 0.0, 1.0)
	var ambient := Color.html(str(_config.get("ambient", "#121018")))
	ambient.a = intensity * 0.55

	# Assombrir toute la carte (couche ambiante)
	draw_rect(Rect2(Vector2.ZERO, _map_size), ambient)

	# Lumière directionnelle (dégradé simulé)
	var dir: String = str(_config.get("direction", "nw"))
	var light_col := Color(1.0, 0.92, 0.78, intensity * 0.45)
	var steps := 12
	for i in range(steps):
		var t := float(i) / float(steps)
		var alpha := (1.0 - t) * intensity * 0.38
		light_col.a = alpha
		var inset := t * _map_size.length() * 0.35
		var r := _map_rect_inset(inset, dir)
		draw_rect(r, light_col)

	# Sources ponctuelles (torches, braseros)
	var sources: Array = _config.get("sources", [])
	if sources is Array:
		for src in sources:
			if not src is Dictionary:
				continue
			var cx := float(src.get("x", 0)) * _grid_size + _grid_size * 0.5
			var cy := float(src.get("y", 0)) * _grid_size + _grid_size * 0.5
			var rad := float(src.get("radius", 3.0)) * _grid_size
			var flicker := 0.92 + sin(_pulse + cx * 0.01) * 0.08
			var src_col := Color.html(str(src.get("color", "#ffaa55")))
			src_col.a = float(src.get("intensity", 0.5)) * flicker
			_draw_radial_glow(Vector2(cx, cy), rad, src_col)

static func token_brightness_at(gx: float, gy: float, lighting: Dictionary, grid_size: int) -> float:
	if not lighting is Dictionary or not bool(lighting.get("enabled", false)):
		return 1.0
	var boost := 1.0
	var sources: Array = lighting.get("sources", [])
	if sources is Array:
		for src in sources:
			if not src is Dictionary:
				continue
			var sx := float(src.get("x", 0))
			var sy := float(src.get("y", 0))
			var rad := float(src.get("radius", 3.0))
			var dist := Vector2(gx - sx, gy - sy).length()
			if dist < rad:
				var falloff := 1.0 - dist / rad
				boost = maxf(boost, 1.0 + falloff * float(src.get("intensity", 0.5)) * 0.45)
	var dir: String = str(lighting.get("direction", "nw"))
	var dir_bias := 0.0
	match dir:
		"nw":
			dir_bias = (1.0 - gy * 0.02) * 0.06 + (1.0 - gx * 0.02) * 0.04
		"ne":
			dir_bias = (1.0 - gy * 0.02) * 0.06 + gx * 0.02 * 0.04
		"sw":
			dir_bias = gy * 0.02 * 0.06 + (1.0 - gx * 0.02) * 0.04
		"se":
			dir_bias = gy * 0.02 * 0.06 + gx * 0.02 * 0.04
	return clampf(boost + dir_bias, 0.75, 1.35)

func _map_rect_inset(inset: float, direction: String) -> Rect2:
	var r := Rect2(Vector2.ZERO, _map_size)
	match direction:
		"nw":
			return Rect2(inset * 0.3, inset * 0.2, r.size.x - inset * 0.5, r.size.y - inset * 0.3)
		"ne":
			return Rect2(0, inset * 0.2, r.size.x - inset * 0.3, r.size.y - inset * 0.3)
		"sw":
			return Rect2(inset * 0.3, 0, r.size.x - inset * 0.3, r.size.y - inset * 0.2)
		"se":
			return Rect2(0, 0, r.size.x - inset * 0.2, r.size.y - inset * 0.2)
		_:
			return r

func _draw_radial_glow(center: Vector2, radius: float, col: Color) -> void:
	var rings := 8
	for i in range(rings):
		var t := float(i) / float(rings)
		var r := radius * (1.0 - t * 0.85)
		var c := col
		c.a = col.a * (1.0 - t) * 0.55
		draw_circle(center, r, c)
