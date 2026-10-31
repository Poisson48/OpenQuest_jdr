extends VBoxContainer
class_name MapEditorSettingsPanel

## Onglet « Carte ». Structure dans `scenes/map_editor/panels/settings.tscn`.

signal import_background_pressed
signal import_overlay_pressed
signal remove_background_pressed
signal size_changed
signal grid_changed
signal measure_changed
signal fog_setting_changed
signal los_changed
signal fog_hide_all_pressed
signal fog_reveal_all_pressed
signal render_style_changed
signal ground_mode_changed
signal water_changed
signal ambient_fx_changed
signal perspective_changed
signal atmosphere_changed
signal lighting_changed
signal night_mode_changed
signal clear_light_reveal_pressed
signal show_links_toggled(on: bool)
signal show_ids_toggled(on: bool)
signal show_vision_toggled(on: bool)
signal save_policy_changed(policy: String, label: String)
signal export_json_pressed
signal import_json_pressed

const SAVE_MANUAL := "manual"
const SAVE_ON_CHANGE := "on_change"
const SAVE_INTERVAL := "interval"

var widgets: Dictionary = {}

func _ready() -> void:
	widgets["bg_status"] = %LblBgStatus
	widgets["width"] = %SpinWidth
	widgets["height"] = %SpinHeight
	widgets["grid_enabled"] = %ChkGrid
	widgets["grid_size"] = %SpinGridSize
	widgets["grid_opacity"] = %SpinGridOpacity
	widgets["grid_color"] = %ClrGrid
	widgets["measure_per_cell"] = %SpinMeasure
	widgets["measure_unit"] = %EditUnit
	widgets["fog_enabled"] = %ChkFog
	widgets["los_enabled"] = %ChkLos
	widgets["render_style"] = %OptRenderStyle
	widgets["perspective"] = %OptPerspective
	widgets["atmo_enabled"] = %ChkAtmo
	widgets["atmo_tint"] = %ClrAtmo
	widgets["atmo_opacity"] = %SpinAtmoOpacity
	widgets["atmo_vignette"] = %SpinAtmoVignette
	widgets["light_enabled"] = %ChkLight
	widgets["light_dir"] = %OptLightDir
	widgets["light_intensity"] = %SpinLightIntensity
	widgets["night_mode"] = %ChkNight
	widgets["night_ambient"] = %SpinNightAmbient

	_fill_option(%OptRenderStyle, [
		["2.5d", "Carte 2.5D (défaut)"],
		["diorama", "Diorama (vue de dessus)"],
		["vtt", "VTT 3D (tactique)"],
		["dd2_hybrid", "Hybride DD2 (2D+3D)"],
	])
	_fill_option(%OptPerspective, [
		["topdown", "Vue de dessus"],
		["isometric", "Isométrique"],
		["perspective", "Perspective inclinée"],
	])
	_fill_option(%OptLightDir, [
		["nw", "Nord-Ouest"],
		["ne", "Nord-Est"],
		["sw", "Sud-Ouest"],
		["se", "Sud-Est"],
	])
	_fill_option(%OptSavePolicy, [
		[SAVE_MANUAL, "Manuelle"],
		[SAVE_ON_CHANGE, "À chaque modification"],
		[SAVE_INTERVAL, "Périodique (30 s)"],
	])

	# Type de sol : vrai terrain 3D (relief) ou fond illustré plat.
	var ground_lbl := Label.new()
	ground_lbl.text = "Type de sol"
	add_child(ground_lbl)
	var ground_opt := OptionButton.new()
	add_child(ground_opt)
	_fill_option(ground_opt, [
		["terrain3d", "Terrain 3D (relief)"],
		["illustrated", "Fond illustré (plat)"],
	])
	widgets["ground_mode"] = ground_opt
	ground_opt.item_selected.connect(func(_i): ground_mode_changed.emit())
	# Niveau d'eau : -1 = pas d'eau, >= 0 = plan d'eau (lac / étang).
	var water_lbl := Label.new()
	water_lbl.text = "Eau (niveau)"
	add_child(water_lbl)
	var water_spin := SpinBox.new()
	water_spin.min_value = -1.0
	water_spin.max_value = 8.0
	water_spin.step = 0.1
	water_spin.value = -1.0
	water_spin.tooltip_text = "-1 = aucune eau ; sinon hauteur du plan d'eau en cases (les creux du relief deviennent un lac)."
	add_child(water_spin)
	widgets["water_level"] = water_spin
	water_spin.value_changed.connect(func(_v): water_changed.emit())
	# Ambiance animée : lucioles, poussière ou feuilles.
	var fx_lbl := Label.new()
	fx_lbl.text = "Ambiance"
	add_child(fx_lbl)
	var fx_opt := OptionButton.new()
	add_child(fx_opt)
	_fill_option(fx_opt, [
		["", "Aucune"],
		["fireflies", "Lucioles (étang / forêt)"],
		["dust", "Poussière (intérieur / donjon)"],
		["leaves", "Feuilles qui tombent (forêt)"],
	])
	widgets["ambient_fx"] = fx_opt
	fx_opt.item_selected.connect(func(_i): ambient_fx_changed.emit())
	var style_node := find_child("LblStyle", true, false)
	if style_node is Node:
		var style_index := style_node.get_index()
		move_child(ground_lbl, style_index)
		move_child(ground_opt, style_index + 1)
		move_child(water_lbl, style_index + 2)
		move_child(water_spin, style_index + 3)
		move_child(fx_lbl, style_index + 4)
		move_child(fx_opt, style_index + 5)

	%BtnImportBg.pressed.connect(func(): import_background_pressed.emit())
	%BtnImportOverlay.pressed.connect(func(): import_overlay_pressed.emit())
	%BtnRemoveBg.pressed.connect(func(): remove_background_pressed.emit())
	%SpinWidth.value_changed.connect(func(_v): size_changed.emit())
	%SpinHeight.value_changed.connect(func(_v): size_changed.emit())
	%ChkGrid.toggled.connect(func(_on): grid_changed.emit())
	%SpinGridSize.value_changed.connect(func(_v): grid_changed.emit())
	%SpinGridOpacity.value_changed.connect(func(_v): grid_changed.emit())
	%ClrGrid.color_changed.connect(func(_c): grid_changed.emit())
	%SpinMeasure.value_changed.connect(func(_v): measure_changed.emit())
	%EditUnit.text_submitted.connect(func(_t): measure_changed.emit())
	%EditUnit.focus_exited.connect(func(): measure_changed.emit())
	%ChkFog.toggled.connect(func(_on): fog_setting_changed.emit())
	%ChkLos.toggled.connect(func(_on): los_changed.emit())
	%BtnFogHide.pressed.connect(func(): fog_hide_all_pressed.emit())
	%BtnFogReveal.pressed.connect(func(): fog_reveal_all_pressed.emit())
	%OptRenderStyle.item_selected.connect(func(_i): render_style_changed.emit())
	%OptPerspective.item_selected.connect(func(_i): perspective_changed.emit())
	%ChkAtmo.toggled.connect(func(_on): atmosphere_changed.emit())
	%ClrAtmo.color_changed.connect(func(_c): atmosphere_changed.emit())
	%SpinAtmoOpacity.value_changed.connect(func(_v): atmosphere_changed.emit())
	%SpinAtmoVignette.value_changed.connect(func(_v): atmosphere_changed.emit())
	%ChkLight.toggled.connect(func(_on): lighting_changed.emit())
	%OptLightDir.item_selected.connect(func(_i): lighting_changed.emit())
	%SpinLightIntensity.value_changed.connect(func(_v): lighting_changed.emit())
	%ChkNight.toggled.connect(func(_on): night_mode_changed.emit())
	%SpinNightAmbient.value_changed.connect(func(_v): night_mode_changed.emit())
	%BtnClearLight.pressed.connect(func(): clear_light_reveal_pressed.emit())
	%ChkShowLinks.toggled.connect(func(on): show_links_toggled.emit(on))
	%ChkShowIds.toggled.connect(func(on): show_ids_toggled.emit(on))
	%ChkShowVision.toggled.connect(func(on): show_vision_toggled.emit(on))
	%OptSavePolicy.item_selected.connect(func(index):
		save_policy_changed.emit(str(%OptSavePolicy.get_item_metadata(index)), %OptSavePolicy.get_item_text(index))
	)
	%BtnExportJson.pressed.connect(func(): export_json_pressed.emit())
	%BtnImportJson.pressed.connect(func(): import_json_pressed.emit())

func _fill_option(opt: OptionButton, entries: Array) -> void:
	for i in range(mini(opt.item_count, entries.size())):
		opt.set_item_metadata(i, str(entries[i][0]))
