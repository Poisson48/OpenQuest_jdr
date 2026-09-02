extends Area2D
class_name MapTokenNode

## Token draggable — base circulaire, ombre portée, anneau PV, surélévation Y-sort.

signal drag_finished(token_id: String, gx: float, gy: float)
signal selected(token_id: String)

var token_data: Dictionary = {}
var grid_size: int = 70
var snap_to_grid: bool = true
var readonly: bool = false
var party: Array = []
var selected_state: bool = false
var highlighted: bool = false
var lighting_brightness: float = 1.0

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _lift_offset: float = 0.0

func _ready() -> void:
	input_pickable = not readonly
	input_event.connect(_on_input_event)
	y_sort_enabled = true

func setup(data: Dictionary, g_size: int, p_party: Array, p_readonly: bool, p_brightness: float = 1.0) -> void:
	token_data = data.duplicate(true)
	grid_size = g_size
	party = p_party
	readonly = p_readonly
	lighting_brightness = p_brightness
	input_pickable = not readonly
	_ensure_collision()
	_sync_position()
	queue_redraw()

func _ensure_collision() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			return
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = float(grid_size) * 0.38
	shape.shape = circle
	add_child(shape)

func set_selected(on: bool) -> void:
	selected_state = on
	_lift_offset = -6.0 if on else 0.0
	queue_redraw()

func set_highlighted(on: bool) -> void:
	highlighted = on
	queue_redraw()

func set_lighting_brightness(b: float) -> void:
	lighting_brightness = b
	queue_redraw()

func get_token_id() -> String:
	return str(token_data.get("id", ""))

func get_sort_y() -> float:
	return position.y

func _sync_position() -> void:
	var gx := float(token_data.get("x", 0))
	var gy := float(token_data.get("y", 0))
	# Ancrage pieds : centre bas de la case
	position = Vector2(gx * grid_size + grid_size * 0.5, gy * grid_size + grid_size * 0.88)

func _elevation_offset() -> float:
	return float(token_data.get("elevation", 0)) * grid_size * 0.12

func _token_radius() -> float:
	return float(grid_size) * 0.38

func _draw() -> void:
	var r := _token_radius()
	var elev := _elevation_offset()
	var lift := _lift_offset + elev
	var draw_center := Vector2(0.0, lift)

	# Ombre portée elliptique (sol)
	var shadow_y := 2.0 - lift * 0.15
	var shadow_scale := 1.0 - lift * 0.004
	if selected_state:
		shadow_scale *= 0.85
		shadow_y += 3.0
	var shadow_col := Color(0, 0, 0, 0.32 if selected_state else 0.38)
	_draw_ellipse(Vector2(0.0, shadow_y), Vector2(r * 1.05 * shadow_scale, r * 0.42 * shadow_scale), shadow_col)

	var col := _token_color()
	col = col.lightened((lighting_brightness - 1.0) * 0.35)
	col.a = minf(col.a * lighting_brightness, 1.0)

	# Halo sélection / surbrillance
	if highlighted:
		draw_circle(draw_center, r + 6.0, Color(1.0, 0.85, 0.2, 0.4))
	if selected_state:
		draw_circle(draw_center, r + 5.0, Color(1.0, 0.88, 0.35, 0.55))
		draw_arc(draw_center, r + 5.0, 0.0, TAU, 48, Color(1.0, 0.92, 0.5, 0.85), 2.5, true)

	# Base circulaire (bord métallique + remplissage)
	draw_circle(draw_center, r + 2.0, Color(0.12, 0.1, 0.08, 0.85))
	draw_circle(draw_center, r, col)
	# Reflet directionnel (pseudo-3D)
	var highlight := col.lightened(0.35)
	highlight.a = 0.45
	draw_arc(draw_center + Vector2(-r * 0.22, -r * 0.28), r * 0.55, PI * 0.85, PI * 1.65, 16, highlight, r * 0.18, true)

	# Icône / initiale portrait
	var icon := _token_icon()
	if not icon.is_empty():
		var font := ThemeDB.fallback_font
		var fs := maxi(14, int(grid_size * 0.34))
		var tw := font.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, draw_center + Vector2(-tw.x * 0.5, fs * 0.32), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.98, 0.95, 0.88))

	# Anneau PV
	var max_hp: int = int(token_data.get("maxHp", 0))
	if max_hp > 0:
		var hp: int = int(token_data.get("hp", 0))
		var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
		var ring_r := r + 4.0
		draw_arc(draw_center, ring_r, 0.0, TAU, 48, Color(0.08, 0.08, 0.08, 0.75), 4.0, true)
		if ratio > 0.001:
			var hp_col := Color(0.25, 0.82, 0.38, 0.95) if ratio > 0.35 else Color(0.9, 0.28, 0.18, 0.95)
			draw_arc(draw_center, ring_r, -PI * 0.5, -PI * 0.5 + TAU * ratio, 32, hp_col, 4.0, true)

	# Nom sous le token
	var label: String = str(token_data.get("label", ""))
	if label.is_empty() and token_data.get("kind") == "member":
		label = _member_name(str(token_data.get("memberId", "")))
	if not label.is_empty():
		var font := ThemeDB.fallback_font
		var fs := maxi(9, int(grid_size * 0.19))
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var name_y := r + fs + 4.0 + lift
		draw_string(font, Vector2(-tw.x * 0.5, name_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.9, 0.78, 0.92))

func _draw_ellipse(center: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	var segments := 24
	for i in range(segments + 1):
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)

func _token_color() -> Color:
	if token_data.get("kind") == "member":
		return MapData.get_member_color(str(token_data.get("memberId", "")), party)
	return Color(0.35, 0.28, 0.2, 0.94)

func _token_icon() -> String:
	if token_data.get("kind") == "member":
		var mid := str(token_data.get("memberId", ""))
		for i in range(party.size()):
			if party[i].get("id") == mid:
				var name: String = str(party[i].get("name", "?"))
				return name.substr(0, 1).to_upper()
		return "?"
	var marker: String = str(token_data.get("markerType", ""))
	if not marker.is_empty() and MapData.MARKERS.has(marker):
		return MapData.MARKERS[marker]
	return "●"

func _member_name(member_id: String) -> String:
	for m in party:
		if m.get("id") == member_id:
			return str(m.get("name", ""))
	return ""

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if readonly:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_offset = get_local_mouse_position()
				selected.emit(get_token_id())
				get_viewport().set_input_as_handled()
			else:
				if _dragging:
					_dragging = false
					_commit_position()
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		position = get_local_mouse_position() - _drag_offset
		queue_redraw()

func _commit_position() -> void:
	var gx := (position.x - grid_size * 0.5) / float(grid_size)
	var gy := (position.y - grid_size * 0.88) / float(grid_size)
	if snap_to_grid:
		gx = roundf(gx)
		gy = roundf(gy)
	token_data["x"] = gx
	token_data["y"] = gy
	_sync_position()
	drag_finished.emit(get_token_id(), gx, gy)
