extends PanelContainer
class_name DiceTrayPanel

## Jets de dés : raccourcis, formule libre, jet secret du MJ.
## Structure dans `scenes/session/panels/dice_tray.tscn`.
##
## Les dés rapides sont de vrais boutons de la scène : leur libellé EST la
## formule (« d20 » → « 1d20 »). Ajouter un dé se fait dans l'éditeur Godot,
## sans toucher au script.

signal roll_requested(formula: String, secret: bool)

@onready var _secret: CheckBox = %ChkSecret
@onready var _quick_row: HBoxContainer = %QuickRow
@onready var _formula: LineEdit = %FormulaInput
@onready var _btn_roll: Button = %BtnRoll
@onready var _result: Label = %LblResult

var _quick_buttons: Array[Button] = []

func _ready() -> void:
	for child in _quick_row.get_children():
		if child is Button:
			var btn: Button = child
			_quick_buttons.append(btn)
			var formula := _formula_for(btn.text)
			btn.tooltip_text = "Lancer %s" % formula
			btn.pressed.connect(func(): _emit(formula))
	_formula.text_submitted.connect(func(_t: String): _emit(_formula.text))
	_btn_roll.pressed.connect(func(): _emit(_formula.text))

## « d20 » → « 1d20 », mais « 2d6 » reste tel quel.
static func _formula_for(label: String) -> String:
	var text := label.strip_edges()
	if text.is_empty():
		return ""
	return text if text[0].is_valid_int() else "1%s" % text

func set_enabled(enabled: bool) -> void:
	for btn in _quick_buttons:
		btn.disabled = not enabled
	_btn_roll.disabled = not enabled
	_formula.editable = enabled

func set_secret_available(available: bool) -> void:
	_secret.visible = available
	if not available:
		_secret.button_pressed = false

func set_result(text: String, secret: bool = false) -> void:
	_result.text = ("Secret · %s" % text) if secret else text
	_result.add_theme_color_override(
		"font_color", ThemeColors.TEXT_MUTED if secret else ThemeColors.ACCENT_LIGHT
	)

func _emit(formula: String) -> void:
	var f := formula.strip_edges()
	if f.is_empty():
		return
	roll_requested.emit(f, _secret.visible and _secret.button_pressed)
