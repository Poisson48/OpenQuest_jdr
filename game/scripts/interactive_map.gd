extends Control
class_name InteractiveMap

signal cell_clicked(x: int, y: int)
signal cell_paint(x: int, y: int)
signal paint_drag_finished()
signal cell_drag_started(x: int, y: int)
signal cell_dragged(x: int, y: int)
signal cell_drag_ended(x: int, y: int)
signal rect_preview(from: Vector2i, to: Vector2i)
signal navigation_requested(action: String, data: Dictionary)
signal zoom_changed(zoom_level: float)
signal token_selected(token_id: String)
signal token_moved(token_id: String, gx: float, gy: float)
signal prop_moved(prop_id: String, gx: float, gy: float)
signal inspect_requested(info: Dictionary)

const INTERACT_CLICK := "click"
const INTERACT_PAINT := "paint"
const INTERACT_PAN := "pan"
const INTERACT_SELECT := "select"
const INTERACT_RECT := "rect"
const INTERACT_MEASURE := "measure"
const AssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")

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
var suppressed_markers: Array = []
var suppressed_areas: Array = []
var suppressed_links: Array = []
var suppressed_props: Array = []
var party: Array = []
var _sprite_cache: Dictionary = {}
var quest_format: String = "oneshot"
var fog_enabled: bool = false
var readonly: bool = false
var paint_drag_enabled: bool = false
var interaction_mode: String = INTERACT_CLICK
var overlay: Dictionary = {}
var suppress_navigation: bool = false
var nav_context: Dictionary = {}

var session_tool: Dictionary = { "mode": "select" }
var zoom: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var _loaded_map_id: String = ""
var is_gm: bool = false
var owned_member_id: String = ""
var selected_token_id: String = ""

var _pan_dragging: bool = false
var _paint_dragging: bool = false
var _tool_dragging: bool = false
var _token_dragging: Dictionary = {}
var _prop_dragging: Dictionary = {}
var _drag_preview_cell: Vector2i = Vector2i(-1, -1)
var _prop_drag_pos: Vector2 = Vector2(-1, -1)
var _pending_click: bool = false
var _press_cell: Vector2i = Vector2i(-1, -1)
var _last_painted_cell: Vector2i = Vector2i(-99999, -99999)
var _drag_origin_cell: Vector2i = Vector2i(-1, -1)
var _last_tool_cell: Vector2i = Vector2i(-1, -1)
var _drag_start: Vector2 = Vector2.ZERO
var _pan_start: Vector2 = Vector2.ZERO
var _base_cell: int = 16
func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL

func configure(p_map: Dictionary, p_tokens: Array, p_party: Array, p_explored: Array, p_quest_format: String, p_readonly: bool = false, p_nav: Dictionary = {}, p_revealed_markers: Array = [], p_revealed_links: Array = [], p_suppressed_markers: Array = [], p_suppressed_areas: Array = [], p_suppressed_links: Array = [], p_suppressed_props: Array = []) -> void:
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
	suppressed_markers = p_suppressed_markers
	suppressed_areas = p_suppressed_areas
	suppressed_links = p_suppressed_links
	suppressed_props = p_suppressed_props
	_loaded_map_id = new_map_id
	fog_enabled = MapData.is_world_map(map_data) and nav_context.is_empty() and not readonly
	if str(session_tool.get("mode", "")) == "member":
		if str(session_tool.get("memberId", "")).is_empty() and not party.is_empty():
			session_tool["memberId"] = str(party[0].get("id", ""))

	if same_map:
		queue_redraw()
	else:
		call_deferred("_fit_to_view")

func set_session_tool(mode: String, extra: Dictionary = {}) -> void:
	session_tool = { "mode": mode }
	session_tool.merge(extra)
	queue_redraw()

func set_move_policy(p_is_gm: bool, p_owned_member_id: String = "") -> void:
	is_gm = p_is_gm
	owned_member_id = p_owned_member_id

func set_selected_token(token_id: String) -> void:
	selected_token_id = token_id
	queue_redraw()

func _is_place_tool() -> bool:
	return str(session_tool.get("mode", "select")) in ["member", "marker", "erase", "effect", "zone", "fog"]

func set_interaction_mode(mode: String) -> void:
	interaction_mode = mode
	paint_drag_enabled = mode == INTERACT_PAINT

func set_overlay(data: Dictionary) -> void:
	overlay = data
	queue_redraw()

func cell_at(pos: Vector2) -> Vector2i:
	return _pos_to_cell(pos)

func cell_rect(x: int, y: int, w: float = 1.0, h: float = 1.0) -> Rect2:
	var cs := float(get_cell_size())
	return Rect2(pan_offset + Vector2(x * cs, y * cs), Vector2(w * cs, h * cs))

func get_cell_size() -> int:
	return maxi(MIN_CELL, mini(MAX_CELL, int(round(_base_cell * zoom))))

## Centre de case → pixels locaux. `height` décale vers le haut (bulles).
func grid_to_screen(gx: float, gy: float, height: float = 0.0) -> Vector2:
	var cs := float(get_cell_size())
	return pan_offset + Vector2((gx + 0.5) * cs, (gy + 0.5) * cs - height * cs)

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
	var max_fit := 12 if MapData.is_world_map(map_data) else 48
	_base_cell = maxi(MIN_CELL, mini(max_fit, mini(by_w, by_h)))

## Borne le déplacement, axe par axe. Quand la carte tient dans le cadre elle
## est centrée : la borner entre 0 et 0 la collerait au coin haut-gauche et
## annulerait tout recadrage.
func _clamp_pan() -> void:
	var vp := _get_viewport_size()
	var map_px := get_map_pixel_size()
	if map_px.x <= vp.x:
		pan_offset.x = (vp.x - map_px.x) * 0.5
	else:
		pan_offset.x = clampf(pan_offset.x, vp.x - map_px.x, 0.0)
	if map_px.y <= vp.y:
		pan_offset.y = (vp.y - map_px.y) * 0.5
	else:
		pan_offset.y = clampf(pan_offset.y, vp.y - map_px.y, 0.0)

## Cadrage complet : la carte trop grande part du coin haut-gauche, la carte
## qui tient est centrée par `_clamp_pan()`.
func _center_or_clamp_pan() -> void:
	pan_offset = Vector2.ZERO
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
				_draw_ground_tile(rect, tile_id)
			else:
				draw_rect(rect, Color(0.05, 0.04, 0.06, 1.0))
				draw_rect(rect, Color(0.2, 0.16, 0.1, 0.5), false, 1.0)

	_draw_props()
	_draw_areas()
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
			if show_marker and not static_mk.is_empty() and _marker_replaced_by_token(static_mk):
				show_marker = false

			if show_link and token.is_empty() and not _is_suppressed_link(x, y):
				_draw_marker_sprite(rect, "exit", "", "")
			elif show_marker and static_mk and token.is_empty() and not _is_suppressed_marker(x, y):
				_draw_static_marker(static_mk, key, rect, cs, cluster_info)
			if not token.is_empty():
				_draw_token(rect, token, cs)
				if _is_selected_token(token):
					draw_rect(rect.grow(-1), ThemeColors.GOLD, false, 2.0)
					_draw_nameplate(rect, str(token.get("label", token.get("name", ""))))

	_draw_notes()
	_draw_overlay()

func _draw_props() -> void:
	var cs := float(get_cell_size())
	for prop_variant in map_data.get("props", []):
		if not prop_variant is Dictionary:
			continue
		var prop: Dictionary = prop_variant
		if bool(prop.get("hidden", false)):
			continue
		if suppressed_props.has(str(prop.get("id", ""))):
			continue
		var tex: Texture2D = AssetLibraryScript.load_texture(str(prop.get("asset", "")))
		if tex == null:
			continue
		var px := float(prop.get("x", 0.0))
		var py := float(prop.get("y", 0.0))
		if not _prop_dragging.is_empty() and str(prop.get("id", "")) == str(_prop_dragging.get("id", "")) \
				and _prop_drag_pos.x >= 0.0:
			px = _prop_drag_pos.x
			py = _prop_drag_pos.y
		var pw := maxf(0.25, float(prop.get("w", 1.0)))
		var ph := maxf(0.25, float(prop.get("h", 1.0)))
		var rect := Rect2(pan_offset + Vector2((px - pw * 0.5) * cs, (py - ph * 0.5) * cs), Vector2(pw * cs, ph * cs))
		var opacity := 1.0
		var display = prop.get("display", {})
		if display is Dictionary:
			opacity = float(display.get("opacity", 1.0))
		draw_texture_rect(tex, rect, false, Color(1, 1, 1, opacity))

func _draw_areas() -> void:
	var cs := float(get_cell_size())
	for area_variant in map_data.get("areas", []):
		if not area_variant is Dictionary:
			continue
		var area: Dictionary = area_variant
		if bool(area.get("hidden", false)):
			continue
		var ax := float(area.get("x", 0.0))
		var ay := float(area.get("y", 0.0))
		var aw := maxf(0.5, float(area.get("w", 2.0)))
		var ah := maxf(0.5, float(area.get("h", 2.0)))
		var rect := Rect2(pan_offset + Vector2((ax - aw * 0.5) * cs, (ay - ah * 0.5) * cs), Vector2(aw * cs, ah * cs))
		if suppressed_areas.has(str(area.get("id", ""))):
			continue
		var fill := Color(0.2, 0.45, 0.7, 0.10)
		if str(area.get("category", "")) == "exit":
			fill = Color(0.55, 0.42, 0.22, 0.08)
		elif not str(area.get("targetMapId", "")).is_empty():
			fill = Color(0.78, 0.62, 0.18, 0.12)
		draw_rect(rect, fill)
		draw_rect(rect, Color(fill.r, fill.g, fill.b, 0.35), false, 1.0)

func _draw_notes() -> void:
	if not bool(overlay.get("show_notes", false)):
		return
	var cs := get_cell_size()
	for note_variant in map_data.get("notes", []):
		if not note_variant is Dictionary:
			continue
		var note: Dictionary = note_variant
		if bool(note.get("hidden", false)):
			continue
		var nx := int(round(float(note.get("x", 0))))
		var ny := int(round(float(note.get("y", 0))))
		var rect := cell_rect(nx, ny)
		draw_rect(rect.grow(-2), Color(0.85, 0.72, 0.25, 0.35))
		_draw_centered_text(rect, "📝", cs)

func _draw_overlay() -> void:
	if overlay.is_empty():
		return
	var cs := float(get_cell_size())
	for rect_variant in overlay.get("selected_rects", []):
		if not rect_variant is Dictionary:
			continue
		var info: Dictionary = rect_variant
		var rx := float(info.get("x", 0.0))
		var ry := float(info.get("y", 0.0))
		var rw := maxf(1.0, float(info.get("w", 1.0)))
		var rh := maxf(1.0, float(info.get("h", 1.0)))
		var rect := Rect2(pan_offset + Vector2((rx - rw * 0.5) * cs, (ry - rh * 0.5) * cs), Vector2(rw * cs, rh * cs))
		if bool(info.get("cell", false)):
			rect = cell_rect(int(round(rx)), int(round(ry)))
		draw_rect(rect, Color(0.9, 0.75, 0.2, 0.12))
		draw_rect(rect, ThemeColors.GOLD, false, 2.0)
	var preview = overlay.get("preview_rect", {})
	if preview is Dictionary and not preview.is_empty():
		var from_c: Vector2i = preview.get("from", Vector2i.ZERO)
		var to_c: Vector2i = preview.get("to", Vector2i.ZERO)
		var min_x := mini(from_c.x, to_c.x)
		var min_y := mini(from_c.y, to_c.y)
		var max_x := maxi(from_c.x, to_c.x)
		var max_y := maxi(from_c.y, to_c.y)
		var prect := cell_rect(min_x, min_y, float(max_x - min_x + 1), float(max_y - min_y + 1))
		draw_rect(prect, Color(0.3, 0.55, 0.85, 0.2))
		draw_rect(prect, Color(0.45, 0.7, 1.0, 0.9), false, 2.0)
	var measure = overlay.get("measure", {})
	if measure is Dictionary and not measure.is_empty():
		var a: Vector2i = measure.get("from", Vector2i(-1, -1))
		var b: Vector2i = measure.get("to", Vector2i(-1, -1))
		if a.x >= 0 and b.x >= 0:
			var p0 := pan_offset + Vector2((a.x + 0.5) * cs, (a.y + 0.5) * cs)
			var p1 := pan_offset + Vector2((b.x + 0.5) * cs, (b.y + 0.5) * cs)
			draw_line(p0, p1, ThemeColors.GOLD_LIGHT, 2.0)
			var dist := Vector2(b - a).length()
			var per_cell := float((map_data.get("measure", {}) as Dictionary).get("perCell", 1.5)) if map_data.get("measure") is Dictionary else 1.5
			var unit := str((map_data.get("measure", {}) as Dictionary).get("unit", "m")) if map_data.get("measure") is Dictionary else "m"
			var text := "%.1f cases · %.1f %s" % [dist, dist * per_cell, unit]
			draw_string(ThemeDB.fallback_font, (p0 + p1) * 0.5 + Vector2(6, -6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ThemeColors.GOLD_LIGHT)
	var hover = overlay.get("hover_cell", Vector2i(-1, -1))
	if hover is Vector2i and hover.x >= 0:
		draw_rect(cell_rect(hover.x, hover.y), Color(1, 1, 1, 0.12))

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
	var info: Dictionary = cluster_info.get(key, {})
	if not info.is_empty() and str(info.get("marker_type", "")) != mtype:
		info = {}

	if info.is_empty() or int(info.get("cluster_size", 0)) < 2:
		_draw_marker_sprite(rect, mtype, str(mk.get("role", "")), str(mk.get("label", "")))
		return
	var cluster_rect: Rect2 = info.get("cluster_rect", rect)
	if info.get("is_anchor", false):
		_draw_marker_sprite(cluster_rect, mtype, str(mk.get("role", "")), str(mk.get("label", "")))

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
	if _is_suppressed_marker(mx, my):
		return false
	if not MapData.is_investigation_hidden_marker(mk_type, map_data, quest_format):
		return true
	return _revealed_marker_set().has(_marker_key(mx, my))

func _should_show_location_link(x: int, y: int) -> bool:
	if _is_suppressed_link(x, y):
		return false
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

func _draw_ground_tile(rect: Rect2, tile_id: String) -> void:
	var fill := MapData.get_tile_color(map_data, tile_id)
	# Toujours peindre la couleur de case d'abord : les textures Gemini
	# détourées ont de l'alpha et laisseraient voir le fond sombre de l'UI.
	draw_rect(rect, fill)
	var tex := _load_sprite(MapData.get_tile_texture_path(tile_id))
	if tex != null:
		draw_texture_rect(tex, rect, false)
	draw_rect(rect, Color(0, 0, 0, 0.08), false, 1.0)

func _load_sprite(path: String) -> Texture2D:
	var key := path.strip_edges()
	if key.is_empty():
		return null
	if _sprite_cache.has(key):
		return _sprite_cache[key]
	if not MapData.is_usable_sprite(key):
		_sprite_cache[key] = null
		return null
	var tex: Texture2D = AssetLibraryScript.load_texture(key)
	_sprite_cache[key] = tex
	return tex

func _draw_sprite_fitted(rect: Rect2, tex: Texture2D) -> void:
	if tex == null or rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var scale := minf(rect.size.x / maxf(tw, 1.0), rect.size.y / maxf(th, 1.0))
	var size := Vector2(tw, th) * scale
	var dest := Rect2(rect.get_center() - size * 0.5, size)
	draw_texture_rect(tex, dest, false)

func _draw_marker_sprite(rect: Rect2, marker_type: String, role: String, label: String) -> void:
	var path := MapData.get_marker_sprite_path(marker_type)
	if path.is_empty() and (marker_type == "npc" or not role.is_empty()):
		path = MapData.get_character_sprite_path(role, label)
	var tex := _load_sprite(path)
	if tex != null:
		_draw_sprite_fitted(rect.grow(-1), tex)
		return
	_draw_quiet_pin(rect, marker_type)

func _draw_quiet_pin(rect: Rect2, marker_type: String) -> void:
	var color := Color(0.72, 0.58, 0.28, 0.85)
	match marker_type:
		"danger":
			color = Color(0.72, 0.38, 0.22, 0.8)
		"treasure":
			color = Color(0.82, 0.68, 0.28, 0.85)
		"exit":
			color = Color(0.48, 0.36, 0.22, 0.55)
		"poi":
			color = Color(0.55, 0.62, 0.72, 0.75)
	var r := mini(rect.size.x, rect.size.y) * 0.16
	draw_circle(rect.get_center(), r, color)

func _draw_nameplate(rect: Rect2, text: String) -> void:
	var label := text.strip_edges()
	if label.is_empty():
		return
	var font := ThemeDB.fallback_font
	var fs := maxi(10, int(get_cell_size() * 0.28))
	var pos := Vector2(rect.position.x, rect.end.y + fs * 0.15)
	draw_string(font, pos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 1.6, fs, Color(0, 0, 0, 0.55))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x * 1.6, fs, Color(0.95, 0.9, 0.78, 0.95))

func _is_suppressed_marker(x: int, y: int) -> bool:
	return suppressed_markers.has(_marker_key(x, y))

func _is_suppressed_link(x: int, y: int) -> bool:
	return suppressed_links.has(_marker_key(x, y))

func _draw_token(rect: Rect2, token: Dictionary, cs: int) -> void:
	var pad := 1.0
	var inner := rect.grow(-pad)
	var image := str(token.get("image", token.get("portrait", ""))).strip_edges()
	var kind := str(token.get("kind", ""))
	var marker_type := str(token.get("markerType", token.get("type", "")))
	var role := str(token.get("role", ""))
	var label := str(token.get("label", token.get("name", "")))
	if image.is_empty() and kind == "member":
		var member := _find_member(str(token.get("memberId", "")))
		image = str(member.get("portrait", member.get("image", ""))).strip_edges()
		if image.is_empty():
			image = MapData.get_character_sprite_path(str(member.get("class", "")), label)
	if image.is_empty() and (kind == "npc" or marker_type == "npc"):
		image = MapData.get_character_sprite_path(role, label)
	if image.is_empty() and not marker_type.is_empty():
		image = MapData.get_marker_sprite_path(marker_type)
	var tex := _load_sprite(image)
	if tex != null:
		_draw_sprite_fitted(inner, tex)
		return
	if kind == "member":
		var col := MapData.get_member_color(token.get("memberId", ""), party)
		draw_circle(inner.get_center(), mini(inner.size.x, inner.size.y) * 0.38, col)
		draw_arc(inner.get_center(), mini(inner.size.x, inner.size.y) * 0.38, 0.0, TAU, 24, Color(0, 0, 0, 0.45), 1.5)
		return
	_draw_quiet_pin(inner, marker_type)

func _static_marker_at(x: int, y: int) -> Dictionary:
	for mk in map_data.get("markers", []):
		if int(mk.get("x", -1)) == x and int(mk.get("y", -1)) == y:
			return mk
	return {}

func _token_at(x: int, y: int) -> Dictionary:
	if not _token_dragging.is_empty() and _drag_preview_cell.x == x and _drag_preview_cell.y == y:
		return _token_dragging
	var best: Dictionary = {}
	var best_dist := 0.85
	for t in tokens:
		if not t is Dictionary:
			continue
		if _is_drag_token(t):
			continue
		var tx := float(t.get("x", -999))
		var ty := float(t.get("y", -999))
		var dist := Vector2(tx - float(x), ty - float(y)).length()
		if dist <= best_dist:
			best_dist = dist
			best = t
	return best

func _prop_at_cell(x: int, y: int) -> Dictionary:
	var best: Dictionary = {}
	var best_area := INF
	var cx := float(x) + 0.5
	var cy := float(y) + 0.5
	for prop_variant in map_data.get("props", []):
		if not prop_variant is Dictionary:
			continue
		var prop: Dictionary = prop_variant
		if bool(prop.get("hidden", false)):
			continue
		if suppressed_props.has(str(prop.get("id", ""))):
			continue
		if not _prop_dragging.is_empty() and str(prop.get("id", "")) == str(_prop_dragging.get("id", "")):
			continue
		var px := float(prop.get("x", 0.0))
		var py := float(prop.get("y", 0.0))
		var pw := maxf(0.25, float(prop.get("w", 1.0)))
		var ph := maxf(0.25, float(prop.get("h", 1.0)))
		var rect := Rect2(px - pw * 0.5, py - ph * 0.5, pw, ph)
		if not rect.has_point(Vector2(cx, cy)):
			continue
		var area := pw * ph
		if area < best_area:
			best_area = area
			best = prop
	return best

func _can_move_prop(prop: Dictionary) -> bool:
	if prop.is_empty() or readonly or not is_gm:
		return false
	return not str(prop.get("id", "")).is_empty()

func _is_drag_token(token: Dictionary) -> bool:
	if _token_dragging.is_empty():
		return false
	var drag_id := str(_token_dragging.get("id", ""))
	return not drag_id.is_empty() and str(token.get("id", "")) == drag_id

func _is_selected_token(token: Dictionary) -> bool:
	return not selected_token_id.is_empty() and str(token.get("id", "")) == selected_token_id

func _marker_replaced_by_token(mk: Dictionary) -> bool:
	var label := str(mk.get("label", mk.get("name", ""))).strip_edges().to_lower()
	if label.is_empty():
		return false
	for t in tokens:
		if not t is Dictionary:
			continue
		var tok_label := str(t.get("label", t.get("name", ""))).strip_edges().to_lower()
		if tok_label == label:
			return true
	return false

func _can_move_token(token: Dictionary) -> bool:
	if token.is_empty() or readonly:
		return false
	var token_id := str(token.get("id", ""))
	if token_id.is_empty():
		return false
	if is_gm:
		return true
	return str(token.get("kind", "")) == "member" and str(token.get("memberId", "")) == owned_member_id

func _inspect_payload(x: int, y: int) -> Dictionary:
	var token := _token_at(x, y)
	if not token.is_empty():
		return {
			"kind": str(token.get("kind", "token")),
			"token_id": str(token.get("id", "")),
			"label": str(token.get("label", token.get("name", ""))),
			"member_id": str(token.get("memberId", "")),
			"marker_type": str(token.get("markerType", "")),
			"role": str(token.get("role", "")),
			"x": x,
			"y": y,
		}
	var mk := _static_marker_at(x, y)
	if not mk.is_empty() and _should_show_static_marker(mk) and not _is_suppressed_marker(x, y):
		return {
			"kind": "marker",
			"token_id": "",
			"label": str(mk.get("label", mk.get("name", ""))),
			"marker_type": str(mk.get("type", "")),
			"role": str(mk.get("role", "")),
			"x": x,
			"y": y,
		}
	var area := MapData.get_area_at(map_data, float(x) + 0.5, float(y) + 0.5)
	if not area.is_empty() and not suppressed_areas.has(str(area.get("id", ""))):
		return {
			"kind": "area",
			"token_id": "",
			"label": str(area.get("label", "")),
			"area_id": str(area.get("id", "")),
			"target_map_id": str(area.get("targetMapId", "")),
			"x": x,
			"y": y,
		}
	var prop := _prop_at_cell(x, y)
	if not prop.is_empty():
		return {
			"kind": "prop",
			"token_id": "",
			"prop_id": str(prop.get("id", "")),
			"label": str(prop.get("label", prop.get("asset", "Décor"))).get_file().get_basename(),
			"x": x,
			"y": y,
		}
	return { "kind": "", "x": x, "y": y }

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
			if readonly and not mb.ctrl_pressed:
				return
			_apply_zoom(1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if readonly and not mb.ctrl_pressed:
				return
			_apply_zoom(1.0 / 1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_pressed(mb)
			else:
				_on_left_released(mb)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_dragging = mb.pressed
			_pending_click = false
			_paint_dragging = false
			_tool_dragging = false
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
		elif _tool_dragging:
			var cell := _pos_to_cell(motion.position)
			if cell.x >= 0:
				_last_tool_cell = cell
				cell_dragged.emit(cell.x, cell.y)
				if interaction_mode in [INTERACT_RECT, INTERACT_MEASURE]:
					rect_preview.emit(_drag_origin_cell, cell)
			accept_event()
		elif not _token_dragging.is_empty():
			var cell := _pos_to_cell(motion.position)
			if cell.x >= 0:
				_drag_preview_cell = cell
				queue_redraw()
			accept_event()
		elif not _prop_dragging.is_empty():
			var cell2 := _pos_to_cell(motion.position)
			if cell2.x >= 0:
				_prop_drag_pos = Vector2(float(cell2.x) + 0.5, float(cell2.y) + 0.5)
				queue_redraw()
			accept_event()
		elif _pending_click and not _pan_dragging:
			if _drag_start.distance_to(motion.position) >= DRAG_THRESHOLD:
				var press_token := _token_at(_press_cell.x, _press_cell.y) if _press_cell.x >= 0 else {}
				if not _is_place_tool() and _can_move_token(press_token):
					_token_dragging = press_token.duplicate(true)
					_drag_preview_cell = _press_cell
					_pending_click = false
					queue_redraw()
				elif not _is_place_tool():
					var press_prop := _prop_at_cell(_press_cell.x, _press_cell.y) if _press_cell.x >= 0 else {}
					if _can_move_prop(press_prop):
						_prop_dragging = press_prop.duplicate(true)
						_prop_drag_pos = Vector2(float(_press_cell.x) + 0.5, float(_press_cell.y) + 0.5)
						_pending_click = false
						queue_redraw()
					else:
						_pan_dragging = true
						_pending_click = false
				else:
					_pan_dragging = true
					_pending_click = false
		if _pan_dragging:
			pan_offset = _pan_start + (motion.position - _drag_start)
			_clamp_pan()
			queue_redraw()
			accept_event()

func _on_left_pressed(mb: InputEventMouseButton) -> void:
	var force_pan := mb.shift_pressed or interaction_mode == INTERACT_PAN
	var cell := _pos_to_cell(mb.position)
	if force_pan:
		_pan_dragging = false
		_pending_click = true
		_press_cell = cell
		_drag_start = mb.position
		_pan_start = pan_offset
		accept_event()
		return
	if not readonly and (paint_drag_enabled or interaction_mode == INTERACT_PAINT):
		_paint_dragging = true
		_pan_dragging = false
		_pending_click = false
		_last_painted_cell = Vector2i(-99999, -99999)
		_try_paint_at(mb.position)
		accept_event()
		return
	if not readonly and interaction_mode in [INTERACT_SELECT, INTERACT_RECT, INTERACT_MEASURE]:
		_tool_dragging = true
		_pan_dragging = false
		_pending_click = false
		_drag_origin_cell = cell
		_last_tool_cell = cell
		_press_cell = cell
		_drag_start = mb.position
		if cell.x >= 0:
			cell_drag_started.emit(cell.x, cell.y)
			if interaction_mode in [INTERACT_RECT, INTERACT_MEASURE]:
				rect_preview.emit(cell, cell)
		accept_event()
		return
	_pan_dragging = false
	_pending_click = true
	_press_cell = cell
	_drag_start = mb.position
	_pan_start = pan_offset
	accept_event()

func _on_left_released(mb: InputEventMouseButton) -> void:
	if _paint_dragging:
		_paint_dragging = false
		_last_painted_cell = Vector2i(-99999, -99999)
		paint_drag_finished.emit()
	elif _tool_dragging:
		var cell := _last_tool_cell if _last_tool_cell.x >= 0 else _press_cell
		cell_drag_ended.emit(cell.x, cell.y)
		_tool_dragging = false
		_last_tool_cell = Vector2i(-1, -1)
	elif not _token_dragging.is_empty():
		var dest := _drag_preview_cell if _drag_preview_cell.x >= 0 else _press_cell
		var token_id := str(_token_dragging.get("id", ""))
		if not token_id.is_empty() and dest.x >= 0:
			for tok_variant in tokens:
				if tok_variant is Dictionary and str(tok_variant.get("id", "")) == token_id:
					tok_variant["x"] = dest.x
					tok_variant["y"] = dest.y
					break
		_token_dragging = {}
		_drag_preview_cell = Vector2i(-1, -1)
		queue_redraw()
		if not token_id.is_empty() and dest.x >= 0:
			token_moved.emit(token_id, float(dest.x), float(dest.y))
	elif not _prop_dragging.is_empty():
		var dest_pos := _prop_drag_pos if _prop_drag_pos.x >= 0.0 else Vector2(float(_press_cell.x) + 0.5, float(_press_cell.y) + 0.5)
		var prop_id := str(_prop_dragging.get("id", ""))
		if not prop_id.is_empty() and dest_pos.x >= 0.0:
			for prop_variant in map_data.get("props", []):
				if prop_variant is Dictionary and str(prop_variant.get("id", "")) == prop_id:
					prop_variant["x"] = dest_pos.x
					prop_variant["y"] = dest_pos.y
					break
		_prop_dragging = {}
		_prop_drag_pos = Vector2(-1, -1)
		queue_redraw()
		if not prop_id.is_empty() and dest_pos.x >= 0.0:
			prop_moved.emit(prop_id, dest_pos.x, dest_pos.y)
	elif _pending_click and not _pan_dragging and _press_cell.x >= 0:
		_handle_cell_click(_press_cell.x, _press_cell.y, mb.double_click)
	_pan_dragging = false
	_pending_click = false
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

func _handle_cell_click(x: int, y: int, double_click: bool = false) -> void:
	if readonly:
		return
	var key := "%d,%d" % [x, y]
	if fog_enabled and not explored.has(key):
		return

	if double_click and not suppress_navigation and _try_session_navigation(x, y):
		return

	if _is_place_tool():
		cell_clicked.emit(x, y)
		return

	var info := _inspect_payload(x, y)
	var token_id := str(info.get("token_id", ""))
	selected_token_id = token_id
	token_selected.emit(token_id)
	inspect_requested.emit(info)
	queue_redraw()

func _try_session_navigation(x: int, y: int) -> bool:
	var static_mk := _static_marker_at(x, y)
	if nav_context.get("mode") == "local" and static_mk.get("type") == "exit":
		navigation_requested.emit("exit_world", {})
		return true
	if nav_context.is_empty() and MapData.is_world_map(map_data):
		var link := MapData.get_location_link_at(map_data, x, y)
		if link.has("targetMapId"):
			navigation_requested.emit("enter_local", { "x": x, "y": y, "targetMapId": link.get("targetMapId") })
			return true
	var area := MapData.get_area_at(map_data, float(x) + 0.5, float(y) + 0.5)
	if not area.is_empty() and not str(area.get("targetMapId", "")).is_empty():
		navigation_requested.emit("enter_area", { "areaId": str(area.get("id", "")) })
		return true
	return false

## Échelle réellement affichée : pixels écran par case de grille.
func get_effective_scale() -> float:
	return float(get_cell_size())

func zoom_in() -> void:
	_apply_zoom(1.15, _get_viewport_size() * 0.5)

func zoom_out() -> void:
	_apply_zoom(1.0 / 1.15, _get_viewport_size() * 0.5)

func reset_zoom() -> void:
	_fit_to_view()
