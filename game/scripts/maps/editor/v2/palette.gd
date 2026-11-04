class_name MapEditorPaletteV2
extends VBoxContainer

## Palette d'outils de l'éditeur de carte — refonte UI v2.
##
## Composant 100 % autonome : aucune dépendance à MapData, aux autoloads
## ni à l'éditeur. L'hôte lui soumet sa structure via [method setup] et
## injecte ses options contextuelles via [method get_options_host].
##
## Structure attendue de `groups` :
##   [
##       { "title": "Naviguer", "tools": [
##           { "id": "select", "icon": "", "label": "Sélection", "shortcut": "S" },
##           ...
##       ] },
##       ...
##   ]

## Émis quand l'utilisateur clique sur un outil (jamais depuis set_active).
signal tool_selected(tool_id: String)

# Groupe de boutons global : un seul outil coché à la fois.
var _button_group: ButtonGroup = ButtonGroup.new()

# id d'outil -> Button, dans l'ordre d'insertion (les dictionnaires GDScript
# préservent l'ordre, ce qui garantit un get_active() déterministe).
var _buttons: Dictionary = {}

# Conteneur d'options contextuelles, reconstruit par setup() sous les boutons.
var _options_host: VBoxContainer = null

# Vrai pendant une manipulation programmatique des boutons : sert à ne pas
# émettre tool_selected depuis set_active().
var _programmatic := false


func _init() -> void:
	# Un clic sur le bouton déjà coché ne le décoche pas : il reste au moins
	# un outil actif à tout moment.
	_button_group.allow_unpress = false
	_ensure_options_host()


# ---------------------------------------------------------------------------
# API publique
# ---------------------------------------------------------------------------

## Vide et reconstruit entièrement la palette à partir de la description
## de groupes fournie par l'hôte.
func setup(groups: Array) -> void:
	# On repart d'une feuille blanche : plus aucun bouton, plus d'options.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_options_host = null

	if _button_group == null:
		_button_group = ButtonGroup.new()
		_button_group.allow_unpress = false

	for group_data in groups:
		if typeof(group_data) != TYPE_DICTIONARY:
			continue
		_add_group(group_data)

	# Le conteneur d'options se place toujours en dernier, sous les boutons.
	_ensure_options_host()


## Coche l'outil donné sans émettre [signal tool_selected].
## Un id inconnu est ignoré (la sélection courante reste inchangée).
func set_active(tool_id: String) -> void:
	if not _buttons.has(tool_id):
		return
	_programmatic = true
	# set_pressed_no_signal évite tout signal pendant la synchronisation ;
	# le drapeau _programmatic couvre en plus les émissions résiduelles.
	for id in _buttons:
		var button: Button = _buttons[id]
		button.set_pressed_no_signal(id == tool_id)
	_programmatic = false


## Retourne l'id de l'outil coché ('' si aucun).
func get_active() -> String:
	for id in _buttons:
		var button: Button = _buttons[id]
		if button.button_pressed:
			return id
	return ""


## Conteneur vide sous les boutons, où l'hôte injecte les options
## contextuelles de l'outil actif.
func get_options_host() -> VBoxContainer:
	_ensure_options_host()
	return _options_host


# ---------------------------------------------------------------------------
# Construction de l'interface
# ---------------------------------------------------------------------------

## Ajoute un groupe : un titre en gras, puis une grille d'une colonne de
## boutons pleine largeur.
func _add_group(group_data: Dictionary) -> void:
	var title := Label.new()
	title.text = str(group_data.get("title", ""))
	title.add_theme_font_override("font", _make_bold_font())
	add_child(title)

	var grid := GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)

	var tools: Array = group_data.get("tools", [])
	for tool_data in tools:
		if typeof(tool_data) != TYPE_DICTIONARY:
			continue
		grid.add_child(_make_tool_button(tool_data))


## Crée le bouton d'un outil : 'icône  Libellé' aligné à gauche, pleine
## largeur, en mode bascule, avec une infobulle rappelant le raccourci.
func _make_tool_button(tool_data: Dictionary) -> Button:
	var tool_id := str(tool_data.get("id", ""))
	var icon := str(tool_data.get("icon", ""))
	var label := str(tool_data.get("label", ""))
	var shortcut := str(tool_data.get("shortcut", ""))

	var button := Button.new()
	# 'icône  Libellé' (deux espaces de séparation), libellé seul sans icône.
	button.text = label if icon.is_empty() else icon + "  " + label
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.button_group = _button_group
	# Infobulle : 'libellé (raccourci)', ou 'libellé' si pas de raccourci.
	button.tooltip_text = label if shortcut.is_empty() else label + " (" + shortcut + ")"
	# Astuce pour l'hôte et les tests : retrouver l'id depuis le bouton.
	button.set_meta("tool_id", tool_id)

	button.pressed.connect(_on_tool_button_pressed.bind(tool_id))
	_buttons[tool_id] = button
	return button


## Clic utilisateur sur un outil : on propage l'id.
func _on_tool_button_pressed(tool_id: String) -> void:
	if _programmatic:
		return
	tool_selected.emit(tool_id)


## Garantit l'existence du conteneur d'options, sous les boutons.
func _ensure_options_host() -> void:
	if _options_host != null and is_instance_valid(_options_host):
		return
	_options_host = VBoxContainer.new()
	_options_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_options_host)


## Police en gras pour les titres de groupe (variation empâtée de la police
## de thème, sans dépendre à une police d'éditeur externe).
func _make_bold_font() -> Font:
	var base: Font = get_theme_font("font", "Label")
	if base == null:
		base = ThemeDB.fallback_font
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_embolden = 0.6
	return bold
