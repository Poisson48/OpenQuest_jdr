extends Control

const InteractiveMapScript := preload("res://scripts/interactive_map.gd")
const MapModeScript := preload("res://scripts/maps/map_mode.gd")

@onready var top_bar: HBoxContainer = $VBox/TopBar
@onready var title_lbl: Label = %MapTitle
@onready var content_host: Control = %EditorPanel

var _interactive_map: Control
var _map_data: Dictionary = {}
var _edit_mode: bool = false
var _tool: String = "tile"
var _selected_tile: String = "grass"
var _selected_marker: String = "npc"
var _title_input: LineEdit
var _hint_lbl: Label
var _tile_palette: HBoxContainer
var _marker_palette: HBoxContainer
var _tool_buttons: Dictionary = {}
var _tile_buttons: Dictionary = {}
var _marker_buttons: Dictionary = {}
var _zoom_lbl: Label
var _editor_panel: VBoxContainer
var _palettes_root: VBoxContainer
var _link_panel: VBoxContainer
var _link_target_select: OptionButton
var _link_label_input: LineEdit
var _integration_panel: VBoxContainer
var _integration_status: Label
var _world_map_select: OptionButton
var _mode_row: HBoxContainer
var _btn_mode_simple: Button
var _btn_mode_complex: Button
var _mode_group: ButtonGroup
var _mode_hint_lbl: Label
var _map_frame: PanelContainer
var _map_header: HBoxContainer
var _zoom_row: HBoxContainer
var _tool_row: HBoxContainer
var _complex_editor: Control

func _ready() -> void:
	%BtnBack.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	_edit_mode = MapData.editor_mode == "edit"
	_bind_ui()
	_sync_chrome()
	_load_map()
	resized.connect(_on_viewer_resized)
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_on_viewer_resized):
		vp.size_changed.connect(_on_viewer_resized)

func _on_viewer_resized() -> void:
	# Relayer le resize / fullscreen à l'éditeur pour qu'il mesure sa taille réelle.
	if _complex_editor == null or not _complex_editor.visible:
		return
	if _complex_editor.has_method("_on_viewport_size_changed"):
		_complex_editor.call("_on_viewport_size_changed")

func _bind_ui() -> void:
	_editor_panel = %EditorPanel
	_title_input = %TitleInput
	_hint_lbl = %LblHint
	_mode_row = %ModeRow
	# Unique names inside instanced child scenes belong to that instance, not MapViewer.
	_btn_mode_simple = %ModeRow.get_node("%BtnModeSimple")
	_btn_mode_complex = %ModeRow.get_node("%BtnModeComplex")
	_mode_hint_lbl = %ModeRow.get_node("%LblModeHint")
	_tool_row = %ToolRow
	_palettes_root = %Palettes
	_tile_palette = %Palettes.get_node("%TilePalette")
	_marker_palette = %Palettes.get_node("%MarkerPalette")
	_link_panel = %Palettes.get_node("%LinkPanel")
	_link_target_select = %Palettes.get_node("%LinkTargetSelect")
	_link_label_input = %Palettes.get_node("%LinkLabelInput")
	_integration_panel = %Palettes.get_node("%IntegrationPanel")
	_integration_status = %Palettes.get_node("%LblIntegrationStatus")
	_world_map_select = %Palettes.get_node("%WorldMapSelect")
	_map_header = %SimpleStage.get_node("%MapHeader")
	_map_frame = %SimpleStage.get_node("%MapFrame")
	_zoom_lbl = %SimpleStage.get_node("%LblZoom")
	_complex_editor = %MapEditor

	%BtnSave.pressed.connect(_save_map)
	%BtnEdit.pressed.connect(func():
		_edit_mode = true
		MapData.editor_mode = "edit"
		_rebuild_for_mode()
	)
	%BottomBar.get_node("%BtnPreview").pressed.connect(func():
		if MapData.is_complex_map(_map_data) and _complex_editor:
			_map_data = _complex_editor.apply_to_map_data()
		_edit_mode = false
		MapData.editor_mode = "preview"
		_rebuild_for_mode()
	)
	_btn_mode_simple.pressed.connect(func(): _set_render_mode(MapModeScript.SIMPLE))
	_btn_mode_complex.pressed.connect(func(): _set_render_mode(MapModeScript.COMPLEX))
	%Palettes.get_node("%BtnPlaceWorld").pressed.connect(_open_world_for_link_placement)
	%SimpleStage.get_node("%BtnZoomOut").pressed.connect(func(): _interactive_map.zoom_out())
	%SimpleStage.get_node("%BtnZoomIn").pressed.connect(func(): _interactive_map.zoom_in())
	%SimpleStage.get_node("%BtnZoomReset").pressed.connect(func(): _interactive_map.reset_zoom())

	_tool_buttons["tile"] = %ToolRow.get_node("%BtnToolTile")
	_tool_buttons["marker"] = %ToolRow.get_node("%BtnToolMarker")
	_tool_buttons["link"] = %ToolRow.get_node("%BtnToolLink")
	_tool_buttons["erase"] = %ToolRow.get_node("%BtnToolErase")
	_tool_buttons["tile"].pressed.connect(func(): _set_tool("tile"))
	_tool_buttons["marker"].pressed.connect(func(): _set_tool("marker"))
	_tool_buttons["link"].pressed.connect(func(): _set_tool("link"))
	_tool_buttons["erase"].pressed.connect(func(): _set_tool("erase"))

	_interactive_map = InteractiveMapScript.new()
	_interactive_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_interactive_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_interactive_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_interactive_map.custom_minimum_size = Vector2(160, 120)
	_interactive_map.cell_clicked.connect(_on_cell_clicked)
	_interactive_map.cell_paint.connect(_on_cell_paint)
	_interactive_map.paint_drag_finished.connect(_on_paint_drag_finished)
	_interactive_map.zoom_changed.connect(func(_z): _update_zoom_label())
	%SimpleStage.get_node("%MapHost").add_child(_interactive_map)

	_complex_editor.open_map_requested.connect(_on_editor_open_map)

func _sync_chrome() -> void:
	_title_input.visible = _edit_mode
	title_lbl.visible = not _edit_mode
	%BtnSave.visible = _edit_mode
	%BtnEdit.visible = not _edit_mode
	_tool_row.visible = _edit_mode
	_palettes_root.visible = _edit_mode
	%BottomBar.visible = _edit_mode

func _sync_render_mode_ui() -> void:
	if _btn_mode_simple == null or _map_data.is_empty():
		return
	var mode := MapData.get_render_mode(_map_data)
	_btn_mode_simple.set_pressed_no_signal(mode == MapModeScript.SIMPLE)
	_btn_mode_complex.set_pressed_no_signal(mode == MapModeScript.COMPLEX)
	var editable := _edit_mode
	_btn_mode_simple.disabled = not editable
	_btn_mode_complex.disabled = not editable
	if editable:
		if mode == MapModeScript.COMPLEX:
			var style := str(_map_data.get("renderStyle", "diorama"))
			if style == "vtt":
				_mode_hint_lbl.text = "VTT 3D : grille, murs volumétriques, ombres, fog et tokens."
			elif style == "dd2_hybrid":
				_mode_hint_lbl.text = "Hybride DD2 : fond illustré + caméra inclinée + personnages dressés."
			else:
				_mode_hint_lbl.text = "Diorama 2.5D : fond illustré, lieux cliquables, décors et tokens."
		else:
			_mode_hint_lbl.text = "Exploration classique — peignez tuiles et marqueurs sur la grille."
	else:
		_mode_hint_lbl.text = "Cliquez sur « Modifier » pour changer le mode de cette carte."

func _set_render_mode(mode: String) -> void:
	if _map_data.is_empty() or not _edit_mode:
		return
	var current := MapData.get_render_mode(_map_data)
	if mode == current:
		return
	_map_data["renderMode"] = mode
	_map_data = MapData.ensure_map_schema(_map_data)
	MapData.update_map(_map_data)
	_sync_editor_mode()
	_sync_render_mode_ui()
	_update_hint()
	_refresh_map_view(true)

func _sync_editor_mode() -> void:
	if _map_data.is_empty():
		return
	var is_complex := MapData.is_complex_map(_map_data)
	var show_simple := not is_complex
	if _tool_row:
		_tool_row.visible = show_simple and _edit_mode
	if _palettes_root:
		_palettes_root.visible = show_simple and _edit_mode
	if _map_header:
		_map_header.visible = show_simple
	if _map_frame:
		_map_frame.visible = show_simple
	var simple_stage := get_node_or_null("%SimpleStage")
	if simple_stage:
		simple_stage.visible = show_simple
	if _complex_editor:
		_complex_editor.visible = is_complex
		if is_complex:
			_complex_editor.set_editable(_edit_mode)
			_complex_editor.load_map(_map_data)
	if _editor_panel and is_complex:
		_hint_lbl.visible = not is_complex or not _edit_mode

func _load_map() -> void:
	_map_data = {}
	if not MapData.preview_map_id.is_empty():
		_map_data = MapData.get_by_id(MapData.preview_map_id).duplicate(true)
	if _map_data.is_empty() and not MapData.maps.is_empty():
		_map_data = MapData.maps[0].duplicate(true)
	if _map_data.is_empty():
		title_lbl.text = "🗺️ Aucune carte"
		return

	var title: String = _map_data.get("title", "Carte")
	if _title_input:
		_title_input.text = title
	else:
		title_lbl.text = "🗺️ %s" % title

	_selected_tile = _default_tile()
	_selected_marker = _default_marker()
	_refresh_link_ui()
	_refresh_integration_ui()
	_sync_render_mode_ui()
	var open_link_tool := not MapData.pending_link_target_id.is_empty() and MapData.is_world_map(_map_data)
	_apply_pending_link_target()
	_set_tool("link" if open_link_tool else "tile")
	_refresh_palettes()
	_update_hint()
	_sync_editor_mode()
	_refresh_map_view(true)

func _refresh_link_ui() -> void:
	if not _edit_mode or _link_target_select == null:
		return
	var is_world := MapData.is_world_map(_map_data)
	if _tool_buttons.has("link"):
		_tool_buttons["link"].visible = is_world
	if _link_panel:
		_link_panel.visible = is_world and _tool == "link"

	_link_target_select.clear()
	_link_target_select.add_item("— Choisir une scène locale —", 0)
	_link_target_select.set_item_metadata(0, "")

	if not is_world:
		return

	var roster: String = _map_data.get("roster", "general")
	var local_maps: Array = MapData.get_local_maps_for_linking(roster)
	var idx := 1
	for local_map in local_maps:
		var map_id: String = local_map.get("id", "")
		_link_target_select.add_item(local_map.get("title", map_id), idx)
		_link_target_select.set_item_metadata(idx, map_id)
		idx += 1

	if local_maps.is_empty():
		_link_target_select.add_item("(Aucune scène locale — crée-en une d'abord)", 1)
		_link_target_select.set_item_metadata(1, "")
		_link_target_select.selected = 1
		_link_target_select.disabled = true
	else:
		_link_target_select.disabled = false
		_link_target_select.selected = 0

func _refresh_integration_ui() -> void:
	if not _edit_mode or _integration_panel == null:
		return
	var is_local := not _map_data.is_empty() and not MapData.is_world_map(_map_data)
	_integration_panel.visible = is_local
	if not is_local:
		return

	var map_id: String = _map_data.get("id", "")
	var links: Array = MapData.get_world_links_to_map(map_id)
	if links.is_empty():
		_integration_status.text = "Cette scène n'est pas encore accessible depuis une carte monde.\nCrée d'abord le plan (ex. taverne), puis place son entrée sur la carte du monde."
	else:
		var lines: PackedStringArray = PackedStringArray()
		for link in links:
			lines.append("• %s — case (%d, %d), entrée « %s »" % [
				link.get("worldTitle", "Monde"),
				int(link.get("x", 0)),
				int(link.get("y", 0)),
				link.get("label", "Lieu"),
			])
		_integration_status.text = "Accessible depuis :\n" + "\n".join(lines)

	_world_map_select.clear()
	_world_map_select.add_item("— Choisir une carte monde —", 0)
	_world_map_select.set_item_metadata(0, "")
	var roster: String = _map_data.get("roster", "general")
	var world_maps: Array = MapData.get_world_maps_for_roster(roster)
	var idx := 1
	for world_map in world_maps:
		var world_id: String = world_map.get("id", "")
		_world_map_select.add_item(world_map.get("title", world_id), idx)
		_world_map_select.set_item_metadata(idx, world_id)
		idx += 1

	if world_maps.is_empty():
		_world_map_select.add_item("(Aucune carte monde — crée-en une d'abord)", 1)
		_world_map_select.set_item_metadata(1, "")
		_world_map_select.selected = 1
		_world_map_select.disabled = true
	else:
		_world_map_select.disabled = false
		if links.size() == 1:
			var linked_world: String = links[0].get("worldMapId", "")
			for i in range(_world_map_select.item_count):
				if _world_map_select.get_item_metadata(i) == linked_world:
					_world_map_select.selected = i
					break

func _apply_pending_link_target() -> void:
	if MapData.pending_link_target_id.is_empty():
		return
	if not MapData.is_world_map(_map_data):
		return
	var target_id := MapData.pending_link_target_id
	MapData.pending_link_target_id = ""
	var target_map := MapData.get_by_id(target_id)
	if not target_map.is_empty() and _link_label_input:
		_link_label_input.text = target_map.get("title", "")
	_select_link_target(target_id)
	_set_tool("link")

func _select_link_target(map_id: String) -> void:
	if _link_target_select == null or map_id.is_empty():
		return
	for i in range(_link_target_select.item_count):
		if _link_target_select.get_item_metadata(i) == map_id:
			_link_target_select.selected = i
			return

func _get_selected_link_target() -> String:
	if _link_target_select == null or _link_target_select.selected < 0:
		return ""
	return str(_link_target_select.get_item_metadata(_link_target_select.selected))

func _open_world_for_link_placement() -> void:
	if _world_map_select == null or _world_map_select.selected < 0:
		return
	var world_id: String = str(_world_map_select.get_item_metadata(_world_map_select.selected))
	if world_id.is_empty():
		_integration_status.text = "Choisis d'abord une carte monde, ou crée-en une via « + Monde » dans le Hub."
		return
	_save_map()
	MapData.preview_map_id = world_id
	MapData.editor_mode = "edit"
	MapData.pending_link_target_id = _map_data.get("id", "")
	get_tree().change_scene_to_file("res://scenes/map_viewer.tscn")

func _refresh_palettes() -> void:
	if not _edit_mode or _tile_palette == null:
		return
	for child in _tile_palette.get_children():
		child.queue_free()
	for child in _marker_palette.get_children():
		child.queue_free()
	_tile_buttons.clear()
	_marker_buttons.clear()

	var tiles: Dictionary = MapData.get_tile_palette(_map_data)
	for tile_id in tiles.keys():
		var def: Dictionary = tiles[tile_id]
		var btn := _make_palette_button(def.get("label", tile_id), def.get("color", "#444444"))
		btn.button_pressed = tile_id == _selected_tile
		btn.pressed.connect(func(): _select_tile(tile_id))
		_tile_palette.add_child(btn)
		_tile_buttons[tile_id] = btn

	var markers: Array = MapData.get_editor_marker_types(_map_data)
	for marker_id in markers:
		var btn := Button.new()
		btn.text = "%s %s" % [MapData.get_marker_emoji(marker_id), MapData.get_marker_label(marker_id)]
		btn.toggle_mode = true
		btn.button_pressed = marker_id == _selected_marker
		btn.custom_minimum_size = Vector2(0, 38)
		btn.pressed.connect(func(): _select_marker(marker_id))
		_marker_palette.add_child(btn)
		_marker_buttons[marker_id] = btn

func _make_palette_button(label_text: String, color_hex: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(0, 38)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.html(color_hex)
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	btn.add_theme_stylebox_override("normal", style)
	var pressed := style.duplicate()
	pressed.border_color = ThemeColors.GOLD
	pressed.set_border_width_all(2)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover", pressed)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	return btn

func _refresh_map_view(reset_view: bool = false) -> void:
	if MapData.is_complex_map(_map_data):
		if _complex_editor:
			_complex_editor.set_editable(_edit_mode)
			_complex_editor.load_map(_map_data)
		return
	var explored: Array = _all_explored()
	_interactive_map.paint_drag_enabled = _edit_mode and _tool in ["tile", "marker", "erase"]
	_interactive_map.configure(_map_data, [], [], explored, "oneshot", not _edit_mode, {})
	call_deferred("_update_zoom_label")
	if reset_view:
		_interactive_map.call_deferred("reset_zoom")

func _all_explored() -> Array:
	var explored: Array = []
	var w: int = int(_map_data.get("width", 0))
	var h: int = int(_map_data.get("height", 0))
	for y in range(h):
		for x in range(w):
			explored.append("%d,%d" % [x, y])
	return explored

func _default_tile() -> String:
	if MapData.is_world_map(_map_data):
		return "ocean"
	if _map_data.get("roster") == "investigation":
		return "street"
	return "grass"

func _default_marker() -> String:
	if MapData.is_world_map(_map_data):
		return "camp"
	if _map_data.get("roster") == "investigation":
		return "detective"
	return "npc"

func _set_tool(tool: String) -> void:
	_tool = tool
	for key in _tool_buttons:
		_tool_buttons[key].button_pressed = key == tool
	if _tile_palette:
		_tile_palette.get_parent().visible = tool == "tile"
	if _marker_palette:
		_marker_palette.get_parent().visible = tool == "marker"
	if _link_panel:
		_link_panel.visible = tool == "link" and MapData.is_world_map(_map_data)
	if _interactive_map:
		_interactive_map.paint_drag_enabled = _edit_mode and tool in ["tile", "marker", "erase"]
	_update_hint()

func _select_tile(tile_id: String) -> void:
	_selected_tile = tile_id
	_set_tool("tile")
	for key in _tile_buttons:
		_tile_buttons[key].button_pressed = key == tile_id

func _select_marker(marker_id: String) -> void:
	_selected_marker = marker_id
	_set_tool("marker")
	for key in _marker_buttons:
		_marker_buttons[key].button_pressed = key == marker_id

func _update_hint() -> void:
	if not _hint_lbl:
		return
	if not _edit_mode:
		var mode := MapData.get_render_mode(_map_data) if not _map_data.is_empty() else MapModeScript.SIMPLE
		var mode_note := " · %s" % MapModeScript.badge(mode)
		if mode == MapModeScript.COMPLEX:
			_hint_lbl.text = "Aperçu battlemap 3D — tokens, effets et brouillard configurés dans l'éditeur.%s" % mode_note
		else:
			_hint_lbl.text = "Molette ou boutons ± pour zoomer · clic-glisser pour déplacer la vue.%s" % mode_note
		return
	if MapData.is_complex_map(_map_data):
		var style := str(_map_data.get("renderStyle", "diorama"))
		if style == "vtt":
			_hint_lbl.text = "Éditeur VTT 3D — murs, fog, tokens, effets. Enregistrez pour persister."
		elif style == "dd2_hybrid":
			_hint_lbl.text = "Éditeur hybride DD2 — fond illustré, caméra inclinée, props/tokens dressés."
		else:
			_hint_lbl.text = "Éditeur diorama — importez un PNG, placez lieux/décors/tokens. Enregistrez pour persister."
		return
	match _tool:
		"tile":
			_hint_lbl.text = "Clique ou clique-glisse pour peindre plusieurs cases d'un coup. Maj+glisser pour déplacer la vue."
		"marker":
			_hint_lbl.text = "Clique ou glisse pour placer le marqueur. Les types différents (ville, campement…) peuvent être côte à côte."
		"link":
			_hint_lbl.text = "Choisis une scène locale, puis clique sur la carte monde pour y placer son entrée (🌀)."
		"erase":
			_hint_lbl.text = "Clique ou clique-glisse pour effacer tuile, marqueur et lien."
		_:
			_hint_lbl.text = ""

func _get_marker_at(x: int, y: int) -> Dictionary:
	for mk in _map_data.get("markers", []):
		if int(mk.get("x", -1)) == x and int(mk.get("y", -1)) == y:
			return mk
	return {}

func _on_cell_clicked(x: int, y: int) -> void:
	if not _edit_mode or _map_data.is_empty() or _tool != "link":
		return
	_apply_paint_at(x, y, true)

func _on_cell_paint(x: int, y: int) -> void:
	if not _edit_mode or _map_data.is_empty() or _tool == "link":
		return
	_apply_paint_at(x, y, false)

func _on_paint_drag_finished() -> void:
	if not _edit_mode or _map_data.is_empty():
		return
	MapData.update_map(_map_data)
	_refresh_integration_ui()
	if _interactive_map:
		_interactive_map.map_data = _map_data
		_interactive_map.queue_redraw()

func _apply_paint_at(x: int, y: int, save_now: bool) -> void:
	var w: int = int(_map_data.get("width", 0))
	var idx := y * w + x
	var tiles: Array = _map_data.get("tiles", [])
	if idx < 0 or idx >= tiles.size():
		return

	if _tool == "erase":
		tiles[idx] = _default_tile()
		_map_data["tiles"] = tiles
		_map_data["markers"] = _map_data.get("markers", []).filter(func(m): return not (int(m.get("x", -1)) == x and int(m.get("y", -1)) == y))
		if _map_data.has("locationLinks"):
			_map_data["locationLinks"] = _map_data.get("locationLinks", []).filter(func(l): return not (l.get("x") == x and l.get("y") == y))
	elif _tool == "marker":
		var existing := _get_marker_at(x, y)
		if not existing.is_empty() and str(existing.get("type", "")) != _selected_marker:
			return
		var markers: Array = _map_data.get("markers", [])
		markers = markers.filter(func(m): return not (int(m.get("x", -1)) == x and int(m.get("y", -1)) == y))
		markers.append({
			"x": int(x), "y": int(y),
			"type": _selected_marker,
			"label": MapData.get_marker_label(_selected_marker),
		})
		_map_data["markers"] = markers
	elif _tool == "link":
		if not MapData.is_world_map(_map_data):
			return
		var target_id := _get_selected_link_target()
		if target_id.is_empty():
			_hint_lbl.text = "Choisis d'abord une scène locale dans la liste (ex. taverne)."
			return
		var target_map := MapData.get_by_id(target_id)
		var link_label := _link_label_input.text.strip_edges() if _link_label_input else ""
		if link_label.is_empty():
			link_label = target_map.get("title", "Lieu")
		if not _map_data.has("locationLinks"):
			_map_data["locationLinks"] = []
		var links: Array = _map_data.get("locationLinks", [])
		links = links.filter(func(l): return not (l.get("x") == x and l.get("y") == y))
		links.append({
			"x": x, "y": y,
			"targetMapId": target_id,
			"label": link_label,
		})
		_map_data["locationLinks"] = links
	else:
		tiles[idx] = _selected_tile
		_map_data["tiles"] = tiles

	if save_now:
		MapData.update_map(_map_data)
		_refresh_integration_ui()
		_refresh_map_view()
	else:
		_interactive_map.map_data = _map_data
		_interactive_map.queue_redraw()

func _save_map() -> void:
	if _title_input:
		_map_data["title"] = _title_input.text.strip_edges()
		if _map_data["title"].is_empty():
			_map_data["title"] = "Carte sans titre"
	if MapData.is_complex_map(_map_data) and _complex_editor:
		_map_data = _complex_editor.apply_to_map_data()
	MapData.update_map(_map_data)
	title_lbl.text = "🗺️ %s" % _map_data.get("title", "Carte")

func _update_zoom_label() -> void:
	if _zoom_lbl and _interactive_map:
		_zoom_lbl.text = "%d%%" % int(round(_interactive_map.zoom * 100.0))

func _rebuild_for_mode() -> void:
	_sync_chrome()
	_load_map()

func _on_editor_open_map(map_id: String) -> void:
	if map_id.is_empty() or map_id == _map_data.get("id", ""):
		return
	var target := MapData.get_by_id(map_id)
	if target.is_empty():
		return
	MapData.preview_map_id = map_id
	_map_data = target.duplicate(true)
	if _title_input:
		_title_input.text = str(_map_data.get("title", ""))
	else:
		title_lbl.text = "🗺️ %s" % _map_data.get("title", "Carte")
	_sync_render_mode_ui()
	_sync_editor_mode()
	_refresh_integration_ui()
	_update_hint()
	_refresh_map_view(true)
