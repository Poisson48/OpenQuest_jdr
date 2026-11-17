extends RefCounted
class_name CartographerTheme

## Thème « Dark Cartographer » — deux variantes de couleur pour la MÊME
## disposition d'interface :
##
##  - `or` (défaut) : chrome chaude brun/or de l'éditeur immersif historique ;
##  - `jade` : chrome ardoise froide, accent jade (le thème « cartographe »
##    d'origine, appliqué aussi à la chrome immersive).
##
## Le thème ne concerne **que l'interface** : la carte 3D garde ses propres
## réglages (preset qualité, lumière, ambiance) — changer de variante ne
## modifie pas une seule couleur de la carte.
##
## `build(immersive, variant)` produit le `Theme` Godot ; `palette(variant)` et
## `color(key)` donnent les couleurs aux composants qui dessinent eux-mêmes
## (chrome immersive, palettes flottantes, volants d'outils, menus).
## La variante courante est globale (`set_active_variant`) pour que tout le code
## d'interface la lise sans plomberie.

const VARIANT_OR := "or"
const VARIANT_JADE := "jade"
const VARIANT_ORDER := [VARIANT_OR, VARIANT_JADE]
const VARIANT_LABELS := {
	VARIANT_OR: "Cartographe Or",
	VARIANT_JADE: "Cartographe Jade",
}

## Palette active : l'éditeur la fixe au démarrage et à chaque changement.
static var _active_variant: String = VARIANT_OR

# ===========================================================================
# Palettes
# ===========================================================================

static func normalize_variant(variant: String) -> String:
	var value := variant.strip_edges().to_lower()
	if value in ["jade", "vert", "green", "teal"]:
		return VARIANT_JADE
	return VARIANT_OR

## Palette complète d'une variante (`""` = variante active).
static func palette(variant: String = "") -> Dictionary:
	var id := normalize_variant(variant if not variant.is_empty() else _active_variant)
	if id == VARIANT_JADE:
		# Palette « Dark Cartographer » documentée (docs/UI_DESIGN_CARTOGRAPHE.md).
		return {
			"bg": Color("#181e22"),
			"bg_deep": Color("#101518"),
			"panel": Color("#222a2f"),
			"panel_alpha": Color("#222a2ff5"),
			"surface": Color("#2c363c"),
			"surface_2": Color("#3a464d"),
			"header": Color("#1e2529"),
			"header_alpha": Color("#1e2529ef"),
			"dock": Color("#20282d"),
			"dock_alpha": Color("#20282df5"),
			"advanced_alpha": Color("#1b2226f5"),
			"button_accent_bg": Color("#2c363c"),
			"button_accent_border": Color("#55d6be"),
			"hover": Color("#36434a"),
			"hover_soft": Color("#2e383e"),
			"field": Color("#1d2529"),
			"border": Color("#414e54"),
			"border_soft": Color("#2f3a40"),
			"text": Color("#e1e8e8"),
			"secondary": Color("#a1afb2"),
			"muted": Color("#718087"),
			"disabled": Color("#4a575d"),
			"accent": Color("#55d6be"),
			"accent_light": Color("#8febe0"),
			"accent_soft": Color("#3fae99"),
			"accent_dim": Color(0.33, 0.84, 0.75, 0.16),
			"selection": Color("#263c3a"),
			"selection_soft": Color(0.15, 0.24, 0.23, 0.55),
			"danger": Color("#e2866b"),
			"danger_border": Color("#55352c"),
			"success": Color("#9fd49b"),
			"info": Color("#8fcbb6"),
			"brand_shadow": Color("#0e1418"),
			"note_text": Color("#bcd8ce"),
			"note_bg": Color(0.33, 0.84, 0.75, 0.07),
			"note_border": Color(0.33, 0.84, 0.75, 0.24),
			"tooltip_bg": Color("#0f1417"),
			"icon_disabled": Color("#4a575d"),
		}
	return {
		"bg": Color("#1a160f"),
		"bg_deep": Color("#14110b"),
		"panel": Color("#292218"),
		"panel_alpha": Color("#292218f5"),
		"surface": Color("#32291d"),
		"surface_2": Color("#3a2f21"),
		"header": Color("#241f17"),
		"header_alpha": Color("#241f17ef"),
		"dock": Color("#262016"),
		"dock_alpha": Color("#262016f5"),
		"advanced_alpha": Color("#231d15f5"),
		"button_accent_bg": Color("#39301d"),
		"button_accent_border": Color("#daaf56"),
		"hover": Color("#473923"),
		"hover_soft": Color("#2e2519"),
		"field": Color("#201a12"),
		"border": Color("#6b573a"),
		"border_soft": Color("#443723"),
		"text": Color("#f1e3cc"),
		"secondary": Color("#d2bd9e"),
		"muted": Color("#a59173"),
		"disabled": Color("#877758"),
		"accent": Color("#f2c46c"),
		"accent_light": Color("#f6d48f"),
		"accent_soft": Color("#daaf56"),
		"accent_dim": Color(0.949, 0.769, 0.424, 0.16),
		"selection": Color("#4a381c"),
		"selection_soft": Color(0.29, 0.22, 0.11, 0.55),
		"danger": Color("#e2866b"),
		"danger_border": Color("#5e3527"),
		"success": Color("#9fd49b"),
		"info": Color("#8fcbb6"),
		"brand_shadow": Color("#17130e"),
		"note_text": Color("#bcd8ce"),
		"note_bg": Color(0.56, 0.8, 0.71, 0.07),
		"note_border": Color(0.56, 0.8, 0.71, 0.24),
		"tooltip_bg": Color("#0f1417"),
		"icon_disabled": Color("#877758"),
	}

static func set_active_variant(variant: String) -> void:
	_active_variant = normalize_variant(variant)

static func active_variant() -> String:
	return _active_variant

static func active_palette() -> Dictionary:
	return palette(_active_variant)

## Couleur de la palette active (résout la variante sans plomberie).
static func color(key: String) -> Color:
	var pal := active_palette()
	return pal.get(key, Color.MAGENTA)

static func variant_label(variant: String) -> String:
	return str(VARIANT_LABELS.get(normalize_variant(variant), str(VARIANT_LABELS[VARIANT_OR])))

## Correspondance ancienne palette → nouvelle palette, par clé sémantique.
## Sert à re-colorer les surcharges locales déjà posées sur les nœuds
## (`add_theme_*_override`) quand on change de variante à chaud.
static func retheme_colors(from_variant: String, to_variant: String) -> Dictionary:
	var from := palette(from_variant)
	var to := palette(to_variant)
	var mapping: Dictionary = {}
	for key in from.keys():
		if not to.has(key):
			continue
		var old_color: Color = from[key]
		var new_color: Color = to[key]
		if old_color == new_color:
			continue
		if not mapping.has(old_color):
			mapping[old_color] = new_color
	return mapping

# ===========================================================================
# Construction du Theme Godot
# ===========================================================================

static func build(immersive: bool = false, variant: String = "") -> Theme:
	var resolved := normalize_variant(
		variant if not variant.is_empty() else (VARIANT_OR if immersive else VARIANT_JADE))
	var pal := palette(resolved)
	var t := Theme.new()
	t.default_font_size = 13

	if immersive:
		var ui_font := SystemFont.new()
		ui_font.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "DejaVu Sans"])
		t.default_font = ui_font

	# Palette (raccourcis lisibles dans le reste de la fonction)
	var bg: Color = pal["bg"]
	var panel: Color = pal["panel"]
	var surface: Color = pal["surface"]
	var hover: Color = pal["hover"]
	var border: Color = pal["border"]
	var field: Color = pal["field"]
	var text: Color = pal["text"]
	var secondary: Color = pal["secondary"]
	var muted: Color = pal["muted"]
	var accent: Color = pal["accent"]
	var accent_light: Color = pal["accent_light"]
	var selection: Color = pal["selection"]
	var icon_disabled: Color = pal["icon_disabled"]
	var tooltip_bg: Color = pal["tooltip_bg"]
	var danger: Color = pal["danger"]

	t.set_color("font_color", "Label", text)
	t.set_color("font_color", "Button", text)
	t.set_color("font_hover_color", "Button", text)
	t.set_color("font_pressed_color", "Button", accent)
	t.set_color("font_disabled_color", "Button", muted)
	t.set_color("icon_disabled_color", "Button", icon_disabled)
	t.set_color("icon_normal_color", "Button", secondary)
	t.set_color("icon_hover_color", "Button", text)
	t.set_color("icon_pressed_color", "Button", accent)
	t.set_color("icon_focus_color", "Button", accent)

	# Échelle typographique (§5) — tailles par usage.
	t.set_font_size("font_size", "Label", 13)
	t.set_font_size("font_size", "Button", 13)
	t.set_font_size("font_size", "LineEdit", 12)
	t.set_font_size("font_size", "OptionButton", 13)
	t.set_font_size("font_size", "SpinBox", 12)
	t.set_font_size("font_size", "TabContainer", 13)
	t.set_font_size("font_size", "TooltipLabel", 12)
	t.set_font_size("font_size", "PopupMenu", 13)

	# Panels
	t.set_stylebox("panel", "PanelContainer", _panel(panel, border, 8))
	t.set_stylebox("panel", "Panel", _panel(panel, border, 8))

	# Boutons
	t.set_stylebox("normal", "Button", _btn(surface, border, 6))
	t.set_stylebox("hover", "Button", _btn(hover, accent, 6))
	t.set_stylebox("pressed", "Button", _btn(selection, accent, 6))
	t.set_stylebox("disabled", "Button", _btn(bg, border, 6))
	t.set_stylebox("focus", "Button", _focus_ring(accent, 6))

	# Cases à cocher / boutons à cocher
	t.set_stylebox("normal", "CheckBox", _field(field, border, 5))
	t.set_stylebox("hover", "CheckBox", _field(field, border, 5))
	t.set_stylebox("pressed", "CheckBox", _field(field, border, 5))
	t.set_color("font_color", "CheckBox", text)
	t.set_color("font_hover_color", "CheckBox", text)
	t.set_color("font_pressed_color", "CheckBox", accent)
	t.set_color("font_disabled_color", "CheckBox", muted)
	t.set_color("font_color", "CheckButton", text)
	t.set_color("font_hover_color", "CheckButton", text)
	t.set_color("font_pressed_color", "CheckButton", accent)
	t.set_color("font_disabled_color", "CheckButton", muted)

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
	t.set_color("caret_color", "LineEdit", text)
	t.set_color("selection_color", "LineEdit", selection)
	t.set_color("font_color", "OptionButton", text)
	t.set_color("font_hover_color", "OptionButton", text)
	t.set_color("font_pressed_color", "OptionButton", accent)
	t.set_color("font_color", "SpinBox", text)
	t.set_color("font_color", "PopupMenu", text)
	t.set_color("font_hover_color", "PopupMenu", text)
	t.set_color("font_accelerator_color", "PopupMenu", muted)
	t.set_stylebox("panel", "PopupMenu", _panel(panel, border, 6))

	# Onglets
	t.set_stylebox("tab_selected", "TabContainer", _tab_underline(panel, accent, 2))
	t.set_stylebox("tab_unselected", "TabContainer", _tab_underline(Color(0, 0, 0, 0), border, 1))
	t.set_stylebox("tab_hovered", "TabContainer", _btn(hover, border, 6))
	t.set_color("font_selected_color", "TabContainer", accent)
	t.set_color("font_unselected_color", "TabContainer", secondary)

	# Séparateurs
	t.set_stylebox("separator", "HSeparator", _separator(border))
	t.set_stylebox("separator", "VSeparator", _separator(border))

	# Scrollbars (discrètes)
	t.set_stylebox("scroll", "VScrollBar", _btn(surface, border, 4))
	t.set_stylebox("scroll", "HScrollBar", _btn(surface, border, 4))
	t.set_stylebox("grabber", "VScrollBar", _scroll_handle(border, 4))
	t.set_stylebox("grabber", "HScrollBar", _scroll_handle(border, 4))

	# Tooltip
	t.set_stylebox("panel", "TooltipPanel", _panel(tooltip_bg, border, 6))
	t.set_color("font_color", "TooltipLabel", text)

	# Variations de libellés utilisées par les docks de l'éditeur : on les définit
	# ici (mêmes tailles que le thème projet, seules les couleurs suivent la
	# variante) pour que le dock « Carte / Biblio / Historique » et les panneaux
	# changent de palette avec le reste.
	t.set_type_variation("SectionLabel", "Label")
	t.set_color("font_color", "SectionLabel", secondary)
	t.set_font_size("font_size", "SectionLabel", 16)
	t.set_type_variation("CaptionLabel", "Label")
	t.set_color("font_color", "CaptionLabel", muted)
	t.set_font_size("font_size", "CaptionLabel", 16)
	t.set_type_variation("HeadingLabel", "Label")
	t.set_color("font_color", "HeadingLabel", accent_light)
	t.set_font_size("font_size", "HeadingLabel", 20)
	t.set_type_variation("GoldHeadingLabel", "Label")
	t.set_color("font_color", "GoldHeadingLabel", accent_light)
	t.set_font_size("font_size", "GoldHeadingLabel", 20)
	t.set_type_variation("DangerButton", "Button")
	t.set_color("font_color", "DangerButton", danger)
	t.set_color("font_hover_color", "DangerButton", danger.lightened(0.12))
	t.set_color("font_pressed_color", "DangerButton", danger)

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


static func _tab_underline(bg: Color, line: Color, line_width: int) -> StyleBoxFlat:
	# Onglet « souligné » : pas de cadre complet, uniquement une bordure basse.
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = line
	sb.set_border_width_all(0)
	sb.border_width_bottom = line_width
	sb.set_corner_radius_all(0)
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
