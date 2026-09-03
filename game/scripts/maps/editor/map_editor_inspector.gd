extends VBoxContainer
class_name MapEditorInspector

## Inspecteur de l'élément (ou du lot) sélectionné : identité, transformation,
## effets visuels, propriétés spécifiques au type et liens sortants/entrants.
##
## Équivalent du couple caseConfigPanel + visualEffectPanel de Meownopoly.

signal focus_requested(element_id: String)
signal unlink_requested(source_id: String, target_id: String)
signal link_mode_requested(source_id: String)

var doc: MapEditDocument = null
var _suppress: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func set_document(p_doc: MapEditDocument) -> void:
	doc = p_doc
	rebuild()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	if doc == null:
		return
	var selected := doc.selection()
	if selected.is_empty():
		_add_placeholder("Aucune sélection.\nCliquez un élément, ou glissez dans le vide pour un rectangle de sélection.")
		return
	if selected.size() > 1:
		_build_multi(selected)
		return
	_build_single(doc.get_element(str(selected[0])))

# ===========================================================================
# Construction
# ===========================================================================

func _build_single(elem: Dictionary) -> void:
	if elem.is_empty():
		return
	var kind := str(elem.get("kind", ""))
	_title("%s %s" % [MapEditDocument.KIND_ICONS.get(kind, "•"), MapEditDocument.KIND_LABELS.get(kind, kind)])

	_line_edit("Nom", str(elem.get("label", "")), func(text): _apply({"label": text}, "Renommage"))

	_section("Position & taille")
	var pos_row := _row()
	_spin(pos_row, "X", -999.0, 999.0, float(elem.get("x", 0.0)), 0.25,
		func(v): _apply({"x": v}, "Position"))
	_spin(pos_row, "Y", -999.0, 999.0, float(elem.get("y", 0.0)), 0.25,
		func(v): _apply({"y": v}, "Position"))
	var size_row := _row()
	_spin(size_row, "Largeur", 0.25, 64.0, float(elem.get("w", 1.0)), 0.25,
		func(v): _apply({"w": v}, "Taille"))
	_spin(size_row, "Hauteur", 0.25, 64.0, float(elem.get("h", 1.0)), 0.25,
		func(v): _apply({"h": v}, "Taille"))

	var display: Dictionary = elem.get("display", {}) if elem.get("display") is Dictionary else {}
	_section("Effets visuels")
	var fx_row := _row()
	_spin(fx_row, "Rotation °", -180.0, 180.0, float(display.get("rotation", 0.0)), 5.0,
		func(v): _apply({"display": {"rotation": v}}, "Rotation"))
	_spin(fx_row, "Opacité", 0.0, 1.0, float(display.get("opacity", 1.0)), 0.05,
		func(v): _apply({"display": {"opacity": v}}, "Opacité"))
	var fx_row2 := _row()
	_spin(fx_row2, "Échelle", 0.25, 4.0, float(display.get("scale", 1.0)), 0.05,
		func(v): _apply({"display": {"scale": v}}, "Échelle"))
	_spin(fx_row2, "Luminosité", -1.0, 1.0, float(display.get("brightness", 0.0)), 0.05,
		func(v): _apply({"display": {"brightness": v}}, "Luminosité"))
	var mirror_row := _row()
	_check(mirror_row, "Miroir ↔", bool(display.get("mirrorH", false)),
		func(on): _apply({"display": {"mirrorH": on}}, "Miroir"))
	_check(mirror_row, "Miroir ↕", bool(display.get("mirrorV", false)),
		func(on): _apply({"display": {"mirrorV": on}}, "Miroir"))
	_color_field("Teinte", str(display.get("tint", "")),
		func(hex): _apply({"display": {"tint": hex}}, "Teinte"))

	_build_kind_fields(elem, kind)

	_section("Organisation")
	_layer_selector(int(elem.get("layer", 3)))
	var flags_row := _row()
	_check(flags_row, "Verrouillé", bool(elem.get("locked", false)),
		func(on): _apply({"locked": on}, "Verrou"))
	_check(flags_row, "Masqué", bool(elem.get("hidden", false)),
		func(on): _apply({"hidden": on}, "Visibilité"))
	if not str(elem.get("group", "")).is_empty():
		_add_note("Membre d'un groupe (Ctrl+Maj+G pour dégrouper)")

	_multiline("Notes MJ", str(elem.get("notes", "")),
		func(text): _apply({"notes": text}, "Notes"))

	_build_links(elem)

func _build_multi(selected: Array) -> void:
	_title("🎯 %d éléments sélectionnés" % selected.size())
	var kinds: Dictionary = {}
	for id in selected:
		kinds[str(doc.get_element(str(id)).get("kind", "?"))] = true
	_add_note("Types : %s" % ", ".join(kinds.keys()))

	_section("Appliquer à toute la sélection")
	var fx_row := _row()
	_spin(fx_row, "Rotation °", -180.0, 180.0, 0.0, 5.0,
		func(v): _apply({"display": {"rotation": v}}, "Rotation"))
	_spin(fx_row, "Opacité", 0.0, 1.0, 1.0, 0.05,
		func(v): _apply({"display": {"opacity": v}}, "Opacité"))
	_color_field("Teinte", "", func(hex): _apply({"display": {"tint": hex}}, "Teinte"))
	_layer_selector(int(doc.get_element(str(selected[0])).get("layer", 3)))
	var flags_row := _row()
	_check(flags_row, "Verrouillé", false, func(on): _apply({"locked": on}, "Verrou"))
	_check(flags_row, "Masqué", false, func(on): _apply({"hidden": on}, "Visibilité"))

	_section("Éléments")
	for id_variant in selected:
		var id := str(id_variant)
		var elem: Dictionary = doc.get_element(id)
		var row := _row()
		var btn := Button.new()
		btn.text = "%s %s" % [MapEditDocument.KIND_ICONS.get(str(elem.get("kind", "")), "•"), elem.get("label", id)]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func(): focus_requested.emit(id))
		row.add_child(btn)

func _build_kind_fields(elem: Dictionary, kind: String) -> void:
	if kind == MapEditDocument.KIND_TOKEN:
		_section("Token")
		_portrait_field(str(elem.get("image", "")))
		var size_row := _row()
		_spin(size_row, "Vision (cases)", 0.0, 40.0, float(elem.get("visionRadius", MapVision.DEFAULT_VISION_RADIUS)), 0.5,
			func(v): _apply({"visionRadius": v}, "Vision"))
		_check(size_row, "Porte la vue", bool(elem.get("providesVision", true)),
			func(on): _apply({"providesVision": on}, "Vision"))
		_color_field("Couleur", str(elem.get("color", "#e8c547")),
			func(hex): _apply({"color": hex}, "Couleur"))
		_line_edit("Emoji", str(elem.get("emoji", "")),
			func(text): _apply({"emoji": text}, "Emoji"))
		_line_edit("Identifiant membre", str(elem.get("memberId", "")),
			func(text): _apply({"memberId": text}, "Membre"))
	elif kind == MapEditDocument.KIND_MARKER:
		_section("Marqueur")
		_marker_selector(str(elem.get("markerType", "npc")))
	elif kind == MapEditDocument.KIND_EFFECT:
		_section("Effet")
		_preset_selector(str(elem.get("preset", "fire")))
		var row := _row()
		_spin(row, "Rayon", 0.25, 8.0, float(elem.get("radius", 1.0)), 0.25,
			func(v): _apply({"radius": v, "w": v * 2.0, "h": v * 2.0}, "Rayon"))
		_check(row, "Actif", bool(elem.get("triggered", false)),
			func(on): _apply({"triggered": on}, "Déclenchement"))
	elif kind == MapEditDocument.KIND_ZONE:
		_section("Zone")
		_shape_selector(str(elem.get("shape", "circle")))
		_spin(_row(), "Rayon", 0.25, 12.0, float(elem.get("radius", 1.5)), 0.25,
			func(v): _apply({"radius": v, "w": v * 2.0, "h": v * 2.0}, "Rayon"))
		_color_field("Couleur", str(elem.get("color", "#c9a227")),
			func(hex): _apply({"color": hex}, "Couleur"))
	elif kind == MapEditDocument.KIND_PLATFORM:
		_section("Plateforme")
		var row := _row()
		_spin(row, "Élévation", 0.1, 6.0, float(elem.get("elevation", 1.0)), 0.1,
			func(v): _apply({"elevation": v}, "Élévation"))
		_spin(row, "Opacité", 0.05, 1.0, float(elem.get("opacity", 0.38)), 0.05,
			func(v): _apply({"opacity": v}, "Opacité"))
		_color_field("Teinte", str(elem.get("tint", "#8a7a60")),
			func(hex): _apply({"tint": hex}, "Teinte"))
	elif kind == MapEditDocument.KIND_OVERLAY:
		_section("Calque image")
		_add_note(str(elem.get("image", "")).get_file())
		var row := _row()
		_spin(row, "Élévation", 0.0, 6.0, float(elem.get("elevation", 0.18)), 0.02,
			func(v): _apply({"elevation": v}, "Élévation"))
		_spin(row, "Opacité", 0.05, 1.0, float(elem.get("opacity", 0.92)), 0.05,
			func(v): _apply({"opacity": v}, "Opacité"))
	elif kind == MapEditDocument.KIND_WALL:
		_section("Mur")
		var row := _row()
		_spin(row, "Hauteur", 0.2, 6.0, float(elem.get("height", 1.4)), 0.1,
			func(v): _apply({"height": v}, "Hauteur"))
		_spin(row, "Épaisseur", 0.05, 2.0, float(elem.get("h", 0.25)), 0.05,
			func(v): _apply({"h": v}, "Épaisseur"))
		_color_field("Couleur", str(elem.get("color", "#4a423a")),
			func(hex): _apply({"color": hex}, "Couleur"))
		var sight_row := _row()
		_check(sight_row, "Bloque la vue", bool(elem.get("blocksSight", true)),
			func(on): _apply({"blocksSight": on}, "Occlusion"))
		_check(sight_row, "Porte", bool(elem.get("isDoor", false)),
			func(on): _apply({"isDoor": on}, "Porte"))
		if bool(elem.get("isDoor", false)):
			_check(_row(), "Ouverte au départ", bool(elem.get("open", false)),
				func(on): _apply({"open": on}, "Porte"))
			_add_note("Une porte ouverte ne bloque plus la ligne de vue. En session, le MJ l'ouvre et le brouillard se recalcule.")
	elif kind == MapEditDocument.KIND_LIGHT:
		_section("Lumière")
		var row := _row()
		_spin(row, "Rayon", 0.5, 24.0, float(elem.get("radius", 3.0)), 0.5,
			func(v): _apply({"radius": v}, "Rayon"))
		_spin(row, "Intensité", 0.1, 6.0, float(elem.get("energy", 1.6)), 0.1,
			func(v): _apply({"energy": v}, "Intensité"))
		_color_field("Couleur", str(elem.get("color", "#ffb35c")),
			func(hex): _apply({"color": hex}, "Couleur"))
		var flags := _row()
		_check(flags, "Vacille", bool(elem.get("flicker", true)),
			func(on): _apply({"flicker": on}, "Vacillement"))
		_check(flags, "Ombres", bool(elem.get("shadows", false)),
			func(on): _apply({"shadows": on}, "Ombres"))
	elif kind == MapEditDocument.KIND_NOTE:
		_section("Note MJ")
		_multiline("Texte", str(elem.get("text", "")),
			func(text): _apply({"text": text}, "Note"))
	elif kind == MapEditDocument.KIND_LINK:
		_section("Passage vers une scène")
		_target_map_selector(str(elem.get("targetMapId", "")))

func _build_links(elem: Dictionary) -> void:
	_section("Liens")
	var id := str(elem.get("id", ""))
	var links: Dictionary = elem.get("links", {}) if elem.get("links") is Dictionary else {}
	var btn_link := Button.new()
	btn_link.text = "🔗 Lier vers…"
	btn_link.tooltip_text = "Puis cliquez l'élément cible sur la carte"
	btn_link.pressed.connect(func(): link_mode_requested.emit(id))
	add_child(btn_link)
	var next_list: Array = links.get("next", [])
	var prev_list: Array = links.get("prev", [])
	if next_list.is_empty() and prev_list.is_empty():
		_add_note("Aucun lien.")
		return
	for target_variant in next_list:
		var target_id := str(target_variant)
		var row := _row()
		var lbl := Label.new()
		lbl.text = "→ %s" % doc.get_element(target_id).get("label", target_id)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.clip_text = true
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "✕"
		btn.custom_minimum_size = Vector2(26, 22)
		btn.pressed.connect(func(): unlink_requested.emit(id, target_id))
		row.add_child(btn)
	for source_variant in prev_list:
		var source_id := str(source_variant)
		var lbl := Label.new()
		lbl.text = "← %s" % doc.get_element(source_id).get("label", source_id)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		add_child(lbl)

# ===========================================================================
# Sélecteurs spécialisés
# ===========================================================================

func _layer_selector(current: int) -> void:
	var row := _row()
	var lbl := Label.new()
	lbl.text = "Calque"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	row.add_child(lbl)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var layers: Array = doc.map_data.get("layers", [])
	for i in range(layers.size()):
		var layer_def: Dictionary = layers[i]
		option.add_item(str(layer_def.get("name", "Calque")), i)
		option.set_item_metadata(i, int(layer_def.get("id", i)))
		if int(layer_def.get("id", i)) == current:
			option.select(i)
	option.item_selected.connect(func(index):
		_apply({"layer": int(option.get_item_metadata(index))}, "Calque")
	)
	row.add_child(option)

func _marker_selector(current: String) -> void:
	var option := OptionButton.new()
	var types: Array = MapData.get_editor_marker_types(doc.map_data)
	for i in range(types.size()):
		var marker_id := str(types[i])
		option.add_item("%s %s" % [MapData.get_marker_emoji(marker_id), MapData.get_marker_label(marker_id)], i)
		option.set_item_metadata(i, marker_id)
		if marker_id == current:
			option.select(i)
	option.item_selected.connect(func(index):
		var marker_id := str(option.get_item_metadata(index))
		_apply({"markerType": marker_id, "label": MapData.get_marker_label(marker_id)}, "Type marqueur")
	)
	add_child(option)

func _preset_selector(current: String) -> void:
	var option := OptionButton.new()
	var presets: Array = MapEffectPresets.PRESET_IDS
	for i in range(presets.size()):
		var preset_id := str(presets[i])
		var preset := MapEffectPresets.get_preset(preset_id)
		option.add_item("%s %s" % [preset.get("emoji", "✨"), preset.get("label", preset_id)], i)
		option.set_item_metadata(i, preset_id)
		if preset_id == current:
			option.select(i)
	option.item_selected.connect(func(index):
		_apply({"preset": str(option.get_item_metadata(index))}, "Preset")
	)
	add_child(option)

func _shape_selector(current: String) -> void:
	var option := OptionButton.new()
	var shapes := [["circle", "⭕ Cercle"], ["rect", "▭ Rectangle"], ["polygon", "⬡ Polygone"], ["cone", "🔺 Cône"]]
	for i in range(shapes.size()):
		option.add_item(str(shapes[i][1]), i)
		option.set_item_metadata(i, str(shapes[i][0]))
		if str(shapes[i][0]) == current:
			option.select(i)
	option.item_selected.connect(func(index):
		_apply({"shape": str(option.get_item_metadata(index))}, "Forme")
	)
	add_child(option)

func _target_map_selector(current: String) -> void:
	var option := OptionButton.new()
	option.add_item("— Aucune —", 0)
	option.set_item_metadata(0, "")
	var roster := str(doc.map_data.get("roster", "general"))
	var candidates: Array = MapData.get_local_maps_for_linking(roster)
	for i in range(candidates.size()):
		var candidate: Dictionary = candidates[i]
		option.add_item(str(candidate.get("title", "Carte")), i + 1)
		option.set_item_metadata(i + 1, str(candidate.get("id", "")))
		if str(candidate.get("id", "")) == current:
			option.select(i + 1)
	option.item_selected.connect(func(index):
		_apply({"targetMapId": str(option.get_item_metadata(index))}, "Destination")
	)
	add_child(option)

# ===========================================================================
# Fabrique de widgets
# ===========================================================================

func _apply(mutations: Dictionary, note: String) -> void:
	if _suppress or doc == null:
		return
	doc.modify_selection(mutations, note)

func _title(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	lbl.add_theme_font_size_override("font_size", 14)
	add_child(lbl)

func _section(text: String) -> void:
	var sep := HSeparator.new()
	add_child(sep)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	lbl.add_theme_font_size_override("font_size", 12)
	add_child(lbl)

func _add_note(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	add_child(lbl)

func _add_placeholder(text: String) -> void:
	_add_note(text)

func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	return row

func _spin(parent: HBoxContainer, label_text: String, min_v: float, max_v: float, value: float, step: float, on_change: Callable) -> SpinBox:
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
	spin.allow_greater = false
	spin.set_value_no_signal(clampf(value, min_v, max_v))
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v): on_change.call(v))
	col.add_child(spin)
	return spin

func _check(parent: HBoxContainer, label_text: String, value: bool, on_change: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = label_text
	check.set_pressed_no_signal(value)
	check.add_theme_font_size_override("font_size", 11)
	check.toggled.connect(func(on): on_change.call(on))
	parent.add_child(check)
	return check

func _line_edit(label_text: String, value: String, on_change: Callable) -> LineEdit:
	var row := _row()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(76, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	row.add_child(lbl)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# On valide à la sortie du champ pour ne pas créer un delta par caractère.
	edit.text_submitted.connect(func(text): on_change.call(text))
	edit.focus_exited.connect(func(): on_change.call(edit.text))
	row.add_child(edit)
	return edit

func _multiline(label_text: String, value: String, on_change: Callable) -> TextEdit:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	add_child(lbl)
	var edit := TextEdit.new()
	edit.text = value
	edit.custom_minimum_size = Vector2(0, 60)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.focus_exited.connect(func(): on_change.call(edit.text))
	add_child(edit)
	return edit

## Avatar du token : aperçu, import depuis le disque, réutilisation des
## portraits déjà importés, retour au disque coloré par défaut.
func _portrait_field(current: String) -> void:
	var row := _row()
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(48, 48)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not current.is_empty():
		preview.texture = MapData.load_token_portrait(current)
	row.add_child(preview)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 2)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(actions)

	var import_btn := Button.new()
	import_btn.text = "Importer une image…"
	import_btn.pressed.connect(_open_portrait_dialog)
	actions.add_child(import_btn)

	var known: Array = MapData.list_token_images()
	if not known.is_empty():
		var picker := OptionButton.new()
		picker.add_item("— Portraits importés —", 0)
		picker.set_item_metadata(0, "")
		for i in range(known.size()):
			picker.add_item(str(known[i]).get_file(), i + 1)
			picker.set_item_metadata(i + 1, str(known[i]))
			if str(known[i]) == current:
				picker.select(i + 1)
		picker.item_selected.connect(func(index):
			var path := str(picker.get_item_metadata(index))
			if not path.is_empty():
				_apply({"image": path}, "Portrait")
		)
		actions.add_child(picker)

	if not current.is_empty():
		var clear_btn := Button.new()
		clear_btn.text = "✕ Retirer l'image"
		clear_btn.pressed.connect(func(): _apply({"image": ""}, "Portrait"))
		actions.add_child(clear_btn)

func _open_portrait_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.title = "Portrait du token"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray([
		"*.png ; Images PNG", "*.jpg, *.jpeg ; Images JPEG", "*.webp ; Images WebP",
	])
	dialog.file_selected.connect(func(path):
		var dest := MapData.import_token_image(path)
		if not dest.is_empty():
			_apply({"image": dest}, "Portrait")
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(760, 500))

func _color_field(label_text: String, value: String, on_change: Callable) -> void:
	var row := _row()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(76, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	row.add_child(lbl)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(56, 26)
	picker.edit_alpha = false
	if not value.is_empty():
		picker.color = Color.html(value)
	picker.color_changed.connect(func(color): on_change.call("#" + color.to_html(false)))
	row.add_child(picker)
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = "#rrggbb"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(text): on_change.call(text.strip_edges()))
	row.add_child(edit)
