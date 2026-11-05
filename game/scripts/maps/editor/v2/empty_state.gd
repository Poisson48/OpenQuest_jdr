class_name MapEditorEmptyState
extends VBoxContainer

## État vide générique de l'éditeur v2 : icône + titre + description centrés,
## et éventuellement une action secondaire. 100% autonome (aucune dépendance
## au reste de l'éditeur) : le composant construit tous ses enfants lui-même.

const ICON_COLOR := Color("414E54")
const TITLE_COLOR := Color("A1AFB2")
const TEXT_COLOR := Color("718087")

const TEXT_MAX_WIDTH := 220.0

var _icon_label: Label = null
var _title_label: Label = null
var _text_label: Label = null
var _action_button: Button = null


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 6)

	_icon_label = _make_label("", 32, ICON_COLOR)
	_title_label = _make_label("", 13, TITLE_COLOR)
	_text_label = _make_label("", 12, TEXT_COLOR)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_text_label.custom_minimum_size = Vector2(TEXT_MAX_WIDTH, 0)
	add_child(_icon_label)
	add_child(_title_label)
	add_child(_text_label)


## Configure l'état vide. Si `action_label` est non vide, un bouton secondaire
## est créé (ou mis à jour) et connecté à `on_action`.
func setup(icon_text: String, title: String, text: String, action_label: String = '', on_action: Callable = Callable()) -> void:
	_icon_label.text = icon_text
	_icon_label.visible = icon_text != ""
	_title_label.text = title
	_title_label.visible = title != ""
	_text_label.text = text
	_text_label.visible = text != ""

	if action_label == "":
		_remove_action_button()
		return

	if _action_button == null:
		_action_button = Button.new()
		_action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_action_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_action_button)
	if _action_button.pressed.is_connected(_on_action_pressed):
		_action_button.pressed.disconnect(_on_action_pressed)
	_action_button.text = action_label
	_action_button.set_meta("on_action", on_action)
	_action_button.pressed.connect(_on_action_pressed)


func _on_action_pressed() -> void:
	if _action_button == null:
		return
	var cb: Variant = _action_button.get_meta("on_action", Callable())
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()


func _remove_action_button() -> void:
	if _action_button == null:
		return
	if _action_button.pressed.is_connected(_on_action_pressed):
		_action_button.pressed.disconnect(_on_action_pressed)
	remove_child(_action_button)
	_action_button.queue_free()
	_action_button = null


func _make_label(content: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
