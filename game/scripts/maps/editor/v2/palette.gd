class_name MapEditorPaletteV2
extends VBoxContainer

## Palette d'outils compacte (refonte UI v2) : icônes seules, empilées en
## colonne étroite, groupes séparés par un filet. Les libellés et raccourcis
## ne vivent que dans l'infobulle → beaucoup moins de bruit visuel.

signal tool_selected(tool_id: String)

var _button_group := ButtonGroup.new()
var _buttons: Dictionary = {}
var _options_host: VBoxContainer = null
var _programmatic := false


func _init() -> void:
	_button_group.allow_unpress = false
	custom_minimum_size = Vector2(48, 0)
	add_theme_constant_override("separation", 3)


## Vide et reconstruit la palette (icônes seules, séparateurs entre groupes).
func setup(groups: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_options_host = null

	var first_group := true
	for group_data in groups:
		if typeof(group_data) != TYPE_DICTIONARY:
			continue
		var tools: Array = group_data.get("tools", [])
		if tools.is_empty():
			continue
		if not first_group:
			add_child(_separator())
		first_group = false
		for tool_data in tools:
			if typeof(tool_data) != TYPE_DICTIONARY:
				continue
			add_child(_make_button(tool_data))

	_ensure_options_host()


func set_active(tool_id: String) -> void:
	if not _buttons.has(tool_id):
		return
	_programmatic = true
	for id in _buttons:
		(_buttons[id] as Button).set_pressed_no_signal(id == tool_id)
	_programmatic = false


func get_active() -> String:
	for id in _buttons:
		if (_buttons[id] as Button).button_pressed:
			return id
	return ""


## Conteneur (sous les boutons) où l'hôte injecte les options de l'outil actif.
func get_options_host() -> VBoxContainer:
	_ensure_options_host()
	return _options_host


func _make_button(tool_data: Dictionary) -> Button:
	var id := str(tool_data.get("id", ""))
	var icon := str(tool_data.get("icon", ""))
	var label := str(tool_data.get("label", ""))
	var shortcut := str(tool_data.get("shortcut", ""))

	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _button_group
	b.custom_minimum_size = Vector2(42, 38)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if icon.begins_with("res://") or icon.begins_with("user://"):
		# Icône TEXTURE : charger la Texture2D et l'afficher sans texte.
		b.icon = load(icon) as Texture2D
		b.text = ""
	else:
		# Comportement emoji existant : l'icône est du texte.
		b.text = icon if not icon.is_empty() else label.substr(0, 1)
	b.tooltip_text = label if shortcut.is_empty() else "%s (%s)" % [label, shortcut]
	b.set_meta("tool_id", id)
	b.pressed.connect(_on_pressed.bind(id))
	_buttons[id] = b
	return b


func _separator() -> HSeparator:
	var s := HSeparator.new()
	s.custom_minimum_size = Vector2(0, 8)
	return s


func _on_pressed(tool_id: String) -> void:
	if _programmatic:
		return
	tool_selected.emit(tool_id)


func _ensure_options_host() -> void:
	if _options_host != null and is_instance_valid(_options_host):
		return
	_options_host = VBoxContainer.new()
	_options_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_options_host)
