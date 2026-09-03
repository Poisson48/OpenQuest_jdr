extends Control
class_name MapEditorMinimap

## Mini-carte : vue d'ensemble cliquable avec rectangle du viewport courant.

signal jump_requested(grid_pos: Vector2)

var doc: MapEditDocument = null
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
}

func _ready() -> void:
	custom_minimum_size = Vector2(0, 140)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Mini-carte — clic pour recadrer la vue"

func set_context(p_engine: Control, p_doc: MapEditDocument) -> void:
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

	for elem_variant in doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if not doc.is_element_visible(elem):
			continue
		var kind := str(elem.get("kind", ""))
		var color: Color = KIND_COLORS.get(kind, Color(0.7, 0.7, 0.7))
		var pos := _grid_to_local(float(elem.get("x", 0.0)) + 0.5, float(elem.get("y", 0.0)) + 0.5)
		if kind == MapEditDocument.KIND_PLATFORM or kind == MapEditDocument.KIND_OVERLAY or kind == MapEditDocument.KIND_WALL:
			var top_left := _grid_to_local(
				float(elem.get("x", 0.0)) + 0.5 - float(elem.get("w", 1.0)) * 0.5,
				float(elem.get("y", 0.0)) + 0.5 - float(elem.get("h", 1.0)) * 0.5
			)
			var bottom_right := _grid_to_local(
				float(elem.get("x", 0.0)) + 0.5 + float(elem.get("w", 1.0)) * 0.5,
				float(elem.get("y", 0.0)) + 0.5 + float(elem.get("h", 1.0)) * 0.5
			)
			draw_rect(Rect2(top_left, bottom_right - top_left), Color(color, 0.5), true)
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

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			jump_requested.emit(_local_to_grid(mb.position))
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			jump_requested.emit(_local_to_grid(motion.position))
			accept_event()
