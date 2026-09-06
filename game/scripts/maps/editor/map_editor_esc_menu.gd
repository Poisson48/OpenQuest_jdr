extends PopupPanel
class_name MapEditorEscMenu

## Menu Échap. Structure dans `scenes/map_editor/panels/esc_menu.tscn`.

const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

signal save_pressed
signal undo_pressed
signal redo_pressed
signal fit_view_pressed
signal clear_selection_pressed
signal import_json_pressed
signal export_json_pressed
signal save_policy_selected(policy: String, label: String)

const SAVE_MANUAL := "manual"
const SAVE_ON_CHANGE := "on_change"
const SAVE_INTERVAL := "interval"

var _policy_buttons: Dictionary = {}

func _ready() -> void:
	%BtnSave.pressed.connect(func():
		save_pressed.emit()
		hide()
	)
	%BtnUndo.pressed.connect(func(): undo_pressed.emit())
	%BtnRedo.pressed.connect(func(): redo_pressed.emit())
	%BtnFit.pressed.connect(func():
		fit_view_pressed.emit()
		hide()
	)
	%BtnClearSel.pressed.connect(func():
		clear_selection_pressed.emit()
		hide()
	)
	%BtnImportJson.pressed.connect(func():
		hide()
		import_json_pressed.emit()
	)
	%BtnExportJson.pressed.connect(func():
		hide()
		export_json_pressed.emit()
	)
	_policy_buttons[SAVE_MANUAL] = %BtnPolicyManual
	_policy_buttons[SAVE_ON_CHANGE] = %BtnPolicyChange
	_policy_buttons[SAVE_INTERVAL] = %BtnPolicyInterval
	for policy in _policy_buttons.keys():
		var key := str(policy)
		var btn: Button = _policy_buttons[key]
		var label := btn.text
		btn.pressed.connect(func():
			_set_policy_ui(key)
			save_policy_selected.emit(key, label)
			hide()
		)
	%LblHelp.text = ToolsScript.shortcuts_text()

func sync_policy(policy: String) -> void:
	_set_policy_ui(policy)

func open_centered() -> void:
	popup_centered(Vector2i(340, 520))

func _set_policy_ui(policy: String) -> void:
	for key in _policy_buttons:
		(_policy_buttons[key] as Button).button_pressed = (str(key) == policy)
