extends RefCounted
class_name CartographerTheme

## Thème « Dark Cartographer » (refonte UI v2) — palette exacte validée par la
## direction artistique. Construit un Theme Godot à appliquer sur la racine de
## l'éditeur pour obtenir la palette sombre + accent jade sans toucher au .tres.

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13

	# Palette
	var bg := Color("#181E22")
	var panel := Color("#222A2F")
	var surface := Color("#2C363C")
	var hover := Color("#36434A")
	var border := Color("#414E54")
	var field := Color("#1D2529")
	var text := Color("#E1E8E8")
	var secondary := Color("#A1AFB2")
	var muted := Color("#718087")
	var accent := Color("#55D6BE")
	var selection := Color("#263C3A")

	t.set_color("font_color", "Label", text)
	t.set_color("font_color", "Button", text)
	t.set_color("font_hover_color", "Button", text)
	t.set_color("font_pressed_color", "Button", accent)
	t.set_color("font_disabled_color", "Button", muted)

	# Panels
	t.set_stylebox("panel", "PanelContainer", _panel(panel, border, 8))
	t.set_stylebox("panel", "Panel", _panel(panel, border, 8))

	# Boutons
	t.set_stylebox("normal", "Button", _btn(surface, border, 6))
	t.set_stylebox("hover", "Button", _btn(hover, accent, 6))
	t.set_stylebox("pressed", "Button", _btn(selection, accent, 6))
	t.set_stylebox("disabled", "Button", _btn(bg, border, 6))
	t.set_stylebox("focus", "Button", _focus(accent, 6))

	# Champs
	t.set_stylebox("normal", "LineEdit", _field(field, border, 5))
	t.set_stylebox("focus", "LineEdit", _field(field, accent, 5))
	t.set_color("font_color", "LineEdit", text)

	# Onglets
	t.set_stylebox("tab_selected", "TabContainer", _btn(selection, accent, 6))
	t.set_stylebox("tab_unselected", "TabContainer", _btn(panel, border, 6))
	t.set_stylebox("tab_hovered", "TabContainer", _btn(hover, border, 6))
	t.set_color("font_selected_color", "TabContainer", accent)
	t.set_color("font_unselected_color", "TabContainer", secondary)

	# Séparateurs
	t.set_stylebox("separator", "HSeparator", _separator(border))
	t.set_stylebox("separator", "VSeparator", _separator(border))

	# Scrollbars (discretes)
	t.set_stylebox("scroll", "VScrollBar", _btn(surface, border, 4))
	t.set_stylebox("scroll", "HScrollBar", _btn(surface, border, 4))

	# Tooltip
	t.set_stylebox("panel", "TooltipPanel", _panel(panel, accent, 6))
	t.set_color("font_color", "TooltipLabel", text)

	return t


static func _panel(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb


static func _btn(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


static func _field(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb


static func _focus(accent: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	return sb


static func _separator(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_content_margin_all(0.0)
	return sb
