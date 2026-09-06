extends PanelContainer
class_name StatChip

## Jeton PV / CA / humeur de la fiche. Structure dans `stat_chip.tscn`.

@onready var _name: Label = %LblName
@onready var _value: Label = %LblValue

func setup(label: String, value: String, accent: Color = ThemeColors.TEXT) -> void:
	if not is_node_ready():
		await ready
	_name.text = label
	_value.text = value
	_value.add_theme_color_override("font_color", accent)
