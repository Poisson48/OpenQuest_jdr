extends Control
class_name SessionMinimap

## Mini-carte de la zone courante en session : sols, eau, objets et pions.
## Clic : recentre la caméra sur le point correspondant.

signal jump_requested(grid_pos: Vector2)

const PAD := 8.0
const TITLE_H := 18.0

var map_data: Dictionary = {}
var tokens: Array = []
var selected_token_id: String = ""
var _map_rect := Rect2()

func configure(p_map: Dictionary, p_tokens: Array, p_selected: String = "") -> void:
	map_data = p_map
	tokens = p_tokens
	selected_token_id = p_selected
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.045, 0.82), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.72, 0.42, 0.7), false, 1.0)
	var font := get_theme_default_font()
	var title := "Zone"
	if not map_data.is_empty():
		title = str(map_data.get("title", "Zone"))
	draw_string(font, Vector2(PAD, 14), title, HORIZONTAL_ALIGNMENT_LEFT,
		size.x - PAD * 2.0, 11, Color(1.0, 0.93, 0.75))
	if map_data.is_empty():
		return
	var w := int(map_data.get("width", 0))
	var h := int(map_data.get("height", 0))
	if w <= 0 or h <= 0:
		return
	var area := Rect2(PAD, TITLE_H + 4.0, size.x - PAD * 2.0, size.y - TITLE_H - 12.0)
	var px := minf(area.size.x / float(w), area.size.y / float(h))
	var draw_size := Vector2(w, h) * px
	_map_rect = Rect2(area.position + (area.size - draw_size) * 0.5, draw_size)
	var materials = map_data.get("terrainMaterials", [])
	var heights = map_data.get("terrainHeights", [])
	var water := float(map_data.get("waterLevel", -1.0))
	var md = get_node_or_null("/root/MapData")
	for cy in range(h):
		for cx in range(w):
			var idx := cy * w + cx
			var material := 0
			if materials is Array and idx < (materials as Array).size():
				material = int((materials as Array)[idx])
			var color: Color = Color(0.33, 0.45, 0.25)
			if md != null and md.has_method("terrain_material_color"):
				color = md.terrain_material_color(material)
			if heights is Array and idx < (heights as Array).size() and water > -1.0:
				if float((heights as Array)[idx]) < water - 0.01:
					color = Color(0.20, 0.42, 0.60)
			draw_rect(Rect2(_map_rect.position + Vector2(cx, cy) * px, Vector2(px, px) + Vector2(0.5, 0.5)), color, true)
	var meshes = map_data.get("meshes", [])
	if meshes is Array:
		for mesh_variant in meshes:
			if not mesh_variant is Dictionary:
				continue
			var mesh: Dictionary = mesh_variant
			var mpos := _map_rect.position + Vector2(float(mesh.get("x", 0.0)) + 0.5, float(mesh.get("y", 0.0)) + 0.5) * px
			draw_circle(mpos, clampf(px * 0.55, 1.0, 2.5), Color(0.14, 0.10, 0.07, 0.9))
	for token_variant in tokens:
		if not token_variant is Dictionary:
			continue
		var token: Dictionary = token_variant
		var tpos := _map_rect.position + Vector2(float(token.get("x", 0.0)) + 0.5, float(token.get("y", 0.0)) + 0.5) * px
		var token_color := Color(0.95, 0.82, 0.45)
		var raw_color := str(token.get("color", ""))
		if not raw_color.is_empty() and Color.html_is_valid(raw_color):
			token_color = Color.html(raw_color)
		elif str(token.get("kind", "")) != "member":
			token_color = Color(0.9, 0.35, 0.28)
		draw_circle(tpos, clampf(px * 0.8, 2.0, 5.0), Color(0.0, 0.0, 0.0, 0.7))
		draw_circle(tpos, clampf(px * 0.65, 1.5, 4.0), token_color)
		if str(token.get("id", "")) == selected_token_id:
			draw_arc(tpos, clampf(px * 1.1, 3.5, 7.0), 0.0, TAU, 20, Color(1.0, 1.0, 1.0, 0.9), 1.5, true)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _map_rect.size.x <= 0.0 or not _map_rect.has_point(mb.position):
		return
	var w := maxi(1, int(map_data.get("width", 1)))
	var h := maxi(1, int(map_data.get("height", 1)))
	var local := (mb.position - _map_rect.position) / _map_rect.size
	jump_requested.emit(Vector2(local.x * w, local.y * h))
	accept_event()
