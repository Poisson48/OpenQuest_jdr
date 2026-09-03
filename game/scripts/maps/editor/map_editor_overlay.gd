extends Control
class_name MapEditorOverlay

## Calque 2D dessiné par-dessus le viewport 3D : sélection, rectangle de
## sélection, liens, aperçu d'outil, règle de mesure, icônes des éléments
## sans représentation 3D (murs en cours, notes, lumières).
##
## Toutes les positions sont projetées via `engine.grid_to_screen()`, ce qui
## rend l'overlay correct en vue de dessus comme en isométrique.

var engine: Control = null
var doc: MapEditDocument = null

# --- État transitoire piloté par l'éditeur ---------------------------------
var hover_grid: Vector2 = Vector2(-999, -999)
var hover_valid: bool = false
var band_active: bool = false
var band_start: Vector2 = Vector2.ZERO
var band_end: Vector2 = Vector2.ZERO
var polygon_points: Array = []
var measure_from: Vector2 = Vector2.ZERO
var measure_to: Vector2 = Vector2.ZERO
var measure_active: bool = false
var ghost: Dictionary = {}
var drag_preview: Dictionary = {}
var link_source_id: String = ""
var show_links: bool = true
var show_ids: bool = false
var show_vision: bool = false
var vision_cells: Dictionary = {}
var vision_origin: Vector2 = Vector2.ZERO
var has_vision_origin: bool = false

const COL_SELECT := Color(1.0, 0.82, 0.28, 0.95)
const COL_SELECT_FILL := Color(1.0, 0.82, 0.28, 0.10)
const COL_BAND := Color(0.42, 0.72, 1.0, 0.85)
const COL_BAND_FILL := Color(0.42, 0.72, 1.0, 0.16)
const COL_HOVER := Color(1.0, 1.0, 1.0, 0.35)
const COL_LINK := Color(0.62, 0.86, 1.0, 0.8)
const COL_GHOST := Color(0.75, 1.0, 0.75, 0.55)
const COL_MEASURE := Color(1.0, 0.55, 0.25, 0.95)
const COL_LOCKED := Color(0.85, 0.35, 0.35, 0.8)
const COL_GROUP := Color(0.7, 0.55, 1.0, 0.7)
const COL_VISION := Color(1.0, 0.94, 0.72, 0.13)
const COL_DOOR_OPEN := Color(0.45, 0.9, 0.55, 0.95)
const COL_DOOR_SHUT := Color(1.0, 0.62, 0.25, 0.95)
const COL_AREA := Color(0.55, 0.78, 0.95, 0.75)
const COL_AREA_LINKED := Color(0.95, 0.78, 0.35, 0.95)
const COL_CALLOUT_BG := Color(0.96, 0.92, 0.80, 0.94)
const COL_CALLOUT_TEXT := Color(0.16, 0.12, 0.08)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func set_context(p_engine: Control, p_doc: MapEditDocument) -> void:
	engine = p_engine
	doc = p_doc
	queue_redraw()

func clear_transient() -> void:
	band_active = false
	polygon_points.clear()
	measure_active = false
	ghost.clear()
	drag_preview.clear()
	link_source_id = ""
	queue_redraw()

# ===========================================================================
# Projection
# ===========================================================================

func _p(gx: float, gy: float, height: float = 0.0) -> Vector2:
	if engine == null or not engine.has_method("grid_to_screen"):
		return Vector2.ZERO
	return engine.grid_to_screen(gx, gy, height)

## Coins projetés de l'empreinte au sol d'un élément.
func _footprint(elem: Dictionary) -> PackedVector2Array:
	var cx := float(elem.get("x", 0.0))
	var cy := float(elem.get("y", 0.0))
	var hw := float(elem.get("w", 1.0)) * 0.5
	var hh := float(elem.get("h", 1.0)) * 0.5
	var angle := deg_to_rad(float((elem.get("display", {}) as Dictionary).get("rotation", 0.0)))
	var corners: PackedVector2Array = PackedVector2Array()
	for offset in [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]:
		var rotated := (offset as Vector2).rotated(angle)
		corners.append(_p(cx + rotated.x, cy + rotated.y))
	return corners

func _cell_rect_points(cx: int, cy: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(_p(float(cx) - 0.5, float(cy) - 0.5))
	pts.append(_p(float(cx) + 0.5, float(cy) - 0.5))
	pts.append(_p(float(cx) + 0.5, float(cy) + 0.5))
	pts.append(_p(float(cx) - 0.5, float(cy) + 0.5))
	return pts

static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(points)
	if out.size() > 0:
		out.append(out[0])
	return out

# ===========================================================================
# Rendu
# ===========================================================================

func _draw() -> void:
	if engine == null or doc == null:
		return
	if show_vision:
		_draw_vision()
	_draw_hover()
	if show_links:
		_draw_links()
	_draw_flat_elements()
	_draw_areas()
	_draw_selection()
	_draw_ghost()
	_draw_drag_preview()
	_draw_polygon()
	_draw_band()
	_draw_measure()

## Aperçu du champ de vision : les cases atteintes sont éclaircies, la source
## est marquée. Ce que le calque ne peint pas est dans l'ombre d'un mur.
func _draw_vision() -> void:
	for key in vision_cells.keys():
		var parts := str(key).split(",")
		if parts.size() != 2:
			continue
		var pts := _cell_rect_points(int(parts[0]), int(parts[1]))
		if pts.size() == 4:
			draw_colored_polygon(pts, COL_VISION)
	if has_vision_origin:
		var center := _p(vision_origin.x, vision_origin.y, 0.1)
		draw_circle(center, 5.0, Color(1.0, 0.92, 0.6, 0.9))
		draw_arc(center, 9.0, 0.0, TAU, 24, Color(1.0, 0.92, 0.6, 0.55), 1.5, true)

func _draw_hover() -> void:
	if not hover_valid:
		return
	var pts := _cell_rect_points(int(roundf(hover_grid.x)), int(roundf(hover_grid.y)))
	draw_polyline(_closed(pts), COL_HOVER, 1.5, true)

func _draw_links() -> void:
	for segment_variant in doc.link_segments():
		var segment: Dictionary = segment_variant
		var from: Vector2 = segment["from"]
		var to: Vector2 = segment["to"]
		var a := _p(from.x, from.y, 0.35)
		var b := _p(to.x, to.y, 0.35)
		draw_line(a, b, COL_LINK, 2.0, true)
		_draw_arrow_head(a, b, COL_LINK)

func _draw_arrow_head(from: Vector2, to: Vector2, color: Color) -> void:
	var dir := (to - from)
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var tip := to - dir * 8.0
	var left := tip + dir.orthogonal() * 5.0
	var right := tip - dir.orthogonal() * 5.0
	draw_colored_polygon(PackedVector2Array([to - dir * 2.0, left, right]), color)

## Éléments sans rendu 3D dédié : murs (contour), notes, lumières, passages.
func _draw_flat_elements() -> void:
	var font := get_theme_default_font()
	var font_size := 13
	for elem_variant in doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if not doc.is_element_visible(elem):
			continue
		var kind := str(elem.get("kind", ""))
		if kind == MapEditDocument.KIND_WALL:
			if bool(elem.get("isDoor", false)):
				var door_color := COL_DOOR_OPEN if bool(elem.get("open", false)) else COL_DOOR_SHUT
				draw_polyline(_closed(_footprint(elem)), door_color, 2.5, true)
			else:
				draw_polyline(_closed(_footprint(elem)), Color(0.85, 0.78, 0.66, 0.55), 1.5, true)
		elif kind in [MapEditDocument.KIND_NOTE, MapEditDocument.KIND_LIGHT, MapEditDocument.KIND_LINK, MapEditDocument.KIND_MARKER]:
			var pos := _p(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)), 0.3)
			var icon := str(MapEditDocument.KIND_ICONS.get(kind, "•"))
			if kind == MapEditDocument.KIND_MARKER:
				icon = MapData.get_marker_emoji(str(elem.get("markerType", "npc")))
			if font:
				draw_string(font, pos + Vector2(-8, 6), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 4)
		elif kind in [MapEditDocument.KIND_PLATFORM, MapEditDocument.KIND_OVERLAY]:
			draw_polyline(_closed(_footprint(elem)), Color(0.72, 0.62, 0.45, 0.35), 1.0, true)
		if show_ids and font:
			var label_pos := _p(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)), 0.6)
			draw_string(font, label_pos + Vector2(8, -4), str(elem.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))

## Lieux : emprise + cartouche de nom relié par un trait, à la manière des
## cartes de village illustrées. Un lieu qui ouvre sa propre carte est souligné
## d'un liseré doré et signalé par une loupe.
func _draw_areas() -> void:
	var font := get_theme_default_font()
	for elem_variant in doc.elements_of_kind(MapEditDocument.KIND_AREA):
		var area: Dictionary = elem_variant
		if not doc.is_element_visible(area):
			continue
		var has_child := not str(area.get("targetMapId", "")).is_empty()
		var outline := COL_AREA_LINKED if has_child else COL_AREA
		var center := Vector2(float(area.get("x", 0.0)), float(area.get("y", 0.0)))

		if str(area.get("shape", "rect")) == "circle":
			var radius_px := _p(center.x + float(area.get("w", 2.0)) * 0.5, center.y).distance_to(_p(center.x, center.y))
			draw_arc(_p(center.x, center.y), radius_px, 0.0, TAU, 48, outline, 2.0, true)
		else:
			var pts := _footprint(area)
			draw_colored_polygon(pts, Color(outline.r, outline.g, outline.b, 0.07))
			draw_polyline(_closed(pts), outline, 2.0, true)

		if font == null or not bool(area.get("showCallout", true)):
			continue
		var label := str(area.get("label", "Lieu"))
		if label.is_empty():
			continue
		var offset: Dictionary = area.get("labelOffset", {}) if area.get("labelOffset") is Dictionary else {}
		var anchor := center + Vector2(
			float(offset.get("x", 0.0)),
			float(offset.get("y", -(float(area.get("h", 2.0)) * 0.5 + 0.8)))
		)
		_draw_callout(font, _p(anchor.x, anchor.y), _p(center.x, center.y),
			"%s %s" % [MapData.area_icon(area), label], has_child)

## Cartouche « parchemin » : trait de rappel, fond crème, liseré sombre.
func _draw_callout(font: Font, at: Vector2, target: Vector2, text: String, highlighted: bool) -> void:
	var font_size := 13
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var padding := Vector2(9, 5)
	var box := Rect2(at - text_size * 0.5 - padding, text_size + padding * 2.0)

	draw_line(target, at, Color(0.18, 0.14, 0.10, 0.75), 1.5, true)
	draw_rect(box.grow(1.0), Color(0.18, 0.14, 0.10, 0.85), true)
	draw_rect(box, COL_CALLOUT_BG, true)
	if highlighted:
		draw_rect(box, COL_AREA_LINKED, false, 1.5)
	draw_string(font, Vector2(box.position.x + padding.x, box.position.y + padding.y + text_size.y * 0.8),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_CALLOUT_TEXT)
	if highlighted:
		draw_string(font, Vector2(box.end.x + 3.0, box.position.y + padding.y + text_size.y * 0.8),
			"🔍", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

func _draw_selection() -> void:
	var font := get_theme_default_font()
	var selected := doc.selection()
	if selected.is_empty():
		return
	for id_variant in selected:
		var elem: Dictionary = doc.get_element(str(id_variant))
		if elem.is_empty():
			continue
		var pts := _footprint(elem)
		if pts.size() < 4:
			continue
		draw_colored_polygon(pts, COL_SELECT_FILL)
		draw_polyline(_closed(pts), COL_SELECT, 2.0, true)
		for corner in pts:
			draw_rect(Rect2(corner - Vector2(3, 3), Vector2(6, 6)), COL_SELECT, true)
		if bool(elem.get("locked", false)):
			draw_polyline(_closed(pts), COL_LOCKED, 1.0, true)
		if not str(elem.get("group", "")).is_empty():
			draw_polyline(_closed(pts), COL_GROUP, 1.0, true)
	# Poignées souris : redimensionner / pivoter un décor seul.
	if selected.size() == 1:
		var sole: Dictionary = doc.get_element(str(selected[0]))
		if str(sole.get("kind", "")) == MapEditDocument.KIND_PROP and not bool(sole.get("locked", false)):
			_draw_prop_handles(sole)
	if selected.size() > 1:
		var bounds := doc.selection_bounds()
		var corners := PackedVector2Array([
			_p(bounds.position.x, bounds.position.y),
			_p(bounds.end.x, bounds.position.y),
			_p(bounds.end.x, bounds.end.y),
			_p(bounds.position.x, bounds.end.y),
		])
		draw_polyline(_closed(corners), Color(1.0, 0.82, 0.28, 0.45), 1.0, true)
		if font:
			draw_string(font, corners[0] + Vector2(4, -6), "%d éléments" % selected.size(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.88, 0.5, 0.9))

func _draw_ghost() -> void:
	if ghost.is_empty() or not hover_valid:
		return
	var w := float(ghost.get("w", 1.0))
	var h := float(ghost.get("h", 1.0))
	var cx := float(ghost.get("x", hover_grid.x))
	var cy := float(ghost.get("y", hover_grid.y))
	var pts := PackedVector2Array([
		_p(cx - w * 0.5, cy - h * 0.5),
		_p(cx + w * 0.5, cy - h * 0.5),
		_p(cx + w * 0.5, cy + h * 0.5),
		_p(cx - w * 0.5, cy + h * 0.5),
	])
	# Un décor s'aperçoit avec sa vraie image : on voit où tombe la maison
	# avant de cliquer, pas juste un rectangle.
	var texture = ghost.get("texture")
	if texture is Texture2D:
		var min_p := pts[0]
		var max_p := pts[0]
		for point in pts:
			min_p.x = minf(min_p.x, point.x)
			min_p.y = minf(min_p.y, point.y)
			max_p.x = maxf(max_p.x, point.x)
			max_p.y = maxf(max_p.y, point.y)
		draw_texture_rect(texture, Rect2(min_p, max_p - min_p), false, Color(1, 1, 1, 0.65))
		draw_polyline(_closed(pts), COL_GHOST, 1.5, true)
		return
	draw_colored_polygon(pts, Color(COL_GHOST.r, COL_GHOST.g, COL_GHOST.b, 0.14))
	draw_polyline(_closed(pts), COL_GHOST, 1.5, true)
	var font := get_theme_default_font()
	var icon := str(ghost.get("icon", ""))
	if font and not icon.is_empty():
		draw_string(font, _p(cx, cy) + Vector2(-8, 6), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)

## Aperçu du tracé en cours (zone rectangle, mur, plateforme).
func _draw_drag_preview() -> void:
	if drag_preview.is_empty():
		return
	var mode := str(drag_preview.get("mode", ""))
	var from: Vector2 = drag_preview.get("from", Vector2.ZERO)
	var to: Vector2 = drag_preview.get("to", Vector2.ZERO)
	match mode:
		"rect":
			var pts := PackedVector2Array([
				_p(from.x, from.y), _p(to.x, from.y), _p(to.x, to.y), _p(from.x, to.y),
			])
			draw_colored_polygon(pts, Color(0.9, 0.75, 0.3, 0.16))
			draw_polyline(_closed(pts), Color(0.95, 0.8, 0.35, 0.9), 2.0, true)
			_draw_size_label(pts[0], absf(to.x - from.x), absf(to.y - from.y))
		"line":
			var a := _p(from.x, from.y, 0.2)
			var b := _p(to.x, to.y, 0.2)
			draw_line(a, b, Color(0.85, 0.7, 0.5, 0.95), 4.0, true)
			draw_circle(a, 4.0, Color(0.95, 0.85, 0.6, 0.9))
			draw_circle(b, 4.0, Color(0.95, 0.85, 0.6, 0.9))
		"circle":
			var center := _p(from.x, from.y)
			var edge := _p(to.x, to.y)
			draw_arc(center, center.distance_to(edge), 0.0, TAU, 48, Color(0.9, 0.75, 0.3, 0.9), 2.0, true)

func _draw_size_label(anchor: Vector2, w: float, h: float) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	draw_string(font, anchor + Vector2(4, -6), "%.1f × %.1f cases" % [w, h],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.9, 0.6, 0.95))

func _draw_polygon() -> void:
	if polygon_points.size() == 0:
		return
	var pts := PackedVector2Array()
	for point in polygon_points:
		pts.append(_p((point as Vector2).x, (point as Vector2).y))
	if hover_valid:
		pts.append(_p(hover_grid.x, hover_grid.y))
	if pts.size() >= 3:
		draw_colored_polygon(pts, Color(0.5, 0.85, 0.6, 0.14))
	if pts.size() >= 2:
		draw_polyline(_closed(pts), Color(0.55, 0.95, 0.65, 0.9), 2.0, true)
	for point in pts:
		draw_circle(point, 4.0, Color(0.6, 1.0, 0.7, 0.95))

func _draw_band() -> void:
	if not band_active:
		return
	var rect := Rect2(band_start, band_end - band_start).abs()
	draw_rect(rect, COL_BAND_FILL, true)
	draw_rect(rect, COL_BAND, false, 1.5)

func _draw_measure() -> void:
	if not measure_active:
		return
	var a := _p(measure_from.x, measure_from.y, 0.15)
	var b := _p(measure_to.x, measure_to.y, 0.15)
	draw_line(a, b, COL_MEASURE, 2.5, true)
	draw_circle(a, 5.0, COL_MEASURE)
	draw_circle(b, 5.0, COL_MEASURE)
	var font := get_theme_default_font()
	if font == null:
		return
	var cells := measure_from.distance_to(measure_to)
	var measure_cfg: Dictionary = doc.map_data.get("measure", {}) if doc.map_data.get("measure") is Dictionary else {}
	var per_cell := float(measure_cfg.get("perCell", 1.5))
	var unit := str(measure_cfg.get("unit", "m"))
	var text := "%.1f cases · %.1f %s" % [cells, cells * per_cell, unit]
	var mid := (a + b) * 0.5
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_rect(Rect2(mid + Vector2(8, -16), text_size + Vector2(10, 6)), Color(0, 0, 0, 0.65), true)
	draw_string(font, mid + Vector2(13, -2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.92, 0.8))

# ===========================================================================
# Test d'intersection (sélection rectangle, façon AABB Meownopoly)
# ===========================================================================

## Éléments dont l'empreinte projetée croise le rectangle écran donné.
func elements_in_band(rect: Rect2) -> Array:
	var ids: Array = []
	if doc == null:
		return ids
	var band := rect.abs()
	for elem_variant in doc.elements():
		var elem: Dictionary = elem_variant
		if not doc.is_element_selectable(elem):
			continue
		var pts := _footprint(elem)
		if pts.is_empty():
			continue
		var min_p := pts[0]
		var max_p := pts[0]
		for point in pts:
			min_p.x = minf(min_p.x, point.x)
			min_p.y = minf(min_p.y, point.y)
			max_p.x = maxf(max_p.x, point.x)
			max_p.y = maxf(max_p.y, point.y)
		var extent := max_p - min_p
		var elem_rect := Rect2(min_p, Vector2(maxf(extent.x, 6.0), maxf(extent.y, 6.0)))
		if band.intersects(elem_rect):
			ids.append(str(elem.get("id", "")))
	return ids

const HANDLE_HIT := 10.0

## Poignées d'un décor : 4 coins (resize) + 1 poignée de rotation au-dessus.
func prop_handle_points(elem: Dictionary) -> Dictionary:
	var pts := _footprint(elem)
	if pts.size() < 4:
		return {}
	var top_mid := (pts[0] + pts[1]) * 0.5
	var rotate_at := top_mid + Vector2(0.0, -28.0)
	return {"corners": pts, "rotate": rotate_at, "top": top_mid}

func _draw_prop_handles(elem: Dictionary) -> void:
	var handles := prop_handle_points(elem)
	if handles.is_empty():
		return
	var corners: PackedVector2Array = handles["corners"]
	for corner in corners:
		draw_rect(Rect2(corner - Vector2(5, 5), Vector2(10, 10)), Color(0.12, 0.10, 0.08, 0.85), true)
		draw_rect(Rect2(corner - Vector2(5, 5), Vector2(10, 10)), COL_SELECT, false, 1.5)
	var rot: Vector2 = handles["rotate"]
	var top: Vector2 = handles["top"]
	draw_line(top, rot, COL_SELECT, 1.5, true)
	draw_circle(rot, 6.0, Color(0.12, 0.10, 0.08, 0.9))
	draw_arc(rot, 6.0, 0.0, TAU, 24, COL_SELECT, 1.5, true)

## `{ id, kind: "resize"|"rotate", corner }` si le curseur est sur une poignée.
func handle_at_screen(pos: Vector2, radius: float = HANDLE_HIT) -> Dictionary:
	if doc == null:
		return {}
	var selected := doc.selection()
	if selected.size() != 1:
		return {}
	var id := str(selected[0])
	var elem: Dictionary = doc.get_element(id)
	if str(elem.get("kind", "")) != MapEditDocument.KIND_PROP:
		return {}
	if bool(elem.get("locked", false)):
		return {}
	var handles := prop_handle_points(elem)
	if handles.is_empty():
		return {}
	var rot: Vector2 = handles["rotate"]
	if rot.distance_to(pos) <= radius:
		return {"id": id, "kind": "rotate", "corner": -1}
	var corners: PackedVector2Array = handles["corners"]
	for i in range(corners.size()):
		if corners[i].distance_to(pos) <= radius:
			return {"id": id, "kind": "resize", "corner": i}
	return {}

## Élément le plus « au-dessus » sous un point écran (ordre de calque inversé).
func element_at_screen(pos: Vector2, tolerance: float = 6.0) -> String:
	if doc == null:
		return ""
	var sorted := doc.elements_sorted()
	for i in range(sorted.size() - 1, -1, -1):
		var elem: Dictionary = sorted[i]
		if not doc.is_element_selectable(elem):
			continue
		var pts := _footprint(elem)
		if pts.is_empty():
			continue
		if Geometry2D.is_point_in_polygon(pos, pts):
			return str(elem.get("id", ""))
		var center := _p(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		if center.distance_to(pos) <= tolerance + 8.0:
			return str(elem.get("id", ""))
	return ""
