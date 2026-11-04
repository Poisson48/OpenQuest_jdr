extends VBoxContainer
class_name MapEditorEnvironPalette

## Palette compacte « Décor & ambiance » : végétation, eau + décor, ambiance et
## preset de lumière, pour tester le système sans passer par l'onglet Carte.
## Auto-suffisante : lit/écrit directement `map_data` via `doc` de l'éditeur.

var _host = null
var _syncing := false

var _veg_chk: CheckBox
var _veg_density: SpinBox
var _water_level: SpinBox
var _water_decor_density: SpinBox
var _water_seed: SpinBox
var _fx_opt: OptionButton
var _light_opt: OptionButton

func _ready() -> void:
	_build_ui()

func setup(editor) -> void:
	_host = editor
	if _veg_chk == null:
		_build_ui()
	sync_from_host()

func _build_ui() -> void:
	var heading := Label.new()
	heading.text = "🎨 Décor & ambiance"
	heading.add_theme_font_size_override("font_size", 12)
	heading.add_theme_color_override("font_color", Color(0.92, 0.80, 0.45))
	add_child(heading)

	_veg_chk = CheckBox.new()
	_veg_chk.text = "Végétation procédurale"
	_veg_chk.toggled.connect(func(_on): _apply())
	add_child(_veg_chk)

	_veg_density = _spin(0.0, 3.0, 0.1)
	add_child(_row("Densité végétation", _veg_density))

	_water_level = _spin(-1.0, 8.0, 0.1)
	add_child(_row("Niveau d'eau", _water_level))

	_water_decor_density = _spin(0.0, 3.0, 0.1)
	add_child(_row("Densité décor eau", _water_decor_density))

	_water_seed = _spin(1.0, 99999.0, 1.0)
	add_child(_row("Graine décor eau", _water_seed))

	_fx_opt = OptionButton.new()
	_fx_opt.add_item("Aucune ambiance", 0)
	_fx_opt.set_item_metadata(0, "")
	var fx := [["fireflies", "Lucioles"], ["dust", "Poussière"], ["leaves", "Feuilles"], ["rain", "Pluie"], ["snow", "Neige"]]
	for i in range(fx.size()):
		_fx_opt.add_item(str(fx[i][1]), i + 1)
		_fx_opt.set_item_metadata(i + 1, str(fx[i][0]))
	_fx_opt.item_selected.connect(func(_i): _apply())
	add_child(_row("Ambiance", _fx_opt))

	_light_opt = OptionButton.new()
	for i in range(MapData.LIGHTING_PRESET_ORDER.size()):
		var preset_id := str(MapData.LIGHTING_PRESET_ORDER[i])
		var preset: Dictionary = MapData.get_lighting_preset(preset_id)
		_light_opt.add_item(str(preset.get("label", preset_id)), i)
		_light_opt.set_item_metadata(i, preset_id)
	_light_opt.item_selected.connect(func(_i): _apply())
	add_child(_row("Lumière", _light_opt))

func _spin(min_v: float, max_v: float, step_v: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step_v
	sb.value_changed.connect(func(_v): _apply())
	return sb

func _row(caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size = Vector2(120, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _apply() -> void:
	if _syncing or _host == null:
		return
	_host.doc.set_meta_values({
		"vegetationEnabled": _veg_chk.button_pressed,
		"vegetationDensity": _veg_density.value,
		"waterLevel": _water_level.value,
		"waterDecorDensity": _water_decor_density.value,
		"waterDecorSeed": int(_water_seed.value),
		"ambientFx": str(_fx_opt.get_item_metadata(_fx_opt.selected)),
	}, "Décor & ambiance")
	var light: Dictionary = MapData.get_lighting_config(_host.doc.map_data).duplicate(true)
	light["preset"] = str(_light_opt.get_item_metadata(_light_opt.selected))
	_host.doc.set_meta_values({"lighting": light}, "Lumière")
	_host._sync_engine()
	_host._set_status("Décor & ambiance mis à jour.")

## Relit map_data et met les contrôles à jour sans ré-émettre `_apply`.
func sync_from_host() -> void:
	if _host == null:
		return
	_syncing = true
	var md: Dictionary = _host.doc.map_data
	_veg_chk.set_pressed_no_signal(bool(md.get("vegetationEnabled", false)))
	_veg_density.set_value_no_signal(float(md.get("vegetationDensity", 1.0)))
	_water_level.set_value_no_signal(float(md.get("waterLevel", -1.0)))
	_water_decor_density.set_value_no_signal(float(md.get("waterDecorDensity", 1.0)))
	_water_seed.set_value_no_signal(float(md.get("waterDecorSeed", 1)))
	var fx := str(md.get("ambientFx", ""))
	for i in range(_fx_opt.item_count):
		if str(_fx_opt.get_item_metadata(i)) == fx:
			_fx_opt.select(i)
			break
	var light: Dictionary = MapData.get_lighting_config(md)
	var preset_id := str(light.get("preset", "jour"))
	for i in range(_light_opt.item_count):
		if str(_light_opt.get_item_metadata(i)) == preset_id:
			_light_opt.select(i)
			break
	_syncing = false
