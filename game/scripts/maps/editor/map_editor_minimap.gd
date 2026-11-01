extends Control
class_name MapEditorMinimap

const DocumentScript := preload("res://scripts/maps/editor/map_edit_document.gd")

## Mini-carte : vue d'ensemble cliquable avec rectangle du viewport courant.

signal jump_requested(grid_pos: Vector2)

var doc = null
var engine: Control = null

const KIND_COLORS := {
	"token": Color(0.35, 0.75, 1.0),
	"marker": Color(1.0, 0.78, 0.3),
	"effect": Color(1.0, 0.45, 0.25),
	"zone": Color(0.78, 0.45, 1.0),
	"platform": Color(0.6, 0.52, 0.4),
	"wall": Color(0.85, 0.82, 0.75),
	"note": Color(0.5, 0.9, 0.6),
	"light": Color(1.0, 0.9, 0.5),
	"link": Color(0.4, 0.85, 0.9),
	"mesh": Color(0.72, 0.55, 0.36, 0.9),
	"prop": Color(0.55, 0.78, 0.45, 0.9),
	"area": Color(0.55, 0.78, 0.95),
}

## Case survolée par la souris, pour un retour visuel avant le clic.
var _hover_cell: Vector2 = Vector2(-1, -1)

func _ready() -> void:
	custom_minimum_size = Vector2(0, 140)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Mini-carte — clic pour recadrer la vue · molette sur la carte pour zoomer"
	mouse_exited.connect(func():
		if _hover_cell != Vector2(-1, -1):
			_hover_cell = Vector2(-1, -1)
			queue_redraw()
	)

func set_preferred_height(h: float) -> void:
	custom_minimum_size = Vector2(0, h)
	queue_redraw()

func set_context(p_engine: Control, p_doc) -> void:
	engine = p_engine
	doc = p_doc
	queue_redraw()

func _map_size() -> Vector2:
	if doc == null:
		return Vector2(16, 12)
	return Vector2(
		maxf(1.0, float(doc.map_data.get("width", 16))),
		maxf(1.0, float(doc.map_data.get("height", 12)))
	)

## Rectangle de dessin de la carte, conservant les proportions.
func _fit_rect() -> Rect2:
	var map_size := _map_size()
	var avail := size - Vector2(8, 8)
	if avail.x <= 0.0 or avail.y <= 0.0:
		return Rect2(Vector2(4, 4), Vector2(1, 1))
	var scale := minf(avail.x / map_size.x, avail.y / map_size.y)
	var draw_size := map_size * scale
	return Rect2((size - draw_size) * 0.5, draw_size)

func _grid_to_local(gx: float, gy: float) -> Vector2:
	var rect := _fit_rect()
	var map_size := _map_size()
	return rect.position + Vector2(gx / map_size.x, gy / map_size.y) * rect.size

func _local_to_grid(pos: Vector2) -> Vector2:
	var rect := _fit_rect()
	var map_size := _map_size()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2.ZERO
	return (pos - rect.position) / rect.size * map_size

func _draw() -> void:
	var rect := _fit_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.05, 0.08, 0.9), true)
	draw_rect(rect, Color(0.16, 0.14, 0.2, 1.0), true)
	draw_rect(rect, Color(0.45, 0.4, 0.35, 0.8), false, 1.0)
	if doc == null:
		return
	_draw_ground_preview(rect)

	for elem_variant in doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if not doc.is_element_visible(elem):
			continue
		var kind := str(elem.get("kind", ""))
		var color: Color = KIND_COLORS.get(kind, Color(0.7, 0.7, 0.7))
		var pos := _grid_to_local(float(elem.get("x", 0.0)) + 0.5, float(elem.get("y", 0.0)) + 0.5)
		if kind in [
			DocumentScript.KIND_PLATFORM, DocumentScript.KIND_OVERLAY, DocumentScript.KIND_WALL,
			DocumentScript.KIND_MESH, DocumentScript.KIND_PROP,
		]:
			draw_rect(_element_rect_local(elem), Color(color, 0.55 if kind != DocumentScript.KIND_MESH else 0.7), true)
		elif kind == DocumentScript.KIND_AREA:
			draw_rect(_element_rect_local(elem), Color(color, 0.85), false, 1.0)
		else:
			draw_circle(pos, 2.5, color)
		if doc.is_selected(str(elem.get("id", ""))):
			draw_circle(pos, 4.5, Color(1.0, 0.85, 0.3, 0.85))

	if engine and engine.has_method("visible_grid_rect"):
		var view: Rect2 = engine.visible_grid_rect()
		if view.size != Vector2.ZERO:
			var a := _grid_to_local(view.position.x, view.position.y)
			var b := _grid_to_local(view.end.x, view.end.y)
			draw_rect(Rect2(a, b - a), Color(1.0, 1.0, 1.0, 0.85), false, 1.5)

	_draw_hover_cell(rect)
	_draw_empty_hint()
	_draw_help_text()

## Rectangle local d'un élément à empreinte rectangulaire (bâtiments, murs…).
func _element_rect_local(elem: Dictionary) -> Rect2:
	var top_left := _grid_to_local(
		float(elem.get("x", 0.0)) + 0.5 - float(elem.get("w", 1.0)) * 0.5,
		float(elem.get("y", 0.0)) + 0.5 - float(elem.get("h", 1.0)) * 0.5
	)
	var bottom_right := _grid_to_local(
		float(elem.get("x", 0.0)) + 0.5 + float(elem.get("w", 1.0)) * 0.5,
		float(elem.get("y", 0.0)) + 0.5 + float(elem.get("h", 1.0)) * 0.5
	)
	return Rect2(top_left, bottom_right - top_left)

## Met en évidence la case sous le curseur (retour avant le clic de recentrage).
func _draw_hover_cell(rect: Rect2) -> void:
	if _hover_cell == Vector2(-1, -1) or doc == null:
		return
	var map_size := _map_size()
	var cell := Vector2(rect.size.x / map_size.x, rect.size.y / map_size.y)
	var gx := clampi(int(floor(_hover_cell.x)), 0, int(map_size.x) - 1)
	var gy := clampi(int(floor(_hover_cell.y)), 0, int(map_size.y) - 1)
	var cell_rect := Rect2(_grid_to_local(float(gx), float(gy)), cell)
	draw_rect(cell_rect, Color(1.0, 1.0, 1.0, 0.18), true)
	draw_rect(cell_rect, Color(1.0, 0.92, 0.65, 0.65), false, 1.0)

## Aide discrète quand il n'y a encore rien sur la carte.
func _draw_empty_hint() -> void:
	if doc == null or not doc.elements_sorted().is_empty():
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var text := "Vide — cliquez pour centrer la vue"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, size.y * 0.5 + 4.0),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.66, 0.56, 0.9))

func _draw_help_text() -> void:
	if size.y < 84.0 or size.x < 150.0:
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var text := "Clic : centrer la vue"
	draw_string(font, Vector2(8.0, size.y - 6.0),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.72, 0.66, 0.56, 0.8))

## Aperçu du sol : matières peintes (herbe/terre/pierre/neige/sable) et relief.
func _draw_ground_preview(rect: Rect2) -> void:
	var size_cells: Vector2i = doc.terrain_size()
	if size_cells.x <= 0 or size_cells.y <= 0:
		return
	var cell_px := rect.size.x / float(size_cells.x)
	if cell_px < 1.0:
		return
	var mats: Array = doc.terrain_materials()
	var has_mats := not mats.is_empty()
	var has_relief: bool = doc.has_terrain_relief()
	if not has_mats and not has_relief:
		return
	for cy in range(size_cells.y):
		for cx in range(size_cells.x):
			var color := Color(0.33, 0.45, 0.25)
			if has_mats:
				var idx: int = cy * size_cells.x + cx
				if idx < mats.size():
					match int(mats[idx]):
						1:
							color = Color(0.46, 0.36, 0.25)
						2:
							color = Color(0.55, 0.52, 0.46)
						3:
							color = Color(0.88, 0.91, 0.96)
						4:
							color = Color(0.86, 0.76, 0.56)
			if has_relief:
				var h: float = doc.terrain_height(cx, cy)
				if h > 0.0:
					color = color.lightened(clampf(h * 0.12, 0.0, 0.4))
				elif h < 0.0:
					color = color.darkened(clampf(-h * 0.12, 0.0, 0.4))
			draw_rect(Rect2(
				rect.position + Vector2(cx, cy) * cell_px,
				Vector2(cell_px, cell_px) * 1.02), color, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_hover_cell = _local_to_grid(mb.position)
			queue_redraw()
			jump_requested.emit(_hover_cell)
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_hover_cell = _local_to_grid(motion.position)
		queue_redraw()
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			jump_requested.emit(_hover_cell)
			accept_event()
