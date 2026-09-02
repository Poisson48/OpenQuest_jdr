extends Control
class_name InteractiveMap

signal cell_clicked(x: int, y: int)
signal navigation_requested(action: String, data: Dictionary)
signal zoom_changed(zoom_level: float)

const MIN_CELL := 6
const MAX_CELL := 64
const MIN_ZOOM := 0.5
const MAX_ZOOM := 5.0
const DRAG_THRESHOLD := 5.0

var map_data: Dictionary = {}
var tokens: Array = []
var explored: Array = []
var party: Array = []
var quest_format: String = "oneshot"
var fog_enabled: bool = false
var readonly: bool = false
var nav_context: Dictionary = {}

var session_tool: Dictionary = { "mode": "member", "member_id": "" }
var zoom: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var _loaded_map_id: String = ""

var _dragging: bool = false
var _pending_click: bool = false
var _press_cell: Vector2i = Vector2i(-1, -1)
var _drag_start: Vector2 = Vector2.ZERO
var _pan_start: Vector2 = Vector2.ZERO
var _base_cell: int = 16

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL

func configure(p_map: Dictionary, p_tokens: Array, p_party: Array, p_explored: Array, p_quest_format: String, p_readonly: bool = false, p_nav: Dictionary = {}) -> void:
	var new_map_id: String = p_map.get("id", "")
	var same_map := not new_map_id.is_empty() and new_map_id == _loaded_map_id

	map_data = p_map
	tokens = p_tokens
	party = p_party
	explored = p_explored
	quest_format = p_quest_format
	readonly = p_readonly
	nav_context = p_nav
	_loaded_map_id = new_map_id
	fog_enabled = MapData.is_world_map(map_data) and nav_context.is_empty() and not readonly
	if session_tool.get("memberId", "").is_empty() and not party.is_empty():
		session_tool = { "mode": "member", "memberId": party[0].get("id", "") }

	if same_map:
		queue_redraw()
	else:
		call_deferred("_fit_to_view")

func set_session_tool(mode: String, extra: Dictionary = {}) -> void:
	session_tool = { "mode": mode }
	session_tool.merge(extra)
	queue_redraw()

func get_cell_size() -> int:
	return maxi(MIN_CELL, mini(MAX_CELL, int(round(_base_cell * zoom))))

func get_map_pixel_size() -> Vector2:
	if map_data.is_empty():
		return Vector2.ZERO
	var cs := get_cell_size()
	return Vector2(map_data.get("width", 0) * cs, map_data.get("height", 0) * cs)

func _get_viewport_size() -> Vector2:
	if size.x > 16 and size.y > 16:
		return size
	return Vector2(640, 320)

func _recalc_base_cell() -> void:
	if map_data.is_empty():
		return
	var w: int = maxi(1, map_data.get("width", 16))
	var h: int = maxi(1, map_data.get("height", 12))
	var avail := _get_viewport_size()
	var by_w := int(avail.x / w)
	var by_h := int(avail.y / h)
	var max_fit := 12 if MapData.is_world_map(map_data) else 24
	_base_cell = maxi(MIN_CELL, mini(max_fit, mini(by_w, by_h)))

func _clamp_pan() -> void:
	var vp := _get_viewport_size()
	var map_px := get_map_pixel_size()
	var min_x := mini(0.0, vp.x - map_px.x)
	var min_y := mini(0.0, vp.y - map_px.y)
	pan_offset.x = clampf(pan_offset.x, min_x, 0.0)
	pan_offset.y = clampf(pan_offset.y, min_y, 0.0)

func _center_or_clamp_pan() -> void:
	var vp := _get_viewport_size()
	var map_px := get_map_pixel_size()
	if map_px.x <= vp.x:
		pan_offset.x = (vp.x - map_px.x) * 0.5
	else:
		pan_offset.x = 0.0
	if map_px.y <= vp.y:
		pan_offset.y = (vp.y - map_px.y) * 0.5
	else:
		pan_offset.y = 0.0
	_clamp_pan()

func _fit_to_view() -> void:
	zoom = 1.0
	_recalc_base_cell()
	_center_or_clamp_pan()
	queue_redraw()
	zoom_changed.emit(zoom)

func _apply_zoom(factor: float, anchor: Vector2) -> void:
	var old_cs := get_cell_size()
	var new_zoom := clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, zoom):
		return

	var content_anchor := anchor - pan_offset
	zoom = new_zoom
	var new_cs := get_cell_size()
	if old_cs > 0:
		var ratio := float(new_cs) / float(old_cs)
		pan_offset = anchor - content_anchor * ratio
	_clamp_pan()
	queue_redraw()
	zoom_changed.emit(zoom)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not map_data.is_empty():
		_recalc_base_cell()
		_clamp_pan()
		queue_redraw()

func _draw() -> void:
	if map_data.is_empty():
		return
	var w: int = map_data.get("width", 0)
	var h: int = map_data.get("height", 0)
	var cs := get_cell_size()
	var explored_set := {}
	if fog_enabled:
		for key in explored:
			explored_set[key] = true

	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			var tile_id: String = map_data.get("tiles", [])[idx] if idx < map_data.get("tiles", []).size() else "grass"
			var key := "%d,%d" % [x, y]
			var explored_cell := not fog_enabled or explored_set.has(key)
			var rect := Rect2(pan_offset + Vector2(x * cs, y * cs), Vector2(cs, cs))

			if explored_cell:
				draw_rect(rect, MapData.get_tile_color(map_data, tile_id))
				draw_rect(rect, Color(0, 0, 0, 0.12), false, 1.0)
			else:
				draw_rect(rect, Color(0.05, 0.04, 0.06, 1.0))
				draw_rect(rect, Color(0.2, 0.16, 0.1, 0.5), false, 1.0)
				continue

			var static_mk: Dictionary = _static_marker_at(x, y)
			var link: Dictionary = MapData.get_location_link_at(map_data, x, y) if nav_context.is_empty() and MapData.is_world_map(map_data) else {}
			var token: Dictionary = _token_at(x, y)

			if link.has("targetMapId") and token.is_empty():
				_draw_centered_text(rect, "🌀", cs)
				var link_label: String = str(link.get("label", "")).strip_edges()
				if link_label.length() > 0 and cs >= 14:
					_draw_centered_text(rect, link_label.substr(0, mini(6, link_label.length())), cs, 0.35)
			elif static_mk and token.is_empty():
				_draw_centered_text(rect, MapData.get_marker_emoji(static_mk.get("type", "")), cs)
			if not token.is_empty():
				_draw_token(rect, token, cs)

func _draw_centered_text(rect: Rect2, text: String, cs: int, y_ratio: float = 0.7) -> void:
	var font := ThemeDB.fallback_font
	var fs := maxi(10, int(cs * 0.55))
	draw_string(font, rect.position + Vector2(cs * 0.15, cs * y_ratio), text, HORIZONTAL_ALIGNMENT_LEFT, cs, fs)

func _draw_token(rect: Rect2, token: Dictionary, cs: int) -> void:
	var pad := 2.0
	var inner := rect.grow(-pad)
	if token.get("kind") == "member":
		var col := MapData.get_member_color(token.get("memberId", ""), party)
		draw_rect(inner, col)
		draw_rect(inner, Color(0, 0, 0, 0.3), false, 1.0)
		var member := _find_member(token.get("memberId", ""))
		var em := "🤖" if member.get("isBot", false) else ("🔍" if quest_format == "investigation" else "⚔️")
		_draw_centered_text(rect, em, cs)
	else:
		draw_rect(inner, Color(0.25, 0.2, 0.15, 0.9))
		_draw_centered_text(rect, MapData.get_marker_emoji(token.get("markerType", "")), cs)

func _static_marker_at(x: int, y: int) -> Dictionary:
	for mk in map_data.get("markers", []):
		if mk.get("x") == x and mk.get("y") == y:
			return mk
	return {}

func _token_at(x: int, y: int) -> Dictionary:
	for t in tokens:
		if t.get("x") == x and t.get("y") == y:
			return t
	return {}

func _find_member(member_id: String) -> Dictionary:
	for m in party:
		if m.get("id") == member_id:
			return m
	return {}

func _gui_input(event: InputEvent) -> void:
	if map_data.is_empty():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(1.0 / 1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = false
				_pending_click = true
				_press_cell = _pos_to_cell(mb.position)
				_drag_start = mb.position
				_pan_start = pan_offset
				accept_event()
			else:
				if _pending_click and not _dragging and _press_cell.x >= 0:
					_handle_cell_click(_press_cell.x, _press_cell.y)
				_dragging = false
				_pending_click = false
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			_pending_click = false
			if mb.pressed:
				_drag_start = mb.position
				_pan_start = pan_offset
				accept_event()
			else:
				accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _pending_click and not _dragging:
			if _drag_start.distance_to(motion.position) >= DRAG_THRESHOLD:
				_dragging = true
				_pending_click = false
		if _dragging:
			pan_offset = _pan_start + (motion.position - _drag_start)
			_clamp_pan()
			queue_redraw()
			accept_event()

func _pos_to_cell(pos: Vector2) -> Vector2i:
	var cs := get_cell_size()
	var local := pos - pan_offset
	var x := int(floor(local.x / cs))
	var y := int(floor(local.y / cs))
	var w: int = map_data.get("width", 0)
	var h: int = map_data.get("height", 0)
	if x < 0 or y < 0 or x >= w or y >= h:
		return Vector2i(-1, -1)
	return Vector2i(x, y)

func _handle_cell_click(x: int, y: int) -> void:
	if readonly:
		return
	var key := "%d,%d" % [x, y]
	if fog_enabled and not explored.has(key):
		return

	var static_mk := _static_marker_at(x, y)
	if nav_context.get("mode") == "local" and static_mk.get("type") == "exit":
		navigation_requested.emit("exit_world", {})
		return
	if nav_context.is_empty() and MapData.is_world_map(map_data):
		var link := MapData.get_location_link_at(map_data, x, y)
		if link.has("targetMapId"):
			navigation_requested.emit("enter_local", { "x": x, "y": y, "targetMapId": link.get("targetMapId") })
			return

	var mode: String = session_tool.get("mode", "member")
	cell_clicked.emit(x, y)

func zoom_in() -> void:
	_apply_zoom(1.15, _get_viewport_size() * 0.5)

func zoom_out() -> void:
	_apply_zoom(1.0 / 1.15, _get_viewport_size() * 0.5)

func reset_zoom() -> void:
	_fit_to_view()
