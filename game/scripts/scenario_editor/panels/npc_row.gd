extends PanelContainer

## Ligne PNJ du scénario. Structure dans `npc_row.tscn`.

signal name_changed(text: String)
signal role_changed(text: String)
signal description_changed(text: String)
signal delete_pressed

func _ready() -> void:
	%EditName.text_changed.connect(func(t): name_changed.emit(t.strip_edges()))
	%EditRole.text_changed.connect(func(t): role_changed.emit(t.strip_edges()))
	%EditDesc.text_changed.connect(func(): description_changed.emit(%EditDesc.text.strip_edges()))
	%BtnDelete.pressed.connect(func(): delete_pressed.emit())

func setup(npc: Dictionary) -> void:
	if not is_node_ready():
		await ready
	%EditName.text = str(npc.get("name", ""))
	%EditRole.text = str(npc.get("role", ""))
	%EditDesc.text = str(npc.get("description", ""))
