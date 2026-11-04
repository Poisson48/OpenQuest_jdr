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
signal vegetation_changed
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
	widgets["light_preset"] = %OptLightPreset
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
	var lighting_presets: Array = []
	for preset_id in MapData.LIGHTING_PRESET_ORDER:
		var preset: Dictionary = MapData.get_lighting_preset(preset_id)
		lighting_presets.append([preset_id, str(preset.get("label", preset_id))])
	_fill_option(%OptLightPreset, lighting_presets)
	_fill_option(%OptSavePolicy, [
		[SAVE_MANUAL, "Manuelle"],
		[SAVE_ON_CHANGE, "À chaque modification"],
		[SAVE_INTERVAL, "Périodique (30 s)"],
	])

	# --- Terrain & eau -------------------------------------------------------
	# Groupe inséré juste avant « Style de rendu » : la lecture va du sol vers
	# le rendu (terrain → eau → ambiance → style → lumière).
	var terrain_group := VBoxContainer.new()
	terrain_group.name = "TerrainGroup"
	terrain_group.add_theme_constant_override("separation", 4)
	add_child(terrain_group)
	terrain_group.add_child(_heading("🌍 Terrain & eau"))
	terrain_group.add_child(_caption(
		"Type de sol : terrain 3D avec relief et jupe de falaise, ou fond illustré plat."))
	var ground_opt := OptionButton.new()
	ground_opt.tooltip_text = "Choisit un terrain 3D (relief, eau, objets qui suivent le sol) ou une image de fond plate."
	terrain_group.add_child(ground_opt)
	_fill_option(ground_opt, [
		["terrain3d", "Terrain 3D (relief)"],
		["illustrated", "Fond illustré (plat)"],
	])
	widgets["ground_mode"] = ground_opt
	ground_opt.item_selected.connect(func(_i): ground_mode_changed.emit())

	terrain_group.add_child(_caption(
		"Eau : −1 = aucune ; sinon hauteur du plan d'eau en cases. Creusez d'abord le relief avec l'outil ⛰ Relief (U)."))
	var water_spin := SpinBox.new()
	water_spin.min_value = -1.0
	water_spin.max_value = 8.0
	water_spin.step = 0.1
	water_spin.value = -1.0
	water_spin.tooltip_text = "−1 = aucune eau ; sinon hauteur du plan d'eau en cases (les creux du relief deviennent un lac)."
	terrain_group.add_child(water_spin)
	widgets["water_level"] = water_spin
	water_spin.value_changed.connect(func(_v): water_changed.emit())

	terrain_group.add_child(_caption("Densité du décor d'eau (lentilles + nénuphars). 0 = aucune."))
	var water_decor_spin := SpinBox.new()
	water_decor_spin.min_value = 0.0
	water_decor_spin.max_value = 3.0
	water_decor_spin.step = 0.1
	water_decor_spin.value = 1.0
	water_decor_spin.tooltip_text = "Multiplie la densité des lentilles d'eau et des nénuphars. Baissez sur les grandes cartes pour soulager le GPU."
	terrain_group.add_child(water_decor_spin)
	widgets["water_decor_density"] = water_decor_spin
	water_decor_spin.value_changed.connect(func(_v): water_changed.emit())

	terrain_group.add_child(_caption("Graine du décor d'eau (lentilles + nénuphars)."))
	var water_seed_spin := SpinBox.new()
	water_seed_spin.min_value = 1.0
	water_seed_spin.max_value = 99999.0
	water_seed_spin.step = 1.0
	water_seed_spin.value = 1.0
	water_seed_spin.tooltip_text = "Change la disposition des lentilles d'eau et des nénuphars (déterministe)."
	terrain_group.add_child(water_seed_spin)
	widgets["water_decor_seed"] = water_seed_spin
	water_seed_spin.value_changed.connect(func(_v): water_changed.emit())

	terrain_group.add_child(_caption(
		"Ambiance : particules décoratives (lucioles, poussière, feuilles, pluie, neige)."))
	var fx_opt := OptionButton.new()
	fx_opt.tooltip_text = "Particules animées purement décoratives ; elles ne modifient pas le gameplay."
	terrain_group.add_child(fx_opt)
	_fill_option(fx_opt, [
		["", "Aucune"],
		["fireflies", "Lucioles (étang / forêt)"],
		["dust", "Poussière (intérieur / donjon)"],
		["leaves", "Feuilles qui tombent (forêt)"],
		["rain", "Pluie"],
		["snow", "Neige"],
	])
	widgets["ambient_fx"] = fx_opt
	fx_opt.item_selected.connect(func(_i): ambient_fx_changed.emit())

	terrain_group.add_child(_caption(
		"Végétation : herbe, fleurs, buissons et feuilles mortes procéduraux sur les cases d'herbe."))
	var veg_chk := CheckBox.new()
	veg_chk.text = "Végétation procédurale"
	veg_chk.tooltip_text = "Affiche l'herbe, les fleurs, les buissons et les feuilles mortes (ignorés dans l'eau et hors des cases d'herbe)."
	terrain_group.add_child(veg_chk)
	widgets["vegetation_enabled"] = veg_chk
	veg_chk.toggled.connect(func(_on): vegetation_changed.emit())

	terrain_group.add_child(_caption("Densité de la végétation (0 = aucune, 1 = normale, 2 = dense)."))
	var density_spin := SpinBox.new()
	density_spin.min_value = 0.0
	density_spin.max_value = 3.0
	density_spin.step = 0.1
	density_spin.value = 1.0
	density_spin.tooltip_text = "Multiplie la densité des touffes/fleurs/buissons/feuilles. Baissez sur les grandes cartes pour soulager le GPU."
	terrain_group.add_child(density_spin)
	widgets["vegetation_density"] = density_spin
	density_spin.value_changed.connect(func(_v): vegetation_changed.emit())

	var style_node := find_child("LblStyle", true, false)
	if style_node is Node:
		move_child(terrain_group, style_node.get_index())

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
	%OptLightPreset.item_selected.connect(func(_i): lighting_changed.emit())
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
	# Si le .tscn et le catalogue divergent (ex. ajout du style « 2.5D »), on
	# reconstruit les items depuis le catalogue : libellés ET métadonnées
	# restent ainsi alignés.
	if opt.item_count != entries.size():
		opt.clear()
		for i in range(entries.size()):
			opt.add_item(str(entries[i][1]), i)
			opt.set_item_metadata(i, str(entries[i][0]))
		return
	for i in range(entries.size()):
		opt.set_item_metadata(i, str(entries[i][0]))

func _heading(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.theme_type_variation = &"HeadingLabel"
	lbl.add_theme_font_size_override("font_size", 12)
	return lbl

func _caption(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.theme_type_variation = &"CaptionLabel"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl
