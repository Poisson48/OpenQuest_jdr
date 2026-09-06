extends RefCounted
class_name SessionStyle

## Fabriques de contrôles pour la session.
##
## Tout passe par les variantes de thème (`openquest_theme.tres`) : aucun
## panneau ne code en dur une couleur ou une taille de police. Si la charte
## change, elle change ici et dans le thème, pas dans dix fichiers.

const GAP_TIGHT := 4
const GAP_ROW := 6
const GAP_PANEL := 10
const GAP_SECTION := 14

const ROW_HEIGHT := 32
const CONTROL_HEIGHT := 34
const TOOL_HEIGHT := 34
const TOOL_MIN_WIDTH := 38

static func heading(text: String) -> Label:
	var lbl := Label.new()
	lbl.theme_type_variation = &"HeadingLabel"
	lbl.text = text
	lbl.clip_text = true
	return lbl

static func section(text: String) -> Label:
	var lbl := Label.new()
	lbl.theme_type_variation = &"SectionLabel"
	lbl.text = text
	lbl.clip_text = true
	return lbl

static func caption(text: String = "") -> Label:
	var lbl := Label.new()
	lbl.theme_type_variation = &"CaptionLabel"
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl

static func badge(text: String, color: Color = ThemeColors.ACCENT) -> Label:
	var lbl := Label.new()
	lbl.theme_type_variation = &"BadgeLabel"
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

static func button(text: String, tooltip: String = "", variation: StringName = &"") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	if variation != &"":
		btn.theme_type_variation = variation
	return btn

static func ghost_button(text: String, tooltip: String = "") -> Button:
	return button(text, tooltip, &"GhostButton")

static func accent_button(text: String, tooltip: String = "") -> Button:
	return button(text, tooltip, &"AccentButton")

static func danger_button(text: String, tooltip: String = "") -> Button:
	return button(text, tooltip, &"DangerButton")

## Bouton compact de barre d'outils. `glyph` reste court (1–3 signes) et le
## libellé complet vit dans l'infobulle.
static func tool_button(glyph: String, tooltip: String, toggle: bool = true) -> Button:
	var btn := Button.new()
	btn.theme_type_variation = &"ToolButton"
	btn.text = glyph
	btn.tooltip_text = tooltip
	btn.toggle_mode = toggle
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(TOOL_MIN_WIDTH, TOOL_HEIGHT)
	return btn

static func dock_panel(expand: bool = true) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DockPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_SHRINK_BEGIN
	panel.clip_contents = true
	return panel

static func inset_panel(expand: bool = true) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InsetPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_SHRINK_BEGIN
	return panel

static func toolbar_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ToolbarPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return panel

static func column(separation: int = GAP_ROW) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box

static func row(separation: int = GAP_ROW) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box

static func spacer() -> Control:
	var ctl := Control.new()
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ctl

static func line_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return edit

static func text_edit(placeholder: String, height: int = 64) -> TextEdit:
	var edit := TextEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, height)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return edit

static func option_button(tooltip: String = "") -> OptionButton:
	var opt := OptionButton.new()
	opt.tooltip_text = tooltip
	opt.clip_text = true
	opt.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return opt

static func scroll(vertical: bool = true) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if vertical:
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		sc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return sc

## Cadre plat sans bordure, utilisé pour l'affichage carte plein cadre.
static func flat_stylebox(color: Color, radius: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_border_width_all(0)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box
