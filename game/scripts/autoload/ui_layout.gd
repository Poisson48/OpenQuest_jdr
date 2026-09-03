extends Node

## Conventions de mise en page partagées (marges, espacements, seuils responsive).

const MARGIN_SCREEN := 20
const MARGIN_SCREEN_TIGHT := 16
const SPACING_SECTION := 16
const SPACING_PANEL := 12
const SPACING_ROW := 8
const MIN_BUTTON_HEIGHT := 44
const MIN_CTA_HEIGHT := 48

const BREAKPOINT_NARROW := 960
const BREAKPOINT_COMPACT := 800
const DESIGN_RATIO := 1280.0 / 800.0
const WINDOW_CHROME := 72

func _ready() -> void:
	_fit_windowed_keep_ratio()

static func is_narrow_viewport() -> bool:
	return DisplayServer.window_get_size().x < BREAKPOINT_NARROW

static func is_compact_viewport() -> bool:
	return DisplayServer.window_get_size().x < BREAKPOINT_COMPACT

static func apply_full_rect(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL

static func apply_expand_fill(control: Control, horizontal: bool = true, vertical: bool = true) -> void:
	if horizontal:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if vertical:
		control.size_flags_vertical = Control.SIZE_EXPAND_FILL

static func center_modal(panel: Control, min_size: Vector2 = Vector2(440, 240)) -> void:
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = min_size
	var half := min_size * 0.5
	panel.offset_left = -half.x
	panel.offset_top = -half.y
	panel.offset_right = half.x
	panel.offset_bottom = half.y

func _fit_windowed_keep_ratio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if usable.size.x < 2 or usable.size.y < 2:
		return
	var max_w := maxi(800, usable.size.x - 24)
	var max_h := maxi(500, usable.size.y - WINDOW_CHROME)
	var height := max_h
	var width := int(round(float(height) * DESIGN_RATIO))
	if width > max_w:
		width = max_w
		height = int(round(float(width) / DESIGN_RATIO))
	DisplayServer.window_set_size(Vector2i(width, height))
	var pos := usable.position + Vector2i(
		maxi(0, (usable.size.x - width) / 2),
		maxi(8, (usable.size.y - height - WINDOW_CHROME) / 2)
	)
	DisplayServer.window_set_position(pos)
