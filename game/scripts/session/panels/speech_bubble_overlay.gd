extends Control
class_name SpeechBubbleOverlay

## Bulles de dialogue ancrées sur la carte. Les clics traversent vers le moteur.

const LIFETIME_MS := 4200
const MAX_VISIBLE := 3
const BUBBLE_WIDTH := 220.0
const LIFT_CELLS := 0.85

var _queue: Array = []
var _active: Array = []
var _project: Callable = Callable()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 40

func set_projector(cb: Callable) -> void:
	_project = cb

func enqueue(speaker: String, text: String, grid: Vector2) -> void:
	var body := _plain_line(text)
	if speaker.is_empty() or body.is_empty():
		return
	for item_variant in _active:
		var item: Dictionary = item_variant
		if str(item.get("speaker", "")) == speaker:
			item["text"] = body
			item["grid"] = grid
			item["until"] = Time.get_ticks_msec() + LIFETIME_MS
			_paint_bubble(item)
			return
	_queue.append({
		"speaker": speaker,
		"text": body,
		"grid": grid,
	})
	_flush()

func clear() -> void:
	_queue.clear()
	for item_variant in _active:
		var item: Dictionary = item_variant
		var node: Node = item.get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	_active.clear()

func visible_count() -> int:
	return _active.size()

func queued_count() -> int:
	return _queue.size()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var kept: Array = []
	var dismissed := false
	for item_variant in _active:
		var item: Dictionary = item_variant
		if now >= int(item.get("until", 0)):
			var node: Node = item.get("node")
			if node != null and is_instance_valid(node):
				node.queue_free()
			dismissed = true
		else:
			kept.append(item)
	if dismissed:
		_active = kept
		_flush()
	_reposition()

func _flush() -> void:
	while _active.size() < MAX_VISIBLE and not _queue.is_empty():
		var next: Dictionary = _queue.pop_front()
		next["until"] = Time.get_ticks_msec() + LIFETIME_MS
		next["node"] = _make_bubble()
		_paint_bubble(next)
		add_child(next["node"])
		_active.append(next)
	_reposition()

func _make_bubble() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(120, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = ThemeColors.SURFACE_RAISED
	box.border_color = ThemeColors.LOG_NPC
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", box)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	var speaker := Label.new()
	speaker.name = "Speaker"
	speaker.theme_type_variation = &"BadgeLabel"
	speaker.add_theme_color_override("font_color", ThemeColors.LOG_NPC)
	speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speaker.autowrap_mode = TextServer.AUTOWRAP_OFF
	var line := Label.new()
	line.name = "Line"
	line.theme_type_variation = &"CaptionLabel"
	line.add_theme_color_override("font_color", ThemeColors.TEXT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(BUBBLE_WIDTH - 20.0, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(speaker)
	col.add_child(line)
	panel.add_child(col)
	return panel

func _paint_bubble(item: Dictionary) -> void:
	var panel: PanelContainer = item.get("node")
	if panel == null or not is_instance_valid(panel):
		return
	var speaker: Label = panel.get_node_or_null("Column/Speaker")
	var line: Label = panel.get_node_or_null("Column/Line")
	if speaker:
		speaker.text = str(item.get("speaker", "PNJ"))
	if line:
		line.text = str(item.get("text", ""))
	panel.reset_size()

func _reposition() -> void:
	if _project.is_null():
		return
	for item_variant in _active:
		var item: Dictionary = item_variant
		var panel: Control = item.get("node")
		if panel == null or not is_instance_valid(panel):
			continue
		var grid: Vector2 = item.get("grid", Vector2(-1, -1))
		var anchor: Vector2 = _project.call(grid)
		if anchor.x < -10000.0:
			panel.visible = false
			continue
		panel.visible = true
		var sz := panel.get_combined_minimum_size()
		if sz.x < 8.0:
			sz = Vector2(BUBBLE_WIDTH, 48)
		panel.size = sz
		var pos := Vector2(anchor.x - sz.x * 0.5, anchor.y - sz.y - 8.0)
		pos.x = clampf(pos.x, 4.0, maxf(4.0, size.x - sz.x - 4.0))
		pos.y = clampf(pos.y, 4.0, maxf(4.0, size.y - sz.y - 4.0))
		panel.position = pos

static func _plain_line(text: String) -> String:
	var body := text.strip_edges()
	if body.begins_with("«"):
		body = body.substr(1).strip_edges()
	if body.ends_with("»"):
		body = body.substr(0, body.length() - 1).strip_edges()
	return body
