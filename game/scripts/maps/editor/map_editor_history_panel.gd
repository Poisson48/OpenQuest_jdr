extends VBoxContainer
class_name MapEditorHistoryPanel

## Onglet Historique + raccourcis — extrait du monolithe map_complex_editor (P1-C).

const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

signal undo_pressed
signal redo_pressed

var history_list: VBoxContainer

func _init() -> void:
	add_theme_constant_override("separation", 4)
	_section("🕘 Historique")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	_text_button(row, "↶ Annuler", func(): undo_pressed.emit())
	_text_button(row, "↷ Rétablir", func(): redo_pressed.emit())
	history_list = VBoxContainer.new()
	history_list.add_theme_constant_override("separation", 1)
	add_child(history_list)

	_section("⌨ Raccourcis")
	for entry_variant in ToolsScript.SHORTCUTS:
		var entry: Dictionary = entry_variant
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		add_child(line)
		var keys := Label.new()
		keys.text = str(entry["keys"])
		keys.custom_minimum_size = Vector2(120, 0)
		keys.add_theme_font_size_override("font_size", 11)
		keys.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		line.add_child(keys)
		var action := Label.new()
		action.text = str(entry["action"])
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.add_theme_font_size_override("font_size", 11)
		action.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		line.add_child(action)

func _section(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	lbl.add_theme_font_size_override("font_size", 12)
	add_child(lbl)

func _text_button(parent: Node, text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn
