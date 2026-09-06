extends VBoxContainer
class_name MapEditorHistoryPanel

## Onglet Historique. Structure dans `scenes/map_editor/panels/history.tscn`.

const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

signal undo_pressed
signal redo_pressed

var history_list: VBoxContainer

func _ready() -> void:
	history_list = %HistoryList
	%BtnUndo.pressed.connect(func(): undo_pressed.emit())
	%BtnRedo.pressed.connect(func(): redo_pressed.emit())
	_fill_shortcuts(%ShortcutsHost)

func _fill_shortcuts(host: VBoxContainer) -> void:
	for entry_variant in ToolsScript.SHORTCUTS:
		var entry: Dictionary = entry_variant
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		host.add_child(line)
		var keys := Label.new()
		keys.text = str(entry["keys"])
		keys.custom_minimum_size = Vector2(120, 0)
		keys.theme_type_variation = &"HeadingLabel"
		keys.add_theme_font_size_override("font_size", 11)
		line.add_child(keys)
		var action := Label.new()
		action.text = str(entry["action"])
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.theme_type_variation = &"CaptionLabel"
		line.add_child(action)
