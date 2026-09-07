extends Control

## Éditeur 2D (mode Simple) : même flux que l'éditeur complexe
## (outils, inspecteur, calques, biblio, undo) sur InteractiveMap.

signal open_map_requested(map_id: String)
signal place_on_world_requested(world_id: String, local_id: String)
signal save_requested

const InteractiveMapScript := preload("res://scripts/interactive_map.gd")
const DocumentScript := preload("res://scripts/maps/editor/map_edit_document.gd")
const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")
const AssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")

var doc = DocumentScript.new()
var _editable: bool = true
var _tool: String = ToolsScript.PAINT
var _snap_mode: String = "cell"
var _paint_tile: String = "grass"
var _marker_type: String = "npc"
var _area_label: String = ""
var _area_category: String = "building"
var _prop_asset: String = ""
var _prop_size: float = 2.0
var _brush_size: int = 0
var _link_target: String = ""
var _link_label: String = ""
var _note_text: String = "Note MJ"
var _moving: bool = false
var _move_origin: Vector2 = Vector2.ZERO
var _move_start: Vector2 = Vector2.ZERO
var _rect_from: Vector2i = Vector2i(-1, -1)
var _preview_from: Vector2i = Vector2i(-1, -1)
var _preview_to: Vector2i = Vector2i(-1, -1)
var _paint_tx: bool = false

var _imap: Control
var _tool_buttons: Dictionary = {}
var _left_scroll: ScrollContainer
var _right_tabs: TabContainer
var _tool_options: VBoxContainer
var _hint_lbl: Label
var _status_lbl: Label
var _zoom_lbl: Label
var _undo_btn: Button
var _redo_btn: Button
var _inspector
var _outliner
var _settings
var _library
var _history
var _esc
var _link_target_select: OptionButton
var _link_label_input: LineEdit
var _world_select: OptionButton
var _integration_status: Label

func _ready() -> void:
	_bind_ui()
	doc.changed.connect(_on_doc_changed)
	doc.selection_changed.connect(_on_selection_changed)
	doc.history_changed.connect(_on_history_changed)

func set_editable(on: bool) -> void:
	_editable = on
	if _left_scroll:
		_left_scroll.visible = on
	if _right_tabs:
		_right_tabs.visible = on
	_update_hint()
	_sync_view()

func load_map(map_data: Dictionary) -> void:
	doc.load_map(map_data)
	_paint_tile = _default_tile()
	_marker_type = _default_marker()
	if _settings:
		_settings.sync_from(doc.map_data)
	_rebuild_library()
	_refresh_link_ui()
	_refresh_panels()
	_sync_view(true)
	_update_hint()
	_on_history_changed()

func apply_to_map_data() -> Dictionary:
	return doc.to_map_data()

func save_now() -> void:
	var snapshot := apply_to_map_data()
	MapData.update_map(snapshot)
	doc.mark_saved()
	_set_status("Carte enregistrée.")
	save_requested.emit()

func apply_title(title: String) -> void:
	if title.is_empty():
		title = "Carte sans titre"
	doc.map_data["title"] = title

func mark_saved() -> void:
	doc.mark_saved()

# ===========================================================================
# UI
# ===========================================================================

func _bind_ui() -> void:
	_left_scroll = %LeftScroll
	_right_tabs = %RightTabs
	_tool_options = %ToolOptions
	_hint_lbl = %LblHint
	_inspector = %Inspector
	_outliner = %Outliner
	_settings = %Settings
	_library = %Library
	_history = %History
	_esc = %EscMenu

	_populate_tools(%ToolHost)
	_populate_snap(%SnapOption)

	var action := %ActionBar
	_undo_btn = action.get_node("%BtnUndo")
	_redo_btn = action.get_node("%BtnRedo")
	_zoom_lbl = action.get_node("%LblZoom")
	_status_lbl = action.get_node("%LblStatus")
	_undo_btn.pressed.connect(func(): doc.undo())
	_redo_btn.pressed.connect(func(): doc.redo())
	action.get_node("%BtnZoomOut").pressed.connect(func(): _imap.zoom_out())
	action.get_node("%BtnZoomIn").pressed.connect(func(): _imap.zoom_in())
	action.get_node("%BtnZoomReset").pressed.connect(func(): _imap.reset_zoom())
	action.get_node("%BtnMenu").pressed.connect(func(): _esc.open_centered())

	var stage := %SimpleStage
	stage.get_node("%MapHeader").visible = false
	_imap = InteractiveMapScript.new()
	_imap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_imap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_imap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_imap.custom_minimum_size = Vector2(160, 120)
	_imap.suppress_navigation = true
	_imap.cell_clicked.connect(_on_cell_clicked)
	_imap.cell_paint.connect(_on_cell_paint)
	_imap.paint_drag_finished.connect(_on_paint_finished)
	_imap.cell_drag_started.connect(_on_drag_started)
	_imap.cell_dragged.connect(_on_dragged)
	_imap.cell_drag_ended.connect(_on_drag_ended)
	_imap.rect_preview.connect(_on_rect_preview)
	_imap.zoom_changed.connect(func(_z): _update_zoom_label())
	stage.get_node("%MapHost").add_child(_imap)

	_inspector.set_document(doc)
	_outliner.set_document(doc)
	_inspector.focus_requested.connect(func(id): doc.select_only(id))
	_inspector.child_map_requested.connect(_create_child_map)
	_inspector.open_map_requested.connect(func(map_id): open_map_requested.emit(map_id))
	_outliner.focus_requested.connect(func(id):
		doc.select_only(id)
		_focus_selection()
	)

	_settings.size_changed.connect(_on_size_changed)
	_settings.fog_setting_changed.connect(_on_fog_setting)
	_settings.measure_changed.connect(_on_measure_changed)
	_settings.fog_hide_all_pressed.connect(func():
		doc.set_fog_cells([], "Tout masquer")
		_sync_view()
	)
	_settings.fog_reveal_all_pressed.connect(func():
		doc.reveal_all_fog()
		_sync_view()
	)

	_library.tile_picked.connect(func(tile_id):
		_paint_tile = tile_id
		_set_tool(ToolsScript.PAINT)
	)
	_library.marker_picked.connect(func(marker_id):
		_marker_type = marker_id
		_set_tool(ToolsScript.MARKER)
	)
	_library.prop_picked.connect(func(path, size):
		_prop_asset = path
		_prop_size = size
		_set_tool(ToolsScript.PROP)
		_set_status("Décor armé — cliquez la grille.")
	)
	_library.refresh_assets_pressed.connect(func(): _library.rebuild_props())

	_history.undo_pressed.connect(func(): doc.undo())
	_history.redo_pressed.connect(func(): doc.redo())

	_esc.save_pressed.connect(save_now)
	_esc.undo_pressed.connect(func(): doc.undo())
	_esc.redo_pressed.connect(func(): doc.redo())
	_esc.fit_view_pressed.connect(func(): _imap.reset_zoom())
	_esc.clear_selection_pressed.connect(func(): doc.clear_selection())
	_set_tool(ToolsScript.PAINT)

func _populate_tools(host: VBoxContainer) -> void:
	for child in host.get_children():
		child.queue_free()
	_tool_buttons.clear()
	for group in ToolsScript.GROUP_ORDER:
		var defs: Array = ToolsScript.simple_defs_in_group(group)
		if defs.is_empty():
			continue
		var lbl := Label.new()
		lbl.text = str(ToolsScript.GROUP_LABELS.get(group, group))
		lbl.theme_type_variation = &"HeadingLabel"
		lbl.add_theme_font_size_override("font_size", 12)
		host.add_child(lbl)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.add_child(row)
		for def_variant in defs:
			var def: Dictionary = def_variant
			var btn := Button.new()
			btn.toggle_mode = true
			btn.text = "%s %s" % [def.get("icon", ""), def.get("label", "")]
			btn.tooltip_text = ToolsScript.tooltip(str(def["id"]))
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(0, 30)
			var tool_id := str(def["id"])
			btn.pressed.connect(func(): _set_tool(tool_id))
			row.add_child(btn)
			_tool_buttons[tool_id] = btn

func _populate_snap(opt: OptionButton) -> void:
	opt.clear()
	var idx := 0
	for mode in ToolsScript.SNAP_MODES:
		opt.add_item(str(mode["label"]), idx)
		opt.set_item_metadata(idx, str(mode["id"]))
		if str(mode["id"]) == _snap_mode:
			opt.selected = idx
		idx += 1
	opt.item_selected.connect(func(i):
		_snap_mode = str(opt.get_item_metadata(i))
	)

func _rebuild_tool_options() -> void:
	for child in _tool_options.get_children():
		child.queue_free()
	_link_target_select = null
	_link_label_input = null
	_world_select = null
	_integration_status = null
	match _tool:
		ToolsScript.PAINT, ToolsScript.BUCKET:
			_add_option_label("Tuile")
			_add_tile_buttons()
			if _tool == ToolsScript.PAINT:
				_add_brush_spin()
		ToolsScript.MARKER:
			_add_option_label("Type")
			_add_marker_buttons()
		ToolsScript.AREA:
			_add_option_label("Nom du lieu")
			var edit := LineEdit.new()
			edit.placeholder_text = "Taverne, place…"
			edit.text = _area_label
			edit.text_changed.connect(func(t): _area_label = t)
			_tool_options.add_child(edit)
			_add_option_label("Catégorie")
			var cat := OptionButton.new()
			var i := 0
			for entry in MapData.AREA_CATEGORIES:
				cat.add_item("%s %s" % [entry.get("icon", ""), entry.get("label", "")], i)
				cat.set_item_metadata(i, str(entry.get("id", "")))
				if str(entry.get("id", "")) == _area_category:
					cat.selected = i
				i += 1
			cat.item_selected.connect(func(idx):
				_area_category = str(cat.get_item_metadata(idx))
			)
			_tool_options.add_child(cat)
		ToolsScript.NOTE:
			var edit := LineEdit.new()
			edit.placeholder_text = "Texte de la note"
			edit.text = _note_text
			edit.text_changed.connect(func(t): _note_text = t)
			_tool_options.add_child(edit)
		ToolsScript.PROP:
			var hint := Label.new()
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.theme_type_variation = &"CaptionLabel"
			hint.text = "Choisissez un décor dans l'onglet Biblio, puis cliquez la grille."
			_tool_options.add_child(hint)
		ToolsScript.LINK:
			_build_link_options()
		ToolsScript.FOG_REVEAL, ToolsScript.FOG_HIDE:
			_add_brush_spin()
		_:
			if not MapData.is_world_map(doc.map_data) and _editable:
				_build_integration_options()

func _add_option_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.theme_type_variation = &"CaptionLabel"
	_tool_options.add_child(lbl)

func _add_tile_buttons() -> void:
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", 4)
	box.add_theme_constant_override("v_separation", 4)
	_tool_options.add_child(box)
	var tiles: Dictionary = MapData.get_tile_palette(doc.map_data)
	for tile_id in tiles.keys():
		var def: Dictionary = tiles[tile_id]
		var btn := Button.new()
		btn.text = str(def.get("label", tile_id))
		btn.toggle_mode = true
		btn.button_pressed = tile_id == _paint_tile
		btn.custom_minimum_size = Vector2(0, 28)
		var tid := str(tile_id)
		btn.pressed.connect(func():
			_paint_tile = tid
			_rebuild_tool_options()
		)
		box.add_child(btn)

func _add_marker_buttons() -> void:
	var box := VBoxContainer.new()
	_tool_options.add_child(box)
	for marker_id in MapData.get_editor_marker_types(doc.map_data):
		var btn := Button.new()
		btn.text = "%s %s" % [MapData.get_marker_emoji(marker_id), MapData.get_marker_label(marker_id)]
		btn.toggle_mode = true
		btn.button_pressed = marker_id == _marker_type
		var mid := str(marker_id)
		btn.pressed.connect(func():
			_marker_type = mid
			_rebuild_tool_options()
		)
		box.add_child(btn)

func _add_brush_spin() -> void:
	_add_option_label("Taille de pinceau")
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 3
	spin.value = _brush_size
	spin.value_changed.connect(func(v): _brush_size = int(v))
	_tool_options.add_child(spin)

func _build_link_options() -> void:
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.theme_type_variation = &"CaptionLabel"
	hint.text = "Relie une case du monde à une scène locale."
	_tool_options.add_child(hint)
	_link_target_select = OptionButton.new()
	_link_label_input = LineEdit.new()
	_link_label_input.placeholder_text = "Nom sur la carte"
	_tool_options.add_child(_link_target_select)
	_tool_options.add_child(_link_label_input)
	_refresh_link_ui()

func _build_integration_options() -> void:
	var title := Label.new()
	title.text = "🌍 Carte monde"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override("font_size", 12)
	_tool_options.add_child(title)
	_integration_status = Label.new()
	_integration_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_integration_status.theme_type_variation = &"CaptionLabel"
	_tool_options.add_child(_integration_status)
	_world_select = OptionButton.new()
	_tool_options.add_child(_world_select)
	var btn := Button.new()
	btn.text = "Placer l'entrée sur le monde"
	btn.pressed.connect(_place_on_world)
	_tool_options.add_child(btn)
	_refresh_integration_ui()

func _refresh_link_ui() -> void:
	if _link_target_select == null:
		return
	_link_target_select.clear()
	_link_target_select.add_item("— Scène locale —", 0)
	_link_target_select.set_item_metadata(0, "")
	if not MapData.is_world_map(doc.map_data):
		_link_target_select.disabled = true
		return
	var roster: String = doc.map_data.get("roster", "general")
	var locals: Array = MapData.get_local_maps_for_linking(roster)
	var idx := 1
	for local_map in locals:
		_link_target_select.add_item(str(local_map.get("title", "")), idx)
		_link_target_select.set_item_metadata(idx, str(local_map.get("id", "")))
		idx += 1
	_link_target_select.disabled = locals.is_empty()
	if not _link_target.is_empty():
		for i in range(_link_target_select.item_count):
			if str(_link_target_select.get_item_metadata(i)) == _link_target:
				_link_target_select.selected = i
				break

func _refresh_integration_ui() -> void:
	if _world_select == null:
		return
	var map_id: String = str(doc.map_data.get("id", ""))
	var links: Array = MapData.get_world_links_to_map(map_id)
	if _integration_status:
		if links.is_empty():
			_integration_status.text = "Cette scène n'est pas encore accessible depuis une carte monde."
		else:
			_integration_status.text = "Accessible depuis %d entrée(s)." % links.size()
	_world_select.clear()
	_world_select.add_item("— Carte monde —", 0)
	_world_select.set_item_metadata(0, "")
	var worlds: Array = MapData.get_world_maps_for_roster(str(doc.map_data.get("roster", "general")))
	var idx := 1
	for world in worlds:
		_world_select.add_item(str(world.get("title", "")), idx)
		_world_select.set_item_metadata(idx, str(world.get("id", "")))
		idx += 1
	_world_select.disabled = worlds.is_empty()

func _place_on_world() -> void:
	if _world_select == null or _world_select.selected < 0:
		return
	var world_id := str(_world_select.get_item_metadata(_world_select.selected))
	if world_id.is_empty():
		_set_status("Choisissez une carte monde.")
		return
	save_now()
	place_on_world_requested.emit(world_id, str(doc.map_data.get("id", "")))

func _rebuild_library() -> void:
	if _library == null:
		return
	_library.rebuild_tiles(doc.map_data, _paint_tile)
	_library.rebuild_markers(doc.map_data, _marker_type)
	_library.rebuild_props()

# ===========================================================================
# Outils
# ===========================================================================

func _set_tool(tool_id: String) -> void:
	if not ToolsScript.is_simple_tool(tool_id):
		tool_id = ToolsScript.PAINT
	if tool_id == ToolsScript.LINK and not MapData.is_world_map(doc.map_data):
		tool_id = ToolsScript.PAINT
	_tool = tool_id
	for key in _tool_buttons:
		_tool_buttons[key].button_pressed = key == tool_id
		if key == ToolsScript.LINK:
			_tool_buttons[key].visible = MapData.is_world_map(doc.map_data)
	_apply_interaction_mode()
	_rebuild_tool_options()
	_update_hint()

func _apply_interaction_mode() -> void:
	if _imap == null:
		return
	if not _editable:
		_imap.set_interaction_mode(InteractiveMapScript.INTERACT_CLICK)
		_imap.readonly = true
		return
	_imap.readonly = false
	match _tool:
		ToolsScript.PAN:
			_imap.set_interaction_mode(InteractiveMapScript.INTERACT_PAN)
		ToolsScript.PAINT, ToolsScript.ERASE, ToolsScript.FOG_REVEAL, ToolsScript.FOG_HIDE:
			_imap.set_interaction_mode(InteractiveMapScript.INTERACT_PAINT)
		ToolsScript.SELECT:
			_imap.set_interaction_mode(InteractiveMapScript.INTERACT_SELECT)
		ToolsScript.AREA:
			_imap.set_interaction_mode(InteractiveMapScript.INTERACT_RECT)
		ToolsScript.MEASURE:
			_imap.set_interaction_mode(InteractiveMapScript.INTERACT_MEASURE)
		_:
			_imap.set_interaction_mode(InteractiveMapScript.INTERACT_CLICK)

func _default_tile() -> String:
	if MapData.is_world_map(doc.map_data):
		return "ocean"
	if str(doc.map_data.get("roster", "")) == "investigation":
		return "street"
	return "grass"

func _default_marker() -> String:
	if MapData.is_world_map(doc.map_data):
		return "camp"
	if str(doc.map_data.get("roster", "")) == "investigation":
		return "detective"
	return "npc"

func _update_hint() -> void:
	if _hint_lbl == null:
		return
	if not _editable:
		_hint_lbl.text = "Aperçu 2D — molette pour zoomer, glisser pour déplacer."
		return
	_hint_lbl.text = ToolsScript.hint(_tool)

func _set_status(text: String) -> void:
	if _status_lbl:
		_status_lbl.text = text

func _update_zoom_label() -> void:
	if _zoom_lbl and _imap:
		_zoom_lbl.text = "%d%%" % int(round(_imap.zoom * 100.0))

# ===========================================================================
# Vue
# ===========================================================================

func _sync_view(reset_view: bool = false) -> void:
	if _imap == null or doc.map_data.is_empty():
		return
	var snapshot := doc.to_map_data()
	var explored: Array = []
	var show_fog := _editable and bool(snapshot.get("fogEnabled", false)) and _tool in [ToolsScript.FOG_REVEAL, ToolsScript.FOG_HIDE]
	if show_fog:
		explored = doc.fog_cells().duplicate()
	else:
		var w: int = int(snapshot.get("width", 0))
		var h: int = int(snapshot.get("height", 0))
		for y in range(h):
			for x in range(w):
				explored.append("%d,%d" % [x, y])
	_imap.configure(snapshot, [], [], explored, "oneshot", not _editable, {})
	_imap.suppress_navigation = true
	_imap.fog_enabled = show_fog
	_apply_interaction_mode()
	_refresh_overlay()
	if reset_view:
		_imap.call_deferred("reset_zoom")
	else:
		_imap.queue_redraw()
	call_deferred("_update_zoom_label")

func _refresh_overlay() -> void:
	if _imap == null:
		return
	var rects: Array = []
	for id in doc.selection():
		var elem: Dictionary = doc.get_element(str(id))
		if elem.is_empty():
			continue
		var kind := str(elem.get("kind", ""))
		var info := {
			"x": float(elem.get("x", 0)),
			"y": float(elem.get("y", 0)),
			"w": float(elem.get("w", 1)),
			"h": float(elem.get("h", 1)),
			"cell": kind in [DocumentScript.KIND_MARKER, DocumentScript.KIND_NOTE, DocumentScript.KIND_LINK],
		}
		rects.append(info)
	var data := {
		"show_notes": _editable,
		"selected_rects": rects,
	}
	if _preview_from.x >= 0:
		data["preview_rect"] = {"from": _preview_from, "to": _preview_to}
	if _tool == ToolsScript.MEASURE and _preview_from.x >= 0:
		data["measure"] = {"from": _preview_from, "to": _preview_to}
	_imap.set_overlay(data)

func _focus_selection() -> void:
	if doc.selection().is_empty() or _imap == null:
		return
	var elem: Dictionary = doc.get_element(str(doc.selection()[0]))
	# Recadrage léger : on ne reset pas le zoom, on redessine.
	_refresh_overlay()
	_imap.queue_redraw()

# ===========================================================================
# Souris
# ===========================================================================

func _brush_cells(cx: int, cy: int) -> Array:
	var cells: Array = []
	var r := _brush_size
	var w: int = int(doc.map_data.get("width", 0))
	var h: int = int(doc.map_data.get("height", 0))
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r + 1:
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		cells.append(Vector2i(cx, cy))
	return cells

func _on_cell_paint(x: int, y: int) -> void:
	if not _editable:
		return
	if not _paint_tx:
		doc.begin_transaction()
		_paint_tx = true
	match _tool:
		ToolsScript.PAINT:
			var batch: Dictionary = {}
			var w: int = int(doc.map_data.get("width", 0))
			for cell in _brush_cells(x, y):
				batch[str(cell.y * w + cell.x)] = _paint_tile
			doc.paint_tiles(batch)
			_imap.map_data = doc.to_map_data()
			_imap.queue_redraw()
		ToolsScript.ERASE:
			_erase_at(x, y, false)
		ToolsScript.FOG_REVEAL:
			var keys: Array = []
			for cell in _brush_cells(x, y):
				keys.append("%d,%d" % [cell.x, cell.y])
			doc.reveal_fog(keys)
			_sync_view()
		ToolsScript.FOG_HIDE:
			var keys: Array = []
			for cell in _brush_cells(x, y):
				keys.append("%d,%d" % [cell.x, cell.y])
			doc.hide_fog(keys)
			_sync_view()

func _on_paint_finished() -> void:
	if _paint_tx:
		doc.commit_transaction()
		_paint_tx = false
	_sync_view()
	_refresh_panels()

func _on_cell_clicked(x: int, y: int) -> void:
	if not _editable:
		return
	match _tool:
		ToolsScript.MARKER:
			_place_marker(x, y)
		ToolsScript.NOTE:
			_place_note(x, y)
		ToolsScript.PROP:
			_place_prop(x, y)
		ToolsScript.LINK:
			_place_link(x, y)
		ToolsScript.BUCKET:
			doc.bucket_fill(x, y, _paint_tile)
			_sync_view()
		ToolsScript.ERASE:
			_erase_at(x, y, true)
		ToolsScript.SELECT:
			var id: String = doc.hit_element_at(float(x) + 0.5, float(y) + 0.5)
			if id.is_empty():
				doc.clear_selection()
			else:
				doc.select_only(id)

func _on_drag_started(x: int, y: int) -> void:
	if not _editable:
		return
	_rect_from = Vector2i(x, y)
	_preview_from = Vector2i(x, y)
	_preview_to = Vector2i(x, y)
	if _tool == ToolsScript.SELECT:
		var id: String = doc.hit_element_at(float(x) + 0.5, float(y) + 0.5)
		if id.is_empty():
			doc.clear_selection()
			_moving = false
		else:
			doc.select_only(id)
			var elem: Dictionary = doc.get_element(id)
			_moving = true
			_move_origin = Vector2(x, y)
			_move_start = Vector2(float(elem.get("x", 0)), float(elem.get("y", 0)))
	_refresh_overlay()

func _on_dragged(x: int, y: int) -> void:
	if not _editable:
		return
	_preview_to = Vector2i(x, y)
	if _tool == ToolsScript.SELECT and _moving and not doc.selection().is_empty():
		var id := str(doc.selection()[0])
		var nx := ToolsScript.apply_snap(_move_start.x + (x - _move_origin.x), _snap_mode)
		var ny := ToolsScript.apply_snap(_move_start.y + (y - _move_origin.y), _snap_mode)
		doc.set_live_position(id, nx, ny)
		_sync_view()
	_refresh_overlay()

func _on_drag_ended(x: int, y: int) -> void:
	if not _editable:
		return
	if _tool == ToolsScript.SELECT and _moving:
		doc.commit_live_edit(doc.selection(), "Déplacement")
		_moving = false
	elif _tool == ToolsScript.AREA:
		_create_area(_rect_from, Vector2i(x, y))
	_preview_from = Vector2i(-1, -1)
	_preview_to = Vector2i(-1, -1)
	_refresh_overlay()
	_refresh_panels()

func _on_rect_preview(from: Vector2i, to: Vector2i) -> void:
	_preview_from = from
	_preview_to = to
	_refresh_overlay()

func _place_marker(x: int, y: int) -> void:
	var existing := doc.hit_element_at(float(x) + 0.5, float(y) + 0.5)
	if not existing.is_empty() and str(doc.get_element(existing).get("kind", "")) == DocumentScript.KIND_MARKER:
		var cur: Dictionary = doc.get_element(existing)
		if str(cur.get("markerType", "")) != _marker_type:
			return
		doc.remove_element(existing)
	var id: String = doc.add_element({
		"x": float(x), "y": float(y),
		"markerType": _marker_type,
		"type": _marker_type,
		"label": MapData.get_marker_label(_marker_type),
	}, DocumentScript.KIND_MARKER, "Marqueur")
	doc.select_only(id)
	_sync_view()

func _place_note(x: int, y: int) -> void:
	var id: String = doc.add_element({
		"x": float(x), "y": float(y),
		"text": _note_text if not _note_text.is_empty() else "Note MJ",
		"label": "Note",
	}, DocumentScript.KIND_NOTE, "Note")
	doc.select_only(id)
	_sync_view()

func _place_prop(x: int, y: int) -> void:
	if _prop_asset.is_empty():
		_set_status("Choisissez un décor dans l'onglet Biblio.")
		if _right_tabs:
			_right_tabs.current_tab = 3
		return
	var ratio := AssetLibraryScript.aspect_ratio(_prop_asset)
	var height := maxf(0.5, _prop_size)
	var width := maxf(0.5, height * ratio)
	var asset := AssetLibraryScript.get_asset(_prop_asset)
	var id: String = doc.add_element({
		"x": float(x), "y": float(y),
		"w": width, "h": height,
		"asset": _prop_asset,
		"standing": false,
		"label": str(asset.get("name", _prop_asset.get_file().get_basename())),
		"layer": 1,
	}, DocumentScript.KIND_PROP, "Décor")
	doc.select_only(id)
	_sync_view()

func _place_link(x: int, y: int) -> void:
	if not MapData.is_world_map(doc.map_data):
		return
	var target := _link_target
	if _link_target_select and _link_target_select.selected >= 0:
		target = str(_link_target_select.get_item_metadata(_link_target_select.selected))
	if target.is_empty():
		_set_status("Choisissez d'abord une scène locale.")
		return
	var label := _link_label
	if _link_label_input:
		label = _link_label_input.text.strip_edges()
	if label.is_empty():
		var target_map := MapData.get_by_id(target)
		label = str(target_map.get("title", "Lieu"))
	var id: String = doc.add_element({
		"x": float(x), "y": float(y),
		"targetMapId": target,
		"label": label,
	}, DocumentScript.KIND_LINK, "Lien")
	doc.select_only(id)
	_sync_view()

func _create_area(from: Vector2i, to: Vector2i) -> void:
	var min_x := mini(from.x, to.x)
	var min_y := mini(from.y, to.y)
	var max_x := maxi(from.x, to.x)
	var max_y := maxi(from.y, to.y)
	var w := float(max_x - min_x + 1)
	var h := float(max_y - min_y + 1)
	if w < 1.0:
		w = 3.0
	if h < 1.0:
		h = 3.0
	var id: String = doc.add_element({
		"x": float(min_x) + w * 0.5,
		"y": float(min_y) + h * 0.5,
		"w": w, "h": h,
		"shape": "rect",
		"category": _area_category,
		"label": _area_label if not _area_label.is_empty() else "Nouveau lieu",
		"targetMapId": "",
		"showCallout": true,
		"layer": 5,
	}, DocumentScript.KIND_AREA, "Lieu")
	doc.select_only(id)
	if _right_tabs:
		_right_tabs.current_tab = 0
	_sync_view()

func _erase_at(x: int, y: int, refresh: bool) -> void:
	var stack: Array = doc.hit_stack_at(float(x) + 0.5, float(y) + 0.5)
	if not stack.is_empty():
		doc.remove_elements(stack)
	else:
		var w: int = int(doc.map_data.get("width", 0))
		var batch := {str(y * w + x): _default_tile()}
		doc.paint_tiles(batch)
	if refresh:
		_sync_view()
	else:
		_imap.map_data = doc.to_map_data()
		_imap.queue_redraw()

func _create_child_map(area_id: String) -> void:
	save_now()
	var parent_id := str(doc.map_data.get("id", ""))
	var child := MapData.create_child_map_for_area(parent_id, area_id, 16, 12, MapData.RENDER_MODE_SIMPLE)
	if child.is_empty():
		_set_status("Impossible de créer la carte du lieu.")
		return
	# Recharger le parent pour récupérer le targetMapId.
	var parent := MapData.get_by_id(parent_id)
	if not parent.is_empty():
		doc.load_map(parent)
		_sync_view()
	open_map_requested.emit(str(child.get("id", "")))

# ===========================================================================
# Réglages / historique
# ===========================================================================

func _on_size_changed() -> void:
	if _settings == null:
		return
	var grid_size: Vector2i = _settings.grid_size()
	doc.resize_grid(grid_size.x, grid_size.y)
	_sync_view(true)

func _on_fog_setting() -> void:
	if _settings == null:
		return
	doc.set_meta_values({"fogEnabled": _settings.fog_enabled()}, "Brouillard")
	_sync_view()

func _on_measure_changed() -> void:
	if _settings == null:
		return
	doc.set_meta_values({"measure": _settings.measure_values()}, "Échelle")

func _refresh_panels() -> void:
	if _inspector:
		_inspector.rebuild()
	if _outliner:
		_outliner.rebuild()
	_refresh_history()

func _refresh_history() -> void:
	if _history == null or _history.history_list == null:
		return
	for child in _history.history_list.get_children():
		child.queue_free()
	var labels: Array = doc.history_labels()
	if labels.is_empty():
		var empty := Label.new()
		empty.text = "Aucune action enregistrée."
		empty.theme_type_variation = &"CaptionLabel"
		_history.history_list.add_child(empty)
		return
	for i in range(labels.size() - 1, -1, -1):
		var lbl := Label.new()
		lbl.text = "%d. %s" % [i + 1, labels[i]]
		lbl.add_theme_font_size_override("font_size", 11)
		_history.history_list.add_child(lbl)

func _on_doc_changed(reason: String) -> void:
	if reason in ["undo", "redo", "meta", "load"]:
		if _settings:
			_settings.sync_from(doc.map_data)
	if reason in ["add", "remove", "undo", "redo", "modify", "commit", "tiles", "fog"]:
		if not _moving:
			_refresh_panels()
		_sync_view()

func _on_selection_changed(_ids: Array) -> void:
	if not _moving and _inspector:
		_inspector.call_deferred("rebuild")
	if not _moving and _outliner:
		_outliner.call_deferred("rebuild")
	_refresh_overlay()

func _on_history_changed() -> void:
	if _undo_btn:
		_undo_btn.disabled = not doc.can_undo()
	if _redo_btn:
		_redo_btn.disabled = not doc.can_redo()
	_refresh_history()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _editable:
		return
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() else null
	if focus is LineEdit or focus is TextEdit or focus is SpinBox:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.ctrl_pressed and key.keycode == KEY_Z and not key.shift_pressed:
			doc.undo()
			accept_event()
		elif key.ctrl_pressed and (key.keycode == KEY_Y or (key.keycode == KEY_Z and key.shift_pressed)):
			doc.redo()
			accept_event()
		elif key.ctrl_pressed and key.keycode == KEY_S:
			save_now()
			accept_event()
		elif key.keycode in [KEY_DELETE, KEY_BACKSPACE] and not doc.selection().is_empty():
			doc.remove_elements(doc.selection())
			_sync_view()
			accept_event()
		elif key.keycode == KEY_ESCAPE:
			if not doc.selection().is_empty():
				doc.clear_selection()
			else:
				_esc.open_centered()
			accept_event()
		else:
			var mapped := ToolsScript.tool_for_shortcut(OS.get_keycode_string(key.keycode))
			if mapped.is_empty():
				mapped = ToolsScript.tool_for_shortcut(char(key.unicode))
			if ToolsScript.is_simple_tool(mapped):
				_set_tool(mapped)
				accept_event()
