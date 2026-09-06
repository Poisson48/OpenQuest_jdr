extends CheckBox
class_name SetupToggleRow

## Ligne à cocher (cartes / bots) du lancement de partie.

signal toggled_id(id: String, on: bool)

var item_id: String = ""

func _ready() -> void:
	toggled.connect(func(on: bool): toggled_id.emit(item_id, on))

func setup(id: String, label: String, pressed: bool) -> void:
	if not is_node_ready():
		await ready
	item_id = id
	text = label
	set_pressed_no_signal(pressed)
