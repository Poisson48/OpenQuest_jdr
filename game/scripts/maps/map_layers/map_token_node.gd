extends Area2D
class_name MapTokenNode

## Token draggable avec états visuels (sélection, surbrillance, badge PV).

signal drag_finished(token_id: String, gx: float, gy: float)
signal selected(token_id: String)

var token_data: Dictionary = {}
var grid_size: int = 70
var snap_to_grid: bool = true
var readonly: bool = false
var party: Array = []
var selected_state: bool = false
var highlighted: bool = false

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	input_pickable = not readonly
	input_event.connect(_on_input_event)

func setup(data: Dictionary, g_size: int, p_party: Array, p_readonly: bool) -> void:
	token_data = data.duplicate(true)
	grid_size = g_size
	party = p_party
	readonly = p_readonly
	input_pickable = not readonly
	_ensure_collision()
	_sync_position()
	queue_redraw()

func _ensure_collision() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			return
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(grid_size * 0.82, grid_size * 0.82)
	shape.shape = rect
	add_child(shape)

func set_selected(on: bool) -> void:
	selected_state = on
	queue_redraw()

func set_highlighted(on: bool) -> void:
	highlighted = on
	queue_redraw()

func get_token_id() -> String:
	return str(token_data.get("id", ""))

func _sync_position() -> void:
	position = Vector2(float(token_data.get("x", 0)) * grid_size, float(token_data.get("y", 0)) * grid_size)

func _draw() -> void:
	var size := float(grid_size) * 0.82
	var half := size * 0.5
	var rect := Rect2(-half, -half, size, size)
	var col := _token_color()
	if highlighted:
		draw_circle(Vector2.ZERO, half + 4.0, Color(1.0, 0.85, 0.2, 0.55))
	if selected_state:
		draw_rect(rect.grow(3.0), Color(1.0, 0.85, 0.2, 0.9), false, 2.5)
	draw_rect(rect, col)
	draw_rect(rect, Color(0, 0, 0, 0.35), false, 1.5)

	var hp: int = int(token_data.get("hp", 0))
	var max_hp: int = int(token_data.get("maxHp", 0))
	if max_hp > 0:
		var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
		var bar_w := size
		var bar_h := 4.0
		var bar_y := half + 2.0
		draw_rect(Rect2(-half, bar_y, bar_w, bar_h), Color(0.1, 0.1, 0.1, 0.8))
		draw_rect(Rect2(-half, bar_y, bar_w * ratio, bar_h), Color(0.3, 0.85, 0.4, 0.95))

	var label: String = str(token_data.get("label", ""))
	if label.is_empty() and token_data.get("kind") == "member":
		label = _member_name(str(token_data.get("memberId", "")))
	if not label.is_empty():
		var font := ThemeDB.fallback_font
		var fs := maxi(10, int(grid_size * 0.22))
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, Vector2(-tw.x * 0.5, half + fs + 2.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.9, 0.78))

func _token_color() -> Color:
	if token_data.get("kind") == "member":
		return MapData.get_member_color(str(token_data.get("memberId", "")), party)
	return Color(0.28, 0.22, 0.16, 0.92)

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
	var gx := position.x / float(grid_size)
	var gy := position.y / float(grid_size)
	if snap_to_grid:
		gx = roundf(gx)
		gy = roundf(gy)
	token_data["x"] = gx
	token_data["y"] = gy
	_sync_position()
	drag_finished.emit(get_token_id(), gx, gy)
