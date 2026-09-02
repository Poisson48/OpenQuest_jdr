extends Control

const InteractiveMapScript := preload("res://scripts/interactive_map.gd")

@onready var top_bar: HBoxContainer = $VBox/TopBar
@onready var title_lbl: Label = %MapTitle
@onready var content_host: Control = $VBox/ContentHost

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

func _ready() -> void:
	%BtnBack.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	_edit_mode = MapData.editor_mode == "edit"
	_build_ui()
	_load_map()

func _build_ui() -> void:
	_reset_top_bar()
	for child in content_host.get_children():
		child.queue_free()

	_editor_panel = VBoxContainer.new()
	_editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_panel.add_theme_constant_override("separation", 8)
	content_host.add_child(_editor_panel)

	if _edit_mode:
		_build_edit_top_actions()
		_build_tool_row()
		_build_palettes()
	else:
		_build_preview_actions()

	_hint_lbl = Label.new()
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_hint_lbl.add_theme_font_size_override("font_size", 12)
	_editor_panel.add_child(_hint_lbl)

	var map_header := HBoxContainer.new()
	map_header.add_theme_constant_override("separation", 8)
	_editor_panel.add_child(map_header)

	var map_title := Label.new()
	map_title.text = "Grille"
	map_title.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	map_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_header.add_child(map_title)
	_build_zoom_controls(map_header)

	var map_frame := PanelContainer.new()
	var map_style := StyleBoxFlat.new()
	map_style.bg_color = ThemeColors.BG_INPUT
	map_style.border_color = ThemeColors.BORDER
	map_style.set_border_width_all(1)
	map_style.set_corner_radius_all(4)
	map_frame.add_theme_stylebox_override("panel", map_style)
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_frame.custom_minimum_size = Vector2(0, 420)
	_editor_panel.add_child(map_frame)

	_interactive_map = InteractiveMapScript.new()
	_interactive_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_interactive_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_interactive_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_interactive_map.custom_minimum_size = Vector2(320, 380)
	_interactive_map.cell_clicked.connect(_on_cell_clicked)
	_interactive_map.cell_paint.connect(_on_cell_paint)
	_interactive_map.paint_drag_finished.connect(_on_paint_drag_finished)
	_interactive_map.zoom_changed.connect(func(_z): _update_zoom_label())
	map_frame.add_child(_interactive_map)

	if _edit_mode:
		_build_bottom_bar()

func _reset_top_bar() -> void:
	for child in top_bar.get_children():
		if child != %BtnBack and child != title_lbl:
			child.queue_free()
	title_lbl.visible = not _edit_mode
	_title_input = null

func _build_edit_top_actions() -> void:
	_title_input = LineEdit.new()
	_title_input.placeholder_text = "Titre de la carte"
	_title_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_input.add_theme_font_size_override("font_size", 16)
	top_bar.add_child(_title_input)
	top_bar.move_child(_title_input, 1)
	title_lbl.visible = false

	var btn_save := Button.new()
	btn_save.text = "💾 Enregistrer"
	btn_save.pressed.connect(_save_map)
	top_bar.add_child(btn_save)

func _build_preview_actions() -> void:
	title_lbl.visible = true
	if _title_input:
		_title_input.visible = false
	var btn_edit := Button.new()
	btn_edit.text = "✏️ Modifier"
	btn_edit.pressed.connect(func():
		_edit_mode = true
		MapData.editor_mode = "edit"
		_rebuild_for_mode()
	)
	top_bar.add_child(btn_edit)

func _build_tool_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_editor_panel.add_child(row)
	_editor_panel.move_child(row, 0)

	for spec in [
		["tile", "🖌 Tuile"],
		["marker", "📍 Marqueur"],
		["link", "🌀 Lien lieu"],
		["erase", "🧹 Effacer"],
	]:
		var btn := Button.new()
		btn.text = spec[1]
		btn.toggle_mode = true
		btn.button_pressed = spec[0] == "tile"
		btn.pressed.connect(func(): _set_tool(spec[0]))
		_tool_buttons[spec[0]] = btn
		row.add_child(btn)

func _build_palettes() -> void:
	_palettes_root = VBoxContainer.new()
	_palettes_root.add_theme_constant_override("separation", 6)
	_editor_panel.add_child(_palettes_root)
	_editor_panel.move_child(_palettes_root, 1)

	var tile_scroll := ScrollContainer.new()
	tile_scroll.name = "TileScroll"
	tile_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tile_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tile_scroll.custom_minimum_size = Vector2(0, 44)
	tile_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palettes_root.add_child(tile_scroll)

	_tile_palette = HBoxContainer.new()
	_tile_palette.add_theme_constant_override("separation", 6)
	tile_scroll.add_child(_tile_palette)

	var marker_scroll := ScrollContainer.new()
	marker_scroll.name = "MarkerScroll"
	marker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	marker_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	marker_scroll.custom_minimum_size = Vector2(0, 44)
	marker_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palettes_root.add_child(marker_scroll)

	_marker_palette = HBoxContainer.new()
	_marker_palette.add_theme_constant_override("separation", 6)
	marker_scroll.add_child(_marker_palette)

	_link_panel = VBoxContainer.new()
	_link_panel.name = "LinkPanel"
	_link_panel.add_theme_constant_override("separation", 6)
	_link_panel.visible = false
	_palettes_root.add_child(_link_panel)

	var link_hint := Label.new()
	link_hint.text = "Relie une case du monde à une scène locale (ex. taverne, donjon)."
	link_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	link_hint.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	link_hint.add_theme_font_size_override("font_size", 12)
	_link_panel.add_child(link_hint)

	var link_row := HBoxContainer.new()
	link_row.add_theme_constant_override("separation", 8)
	_link_panel.add_child(link_row)

	var scene_lbl := Label.new()
	scene_lbl.text = "Scène locale :"
	scene_lbl.add_theme_color_override("font_color", ThemeColors.TEXT)
	link_row.add_child(scene_lbl)

	_link_target_select = OptionButton.new()
	_link_target_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_link_target_select.custom_minimum_size = Vector2(180, 0)
	link_row.add_child(_link_target_select)

	var label_lbl := Label.new()
	label_lbl.text = "Nom sur la carte :"
	label_lbl.add_theme_color_override("font_color", ThemeColors.TEXT)
	link_row.add_child(label_lbl)

	_link_label_input = LineEdit.new()
	_link_label_input.placeholder_text = "Ex. Taverne du Vieux Port"
	_link_label_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_link_label_input.custom_minimum_size = Vector2(160, 0)
	link_row.add_child(_link_label_input)

	_integration_panel = VBoxContainer.new()
	_integration_panel.name = "IntegrationPanel"
	_integration_panel.add_theme_constant_override("separation", 6)
	_integration_panel.visible = false
	_palettes_root.add_child(_integration_panel)

	var int_title := Label.new()
	int_title.text = "🌍 Intégration dans une carte monde"
	int_title.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	int_title.add_theme_font_size_override("font_size", 14)
	_integration_panel.add_child(int_title)

	_integration_status = Label.new()
	_integration_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_integration_status.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_integration_status.add_theme_font_size_override("font_size", 12)
	_integration_panel.add_child(_integration_status)

	var int_row := HBoxContainer.new()
	int_row.add_theme_constant_override("separation", 8)
	_integration_panel.add_child(int_row)

	var world_lbl := Label.new()
	world_lbl.text = "Carte monde :"
	world_lbl.add_theme_color_override("font_color", ThemeColors.TEXT)
	int_row.add_child(world_lbl)

	_world_map_select = OptionButton.new()
	_world_map_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_map_select.custom_minimum_size = Vector2(180, 0)
	int_row.add_child(_world_map_select)

	var btn_place := Button.new()
	btn_place.text = "Placer l'entrée sur le monde"
	btn_place.pressed.connect(_open_world_for_link_placement)
	int_row.add_child(btn_place)

func _build_bottom_bar() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_editor_panel.add_child(row)

	var btn_preview := Button.new()
	btn_preview.text = "👁 Aperçu"
	btn_preview.pressed.connect(func():
		_edit_mode = false
		MapData.editor_mode = "preview"
		_rebuild_for_mode()
	)
	row.add_child(btn_preview)

func _build_zoom_controls(parent: HBoxContainer) -> void:
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 4)
	parent.add_child(zoom_row)

	var btn_zoom_out := Button.new()
	btn_zoom_out.text = "−"
	btn_zoom_out.custom_minimum_size = Vector2(32, 30)
	btn_zoom_out.pressed.connect(func(): _interactive_map.zoom_out())
	zoom_row.add_child(btn_zoom_out)

	_zoom_lbl = Label.new()
	_zoom_lbl.text = "100%"
	_zoom_lbl.custom_minimum_size = Vector2(48, 0)
	_zoom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	zoom_row.add_child(_zoom_lbl)

	var btn_zoom_in := Button.new()
	btn_zoom_in.text = "+"
	btn_zoom_in.custom_minimum_size = Vector2(32, 30)
	btn_zoom_in.pressed.connect(func(): _interactive_map.zoom_in())
	zoom_row.add_child(btn_zoom_in)

	var btn_reset := Button.new()
	btn_reset.text = "⟲"
	btn_reset.custom_minimum_size = Vector2(32, 30)
	btn_reset.pressed.connect(func(): _interactive_map.reset_zoom())
	zoom_row.add_child(btn_reset)

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
	var open_link_tool := not MapData.pending_link_target_id.is_empty() and MapData.is_world_map(_map_data)
	_apply_pending_link_target()
	_set_tool("link" if open_link_tool else "tile")
	_refresh_palettes()
	_update_hint()
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
	var explored: Array = _all_explored()
	_interactive_map.paint_drag_enabled = _edit_mode and _tool in ["tile", "marker", "erase"]
	_interactive_map.configure(_map_data, [], [], explored, "oneshot", not _edit_mode, {})
	call_deferred("_update_zoom_label")
	if reset_view:
		call_deferred("_interactive_map.reset_zoom")

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
		_hint_lbl.text = "Molette ou boutons ± pour zoomer · clic-glisser pour déplacer la vue."
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
	MapData.update_map(_map_data)
	title_lbl.text = "🗺️ %s" % _map_data.get("title", "Carte")

func _update_zoom_label() -> void:
	if _zoom_lbl and _interactive_map:
		_zoom_lbl.text = "%d%%" % int(round(_interactive_map.zoom * 100.0))

func _rebuild_for_mode() -> void:
	_build_ui()
	_load_map()
