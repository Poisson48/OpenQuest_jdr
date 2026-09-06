extends PanelContainer

## Une branche du graphe. Structure dans `transition_row.tscn`.

signal target_changed(to_id: String)
signal label_changed(text: String)
signal default_toggled(on: bool)
signal gm_only_toggled(on: bool)
signal delete_pressed

func _ready() -> void:
	%TargetOpt.item_selected.connect(func(_i):
		target_changed.emit(str(%TargetOpt.get_item_metadata(%TargetOpt.selected)))
	)
	%EditLabel.text_changed.connect(func(t): label_changed.emit(t.strip_edges()))
	%ChkDefault.toggled.connect(func(on): default_toggled.emit(on))
	%ChkGm.toggled.connect(func(on): gm_only_toggled.emit(on))
	%BtnDelete.pressed.connect(func(): delete_pressed.emit())

func setup(transition: Dictionary) -> void:
	if not is_node_ready():
		await ready
	var is_default := bool(transition.get("default", false))
	var is_gm := bool(transition.get("gmOnly", false))
	%LblArrow.text = "★→" if is_default else ("👁→" if is_gm else "→")
	%EditLabel.text = str(transition.get("label", ""))
	%ChkDefault.set_pressed_no_signal(is_default)
	%ChkGm.set_pressed_no_signal(is_gm)
	theme_type_variation = &"AlertPanel" if is_default else &"InsetPanel"

func get_target_option() -> OptionButton:
	return %TargetOpt
