extends Control
class_name InteractiveMap

signal cell_clicked(x: int, y: int)
signal cell_paint(x: int, y: int)
signal paint_drag_finished()
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
var revealed_markers: Array = []
var revealed_links: Array = []
var party: Array = []
var quest_format: String = "oneshot"
var fog_enabled: bool = false
var readonly: bool = false
var paint_drag_enabled: bool = false
var nav_context: Dictionary = {}

var session_tool: Dictionary = { "mode": "member", "member_id": "" }
var zoom: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var _loaded_map_id: String = ""

var _pan_dragging: bool = false
var _paint_dragging: bool = false
var _pending_click: bool = false
var _press_cell: Vector2i = Vector2i(-1, -1)
var _last_painted_cell: Vector2i = Vector2i(-99999, -99999)
var _drag_start: Vector2 = Vector2.ZERO
var _pan_start: Vector2 = Vector2.ZERO
var _base_cell: int = 16

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL

func configure(p_map: Dictionary, p_tokens: Array, p_party: Array, p_explored: Array, p_quest_format: String, p_readonly: bool = false, p_nav: Dictionary = {}, p_revealed_markers: Array = [], p_revealed_links: Array = []) -> void:
	var new_map_id: String = p_map.get("id", "")
	var same_map := not new_map_id.is_empty() and new_map_id == _loaded_map_id

	map_data = p_map
	tokens = p_tokens
	party = p_party
	explored = p_explored
	quest_format = p_quest_format
	readonly = p_readonly
	nav_context = p_nav
	revealed_markers = p_revealed_markers
	revealed_links = p_revealed_links
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

	var cluster_info: Dictionary = _build_marker_cluster_info(w, h, cs)

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

	_draw_marker_cluster_backgrounds(cluster_info)

	for y in range(h):
		for x in range(w):
			var key := "%d,%d" % [x, y]
			var explored_cell := not fog_enabled or explored_set.has(key)
			if not explored_cell:
				continue
			var rect := Rect2(pan_offset + Vector2(x * cs, y * cs), Vector2(cs, cs))
			var static_mk: Dictionary = _static_marker_at(x, y)
			var link: Dictionary = MapData.get_location_link_at(map_data, x, y) if nav_context.is_empty() and MapData.is_world_map(map_data) else {}
			var token: Dictionary = _token_at(x, y)
			var show_link := _should_show_location_link(x, y)
			var show_marker := static_mk.is_empty() or _should_show_static_marker(static_mk)

			if show_link and token.is_empty():
				_draw_centered_text(rect, "🌀", cs)
				var link_label: String = str(link.get("label", "")).strip_edges()
				if link_label.length() > 0 and cs >= 14:
					_draw_centered_text(rect, link_label.substr(0, mini(6, link_label.length())), cs, 0.35)
			elif show_marker and static_mk and token.is_empty():
				_draw_static_marker(static_mk, key, rect, cs, cluster_info)
			if not token.is_empty():
				_draw_token(rect, token, cs)

func _build_marker_cluster_info(w: int, h: int, cs: int) -> Dictionary:
	var cell_info: Dictionary = {}
	var marker_types: Dictionary = {}
	for mk in map_data.get("markers", []):
		if not _should_show_static_marker(mk):
			continue
		marker_types[_marker_key(int(mk.get("x", 0)), int(mk.get("y", 0)))] = str(mk.get("type", ""))

	var visited: Dictionary = {}
	for mk in map_data.get("markers", []):
		if not _should_show_static_marker(mk):
			continue
		var mx: int = int(mk.get("x", 0))
		var my: int = int(mk.get("y", 0))
		var start_key := _marker_key(mx, my)
		if visited.has(start_key):
			continue
		var mtype: String = str(mk.get("type", ""))
		if not MapData.is_mergeable_marker(mtype):
			continue

		var cluster: Array = _collect_marker_cluster(mx, my, mtype, marker_types, visited)
		if cluster.size() < 2:
			continue

		var min_x := w
		var min_y := h
		var max_x := 0
		var max_y := 0
		for cell in cluster:
			min_x = mini(min_x, cell.x)
			min_y = mini(min_y, cell.y)
			max_x = maxi(max_x, cell.x)
			max_y = maxi(max_y, cell.y)

		var cluster_rect := Rect2(
			pan_offset + Vector2(min_x * cs, min_y * cs),
			Vector2((max_x - min_x + 1) * cs, (max_y - min_y + 1) * cs)
		)
		var anchor := Vector2i(min_x, min_y)
		for cell in cluster:
			cell_info[_marker_key(cell.x, cell.y)] = {
				"cluster_size": cluster.size(),
				"is_anchor": cell.x == anchor.x and cell.y == anchor.y,
				"cluster_rect": cluster_rect,
				"marker_type": mtype,
			}
	return cell_info

func _draw_marker_cluster_backgrounds(cluster_info: Dictionary) -> void:
	var drawn: Dictionary = {}
	for key in cluster_info:
		var info: Dictionary = cluster_info[key]
		if not info.get("is_anchor", false):
			continue
		var rect: Rect2 = info.get("cluster_rect", Rect2())
		var rect_key := "%f,%f,%f,%f" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		if drawn.has(rect_key):
			continue
		drawn[rect_key] = true
		var mtype: String = info.get("marker_type", "")
		var fill := Color(0.24, 0.2, 0.14, 0.42)
		match mtype:
			"city", "capital":
				fill = Color(0.35, 0.3, 0.18, 0.48)
			"camp":
				fill = Color(0.28, 0.32, 0.2, 0.45)
			"ruin", "dungeon":
				fill = Color(0.22, 0.2, 0.24, 0.48)
		draw_rect(rect, fill)
		draw_rect(rect, Color(0.78, 0.66, 0.34, 0.75), false, maxf(1.0, rect.size.y * 0.06))

func _draw_static_marker(mk: Dictionary, key: String, rect: Rect2, cs: int, cluster_info: Dictionary) -> void:
	var mtype: String = str(mk.get("type", ""))
	var emoji: String = MapData.get_marker_emoji(mtype)
	var info: Dictionary = cluster_info.get(key, {})
	if not info.is_empty() and str(info.get("marker_type", "")) != mtype:
		info = {}

	if info.is_empty() or int(info.get("cluster_size", 0)) < 2:
		_draw_centered_text(rect, emoji, cs)
		return

	var cluster_rect: Rect2 = info.get("cluster_rect", rect)
	var area: int = int(info.get("cluster_size", 1))
	if info.get("is_anchor", false):
		var fs := maxi(14, int(mini(cluster_rect.size.x, cluster_rect.size.y) * (0.38 + sqrt(float(area)) * 0.14)))
		_draw_emoji_in_rect(cluster_rect, emoji, fs)
	else:
		var small_fs := maxi(10, int(cs * 0.42))
		_draw_emoji_in_rect(rect, emoji, small_fs)

func _marker_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]

func _revealed_marker_set() -> Dictionary:
	var result := {}
	for key in revealed_markers:
		result[str(key)] = true
	return result

func _revealed_link_set() -> Dictionary:
	var result := {}
	for key in revealed_links:
		result[str(key)] = true
	return result

func _should_show_static_marker(static_mk: Dictionary) -> bool:
	if static_mk.is_empty():
		return false
	var mk_type: String = str(static_mk.get("type", ""))
	var mx: int = int(static_mk.get("x", 0))
	var my: int = int(static_mk.get("y", 0))
	if not MapData.is_investigation_hidden_marker(mk_type, map_data, quest_format):
		return true
	return _revealed_marker_set().has(_marker_key(mx, my))

func _should_show_location_link(x: int, y: int) -> bool:
	var link: Dictionary = MapData.get_location_link_at(map_data, x, y)
	if link.is_empty() or not link.has("targetMapId"):
		return false
	if not MapData.is_investigation_hidden_link(map_data, quest_format):
		return true
	return _revealed_link_set().has(_marker_key(x, y))

func _draw_emoji_in_rect(rect: Rect2, text: String, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var pos := rect.position + Vector2(
		(rect.size.x - font_size) * 0.5,
		(rect.size.y + font_size) * 0.5 - font_size * 0.2
	)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, font_size)

func _collect_marker_cluster(x: int, y: int, marker_type: String, marker_types: Dictionary, visited: Dictionary) -> Array:
	var cluster: Array = []
	var stack: Array = [Vector2i(x, y)]
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		var key := "%d,%d" % [cell.x, cell.y]
		if visited.has(key):
			continue
		if marker_types.get(key, "") != marker_type:
			continue
		visited[key] = true
		cluster.append(cell)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			stack.append(cell + offset)
	return cluster

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
		var em := MapData.get_member_emoji(token.get("memberId", ""), party, quest_format)
		_draw_centered_text(rect, em, cs)
	else:
		draw_rect(inner, Color(0.25, 0.2, 0.15, 0.9))
		_draw_centered_text(rect, MapData.get_marker_emoji(token.get("markerType", "")), cs)

func _static_marker_at(x: int, y: int) -> Dictionary:
	for mk in map_data.get("markers", []):
		if int(mk.get("x", -1)) == x and int(mk.get("y", -1)) == y:
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
				if paint_drag_enabled and not readonly and not mb.shift_pressed:
					_paint_dragging = true
					_pan_dragging = false
					_pending_click = false
					_last_painted_cell = Vector2i(-99999, -99999)
					_try_paint_at(mb.position)
					accept_event()
				else:
					_pan_dragging = false
					_pending_click = true
					_press_cell = _pos_to_cell(mb.position)
					_drag_start = mb.position
					_pan_start = pan_offset
					accept_event()
			else:
				if _paint_dragging:
					_paint_dragging = false
					_last_painted_cell = Vector2i(-99999, -99999)
					paint_drag_finished.emit()
				elif _pending_click and not _pan_dragging and _press_cell.x >= 0:
					_handle_cell_click(_press_cell.x, _press_cell.y)
				_pan_dragging = false
				_pending_click = false
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_dragging = mb.pressed
			_pending_click = false
			_paint_dragging = false
			if mb.pressed:
				_drag_start = mb.position
				_pan_start = pan_offset
				accept_event()
			else:
				accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _paint_dragging:
			_try_paint_at(motion.position)
			accept_event()
		elif _pending_click and not _pan_dragging:
			if _drag_start.distance_to(motion.position) >= DRAG_THRESHOLD:
				_pan_dragging = true
				_pending_click = false
		if _pan_dragging:
			pan_offset = _pan_start + (motion.position - _drag_start)
			_clamp_pan()
			queue_redraw()
			accept_event()

func _try_paint_at(pos: Vector2) -> void:
	var cell := _pos_to_cell(pos)
	if cell.x < 0:
		return
	if cell == _last_painted_cell:
		return
	if _last_painted_cell.x > -9999:
		for point in _cells_on_line(_last_painted_cell, cell):
			cell_paint.emit(point.x, point.y)
	else:
		cell_paint.emit(cell.x, cell.y)
	_last_painted_cell = cell

func _cells_on_line(from: Vector2i, to: Vector2i) -> Array:
	var points: Array = []
	var x0 := from.x
	var y0 := from.y
	var x1 := to.x
	var y1 := to.y
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return points

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

	cell_clicked.emit(x, y)

func zoom_in() -> void:
	_apply_zoom(1.15, _get_viewport_size() * 0.5)

func zoom_out() -> void:
	_apply_zoom(1.0 / 1.15, _get_viewport_size() * 0.5)

func reset_zoom() -> void:
	_fit_to_view()
