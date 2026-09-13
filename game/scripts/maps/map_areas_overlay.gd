extends Control
class_name MapAreasOverlay

## Callouts des lieux / zones en session (hors éditeur).
## En plein jeu : rien n'est peint tant que le curseur ne survole pas
## l'emprise. Au survol : contour + remplissage + cartouche du lieu (ou de
## la zone d'effet) sous la souris.

var engine: Control = null
var map_data: Dictionary = {}
var play_zones: Array = []
var hovered_id: String = ""
var hovered_zone: Dictionary = {}

const COL_AREA := Color(0.55, 0.78, 0.95, 0.92)
const COL_AREA_LINKED := Color(0.95, 0.78, 0.35, 0.98)
const COL_HOVER_FILL := Color(0.95, 0.88, 0.45, 0.20)
const COL_ZONE := Color(0.82, 0.62, 0.22, 0.95)
const COL_CALLOUT_BG := Color(0.96, 0.92, 0.80, 0.96)
const COL_CALLOUT_TEXT := Color(0.16, 0.12, 0.08)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func configure(p_engine: Control, p_map: Dictionary, p_zones: Array = []) -> void:
	engine = p_engine
	map_data = p_map
	play_zones = p_zones
	hovered_id = ""
	hovered_zone = {}
	queue_redraw()

func set_hovered(area_id: String) -> void:
	if hovered_id == area_id:
		return
	hovered_id = area_id
	queue_redraw()

func set_hovered_zone(zone: Dictionary) -> void:
	var nid := str(zone.get("id", ""))
	if nid == str(hovered_zone.get("id", "")):
		return
	hovered_zone = zone.duplicate(true) if not zone.is_empty() else {}
	queue_redraw()

## IDs actuellement peints (tests + debug). Vide hors survol.
func painted_ids() -> PackedStringArray:
	var out := PackedStringArray()
	if paints_area(hovered_id):
		out.append(hovered_id)
	var zid := str(hovered_zone.get("id", ""))
	if paints_zone(zid):
		out.append(zid)
	return out

func paints_area(area_id: String) -> bool:
	return not area_id.is_empty() and area_id == hovered_id and not _area_by_id(area_id).is_empty()

func paints_zone(zone_id: String) -> bool:
	return not zone_id.is_empty() and zone_id == str(hovered_zone.get("id", ""))

func _area_by_id(area_id: String) -> Dictionary:
	if area_id.is_empty() or map_data.is_empty():
		return {}
	for area_variant in map_data.get("areas", []):
		if not area_variant is Dictionary:
			continue
		var area: Dictionary = area_variant
		if str(area.get("id", "")) != area_id:
			continue
		if bool(area.get("hidden", false)):
			return {}
		return area
	return {}

func _p(gx: float, gy: float, height: float = 0.0) -> Vector2:
	if engine == null or not engine.has_method("grid_to_screen"):
		return Vector2.ZERO
	return engine.grid_to_screen(gx, gy, height)

static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(points)
	if out.size() > 0:
		out.append(out[0])
	return out

func _draw() -> void:
	if engine == null or map_data.is_empty():
		return
	var font := get_theme_default_font()
	_draw_hovered_area(font)
	_draw_hovered_play_zone(font)

func _draw_hovered_area(font: Font) -> void:
	var area := _area_by_id(hovered_id)
	if area.is_empty():
		return
	var has_child := not str(area.get("targetMapId", "")).is_empty()
	var outline := COL_AREA_LINKED if has_child else COL_AREA
	var center := Vector2(float(area.get("x", 0.0)), float(area.get("y", 0.0)))
	var hw := float(area.get("w", 2.0)) * 0.5
	var hh := float(area.get("h", 2.0)) * 0.5
	_draw_footprint(center, hw, hh, str(area.get("shape", "rect")), outline)
	var label := str(area.get("label", "Lieu")).strip_edges()
	if font == null or label.is_empty():
		return
	var offset: Dictionary = area.get("labelOffset", {}) if area.get("labelOffset") is Dictionary else {}
	var anchor := center + Vector2(
		float(offset.get("x", 0.0)),
		float(offset.get("y", -(hh + 0.8)))
	)
	var icon := _area_icon(area)
	_draw_callout(font, _p(anchor.x, anchor.y), _p(center.x, center.y),
		"%s %s" % [icon, label], has_child)

func _draw_hovered_play_zone(font: Font) -> void:
	if hovered_zone.is_empty():
		return
	var center := Vector2(float(hovered_zone.get("x", 0.0)), float(hovered_zone.get("y", 0.0)))
	var hw := float(hovered_zone.get("w", hovered_zone.get("width", hovered_zone.get("radius", 1.5) * 2.0))) * 0.5
	var hh := float(hovered_zone.get("h", hovered_zone.get("height", hovered_zone.get("radius", 1.5) * 2.0))) * 0.5
	if str(hovered_zone.get("shape", "circle")) == "circle":
		var radius := float(hovered_zone.get("radius", maxf(hw, hh)))
		hw = radius
		hh = radius
	var col := Color.html(str(hovered_zone.get("color", "#c9a227")))
	col.a = 0.95
	_draw_footprint(center, hw, hh, str(hovered_zone.get("shape", "circle")), col)
	var label := str(hovered_zone.get("label", "")).strip_edges()
	if label.is_empty():
		label = "Zone"
	if font == null:
		return
	var anchor := center + Vector2(0.0, -(hh + 0.7))
	_draw_callout(font, _p(anchor.x, anchor.y), _p(center.x, center.y), "⭕ %s" % label, false)

func _draw_footprint(center: Vector2, hw: float, hh: float, shape: String, outline: Color) -> void:
	if shape == "circle":
		var radius_px := _p(center.x + hw, center.y).distance_to(_p(center.x, center.y))
		draw_circle(_p(center.x, center.y), radius_px, COL_HOVER_FILL)
		draw_arc(_p(center.x, center.y), radius_px, 0.0, TAU, 48, outline, 2.6, true)
		return
	var pts := PackedVector2Array([
		_p(center.x - hw, center.y - hh),
		_p(center.x + hw, center.y - hh),
		_p(center.x + hw, center.y + hh),
		_p(center.x - hw, center.y + hh),
	])
	draw_colored_polygon(pts, COL_HOVER_FILL)
	draw_polyline(_closed(pts), outline, 2.6, true)

func _area_icon(area: Dictionary) -> String:
	var icon := str(area.get("icon", "")).strip_edges()
	if icon.is_empty():
		var cat := str(area.get("category", "building"))
		match cat:
			"shop": icon = "🏪"
			"poi": icon = "⭐"
			"nature": icon = "🌳"
			"road": icon = "🛤"
			_: icon = "🏠"
	if engine == null or engine.get_tree() == null:
		return icon
	var md := engine.get_tree().root.get_node_or_null("MapData")
	if md != null and md.has_method("area_icon"):
		return str(md.area_icon(area))
	return icon

func _draw_callout(font: Font, at: Vector2, target: Vector2, text: String, highlighted: bool) -> void:
	var font_size := 14
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var padding := Vector2(10, 6)
	var box := Rect2(at - text_size * 0.5 - padding, text_size + padding * 2.0)

	draw_line(target, at, Color(0.18, 0.14, 0.10, 0.80), 1.8, true)
	draw_rect(box.grow(1.5), Color(0.18, 0.14, 0.10, 0.90), true)
	draw_rect(box, COL_CALLOUT_BG, true)
	draw_rect(box, COL_AREA_LINKED if highlighted else COL_AREA, false, 1.6)
	draw_string(font, Vector2(box.position.x + padding.x, box.position.y + padding.y + text_size.y * 0.8),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_CALLOUT_TEXT)
	if highlighted:
		draw_string(font, Vector2(box.end.x + 3.0, box.position.y + padding.y + text_size.y * 0.8),
			"🔍", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
