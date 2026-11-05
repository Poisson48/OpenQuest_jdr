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
	var icon_disabled := Color("#4A575D")
	var tooltip_bg := Color("#0F1417")

	t.set_color("font_color", "Label", text)
	t.set_color("font_color", "Button", text)
	t.set_color("font_hover_color", "Button", text)
	t.set_color("font_pressed_color", "Button", accent)
	t.set_color("font_disabled_color", "Button", muted)
	t.set_color("icon_disabled_color", "Button", icon_disabled)

	# Panels
	t.set_stylebox("panel", "PanelContainer", _panel(panel, border, 8))
	t.set_stylebox("panel", "Panel", _panel(panel, border, 8))

	# Boutons
	t.set_stylebox("normal", "Button", _btn(surface, border, 6))
	t.set_stylebox("hover", "Button", _btn(hover, accent, 6))
	t.set_stylebox("pressed", "Button", _btn(selection, accent, 6))
	t.set_stylebox("disabled", "Button", _btn(bg, border, 6))
	t.set_stylebox("focus", "Button", _focus_ring(accent, 6))

	# Cases à cocher
	t.set_stylebox("normal", "CheckBox", _field(field, border, 5))
	t.set_stylebox("hover", "CheckBox", _field(field, border, 5))
	t.set_stylebox("pressed", "CheckBox", _field(field, border, 5))

	# Curseurs
	t.set_stylebox("slider", "HSlider", _rail(field, 4.0, true))
	t.set_stylebox("grabber_area", "HSlider", _rail(accent, 4.0, true))
	t.set_stylebox("grabber", "HSlider", _grabber_disc(text, 14.0))
	t.set_stylebox("slider", "VSlider", _rail(field, 4.0, false))
	t.set_stylebox("grabber_area", "VSlider", _rail(accent, 4.0, false))
	t.set_stylebox("grabber", "VSlider", _grabber_disc(text, 14.0))

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
	t.set_stylebox("grabber", "VScrollBar", _scroll_handle(border, 4))
	t.set_stylebox("grabber", "HScrollBar", _scroll_handle(border, 4))

	# Tooltip
	t.set_stylebox("panel", "TooltipPanel", _panel(tooltip_bg, border, 6))
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


static func _focus_ring(accent: Color, radius: int) -> StyleBoxFlat:
	# Anneau de focus jade : bordure 2px + marge d'expansion 2, fond transparent.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.set_expand_margin_all(2.0)
	return sb


static func _scroll_handle(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(2.0)
	return sb


static func _rail(bg: Color, thickness: float, horizontal: bool) -> StyleBoxFlat:
	# Rail / aire de curseur : épaisseur 4px (via les content margins).
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(thickness / 2.0))
	if horizontal:
		sb.content_margin_left = 0.0
		sb.content_margin_right = 0.0
		sb.content_margin_top = thickness / 2.0
		sb.content_margin_bottom = thickness / 2.0
	else:
		sb.content_margin_left = thickness / 2.0
		sb.content_margin_right = thickness / 2.0
		sb.content_margin_top = 0.0
		sb.content_margin_bottom = 0.0
	return sb


static func _grabber_disc(color: Color, size: float) -> StyleBoxFlat:
	# Poignée de curseur ronde 14px.
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(size / 2.0))
	sb.set_content_margin_all(size / 2.0)
	return sb


static func _separator(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_content_margin_all(0.0)
	return sb
