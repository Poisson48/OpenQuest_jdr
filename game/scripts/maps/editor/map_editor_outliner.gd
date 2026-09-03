extends VBoxContainer
class_name MapEditorOutliner

## Arborescence des éléments de la carte, groupés par calque.
## Recherche, visibilité/verrou par calque et par élément, sélection croisée
## avec la vue 3D, recadrage au double-clic.

signal focus_requested(element_id: String)

var doc: MapEditDocument = null

var _search: LineEdit
var _tree_host: VBoxContainer
var _counter: Label
var _filter: String = ""
var _collapsed: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	add_child(header)

	_search = LineEdit.new()
	_search.placeholder_text = "Rechercher un élément…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(text):
		_filter = text.strip_edges().to_lower()
		rebuild()
	)
	header.add_child(_search)

	_counter = Label.new()
	_counter.add_theme_font_size_override("font_size", 11)
	_counter.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	add_child(_counter)

	_tree_host = VBoxContainer.new()
	_tree_host.add_theme_constant_override("separation", 1)
	_tree_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_tree_host)

func set_document(p_doc: MapEditDocument) -> void:
	doc = p_doc
	rebuild()

func rebuild() -> void:
	if _tree_host == null:
		return
	for child in _tree_host.get_children():
		child.queue_free()
	if doc == null:
		return

	var by_layer: Dictionary = {}
	var total := 0
	for elem_variant in doc.elements_sorted():
		var elem: Dictionary = elem_variant
		total += 1
		if not _matches(elem):
			continue
		var layer := int(elem.get("layer", 0))
		if not by_layer.has(layer):
			by_layer[layer] = []
		by_layer[layer].append(elem)

	var shown := 0
	for entry in by_layer.values():
		shown += (entry as Array).size()
	_counter.text = "%d élément(s)%s" % [total, "" if _filter.is_empty() else " · %d affiché(s)" % shown]

	var layers: Array = doc.map_data.get("layers", [])
	for layer_variant in layers:
		var layer_def: Dictionary = layer_variant
		var layer_id := int(layer_def.get("id", 0))
		var items: Array = by_layer.get(layer_id, [])
		if items.is_empty() and not _filter.is_empty():
			continue
		_add_layer_header(layer_def, items.size())
		if _collapsed.get(layer_id, false):
			continue
		for elem_variant in items:
			_add_element_row(elem_variant)

	# Éléments dont le calque n'existe plus.
	for layer_id in by_layer.keys():
		var known := false
		for layer_variant in layers:
			if int((layer_variant as Dictionary).get("id", -1)) == int(layer_id):
				known = true
				break
		if known:
			continue
		_add_orphan_header(int(layer_id))
		for elem_variant in by_layer[layer_id]:
			_add_element_row(elem_variant)

func _matches(elem: Dictionary) -> bool:
	if _filter.is_empty():
		return true
	var haystack := "%s %s %s %s" % [
		elem.get("label", ""), elem.get("kind", ""),
		elem.get("markerType", ""), elem.get("notes", ""),
	]
	return haystack.to_lower().contains(_filter)

func _add_layer_header(layer_def: Dictionary, count: int) -> void:
	var layer_id := int(layer_def.get("id", 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_tree_host.add_child(row)

	var toggle := Button.new()
	toggle.text = "▸" if _collapsed.get(layer_id, false) else "▾"
	toggle.flat = true
	toggle.custom_minimum_size = Vector2(20, 22)
	toggle.pressed.connect(func():
		_collapsed[layer_id] = not _collapsed.get(layer_id, false)
		rebuild()
	)
	row.add_child(toggle)

	var name_lbl := Label.new()
	name_lbl.text = "%s (%d)" % [layer_def.get("name", "Calque"), count]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	row.add_child(name_lbl)

	var visible_btn := Button.new()
	visible_btn.text = "👁" if bool(layer_def.get("visible", true)) else "🚫"
	visible_btn.flat = true
	visible_btn.tooltip_text = "Afficher / masquer le calque"
	visible_btn.custom_minimum_size = Vector2(26, 22)
	visible_btn.pressed.connect(func():
		doc.set_layer_visible(layer_id, not bool(layer_def.get("visible", true)))
	)
	row.add_child(visible_btn)

	var lock_btn := Button.new()
	lock_btn.text = "🔒" if bool(layer_def.get("locked", false)) else "🔓"
	lock_btn.flat = true
	lock_btn.tooltip_text = "Verrouiller le calque"
	lock_btn.custom_minimum_size = Vector2(26, 22)
	lock_btn.pressed.connect(func():
		doc.set_layer_locked(layer_id, not bool(layer_def.get("locked", false)))
	)
	row.add_child(lock_btn)

func _add_orphan_header(layer_id: int) -> void:
	var lbl := Label.new()
	lbl.text = "Calque %d (hors liste)" % layer_id
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_tree_host.add_child(lbl)

func _add_element_row(elem: Dictionary) -> void:
	var id := str(elem.get("id", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_tree_host.add_child(row)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(14, 0)
	row.add_child(spacer)

	var btn := Button.new()
	var icon := str(MapEditDocument.KIND_ICONS.get(str(elem.get("kind", "")), "•"))
	btn.text = "%s %s" % [icon, elem.get("label", id)]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	btn.clip_text = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 22)
	btn.tooltip_text = "%s — (%.1f, %.1f)\nClic : sélectionner · Ctrl+clic : ajouter" % [
		MapEditDocument.KIND_LABELS.get(str(elem.get("kind", "")), "Élément"),
		float(elem.get("x", 0.0)), float(elem.get("y", 0.0)),
	]
	if doc.is_selected(id):
		btn.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	elif not doc.is_element_visible(elem):
		btn.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	btn.pressed.connect(func():
		if Input.is_key_pressed(KEY_CTRL):
			doc.toggle_selection(id)
		else:
			doc.select_only(id)
	)
	btn.gui_input.connect(func(event):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
				focus_requested.emit(id)
	)
	row.add_child(btn)

	var eye := Button.new()
	eye.text = "👁" if not bool(elem.get("hidden", false)) else "🚫"
	eye.flat = true
	eye.custom_minimum_size = Vector2(24, 22)
	eye.tooltip_text = "Afficher / masquer"
	eye.pressed.connect(func():
		doc.modify_element(id, {"hidden": not bool(elem.get("hidden", false))}, "Visibilité")
	)
	row.add_child(eye)

	var lock := Button.new()
	lock.text = "🔒" if bool(elem.get("locked", false)) else "🔓"
	lock.flat = true
	lock.custom_minimum_size = Vector2(24, 22)
	lock.tooltip_text = "Verrouiller"
	lock.pressed.connect(func():
		doc.modify_element(id, {"locked": not bool(elem.get("locked", false))}, "Verrou")
	)
	row.add_child(lock)

	var del := Button.new()
	del.text = "✕"
	del.flat = true
	del.custom_minimum_size = Vector2(24, 22)
	del.tooltip_text = "Supprimer"
	del.pressed.connect(func(): doc.remove_element(id))
	row.add_child(del)
