extends Control

signal layout_changed

const ComplexMapEngineScript := preload("res://scripts/maps/complex_map_engine_3d.gd")
const MapEffectPresetsScript := preload("res://scripts/maps/map_effect_presets.gd")

var _map_data: Dictionary = {}
var _play_defaults: Dictionary = {}
var _editable: bool = true
var _tool: String = "token"
var _effect_preset: String = "fire"
var _member_index: int = 0
var _marker_type: String = "npc"
var _token_label: String = "Token"

var _split: HSplitContainer
var _sidebar_scroll: ScrollContainer
var _sidebar: VBoxContainer
var _engine: Control
var _zoom_lbl: Label
var _items_list: VBoxContainer
var _file_dialog: FileDialog
var _token_label_input: LineEdit
var _tool_buttons: Dictionary = {}
var _marker_row: HBoxContainer

var _width_spin: SpinBox
var _height_spin: SpinBox
var _grid_size_spin: SpinBox
var _grid_opacity_spin: SpinBox
var _grid_enabled_check: CheckBox
var _perspective_select: OptionButton
var _atmo_enabled_check: CheckBox
var _atmo_tint_input: LineEdit
var _light_enabled_check: CheckBox
var _light_dir_select: OptionButton
var _fog_enabled_check: CheckBox
var _hint_lbl: Label
var _bg_status_lbl: Label
var _snap_check: CheckBox
var _effect_radius_spin: SpinBox
var _zone_radius_spin: SpinBox
var _zone_label_input: LineEdit
var _platform_w_spin: SpinBox
var _platform_h_spin: SpinBox
var _atmo_opacity_spin: SpinBox
var _fog_brush_spin: SpinBox
var _overlay_dialog: FileDialog

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 620)
	_build_ui()

func set_editable(on: bool) -> void:
	_editable = on
	if _sidebar_scroll:
		_sidebar_scroll.visible = on
	if _split:
		_split.split_offset = 300 if on else 0
	_set_sidebar_interactive(on)
	_refresh_engine()

func load_map(map_data: Dictionary) -> void:
	_map_data = map_data.duplicate(true)
	_map_data = MapData.ensure_map_schema(_map_data)
	_play_defaults = MapData.ensure_play_defaults(_map_data)
	_sync_settings_ui()
	_refresh_marker_row()
	_refresh_bg_status()
	_refresh_items_list()
	_refresh_engine(true)
	_update_tool_hint()

func apply_to_map_data() -> Dictionary:
	_sync_map_from_settings()
	if _engine and _engine.has_method("get_view_state"):
		_play_defaults["viewState"] = _engine.get_view_state()
	_map_data["playDefaults"] = get_play_defaults()
	return MapData.ensure_map_schema(_map_data.duplicate(true))

func get_play_defaults() -> Dictionary:
	if _engine and _engine.has_method("get_view_state"):
		_play_defaults["viewState"] = _engine.get_view_state()
	return _play_defaults.duplicate(true)

func _build_ui() -> void:
	_split = HSplitContainer.new()
	_split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_split)

	_sidebar_scroll = ScrollContainer.new()
	_sidebar_scroll.custom_minimum_size = Vector2(300, 0)
	_sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_split.add_child(_sidebar_scroll)

	_sidebar = VBoxContainer.new()
	_sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sidebar.add_theme_constant_override("separation", 8)
	_sidebar_scroll.add_child(_sidebar)

	_build_import_section()
	_build_size_section()
	_build_grid_section()
	_build_perspective_section()
	_build_atmosphere_section()
	_build_lighting_section()
	_build_tool_options_section()
	_build_tools_section()
	_build_items_section()

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	_split.add_child(right)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	right.add_child(header)

	var title := Label.new()
	title.text = "Vue 3D battlemap"
	title.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_build_zoom_controls(header)

	var viewport_frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = ThemeColors.BG_INPUT
	frame_style.border_color = ThemeColors.BORDER
	frame_style.set_border_width_all(1)
	frame_style.set_corner_radius_all(4)
	viewport_frame.add_theme_stylebox_override("panel", frame_style)
	viewport_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_frame.custom_minimum_size = Vector2(320, 500)
	right.add_child(viewport_frame)

	_engine = ComplexMapEngineScript.new()
	_engine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_engine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_engine.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_engine.map_clicked.connect(_on_map_clicked)
	_engine.token_moved.connect(_on_token_moved)
	_engine.fog_revealed.connect(_on_fog_revealed)
	_engine.fog_hidden.connect(_on_fog_hidden)
	_engine.zoom_changed.connect(func(_z): _update_zoom_label())
	_engine.token_selected.connect(_on_token_selected)
	_engine.effect_trigger_requested.connect(_on_effect_trigger_requested)
	viewport_frame.add_child(_engine)

	_hint_lbl = Label.new()
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.add_theme_font_size_override("font_size", 12)
	_hint_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	right.add_child(_hint_lbl)
	_update_tool_hint()

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png ; Images PNG", "*.jpg, *.jpeg ; Images JPEG", "*.webp ; Images WebP"])
	_file_dialog.title = "Importer battlemap"
	_file_dialog.file_selected.connect(_on_image_imported)
	add_child(_file_dialog)

	_overlay_dialog = FileDialog.new()
	_overlay_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_overlay_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_overlay_dialog.filters = PackedStringArray(["*.png ; Images PNG", "*.webp ; Images WebP"])
	_overlay_dialog.title = "Importer calque d'élévation"
	_overlay_dialog.file_selected.connect(_on_overlay_imported)
	add_child(_overlay_dialog)

func _set_sidebar_interactive(on: bool) -> void:
	for node in [_width_spin, _height_spin, _grid_size_spin, _grid_opacity_spin,
			_grid_enabled_check, _perspective_select, _atmo_enabled_check,
			_atmo_tint_input, _light_enabled_check, _light_dir_select,
			_fog_enabled_check, _token_label_input]:
		if node == null:
			continue
		if node is LineEdit:
			node.editable = on
		if node is SpinBox or node is OptionButton or node is CheckBox or node is LineEdit:
			node.disabled = not on
	for btn in _tool_buttons.values():
		btn.disabled = not on

func _section_title(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	lbl.add_theme_font_size_override("font_size", 13)
	_sidebar.add_child(lbl)

func _build_import_section() -> void:
	_section_title("🖼 Battlemap")
	_bg_status_lbl = Label.new()
	_bg_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bg_status_lbl.add_theme_font_size_override("font_size", 11)
	_bg_status_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_sidebar.add_child(_bg_status_lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_sidebar.add_child(row)
	var btn := Button.new()
	btn.text = "Importer PNG…"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func(): _file_dialog.popup_centered(Vector2i(720, 480)))
	row.add_child(btn)
	var btn_overlay := Button.new()
	btn_overlay.text = "Calque +"
	btn_overlay.tooltip_text = "Overlay PNG (pont, étage, fosse…)"
	btn_overlay.pressed.connect(func(): _overlay_dialog.popup_centered(Vector2i(720, 480)))
	row.add_child(btn_overlay)
	var btn_clear := Button.new()
	btn_clear.text = "✕"
	btn_clear.tooltip_text = "Retirer l'image de fond"
	btn_clear.pressed.connect(_remove_background)
	row.add_child(btn_clear)

func _build_size_section() -> void:
	_section_title("📐 Taille (cases)")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_sidebar.add_child(row)
	_width_spin = _labeled_spin(row, "L", 4, 96, 16)
	_height_spin = _labeled_spin(row, "H", 4, 96, 12)
	_width_spin.value_changed.connect(func(_v): _on_size_changed())
	_height_spin.value_changed.connect(func(_v): _on_size_changed())

func _build_grid_section() -> void:
	_section_title("⊞ Grille")
	_grid_enabled_check = CheckBox.new()
	_grid_enabled_check.text = "Afficher la grille"
	_grid_enabled_check.toggled.connect(func(_on): _on_grid_changed())
	_sidebar.add_child(_grid_enabled_check)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_sidebar.add_child(row)
	_grid_size_spin = _labeled_spin(row, "Taille", 20, 120, 70)
	_grid_opacity_spin = _labeled_spin(row, "Opacité", 0.0, 1.0, 0.22, 0.01)
	_grid_size_spin.value_changed.connect(func(_v): _on_grid_changed())
	_grid_opacity_spin.value_changed.connect(func(_v): _on_grid_changed())
	_fog_enabled_check = CheckBox.new()
	_fog_enabled_check.text = "Brouillard de guerre"
	_fog_enabled_check.toggled.connect(func(_on): _on_fog_setting_changed())
	_sidebar.add_child(_fog_enabled_check)
	var fog_row := HBoxContainer.new()
	fog_row.add_theme_constant_override("separation", 6)
	_sidebar.add_child(fog_row)
	var btn_clear_fog := Button.new()
	btn_clear_fog.text = "Effacer brouillard"
	btn_clear_fog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_clear_fog.pressed.connect(_clear_fog)
	fog_row.add_child(btn_clear_fog)

func _build_perspective_section() -> void:
	_section_title("📷 Perspective")
	_perspective_select = OptionButton.new()
	_perspective_select.add_item("Vue de dessus", 0)
	_perspective_select.set_item_metadata(0, MapData.PERSPECTIVE_TOPDOWN)
	_perspective_select.add_item("Isométrique", 1)
	_perspective_select.set_item_metadata(1, MapData.PERSPECTIVE_ISOMETRIC)
	_perspective_select.add_item("Perspective", 2)
	_perspective_select.set_item_metadata(2, MapData.PERSPECTIVE_TILT)
	_perspective_select.item_selected.connect(func(_i): _on_perspective_changed())
	_sidebar.add_child(_perspective_select)

func _build_atmosphere_section() -> void:
	_section_title("🌫 Atmosphère")
	_atmo_enabled_check = CheckBox.new()
	_atmo_enabled_check.text = "Activer teinte"
	_atmo_enabled_check.toggled.connect(func(_on): _on_atmosphere_changed())
	_sidebar.add_child(_atmo_enabled_check)
	_atmo_tint_input = LineEdit.new()
	_atmo_tint_input.placeholder_text = "#141018"
	_atmo_tint_input.text_changed.connect(func(_t): _on_atmosphere_changed())
	_sidebar.add_child(_atmo_tint_input)
	# Opacité atmo. dans _build_tool_options_section

func _build_lighting_section() -> void:
	_section_title("💡 Éclairage")
	_light_enabled_check = CheckBox.new()
	_light_enabled_check.text = "Éclairage directionnel"
	_light_enabled_check.toggled.connect(func(_on): _on_lighting_changed())
	_sidebar.add_child(_light_enabled_check)
	_light_dir_select = OptionButton.new()
	for i in range(4):
		var dirs := ["nw", "ne", "sw", "se"]
		var labels := ["NO", "NE", "SO", "SE"]
		_light_dir_select.add_item(labels[i], i)
		_light_dir_select.set_item_metadata(i, dirs[i])
	_light_dir_select.item_selected.connect(func(_i): _on_lighting_changed())
	_sidebar.add_child(_light_dir_select)

func _build_tool_options_section() -> void:
	_section_title("⚙️ Options outils")
	_snap_check = CheckBox.new()
	_snap_check.text = "Aimantation grille"
	_snap_check.button_pressed = true
	_snap_check.toggled.connect(func(on):
		if _engine and _engine.has_method("set_snap_to_grid"):
			_engine.set_snap_to_grid(on)
	)
	_sidebar.add_child(_snap_check)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	_sidebar.add_child(row1)
	_effect_radius_spin = _labeled_spin(row1, "Rayon effet", 0.5, 4.0, 1.0, 0.1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	_sidebar.add_child(row2)
	_zone_radius_spin = _labeled_spin(row2, "Rayon zone", 0.5, 6.0, 1.5, 0.1)
	_zone_label_input = LineEdit.new()
	_zone_label_input.placeholder_text = "Nom zone (Sort, piège…)"
	_zone_label_input.text = "Zone"
	_sidebar.add_child(_zone_label_input)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	_sidebar.add_child(row3)
	_platform_w_spin = _labeled_spin(row3, "Plateforme L", 1, 24, 3)
	_platform_h_spin = _labeled_spin(row3, "H", 1, 24, 3)
	_fog_brush_spin = _labeled_spin(row3, "Brouillard", 0, 3, 1)
	var atmo_row := HBoxContainer.new()
	atmo_row.add_theme_constant_override("separation", 8)
	_sidebar.add_child(atmo_row)
	_atmo_opacity_spin = _labeled_spin(atmo_row, "Opacité atmo.", 0.0, 1.0, 0.12, 0.01)
	_atmo_opacity_spin.value_changed.connect(func(_v): _on_atmosphere_changed())
	var fx_row := HBoxContainer.new()
	fx_row.add_theme_constant_override("separation", 6)
	_sidebar.add_child(fx_row)
	var btn_trigger := Button.new()
	btn_trigger.text = "▶ Tester effets"
	btn_trigger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_trigger.pressed.connect(_trigger_all_effects)
	fx_row.add_child(btn_trigger)

func _build_tools_section() -> void:
	_section_title("🛠 Outils")
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	_sidebar.add_child(row1)
	for spec in [
		["select", "👆"], ["token", "🧍"], ["marker", "📍"], ["effect", "🔥"],
		["zone", "⭕"], ["platform", "🟫"], ["fog", "🌫️"], ["fog_hide", "🚫"], ["erase", "🧹"],
	]:
		var btn := Button.new()
		btn.text = spec[1]
		btn.toggle_mode = true
		btn.button_pressed = spec[0] == "token"
		btn.tooltip_text = _tool_tooltip(spec[0])
		btn.custom_minimum_size = Vector2(40, 36)
		btn.pressed.connect(func(): _set_tool(spec[0]))
		_tool_buttons[spec[0]] = btn
		row1.add_child(btn)

	var marker_scroll := ScrollContainer.new()
	marker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	marker_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	marker_scroll.custom_minimum_size = Vector2(0, 40)
	_sidebar.add_child(marker_scroll)
	_marker_row = HBoxContainer.new()
	_marker_row.add_theme_constant_override("separation", 4)
	marker_scroll.add_child(_marker_row)

	var effect_row := HBoxContainer.new()
	effect_row.add_theme_constant_override("separation", 4)
	_sidebar.add_child(effect_row)
	for preset_id in ["fire", "smoke", "magic", "rain"]:
		var preset := MapEffectPresetsScript.get_preset(preset_id)
		var btn := Button.new()
		btn.text = str(preset.get("emoji", "✨"))
		btn.toggle_mode = true
		btn.button_pressed = preset_id == "fire"
		btn.tooltip_text = str(preset.get("label", preset_id))
		btn.custom_minimum_size = Vector2(40, 32)
		btn.pressed.connect(func():
			_effect_preset = preset_id
			_set_tool("effect")
			for c in effect_row.get_children():
				if c is Button:
					c.button_pressed = c.text == btn.text
		)
		effect_row.add_child(btn)

	var member_row := HBoxContainer.new()
	member_row.add_theme_constant_override("separation", 4)
	_sidebar.add_child(member_row)
	for i in range(mini(6, MapData.MEMBER_COLOR_HEX.size())):
		var em: String = MapData.MEMBER_PLAYER_EMOJIS_GENERAL[i % MapData.MEMBER_PLAYER_EMOJIS_GENERAL.size()]
		var btn := Button.new()
		btn.text = em
		btn.toggle_mode = true
		btn.button_pressed = i == 0
		btn.custom_minimum_size = Vector2(36, 32)
		var idx := i
		btn.pressed.connect(func():
			_member_index = idx
			_set_tool("token")
			for c in member_row.get_children():
				if c is Button:
					c.button_pressed = false
			btn.button_pressed = true
		)
		member_row.add_child(btn)

	var label_row := HBoxContainer.new()
	label_row.add_theme_constant_override("separation", 6)
	_sidebar.add_child(label_row)
	var lbl := Label.new()
	lbl.text = "Nom :"
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT)
	label_row.add_child(lbl)
	_token_label_input = LineEdit.new()
	_token_label_input.placeholder_text = "Token"
	_token_label_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_token_label_input.text_changed.connect(func(t): _token_label = t.strip_edges())
	label_row.add_child(_token_label_input)

func _build_items_section() -> void:
	_section_title("📋 Éléments placés")
	_items_list = VBoxContainer.new()
	_items_list.add_theme_constant_override("separation", 2)
	_sidebar.add_child(_items_list)

func _build_zoom_controls(parent: HBoxContainer) -> void:
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 4)
	parent.add_child(zoom_row)
	var btn_out := Button.new()
	btn_out.text = "−"
	btn_out.custom_minimum_size = Vector2(32, 30)
	btn_out.pressed.connect(func(): _engine.zoom_out())
	zoom_row.add_child(btn_out)
	_zoom_lbl = Label.new()
	_zoom_lbl.text = "100%"
	_zoom_lbl.custom_minimum_size = Vector2(48, 0)
	_zoom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	zoom_row.add_child(_zoom_lbl)
	var btn_in := Button.new()
	btn_in.text = "+"
	btn_in.custom_minimum_size = Vector2(32, 30)
	btn_in.pressed.connect(func(): _engine.zoom_in())
	zoom_row.add_child(btn_in)
	var btn_reset := Button.new()
	btn_reset.text = "⟲"
	btn_reset.custom_minimum_size = Vector2(32, 30)
	btn_reset.pressed.connect(func(): _engine.reset_zoom())
	zoom_row.add_child(btn_reset)

func _labeled_spin(parent: HBoxContainer, label_text: String, min_v: float, max_v: float, default_v: float, step: float = 1.0) -> SpinBox:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	parent.add_child(col)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	col.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = default_v
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(spin)
	return spin

func _tool_tooltip(tool: String) -> String:
	match tool:
		"select": return "Sélectionner / déplacer (sans placer)"
		"token": return "Placer un token joueur"
		"marker": return "Placer un marqueur PNJ / POI"
		"effect": return "Placer un effet (feu, fumée, magie)"
		"zone": return "Placer une zone AOE"
		"platform": return "Placer une plateforme surélevée"
		"fog": return "Révéler le brouillard (pinceau)"
		"fog_hide": return "Masquer le brouillard"
		"erase": return "Effacer token / effet / zone"
		_: return ""

func _set_tool(tool: String) -> void:
	_tool = tool
	for key in _tool_buttons:
		_tool_buttons[key].button_pressed = key == tool
	_apply_session_tool()
	_update_tool_hint()

func _update_tool_hint() -> void:
	if _hint_lbl == null:
		return
	if not _editable:
		_hint_lbl.text = "Aperçu 3D — molette zoom · clic-glisser pan · tokens déplaçables si présents."
		return
	_hint_lbl.text = "%s · Clic gauche agir · glisser token · molette zoom · clic milieu pan." % _tool_tooltip(_tool)

func _apply_session_tool() -> void:
	if _engine and _engine.has_method("set_session_tool"):
		_engine.set_session_tool(_session_tool_dict())

func _mock_party() -> Array:
	var party: Array = []
	for i in range(mini(6, MapData.MEMBER_COLOR_HEX.size())):
		party.append({
			"id": "editor-mock-%d" % i,
			"name": "Token %d" % (i + 1),
			"isPlayer": true,
		})
	return party

func _refresh_engine(reset_view: bool = false) -> void:
	if _map_data.is_empty() or _engine == null:
		return
	_apply_session_tool()
	var view_state: Dictionary = _play_defaults.get("viewState", {})
	if _snap_check and _engine.has_method("set_snap_to_grid"):
		_engine.set_snap_to_grid(_snap_check.button_pressed)
	_engine.configure(
		_map_data,
		_play_defaults.get("tokens", []),
		_mock_party(),
		_play_defaults.get("effects", []),
		_play_defaults.get("zones", []),
		_play_defaults.get("fogRevealed", []),
		not _editable,
		true,
		_session_tool_dict(),
		view_state,
	)
	if reset_view and view_state.is_empty():
		call_deferred("_engine.reset_zoom")
	call_deferred("_update_zoom_label")

func _session_tool_dict() -> Dictionary:
	var tool := {"mode": _tool}
	match _tool:
		"effect":
			tool["preset"] = _effect_preset
			tool["radius"] = 1.0
		"zone":
			tool["radius"] = 1.5
			tool["label"] = "Zone"
		"marker":
			tool["mode"] = "marker"
			tool["markerType"] = _marker_type
		"select":
			tool["mode"] = "select"
		"fog", "fog_hide":
			tool["mode"] = _tool
			tool["fogRadius"] = int(_fog_brush_spin.value) if _fog_brush_spin else 1
	return tool

func _refresh_marker_row() -> void:
	if _marker_row == null:
		return
	for child in _marker_row.get_children():
		child.queue_free()
	if _map_data.is_empty():
		return
	var markers: Array = MapData.get_editor_marker_types(_map_data)
	if markers.is_empty():
		_marker_type = "npc"
		return
	if not markers.has(_marker_type):
		_marker_type = str(markers[0])
	for marker_id in markers:
		var btn := Button.new()
		btn.text = "%s %s" % [MapData.get_marker_emoji(marker_id), MapData.get_marker_label(marker_id)]
		btn.toggle_mode = true
		btn.button_pressed = marker_id == _marker_type
		btn.custom_minimum_size = Vector2(0, 32)
		btn.disabled = not _editable
		var captured := str(marker_id)
		btn.pressed.connect(func():
			_marker_type = captured
			_set_tool("marker")
			_refresh_marker_row()
		)
		_marker_row.add_child(btn)

func _sync_settings_ui() -> void:
	if _width_spin:
		_width_spin.set_value_no_signal(int(_map_data.get("width", 16)))
		_height_spin.set_value_no_signal(int(_map_data.get("height", 12)))
	var grid: Dictionary = MapData.get_grid_config(_map_data)
	if _grid_size_spin:
		_grid_size_spin.set_value_no_signal(float(grid.get("size", 70)))
		_grid_opacity_spin.set_value_no_signal(float(grid.get("opacity", 0.22)))
		_grid_enabled_check.set_pressed_no_signal(bool(grid.get("enabled", true)))
	if _fog_enabled_check:
		_fog_enabled_check.set_pressed_no_signal(bool(_map_data.get("fogEnabled", true)))
	var persp := MapData.get_perspective(_map_data)
	if _perspective_select:
		for i in range(_perspective_select.item_count):
			if _perspective_select.get_item_metadata(i) == persp:
				_perspective_select.select(i)
				break
	var atmo: Dictionary = _map_data.get("atmosphere", {})
	if _atmo_enabled_check:
		_atmo_enabled_check.set_pressed_no_signal(bool(atmo.get("enabled", false)))
		_atmo_tint_input.text = str(atmo.get("tint", "#141018"))
	if _atmo_opacity_spin:
		_atmo_opacity_spin.set_value_no_signal(float(atmo.get("opacity", 0.12)))
	_refresh_bg_status()
	var light: Dictionary = MapData.get_lighting_config(_map_data)
	if _light_enabled_check:
		_light_enabled_check.set_pressed_no_signal(bool(light.get("enabled", false)))
	if _light_dir_select:
		var dir := str(light.get("direction", "nw"))
		for i in range(_light_dir_select.item_count):
			if _light_dir_select.get_item_metadata(i) == dir:
				_light_dir_select.select(i)
				break

func _sync_map_from_settings() -> void:
	if _width_spin:
		_map_data["width"] = int(_width_spin.value)
		_map_data["height"] = int(_height_spin.value)
		_resize_tiles()
	_map_data["grid"] = {
		"size": int(_grid_size_spin.value) if _grid_size_spin else 70,
		"opacity": float(_grid_opacity_spin.value) if _grid_opacity_spin else 0.22,
		"color": "#ffffff",
		"enabled": _grid_enabled_check.button_pressed if _grid_enabled_check else true,
	}
	if _fog_enabled_check:
		_map_data["fogEnabled"] = _fog_enabled_check.button_pressed
	if _perspective_select and _perspective_select.selected >= 0:
		_map_data["perspective"] = _perspective_select.get_item_metadata(_perspective_select.selected)
	_map_data["atmosphere"] = {
		"enabled": _atmo_enabled_check.button_pressed if _atmo_enabled_check else false,
		"tint": _atmo_tint_input.text.strip_edges() if _atmo_tint_input else "#141018",
		"opacity": float(_atmo_opacity_spin.value) if _atmo_opacity_spin else 0.12,
		"vignette": 0.18,
	}
	var light := MapData.get_lighting_config(_map_data)
	light["enabled"] = _light_enabled_check.button_pressed if _light_enabled_check else false
	if _light_dir_select and _light_dir_select.selected >= 0:
		light["direction"] = _light_dir_select.get_item_metadata(_light_dir_select.selected)
	_map_data["lighting"] = light
	_map_data["playDefaults"] = _play_defaults.duplicate(true)

func _resize_tiles() -> void:
	var w: int = int(_map_data.get("width", 16))
	var h: int = int(_map_data.get("height", 12))
	var tiles: Array = _map_data.get("tiles", [])
	var needed := w * h
	if tiles.size() < needed:
		var fill := "floor"
		if tiles.size() > 0:
			fill = str(tiles[0])
		while tiles.size() < needed:
			tiles.append(fill)
	elif tiles.size() > needed:
		tiles.resize(needed)
	_map_data["tiles"] = tiles

func _on_size_changed() -> void:
	if _map_data.is_empty():
		return
	_sync_map_from_settings()
	_refresh_engine(true)

func _on_grid_changed() -> void:
	_sync_map_from_settings()
	_refresh_engine()

func _on_perspective_changed() -> void:
	_sync_map_from_settings()
	_refresh_engine()

func _on_atmosphere_changed() -> void:
	_sync_map_from_settings()
	_refresh_engine()

func _on_lighting_changed() -> void:
	_sync_map_from_settings()
	_refresh_engine()

func _on_fog_setting_changed() -> void:
	_sync_map_from_settings()
	_refresh_engine()

func _on_image_imported(path: String) -> void:
	var map_id: String = _map_data.get("id", "")
	if map_id.is_empty():
		return
	var grid_px := int(_grid_size_spin.value) if _grid_size_spin else 70
	var cells := MapData.suggest_cells_from_image(path, grid_px)
	if _width_spin and cells != Vector2i.ZERO:
		_width_spin.set_value_no_signal(cells.x)
		_height_spin.set_value_no_signal(cells.y)
	var dest := MapData.import_background_image(map_id, path)
	if dest.is_empty():
		return
	_map_data = MapData.get_by_id(map_id).duplicate(true)
	_map_data["width"] = cells.x if cells != Vector2i.ZERO else _map_data.get("width", 16)
	_map_data["height"] = cells.y if cells != Vector2i.ZERO else _map_data.get("height", 12)
	_resize_tiles()
	_play_defaults = MapData.ensure_play_defaults(_map_data)
	_sync_settings_ui()
	_refresh_engine(true)
	_refresh_bg_status()
	layout_changed.emit()

func _on_overlay_imported(path: String) -> void:
	var map_id: String = _map_data.get("id", "")
	if map_id.is_empty():
		return
	var dest := MapData.import_elevation_overlay(map_id, path)
	if dest.is_empty():
		return
	_map_data = MapData.get_by_id(map_id).duplicate(true)
	_refresh_engine()
	_refresh_items_list()
	layout_changed.emit()

func _remove_background() -> void:
	var map_id: String = _map_data.get("id", "")
	if map_id.is_empty():
		return
	MapData.clear_background_image(map_id)
	_map_data = MapData.get_by_id(map_id).duplicate(true)
	_refresh_engine()
	_refresh_bg_status()
	layout_changed.emit()

func _refresh_bg_status() -> void:
	if _bg_status_lbl == null:
		return
	var path: String = str(_map_data.get("backgroundImage", "")).strip_edges()
	if path.is_empty():
		_bg_status_lbl.text = "Aucune image — sol généré depuis les tuiles."
	else:
		var fname := path.get_file()
		var px := MapData.get_image_pixel_size(path)
		if px != Vector2i.ZERO:
			_bg_status_lbl.text = "Fond : %s (%d×%d px)" % [fname, px.x, px.y]
		else:
			_bg_status_lbl.text = "Fond : %s" % fname

func _on_map_clicked(gx: float, gy: float, tool_dict: Dictionary) -> void:
	if not _editable:
		return
	if _tool == "select":
		return
	match _tool:
		"token":
			_place_token(gx, gy)
		"marker":
			_place_marker(gx, gy)
		"effect":
			_place_effect(gx, gy)
		"zone":
			_place_zone(gx, gy)
		"platform":
			_place_platform(int(roundf(gx)), int(roundf(gy)))
		"erase":
			_erase_at(gx, gy)
		_:
			if tool_dict.get("mode", "") == "marker":
				_place_marker(gx, gy)
	_refresh_items_list()
	_refresh_engine()
	layout_changed.emit()

func _on_token_moved(token_id: String, gx: float, gy: float) -> void:
	for tok in _play_defaults.get("tokens", []):
		if str(tok.get("id", "")) == token_id:
			tok["x"] = gx
			tok["y"] = gy
			break
	if _engine and _engine.has_method("get_view_state"):
		_play_defaults["viewState"] = _engine.get_view_state()
	_refresh_items_list()
	layout_changed.emit()

func _on_fog_revealed(cells: Array) -> void:
	var fog: Array = _play_defaults.get("fogRevealed", [])
	for key in cells:
		var k := str(key)
		if not fog.has(k):
			fog.append(k)
	_play_defaults["fogRevealed"] = fog
	_refresh_engine()
	layout_changed.emit()

func _on_fog_hidden(cells: Array) -> void:
	var fog: Array = _play_defaults.get("fogRevealed", [])
	for key in cells:
		fog.erase(str(key))
	_play_defaults["fogRevealed"] = fog
	_refresh_engine()
	layout_changed.emit()

func _clear_fog() -> void:
	_play_defaults["fogRevealed"] = []
	_refresh_engine()
	layout_changed.emit()

func _place_token(gx: float, gy: float) -> void:
	var label := _token_label
	if label.is_empty() and _token_label_input:
		label = _token_label_input.text.strip_edges()
	if label.is_empty():
		label = "Token %d" % (_member_index + 1)
	var em: String = MapData.MEMBER_PLAYER_EMOJIS_GENERAL[_member_index % MapData.MEMBER_PLAYER_EMOJIS_GENERAL.size()]
	_play_defaults["tokens"].append({
		"id": MapData.generate_id("tok"),
		"x": gx, "y": gy,
		"kind": "member",
		"memberId": "editor-mock-%d" % _member_index,
		"memberIndex": _member_index,
		"label": label,
		"emoji": em,
		"color": MapData.MEMBER_COLOR_HEX[_member_index % MapData.MEMBER_COLOR_HEX.size()],
	})

func _place_marker(gx: float, gy: float) -> void:
	_erase_token_near(gx, gy)
	_play_defaults["tokens"].append({
		"id": MapData.generate_id("tok"),
		"x": gx, "y": gy,
		"kind": "marker",
		"markerType": _marker_type,
		"label": MapData.get_marker_label(_marker_type),
	})

func _place_effect(gx: float, gy: float) -> void:
	var preset := MapEffectPresetsScript.get_preset(_effect_preset)
	var radius := float(_effect_radius_spin.value) if _effect_radius_spin else 1.0
	_play_defaults["effects"].append({
		"id": MapData.generate_id("fx"),
		"type": "particles",
		"preset": _effect_preset,
		"x": gx, "y": gy,
		"radius": radius,
		"triggered": false,
		"label": str(preset.get("label", _effect_preset)),
	})

func _place_zone(gx: float, gy: float) -> void:
	var radius := float(_zone_radius_spin.value) if _zone_radius_spin else 1.5
	var label := _zone_label_input.text.strip_edges() if _zone_label_input else "Zone"
	if label.is_empty():
		label = "Zone"
	_play_defaults["zones"].append({
		"id": MapData.generate_id("zone"),
		"shape": "circle",
		"x": gx, "y": gy,
		"radius": radius,
		"width": radius * 2.0,
		"height": radius * 2.0,
		"label": label,
		"color": "#c9a227",
	})

func _place_platform(cx: int, cy: int) -> void:
	var pw := int(_platform_w_spin.value) if _platform_w_spin else 3
	var ph := int(_platform_h_spin.value) if _platform_h_spin else 3
	if not _map_data.has("elevationLayers"):
		_map_data["elevationLayers"] = []
	var layers: Array = _map_data.get("elevationLayers", [])
	layers.append({
		"platform": {"x": cx, "y": cy, "w": pw, "h": ph},
		"elevation": 1.0,
		"opacity": 0.38,
		"tint": "#8a7a60",
	})
	_map_data["elevationLayers"] = layers

func _erase_at(gx: float, gy: float) -> void:
	var threshold := 0.45
	_play_defaults["tokens"] = _play_defaults.get("tokens", []).filter(func(t):
		var dx: float = abs(float(t.get("x", 0)) - gx)
		var dy: float = abs(float(t.get("y", 0)) - gy)
		return dx > threshold or dy > threshold
	)
	_play_defaults["effects"] = _play_defaults.get("effects", []).filter(func(e):
		var dx: float = abs(float(e.get("x", 0)) - gx)
		var dy: float = abs(float(e.get("y", 0)) - gy)
		return dx > threshold or dy > threshold
	)
	_play_defaults["zones"] = _play_defaults.get("zones", []).filter(func(z):
		var dx: float = abs(float(z.get("x", 0)) - gx)
		var dy: float = abs(float(z.get("y", 0)) - gy)
		return dx > 1.0 or dy > 1.0
	)
	_erase_platform_at(int(roundf(gx)), int(roundf(gy)))

func _erase_platform_at(cx: int, cy: int) -> void:
	var layers: Array = _map_data.get("elevationLayers", [])
	layers = layers.filter(func(layer):
		if not layer is Dictionary or not layer.get("platform") is Dictionary:
			return true
		var plat: Dictionary = layer["platform"]
		var px := int(plat.get("x", -999))
		var py := int(plat.get("y", -999))
		var pw := int(plat.get("w", 1))
		var ph := int(plat.get("h", 1))
		return not (cx >= px and cx < px + pw and cy >= py and cy < py + ph)
	)
	_map_data["elevationLayers"] = layers

func _erase_token_near(gx: float, gy: float, threshold: float = 0.45) -> void:
	_play_defaults["tokens"] = _play_defaults.get("tokens", []).filter(func(t):
		var dx: float = abs(float(t.get("x", 0)) - gx)
		var dy: float = abs(float(t.get("y", 0)) - gy)
		return dx > threshold or dy > threshold
	)

func _refresh_items_list() -> void:
	if _items_list == null:
		return
	for child in _items_list.get_children():
		child.queue_free()
	var count := 0
	for tok in _play_defaults.get("tokens", []):
		var kind_label := "🧍"
		if tok.get("kind") == "marker":
			kind_label = MapData.get_marker_emoji(str(tok.get("markerType", "npc")))
		_add_item_row("%s %s" % [kind_label, tok.get("label", "Token")], str(tok.get("id", "")), "token")
		count += 1
	for eff in _play_defaults.get("effects", []):
		_add_item_row("✨ %s" % eff.get("label", eff.get("preset", "effet")), str(eff.get("id", "")), "effect")
		count += 1
	for zone in _play_defaults.get("zones", []):
		_add_item_row("⭕ %s" % zone.get("label", "Zone"), str(zone.get("id", "")), "zone")
		count += 1
	var elev_layers: Array = _map_data.get("elevationLayers", [])
	for i in range(elev_layers.size()):
		var layer: Dictionary = elev_layers[i]
		if layer.get("platform") is Dictionary:
			var plat: Dictionary = layer["platform"]
			var plat_lbl := Label.new()
			plat_lbl.text = "🟫 Plateforme (%d,%d) %d×%d" % [int(plat.get("x", 0)), int(plat.get("y", 0)), int(plat.get("w", 1)), int(plat.get("h", 1))]
			plat_lbl.add_theme_font_size_override("font_size", 11)
			plat_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
			_items_list.add_child(plat_lbl)
			count += 1
		elif not str(layer.get("image", "")).is_empty():
			var ov_lbl := Label.new()
			ov_lbl.text = "🖼 Overlay %s" % str(layer.get("image", "")).get_file()
			ov_lbl.add_theme_font_size_override("font_size", 11)
			ov_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
			_items_list.add_child(ov_lbl)
			count += 1
	var fog_count: int = _play_defaults.get("fogRevealed", []).size()
	if fog_count > 0:
		var fog_lbl := Label.new()
		fog_lbl.text = "🌫 %d cases révélées" % fog_count
		fog_lbl.add_theme_font_size_override("font_size", 11)
		fog_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		_items_list.add_child(fog_lbl)
		count += 1
	if count == 0:
		var empty := Label.new()
		empty.text = "(aucun élément)"
		empty.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		empty.add_theme_font_size_override("font_size", 11)
		_items_list.add_child(empty)

func _add_item_row(label_text: String, item_id: String, kind: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.clip_text = true
	row.add_child(lbl)
	if _editable:
		var btn := Button.new()
		btn.text = "✕"
		btn.custom_minimum_size = Vector2(28, 24)
		btn.pressed.connect(func(): _delete_item(kind, item_id))
		row.add_child(btn)
	_items_list.add_child(row)

func _delete_item(kind: String, item_id: String) -> void:
	var key := "tokens"
	match kind:
		"effect":
			key = "effects"
		"zone":
			key = "zones"
	_play_defaults[key] = _play_defaults.get(key, []).filter(func(item): return str(item.get("id", "")) != item_id)
	_refresh_items_list()
	_refresh_engine()
	layout_changed.emit()

func _on_token_selected(_token_id: String) -> void:
	pass

func _on_effect_trigger_requested(effect_id: String) -> void:
	for eff in _play_defaults.get("effects", []):
		if str(eff.get("id", "")) == effect_id:
			eff["triggered"] = true
			break
	_refresh_engine()

func _trigger_all_effects() -> void:
	for eff in _play_defaults.get("effects", []):
		eff["triggered"] = true
		if _engine and _engine.has_method("trigger_effect"):
			_engine.trigger_effect(str(eff.get("id", "")))
	_refresh_engine()

func _update_zoom_label() -> void:
	if _zoom_lbl and _engine and "zoom" in _engine:
		_zoom_lbl.text = "%d%%" % int(round(_engine.zoom * 100.0))
