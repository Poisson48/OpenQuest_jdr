extends PopupPanel
class_name MapEditorEscMenu

## Menu Échap de l'éditeur — extrait du monolithe map_complex_editor (P1-C).

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

func _init() -> void:
	var menu_box := VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 4)
	menu_box.custom_minimum_size = Vector2(300, 0)
	add_child(menu_box)

	_section(menu_box, "☰ Menu éditeur")
	_text_button(menu_box, "💾 Enregistrer", func():
		save_pressed.emit()
		hide()
	)
	_text_button(menu_box, "↶ Annuler", func(): undo_pressed.emit())
	_text_button(menu_box, "↷ Rétablir", func(): redo_pressed.emit())
	_text_button(menu_box, "🎯 Recadrer sur la carte", func():
		fit_view_pressed.emit()
		hide()
	)
	_text_button(menu_box, "🧹 Vider la sélection", func():
		clear_selection_pressed.emit()
		hide()
	)
	_section(menu_box, "Fichier")
	_text_button(menu_box, "⬇ Importer JSON…", func():
		hide()
		import_json_pressed.emit()
	)
	_text_button(menu_box, "⬆ Exporter JSON…", func():
		hide()
		export_json_pressed.emit()
	)
	_section(menu_box, "Sauvegarde auto")
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	menu_box.add_child(save_row)
	for entry in [
		[SAVE_MANUAL, "Manuelle"],
		[SAVE_ON_CHANGE, "À chaque modif"],
		[SAVE_INTERVAL, "Toutes les 30 s"],
	]:
		var policy := str(entry[0])
		var label := str(entry[1])
		var btn := Button.new()
		btn.text = label
		btn.toggle_mode = true
		btn.pressed.connect(func():
			_set_policy_ui(policy)
			save_policy_selected.emit(policy, label)
			hide()
		)
		save_row.add_child(btn)
		_policy_buttons[policy] = btn

	var help := Label.new()
	help.text = ToolsScript.shortcuts_text()
	help.add_theme_font_size_override("font_size", 10)
	help.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_box.add_child(help)

func sync_policy(policy: String) -> void:
	_set_policy_ui(policy)

func open_centered() -> void:
	popup_centered(Vector2i(340, 520))

func _set_policy_ui(policy: String) -> void:
	for key in _policy_buttons:
		(_policy_buttons[key] as Button).button_pressed = (str(key) == policy)

func _section(parent: Node, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	lbl.add_theme_font_size_override("font_size", 12)
	parent.add_child(lbl)

func _text_button(parent: Node, text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn
