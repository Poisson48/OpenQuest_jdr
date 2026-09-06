extends Control
class_name MapAreasOverlay

## Callouts des lieux en session (hors éditeur) : emprise + cartouche relié,
## portés depuis `MapEditorOverlay._draw_areas` pour le mode exploration.

var engine: Control = null
var map_data: Dictionary = {}
var hovered_id: String = ""

const COL_AREA := Color(0.55, 0.78, 0.95, 0.75)
const COL_AREA_LINKED := Color(0.95, 0.78, 0.35, 0.95)
const COL_HOVER_FILL := Color(0.95, 0.88, 0.45, 0.12)
const COL_CALLOUT_BG := Color(0.96, 0.92, 0.80, 0.94)
const COL_CALLOUT_TEXT := Color(0.16, 0.12, 0.08)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func configure(p_engine: Control, p_map: Dictionary) -> void:
	engine = p_engine
	map_data = p_map
	hovered_id = ""
	queue_redraw()

func set_hovered(area_id: String) -> void:
	if hovered_id == area_id:
		return
	hovered_id = area_id
	queue_redraw()

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
	var areas = map_data.get("areas", [])
	if not areas is Array or (areas as Array).is_empty():
		return
	var font := get_theme_default_font()
	for area_variant in areas:
		if not area_variant is Dictionary:
			continue
		var area: Dictionary = area_variant
		if bool(area.get("hidden", false)):
			continue
		var aid := str(area.get("id", ""))
		var has_child := not str(area.get("targetMapId", "")).is_empty()
		var outline := COL_AREA_LINKED if has_child else COL_AREA
		var highlighted := aid == hovered_id
		if highlighted:
			outline = outline.lightened(0.15)
		var center := Vector2(float(area.get("x", 0.0)), float(area.get("y", 0.0)))
		var hw := float(area.get("w", 2.0)) * 0.5
		var hh := float(area.get("h", 2.0)) * 0.5

		if str(area.get("shape", "rect")) == "circle":
			var radius_px := _p(center.x + hw, center.y).distance_to(_p(center.x, center.y))
			if highlighted:
				draw_circle(_p(center.x, center.y), radius_px, COL_HOVER_FILL)
			draw_arc(_p(center.x, center.y), radius_px, 0.0, TAU, 48, outline, 2.0 if highlighted else 1.5, true)
		else:
			var pts := PackedVector2Array([
				_p(center.x - hw, center.y - hh),
				_p(center.x + hw, center.y - hh),
				_p(center.x + hw, center.y + hh),
				_p(center.x - hw, center.y + hh),
			])
			draw_colored_polygon(pts, COL_HOVER_FILL if highlighted else Color(outline.r, outline.g, outline.b, 0.07))
			draw_polyline(_closed(pts), outline, 2.0 if highlighted else 1.5, true)

		if font == null or not bool(area.get("showCallout", true)):
			continue
		var label := str(area.get("label", "Lieu"))
		if label.is_empty():
			continue
		var offset: Dictionary = area.get("labelOffset", {}) if area.get("labelOffset") is Dictionary else {}
		var anchor := center + Vector2(
			float(offset.get("x", 0.0)),
			float(offset.get("y", -(hh + 0.8)))
		)
		var icon := ""
		if Engine.has_singleton("MapData") == false:
			# Autoload présent en jeu ; en tests --script on lit icon/category à la main.
			pass
		icon = str(area.get("icon", "")).strip_edges()
		if icon.is_empty():
			var cat := str(area.get("category", "building"))
			match cat:
				"shop": icon = "🏪"
				"poi": icon = "⭐"
				"nature": icon = "🌳"
				"road": icon = "🛤"
				_: icon = "🏠"
		# Préférer l'API MapData si l'autoload est disponible.
		var md := engine.get_tree().root.get_node_or_null("MapData") if engine.get_tree() else null
		if md != null and md.has_method("area_icon"):
			icon = str(md.area_icon(area))
		_draw_callout(font, _p(anchor.x, anchor.y), _p(center.x, center.y),
			"%s %s" % [icon, label], has_child or highlighted)

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
