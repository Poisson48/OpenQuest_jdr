extends VBoxContainer
class_name MapEditorSettingsPanel

## Onglet « Carte » — extrait du monolithe map_complex_editor (P1-C).

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

func _init() -> void:
	add_theme_constant_override("separation", 5)
	_section("🖼 Fond de carte")
	var bg_status := Label.new()
	bg_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bg_status.add_theme_font_size_override("font_size", 11)
	bg_status.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	add_child(bg_status)
	widgets["bg_status"] = bg_status

	var bg_row := HBoxContainer.new()
	bg_row.add_theme_constant_override("separation", 4)
	add_child(bg_row)
	_text_button(bg_row, "Importer PNG…", func(): import_background_pressed.emit())
	_text_button(bg_row, "Calque +", func(): import_overlay_pressed.emit())
	_text_button(bg_row, "✕", func(): remove_background_pressed.emit())

	_section("📐 Dimensions (cases)")
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 6)
	add_child(size_row)
	widgets["width"] = _spin(size_row, "Largeur", 4, 128, 16, 1, func(_v): size_changed.emit())
	widgets["height"] = _spin(size_row, "Hauteur", 4, 128, 12, 1, func(_v): size_changed.emit())

	_section("⊞ Grille")
	widgets["grid_enabled"] = _checkbox("Afficher la grille", true, func(_on): grid_changed.emit())
	var grid_row := HBoxContainer.new()
	grid_row.add_theme_constant_override("separation", 6)
	add_child(grid_row)
	widgets["grid_size"] = _spin(grid_row, "Taille px", 20, 160, 70, 1, func(_v): grid_changed.emit())
	widgets["grid_opacity"] = _spin(grid_row, "Opacité", 0.0, 1.0, 0.22, 0.01, func(_v): grid_changed.emit())
	widgets["grid_color"] = _color_row("Couleur", "#ffffff", func(_hex): grid_changed.emit())

	_section("📏 Échelle")
	var measure_row := HBoxContainer.new()
	measure_row.add_theme_constant_override("separation", 6)
	add_child(measure_row)
	widgets["measure_per_cell"] = _spin(measure_row, "Par case", 0.1, 100.0, 1.5, 0.1, func(_v): measure_changed.emit())
	widgets["measure_unit"] = _line_row(measure_row, "Unité", "m", func(_t): measure_changed.emit())

	_section("🌫 Brouillard de guerre")
	widgets["fog_enabled"] = _checkbox("Activer le brouillard", true, func(_on): fog_setting_changed.emit())
	widgets["los_enabled"] = _checkbox("Ligne de vue (murs bloquants)", false, func(_on): los_changed.emit())
	var los_note := Label.new()
	los_note.text = "En session, le brouillard se révèle automatiquement selon ce que voient les tokens, murs et portes compris."
	los_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	los_note.add_theme_font_size_override("font_size", 10)
	los_note.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	add_child(los_note)
	var fog_row := HBoxContainer.new()
	fog_row.add_theme_constant_override("separation", 4)
	add_child(fog_row)
	_text_button(fog_row, "Tout masquer", func(): fog_hide_all_pressed.emit())
	_text_button(fog_row, "Tout révéler", func(): fog_reveal_all_pressed.emit())

	_section("🎨 Style de rendu")
	var style_opt := OptionButton.new()
	style_opt.add_item("Diorama 2.5D", 0)
	style_opt.set_item_metadata(0, "diorama")
	style_opt.add_item("VTT 3D (tactique)", 1)
	style_opt.set_item_metadata(1, "vtt")
	style_opt.add_item("Hybride DD2 (2D+3D)", 2)
	style_opt.set_item_metadata(2, "dd2_hybrid")
	style_opt.item_selected.connect(func(_i): render_style_changed.emit())
	add_child(style_opt)
	widgets["render_style"] = style_opt
	var style_hint := Label.new()
	style_hint.text = "Diorama + fond : vue dessus (props à plat). VTT : tactique 3D. Hybride DD2 : fond illustré + caméra inclinée + personnages dressés."
	style_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style_hint.add_theme_font_size_override("font_size", 10)
	style_hint.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	add_child(style_hint)

	_section("📷 Perspective")
	var persp := OptionButton.new()
	persp.add_item("Vue de dessus", 0)
	persp.set_item_metadata(0, "topdown")
	persp.add_item("Isométrique", 1)
	persp.set_item_metadata(1, "isometric")
	persp.add_item("Perspective inclinée", 2)
	persp.set_item_metadata(2, "perspective")
	persp.item_selected.connect(func(_i): perspective_changed.emit())
	add_child(persp)
	widgets["perspective"] = persp

	_section("🌘 Atmosphère")
	widgets["atmo_enabled"] = _checkbox("Teinte d'ambiance", false, func(_on): atmosphere_changed.emit())
	widgets["atmo_tint"] = _color_row("Teinte", "#141018", func(_hex): atmosphere_changed.emit())
	var atmo_row := HBoxContainer.new()
	atmo_row.add_theme_constant_override("separation", 6)
	add_child(atmo_row)
	widgets["atmo_opacity"] = _spin(atmo_row, "Opacité", 0.0, 1.0, 0.12, 0.01, func(_v): atmosphere_changed.emit())
	widgets["atmo_vignette"] = _spin(atmo_row, "Vignettage", 0.0, 1.0, 0.18, 0.01, func(_v): atmosphere_changed.emit())

	_section("💡 Éclairage global")
	widgets["light_enabled"] = _checkbox("Éclairage directionnel", false, func(_on): lighting_changed.emit())
	var light_dir := OptionButton.new()
	var dirs := ["nw", "ne", "sw", "se"]
	var dir_labels := ["Nord-Ouest", "Nord-Est", "Sud-Ouest", "Sud-Est"]
	for i in range(dirs.size()):
		light_dir.add_item(dir_labels[i], i)
		light_dir.set_item_metadata(i, dirs[i])
	light_dir.item_selected.connect(func(_i): lighting_changed.emit())
	add_child(light_dir)
	widgets["light_dir"] = light_dir
	widgets["light_intensity"] = _spin(_hbox(), "Intensité", 0.0, 2.0, 0.35, 0.05, func(_v): lighting_changed.emit())

	_section("🌙 Nuit / lumières")
	widgets["night_mode"] = _checkbox("Mode nuit (révèle le jour)", false, func(_on): night_mode_changed.emit())
	widgets["night_ambient"] = _spin(_hbox(), "Ambiance nuit", 0.05, 1.0, 0.22, 0.01, func(_v): night_mode_changed.emit())
	var night_hint := Label.new()
	night_hint.text = "Comme le brouillard : la carte est nocturne ; chaque lumière révèle le jour dans son rayon. Déplacer une lumière déplace son halo (mis à jour en direct)."
	night_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	night_hint.add_theme_font_size_override("font_size", 10)
	night_hint.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	add_child(night_hint)
	var night_row := HBoxContainer.new()
	night_row.add_theme_constant_override("separation", 4)
	add_child(night_row)
	_text_button(night_row, "Effacer zones éclairées", func(): clear_light_reveal_pressed.emit())

	_section("👁 Affichage éditeur")
	_checkbox("Afficher les liens", true, func(on): show_links_toggled.emit(on))
	_checkbox("Afficher les noms", false, func(on): show_ids_toggled.emit(on))
	_checkbox("Aperçu ligne de vue", false, func(on): show_vision_toggled.emit(on))

	_section("💾 Sauvegarde")
	var policy := OptionButton.new()
	policy.add_item("Manuelle", 0)
	policy.set_item_metadata(0, SAVE_MANUAL)
	policy.add_item("À chaque modification", 1)
	policy.set_item_metadata(1, SAVE_ON_CHANGE)
	policy.add_item("Périodique (30 s)", 2)
	policy.set_item_metadata(2, SAVE_INTERVAL)
	policy.item_selected.connect(func(index):
		save_policy_changed.emit(str(policy.get_item_metadata(index)), policy.get_item_text(index))
	)
	add_child(policy)

	var io_row := HBoxContainer.new()
	io_row.add_theme_constant_override("separation", 4)
	add_child(io_row)
	_text_button(io_row, "⬆ Exporter JSON", func(): export_json_pressed.emit())
	_text_button(io_row, "⬇ Importer JSON", func(): import_json_pressed.emit())

func _section(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	lbl.add_theme_font_size_override("font_size", 12)
	add_child(lbl)

func _hbox() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	return row

func _text_button(parent: Node, text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn

func _spin(parent: Node, label_text: String, min_v: float, max_v: float, value: float, step: float, on_change: Callable) -> SpinBox:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	col.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.set_value_no_signal(clampf(value, min_v, max_v))
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v): on_change.call(v))
	col.add_child(spin)
	return spin

func _checkbox(text: String, value: bool, on_change: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.set_pressed_no_signal(value)
	check.add_theme_font_size_override("font_size", 11)
	check.toggled.connect(func(on): on_change.call(on))
	add_child(check)
	return check

func _line_row(parent: Node, label_text: String, value: String, on_change: Callable) -> LineEdit:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	col.add_child(lbl)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(text): on_change.call(text))
	edit.focus_exited.connect(func(): on_change.call(edit.text))
	col.add_child(edit)
	return edit

func _color_row(label_text: String, value: String, on_change: Callable) -> ColorPickerButton:
	var row := _hbox()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(70, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	row.add_child(lbl)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(64, 26)
	picker.edit_alpha = false
	picker.color = Color.html(value) if not value.is_empty() else Color.WHITE
	picker.color_changed.connect(func(color): on_change.call("#" + color.to_html(false)))
	row.add_child(picker)
	return picker
