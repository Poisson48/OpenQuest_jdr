extends VBoxContainer

## Réglages 2D : taille de grille, brouillard, échelle.

signal size_changed
signal fog_setting_changed
signal measure_changed
signal fog_hide_all_pressed
signal fog_reveal_all_pressed

func _ready() -> void:
	%SpinWidth.value_changed.connect(func(_v): size_changed.emit())
	%SpinHeight.value_changed.connect(func(_v): size_changed.emit())
	%ChkFog.toggled.connect(func(_on): fog_setting_changed.emit())
	%SpinMeasure.value_changed.connect(func(_v): measure_changed.emit())
	%EditUnit.text_submitted.connect(func(_t): measure_changed.emit())
	%EditUnit.focus_exited.connect(func(): measure_changed.emit())
	%BtnFogHide.pressed.connect(func(): fog_hide_all_pressed.emit())
	%BtnFogReveal.pressed.connect(func(): fog_reveal_all_pressed.emit())

func sync_from(map_data: Dictionary) -> void:
	%SpinWidth.set_value_no_signal(int(map_data.get("width", 16)))
	%SpinHeight.set_value_no_signal(int(map_data.get("height", 12)))
	%ChkFog.set_pressed_no_signal(bool(map_data.get("fogEnabled", false)))
	var measure: Dictionary = map_data.get("measure", {}) if map_data.get("measure") is Dictionary else {}
	%SpinMeasure.set_value_no_signal(float(measure.get("perCell", 1.5)))
	%EditUnit.text = str(measure.get("unit", "m"))

func grid_size() -> Vector2i:
	return Vector2i(int(%SpinWidth.value), int(%SpinHeight.value))

func fog_enabled() -> bool:
	return %ChkFog.button_pressed

func measure_values() -> Dictionary:
	return {
		"perCell": float(%SpinMeasure.value),
		"unit": %EditUnit.text.strip_edges() if not %EditUnit.text.strip_edges().is_empty() else "m",
	}
