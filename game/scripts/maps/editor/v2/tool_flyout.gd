class_name MapEditorToolFlyout
extends PopupPanel

## Volant d'outils du mode carte (refonte UI v2) : popup 100 % autonome
## (aucun autoload, aucune scène externe, toute l'interface est construite en
## code). Affiche des outils groupés par catégorie sous forme de tuiles 62x56
## dans une grille 4 colonnes, filtrables par libellé de façon insensible aux
## accents.
##
## API :
##   signal tool_chosen(tool_id: String, keep_open: bool)
##   func setup(categories: Dictionary) -> void   # {catégorie: [{id, icon, label}]}
##   func open_at(pos: Vector2) -> void
##   func close_now() -> void
##
## Interactions : clic sur une tuile -> tool_chosen(id, false) puis fermeture ;
## Maj+clic -> tool_chosen(id, true) sans fermer ; Entrée -> arme le premier
## outil visible ; Échap -> fermeture.

signal tool_chosen(tool_id: String, keep_open: bool)

const WIDTH := 276
const TILE_SIZE := Vector2(62, 56)
const GRID_COLUMNS := 4
const CONTENT_MARGIN := 8.0
const ICON_SIZE := 20
const LABEL_FONT_SIZE := 11
const FOOTER_FONT_SIZE := 10

const BG_COLOR := Color("#222A2F")
const BORDER_COLOR := Color("#414E54")
const CORNER_RADIUS := 8

const FILTER_PLACEHOLDER := "Filtrer…"
const FOOTER_TEXT := "Entrée : armer · Maj+clic : garder ouvert · Échap : fermer"

const _ELLIPSIS := "…"
const _TEXT_COLOR := Color(0.82, 0.87, 0.9)
const _DIM_TEXT_COLOR := Color(0.55, 0.63, 0.68)
const _TILE_BG := Color(1, 1, 1, 0.03)
const _TILE_BG_HOVER := Color(1, 1, 1, 0.1)
const _TILE_BG_PRESSED := Color(0.31, 0.71, 0.86, 0.25)
const _TILE_BORDER := Color(1, 1, 1, 0.06)
const _ACCENT_BORDER := Color(0.42, 0.62, 0.72, 0.9)

## Normalisation des accents pour le filtre (après passage en minuscules).
const _ACCENT_MAP := {
	"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a",
	"è": "e", "é": "e", "ê": "e", "ë": "e",
	"ì": "i", "í": "i", "î": "i", "ï": "i",
	"ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o",
	"ù": "u", "ú": "u", "û": "u", "ü": "u",
	"ý": "y", "ÿ": "y",
	"ñ": "n", "ç": "c", "œ": "oe", "æ": "ae",
}

var _filter: LineEdit = null
var _sections_box: VBoxContainer = null
var _footer: Label = null

## Toutes les tuiles : [{button: Button, haystack: String}].
var _tiles: Array = []
## Sections construites : [{title: Label, grid: GridContainer}].
var _sections: Array = []
## Le volant doit-il être ouvert (pour la frame de stabilisation).
var _wants_open := false


func _init() -> void:
	borderless = true
	transparent_bg = true
	unresizable = true
	add_theme_stylebox_override("panel", _panel_style())
	_build_ui()
	close_requested.connect(close_now)


# ---------------------------------------------------------------------------
# API publique
# ---------------------------------------------------------------------------

## Construit le volant : clés = noms de catégorie, valeurs = tableaux de
## dictionnaires {id, icon, label}. Tout contenu précédent est remplacé.
func setup(categories: Dictionary) -> void:
	for child in _sections_box.get_children():
		_sections_box.remove_child(child)
		child.queue_free()
	_tiles.clear()
	_sections.clear()
	for cat_name in categories:
		var entries: Array = categories[cat_name]
		if entries.is_empty():
			continue
		_add_section(str(cat_name), entries)
	_apply_filter()


## Ouvre le volant à la position donnée (coordonnées écran) et donne le focus
## au champ de filtre. Le filtre est réinitialisé à chaque ouverture.
func open_at(pos: Vector2) -> void:
	_wants_open = true
	position = Vector2i(pos.round())
	if _filter != null:
		_filter.text = ""
		_apply_filter()
	reset_size()
	size = Vector2i(WIDTH, size.y)
	popup()
	if _filter != null:
		_filter.grab_focus()
	_settle_open()


## Ferme immédiatement le volant.
func close_now() -> void:
	_wants_open = false
	hide()


## Godot applique un hide différé quand une popup est rouverte dans la même
## frame que sa fermeture : on ré-affiche à la frame suivante si l'ouverture
## est toujours souhaitée.
func _settle_open() -> void:
	await get_tree().process_frame
	if not _wants_open or not is_inside_tree() or visible:
		return
	popup()
	if _filter != null:
		_filter.grab_focus()


# ---------------------------------------------------------------------------
# Construction de l'interface
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "RootVBox"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = CONTENT_MARGIN
	root.offset_top = CONTENT_MARGIN
	root.offset_right = -CONTENT_MARGIN
	root.offset_bottom = -CONTENT_MARGIN
	root.custom_minimum_size = Vector2(WIDTH - 2.0 * CONTENT_MARGIN, 0)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_filter = LineEdit.new()
	_filter.name = "FilterEdit"
	_filter.placeholder_text = FILTER_PLACEHOLDER
	_filter.clear_button_enabled = true
	_filter.custom_minimum_size = Vector2(0, 26)
	_filter.add_theme_stylebox_override("normal", _input_style(Color(0, 0, 0, 0.25), BORDER_COLOR))
	_filter.add_theme_stylebox_override("focus", _input_style(Color(0, 0, 0, 0.32), _ACCENT_BORDER))
	_filter.text_changed.connect(_on_filter_text_changed)
	_filter.text_submitted.connect(_on_filter_text_submitted)
	_filter.gui_input.connect(_on_filter_gui_input)
	root.add_child(_filter)

	_sections_box = VBoxContainer.new()
	_sections_box.name = "ToolList"
	_sections_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sections_box.add_theme_constant_override("separation", 12)
	root.add_child(_sections_box)

	# Pied de texte : hauteur mesurée à l'avance. Sans ce wrapper, la taille
	# mini d'un Label en auto-wrap (calculée à largeur nulle) ferait exploser
	# la hauteur de la popup dès sa première ouverture.
	var footer_wrap := Control.new()
	footer_wrap.name = "FooterWrap"
	footer_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer_wrap.clip_contents = true
	footer_wrap.custom_minimum_size = Vector2(0, _footer_height())
	root.add_child(footer_wrap)

	_footer = Label.new()
	_footer.name = "FooterLabel"
	_footer.text = FOOTER_TEXT
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_footer.add_theme_font_size_override("font_size", FOOTER_FONT_SIZE)
	_footer.add_theme_color_override("font_color", _DIM_TEXT_COLOR)
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer_wrap.add_child(_footer)


## Hauteur du pied de texte mesurée sur la largeur utile de la popup.
func _footer_height() -> float:
	var font: Font = get_theme_font("font")
	var text_size := font.get_multiline_string_size(
		FOOTER_TEXT, HORIZONTAL_ALIGNMENT_LEFT,
		WIDTH - 2.0 * CONTENT_MARGIN, FOOTER_FONT_SIZE)
	return text_size.y + 2.0


## Ajoute un titre de catégorie (MAJUSCULES) + une grille 4 colonnes de tuiles.
func _add_section(category_name: String, entries: Array) -> void:
	var index := _sections.size() + 1
	var title := Label.new()
	title.name = "CategoryTitle%d" % index
	title.text = category_name.to_upper()
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", _DIM_TEXT_COLOR)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sections_box.add_child(title)

	var grid := GridContainer.new()
	grid.name = "ToolGrid%d" % index
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_sections_box.add_child(grid)

	for entry in entries:
		var button := _make_tile(entry)
		grid.add_child(button)
		_tiles.append({
			"button": button,
			"haystack": _normalize(str(entry.get("label", ""))),
		})
	_sections.append({"title": title, "grid": grid})


## Construit une tuile 62x56 : icône 20px + libellé 11px à ellipsis.
func _make_tile(entry: Dictionary) -> Button:
	var tool_id := str(entry.get("id", ""))
	var label_text := str(entry.get("label", tool_id))

	var button := Button.new()
	button.name = "Tool_" + tool_id
	button.custom_minimum_size = TILE_SIZE
	button.focus_mode = Control.FOCUS_CLICK
	button.clip_contents = true
	button.set_meta("tool_id", tool_id)
	button.tooltip_text = label_text
	button.add_theme_stylebox_override("normal", _tile_style(_TILE_BG, _TILE_BORDER))
	button.add_theme_stylebox_override("hover", _tile_style(_TILE_BG_HOVER, _ACCENT_BORDER))
	button.add_theme_stylebox_override("pressed", _tile_style(_TILE_BG_PRESSED, _ACCENT_BORDER))
	button.add_theme_stylebox_override("focus", _tile_style(_TILE_BG, _ACCENT_BORDER))
	button.gui_input.connect(_on_tile_gui_input.bind(tool_id))

	var stack := VBoxContainer.new()
	stack.name = "TileStack"
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_top = 6.0
	stack.offset_bottom = -6.0
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(stack)

	var icon_rect := TextureRect.new()
	icon_rect.name = "ToolIcon"
	icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect.texture = _resolve_icon(entry.get("icon", null))
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon_rect)

	var label := Label.new()
	label.name = "ToolLabel"
	label.set_meta("full_label", label_text)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", _TEXT_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ellipsis appliquée manuellement pour garantir que le libellé tienne
	# toujours dans la tuile, quel que soit le thème/la police courante.
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	label.text = _ellipsize(label_text, font, font_size, TILE_SIZE.x - 8.0)
	stack.add_child(label)

	return button


# ---------------------------------------------------------------------------
# Filtrage
# ---------------------------------------------------------------------------

## Masque les tuiles dont le libellé ne contient pas la saisie (insensible
## aux accents et à la casse). Une catégorie sans tuile visible est masquée.
func _apply_filter() -> void:
	if _filter == null:
		return
	var needle := _normalize(_filter.text.strip_edges())
	for tile in _tiles:
		var button: Button = tile["button"]
		button.visible = needle.is_empty() or str(tile["haystack"]).contains(needle)
	for section in _sections:
		var grid: GridContainer = section["grid"]
		var title: Label = section["title"]
		var any_visible := false
		for child in grid.get_children():
			if child.visible:
				any_visible = true
				break
		grid.visible = any_visible
		title.visible = any_visible


## Retire les accents (et passe en minuscules) pour comparer filtre et libellés.
func _normalize(text: String) -> String:
	var out := text.to_lower()
	for key in _ACCENT_MAP:
		out = out.replace(str(key), str(_ACCENT_MAP[key]))
	return out


func _on_filter_text_changed(_new_text: String) -> void:
	_apply_filter()


## Entrée dans le filtre : arme le premier outil visible puis ferme.
func _on_filter_text_submitted(_submitted: String) -> void:
	for tile in _tiles:
		var button: Button = tile["button"]
		if button.visible:
			_emit_choice(str(button.get_meta("tool_id")), false)
			return


# ---------------------------------------------------------------------------
# Interactions
# ---------------------------------------------------------------------------

## Clic sur une tuile : clic simple -> choix + fermeture ; Maj+clic -> choix en
## gardant le volant ouvert. Entrée/Espace arment l'outil de la tuile focusée.
func _on_tile_gui_input(event: InputEvent, tool_id: String) -> void:
	if _handle_key(event):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_emit_choice(tool_id, mb.shift_pressed)
			_mark_input_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_emit_choice(tool_id, key.shift_pressed)
			_mark_input_handled()


## Échap dans le champ de filtre : fermeture.
func _on_filter_gui_input(event: InputEvent) -> void:
	_handle_key(event)


## Gère Échap ; renvoie true si l'événement a été consommé.
func _handle_key(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			close_now()
			_mark_input_handled()
			return true
	return false


## Filet de sécurité : Échap quand aucun contrôle focusé ne l'a consommé.
func _unhandled_key_input(event: InputEvent) -> void:
	_handle_key(event)


## Émet le choix ; ferme le volant sauf si keep_open.
func _emit_choice(tool_id: String, keep_open: bool) -> void:
	tool_chosen.emit(tool_id, keep_open)
	if not keep_open:
		_wants_open = false
		hide()


# ---------------------------------------------------------------------------
# Styles et helpers
# ---------------------------------------------------------------------------

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR
	sb.set_border_width_all(1)
	sb.border_color = BORDER_COLOR
	sb.set_corner_radius_all(CORNER_RADIUS)
	sb.set_content_margin_all(0.0)
	return sb


func _input_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	return sb


func _tile_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_corner_radius_all(6)
	return sb


## Accepte une Texture2D ou un chemin String ; null sinon.
func _resolve_icon(value: Variant) -> Texture2D:
	if value is Texture2D:
		return value
	if value is String and value != "":
		var res: Variant = load(value)
		if res is Texture2D:
			return res
	return null


## Coupe le texte avec '…' pour qu'il tienne dans max_width pixels.
func _ellipsize(text: String, font: Font, font_size: int, max_width: float) -> String:
	if font == null or text.is_empty():
		return text
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var out := text
	while out.length() > 1:
		out = out.substr(0, out.length() - 1)
		if font.get_string_size(out + _ELLIPSIS, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			break
	return out.rstrip(" ") + _ELLIPSIS


func _mark_input_handled() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()
