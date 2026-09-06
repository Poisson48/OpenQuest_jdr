extends PanelContainer
class_name ActionBarPanel

## Tour en cours et saisie d'action du joueur.
## Structure dans `scenes/session/panels/action_bar.tscn`.
##
## Les suggestions sont de vrais boutons : leur infobulle EST la phrase
## envoyée. En ajouter une se fait dans l'éditeur Godot.
## Côté MJ, seul l'indicateur de tour reste visible.

signal action_submitted(text: String)

@onready var _headline: Label = %LblTurn
@onready var _hint: Label = %LblHint
@onready var _suggestions: ScrollContainer = %Suggestions
@onready var _suggestion_row: HBoxContainer = %SuggestionRow
@onready var _input_row: HBoxContainer = %InputRow
@onready var _input: LineEdit = %ActionInput
@onready var _send: Button = %BtnSend

var _suggestion_buttons: Array[Button] = []

func _ready() -> void:
	for child in _suggestion_row.get_children():
		if child is Button:
			var btn: Button = child
			_suggestion_buttons.append(btn)
			var phrase := btn.tooltip_text
			btn.pressed.connect(func(): _submit(phrase))
	_input.text_submitted.connect(func(text: String): _submit(text))
	_send.pressed.connect(func(): _submit(_input.text))

func set_turn(turn: Dictionary) -> void:
	_headline.text = str(turn.get("headline", ""))
	_hint.text = str(turn.get("hint", ""))
	var color := ThemeColors.ACCENT_LIGHT
	match str(turn.get("tone", "idle")):
		"alert":
			color = ThemeColors.ALERT
		"muted":
			color = ThemeColors.TEXT_MUTED
		"active":
			color = ThemeColors.SUCCESS
	_headline.add_theme_color_override("font_color", color)

## Le MJ garde l'indicateur de tour mais pas les commandes joueur.
func set_player_controls_visible(shown: bool) -> void:
	_suggestions.visible = shown
	_input_row.visible = shown

func set_enabled(enabled: bool) -> void:
	_input.editable = enabled
	_send.disabled = not enabled
	for btn in _suggestion_buttons:
		btn.disabled = not enabled

func fill(text: String) -> void:
	_input.text = text

func _submit(text: String) -> void:
	var action := text.strip_edges()
	if action.is_empty() or not _input.editable:
		return
	_input.text = ""
	action_submitted.emit(action)
