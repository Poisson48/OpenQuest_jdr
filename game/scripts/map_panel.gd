extends PanelContainer

signal map_changed

const TOOL_ICON_FONT_SIZE := 22
const TOOL_ICON_BUTTON_SIZE := Vector2(48, 44)
const TOOL_TEXT_FONT_SIZE := 14

const SimpleMapRendererScript := preload("res://scripts/maps/simple_map_renderer.gd")
const ComplexMapEngineScript := preload("res://scripts/maps/complex_map_engine.gd")
const MapModeScript := preload("res://scripts/maps/map_mode.gd")
const MapEffectPresetsScript := preload("res://scripts/maps/map_effect_presets.gd")

var _active_map_id: String = ""
var _session_tool: Dictionary = { "mode": "member", "member_id": "" }
var _toolbar_container: HBoxContainer
var _complex_toolbar: HBoxContainer
var _tabs_container: HBoxContainer
var _nav_bar: HBoxContainer
var _map_frame: PanelContainer
var _simple_map: Control
var _complex_engine: Control
var _title_lbl: Label
var _mode_badge: Label
var _mode_select: OptionButton
var _hint_lbl: Label
var _zoom_lbl: Label
var _snap_btn: Button
var _trigger_btn: Button
var _readonly: bool = false
var _current_mode: String = MapModeScript.SIMPLE

func _ready() -> void:
	_build_ui()
	resized.connect(func(): call_deferred("_sync_map_viewport_size"))
	refresh()

func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	outer.add_child(header)

	_title_lbl = Label.new()
	_title_lbl.text = "🗺️ Carte interactive"
	_title_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_lbl)

	_mode_badge = Label.new()
	_mode_badge.add_theme_font_size_override("font_size", 12)
	_mode_badge.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	header.add_child(_mode_badge)

	_mode_select = OptionButton.new()
	_mode_select.add_item("▦ Simple", 0)
	_mode_select.set_item_metadata(0, MapModeScript.SIMPLE)
	_mode_select.add_item("⚙️ Complexe", 1)
	_mode_select.set_item_metadata(1, MapModeScript.COMPLEX)
	_mode_select.custom_minimum_size = Vector2(130, 30)
	_mode_select.item_selected.connect(_on_mode_selected)
	header.add_child(_mode_select)

	_tabs_container = HBoxContainer.new()
	_tabs_container.add_theme_constant_override("separation", 4)
	header.add_child(_tabs_container)

	_build_zoom_controls(header)

	_nav_bar = HBoxContainer.new()
	_nav_bar.add_theme_constant_override("separation", 8)
	_nav_bar.visible = false
	outer.add_child(_nav_bar)

	var toolbar_scroll := ScrollContainer.new()
	toolbar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	toolbar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toolbar_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar_scroll.custom_minimum_size = Vector2(0, 52)
	outer.add_child(toolbar_scroll)

	_toolbar_container = HBoxContainer.new()
	_toolbar_container.add_theme_constant_override("separation", 6)
	_toolbar_container.alignment = BoxContainer.ALIGNMENT_CENTER
	toolbar_scroll.add_child(_toolbar_container)

	var complex_scroll := ScrollContainer.new()
	complex_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	complex_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	complex_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	complex_scroll.custom_minimum_size = Vector2(0, 48)
	complex_scroll.visible = false
	outer.add_child(complex_scroll)

	_complex_toolbar = HBoxContainer.new()
	_complex_toolbar.add_theme_constant_override("separation", 6)
	_complex_toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
	complex_scroll.add_child(_complex_toolbar)
	complex_scroll.set_meta("scroll", complex_scroll)

	_hint_lbl = Label.new()
	_hint_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_hint_lbl.add_theme_font_size_override("font_size", 12)
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_hint_lbl)

	var map_frame := PanelContainer.new()
	_map_frame = map_frame
	var map_style := StyleBoxFlat.new()
	map_style.bg_color = ThemeColors.BG_INPUT
	map_style.border_color = ThemeColors.BORDER
	map_style.set_border_width_all(1)
	map_style.set_corner_radius_all(4)
	map_frame.add_theme_stylebox_override("panel", map_style)
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(map_frame)

	_simple_map = SimpleMapRendererScript.new()
	_simple_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_simple_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_simple_map.cell_clicked.connect(_on_cell_clicked)
	_simple_map.navigation_requested.connect(_on_navigation_requested)
	_simple_map.zoom_changed.connect(func(_z): _update_zoom_label())
	map_frame.add_child(_simple_map)

	_complex_engine = ComplexMapEngineScript.new()
	_complex_engine.visible = false
	_complex_engine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_complex_engine.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_complex_engine.map_clicked.connect(_on_complex_map_clicked)
	_complex_engine.token_moved.connect(_on_complex_token_moved)
	_complex_engine.fog_revealed.connect(_on_fog_revealed)
	_complex_engine.effect_trigger_requested.connect(_on_effect_trigger)
	_complex_engine.token_selected.connect(_on_token_selected)
	_complex_engine.zoom_changed.connect(func(_z): _update_zoom_label())
	map_frame.add_child(_complex_engine)

func _build_zoom_controls(parent: HBoxContainer) -> void:
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 4)
	zoom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(zoom_row)

	var btn_zoom_out := Button.new()
	btn_zoom_out.text = "−"
	btn_zoom_out.custom_minimum_size = Vector2(28, 26)
	btn_zoom_out.tooltip_text = "Dézoomer"
	btn_zoom_out.pressed.connect(func(): _active_renderer().zoom_out())
	zoom_row.add_child(btn_zoom_out)

	_zoom_lbl = Label.new()
	_zoom_lbl.text = "100%"
	_zoom_lbl.custom_minimum_size = Vector2(44, 0)
	_zoom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_lbl.add_theme_font_size_override("font_size", 12)
	_zoom_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	zoom_row.add_child(_zoom_lbl)

	var btn_zoom_in := Button.new()
	btn_zoom_in.text = "+"
	btn_zoom_in.custom_minimum_size = Vector2(28, 26)
	btn_zoom_in.tooltip_text = "Zoomer"
	btn_zoom_in.pressed.connect(func(): _active_renderer().zoom_in())
	zoom_row.add_child(btn_zoom_in)

	var btn_zoom_reset := Button.new()
	btn_zoom_reset.text = "⟲"
	btn_zoom_reset.custom_minimum_size = Vector2(28, 26)
	btn_zoom_reset.tooltip_text = "Réinitialiser le zoom"
	btn_zoom_reset.pressed.connect(func(): _active_renderer().reset_zoom())
	zoom_row.add_child(btn_zoom_reset)

func _active_renderer() -> Control:
	return _complex_engine if _current_mode == MapModeScript.COMPLEX else _simple_map

func refresh() -> void:
	var state := GameData.active_game
	var map_ids: Array = state.get("mapIds", [])
	visible = not map_ids.is_empty()
	if map_ids.is_empty():
		return

	_readonly = state.get("status") == "completed"
	_init_session_tool(state)
	var active_id := _get_active_map_id(map_ids)
	_current_mode = GameData.get_effective_render_mode(active_id)
	_sync_mode_selector()
	_render_tabs(map_ids)
	_render_toolbar(state)
	_render_complex_toolbar(state)
	_render_active_map(state)
	map_changed.emit()

func _sync_mode_selector() -> void:
	_mode_badge.text = MapModeScript.badge(_current_mode)
	_mode_badge.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT if _current_mode == MapModeScript.COMPLEX else ThemeColors.TEXT_MUTED)
	for i in range(_mode_select.item_count):
		if _mode_select.get_item_metadata(i) == _current_mode:
			_mode_select.select(i)
			break
	_mode_select.disabled = _readonly

func _on_mode_selected(index: int) -> void:
	var mode: String = _mode_select.get_item_metadata(index)
	var state := GameData.active_game
	var active_id := _get_active_map_id(state.get("mapIds", []))
	if active_id.is_empty():
		return
	GameData.set_map_render_mode_override(active_id, mode)
	refresh()

func _init_session_tool(state: Dictionary) -> void:
	var party: Array = state.get("party", [])
	if party.is_empty():
		_session_tool = { "mode": "erase" }
	elif _session_tool.is_empty() or (_session_tool.get("mode") == "member" and _session_tool.get("member_id", "").is_empty()):
		_session_tool = { "mode": "member", "member_id": party[0].get("id", "") }

func _render_tabs(map_ids: Array) -> void:
	for child in _tabs_container.get_children():
		child.queue_free()
	if map_ids.size() <= 1:
		return
	for map_id in map_ids:
		var m := MapData.get_by_id(map_id)
		if m.is_empty():
			continue
		var btn := Button.new()
		var kind := "Monde" if MapData.is_world_map(m) else "Scène"
		btn.text = "%s · %s" % [kind, m.get("title", map_id)]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0, 34)
		btn.button_pressed = map_id == _get_active_map_id(map_ids)
		var captured_id: String = map_id
		btn.pressed.connect(func():
			_active_map_id = captured_id
			refresh()
		)
		_tabs_container.add_child(btn)

func _render_toolbar(state: Dictionary) -> void:
	for child in _toolbar_container.get_children():
		child.queue_free()
	var show_simple := _current_mode == MapModeScript.SIMPLE
	_toolbar_container.get_parent().visible = show_simple and not _readonly
	if not show_simple or _readonly:
		return

	var party: Array = state.get("party", [])
	var quest_format: String = state.get("questFormat", "oneshot")
	var active_id := _get_active_map_id(state.get("mapIds", []))
	var ctx := GameData.get_session_display_map(active_id)
	var display_map: Dictionary = ctx.get("displayMap", {})

	for member in party:
		var mid: String = member.get("id", "")
		var em := MapData.get_member_emoji(mid, party, quest_format)
		var btn := _make_tool_button(em, true)
		btn.tooltip_text = member.get("name", "")
		btn.button_pressed = _session_tool.get("mode") == "member" and _session_tool.get("member_id") == mid
		btn.pressed.connect(func():
			_session_tool = { "mode": "member", "member_id": mid }
			_render_toolbar(state)
			_apply_map_config(state, active_id, ctx)
		)
		_toolbar_container.add_child(btn)

	for marker_type in MapData.get_session_marker_types(quest_format, display_map):
		var btn := _make_tool_button(MapData.get_marker_emoji(marker_type), true)
		btn.tooltip_text = MapData.get_marker_label(marker_type)
		btn.button_pressed = _session_tool.get("mode") == "marker" and _session_tool.get("marker_type") == marker_type
		var captured_type: String = marker_type
		btn.pressed.connect(func():
			_session_tool = { "mode": "marker", "marker_type": captured_type }
			_render_toolbar(state)
			_apply_map_config(state, active_id, ctx)
		)
		_toolbar_container.add_child(btn)

	var erase_btn := _make_tool_button("🧹 Effacer", false)
	erase_btn.button_pressed = _session_tool.get("mode") == "erase"
	erase_btn.pressed.connect(func():
		_session_tool = { "mode": "erase" }
		_render_toolbar(state)
		_apply_map_config(state, active_id, ctx)
	)
	_toolbar_container.add_child(erase_btn)

func _render_complex_toolbar(state: Dictionary) -> void:
	for child in _complex_toolbar.get_children():
		child.queue_free()
	var scroll: ScrollContainer = _complex_toolbar.get_parent()
	scroll.visible = _current_mode == MapModeScript.COMPLEX and not _readonly
	if _current_mode != MapModeScript.COMPLEX or _readonly:
		return

	var active_id := _get_active_map_id(state.get("mapIds", []))
	var ctx := GameData.get_session_display_map(active_id)
	var party: Array = state.get("party", [])
	var quest_format: String = state.get("questFormat", "oneshot")

	for member in party:
		var mid: String = member.get("id", "")
		var btn := _make_tool_button(_member_emoji(member, quest_format), true)
		btn.button_pressed = _session_tool.get("mode") == "member" and _session_tool.get("member_id") == mid
		btn.pressed.connect(func():
			_session_tool = { "mode": "member", "member_id": mid }
			_render_complex_toolbar(state)
			_apply_map_config(state, active_id, ctx)
		)
		_complex_toolbar.add_child(btn)

	for preset_id in ["fire", "smoke", "magic"]:
		var preset := MapEffectPresetsScript.get_preset(preset_id)
		var btn := _make_tool_button(str(preset.get("emoji", "✨")), true)
		btn.tooltip_text = "Effet : %s" % preset.get("label", preset_id)
		btn.button_pressed = _session_tool.get("mode") == "effect" and _session_tool.get("preset") == preset_id
		btn.pressed.connect(func():
			_session_tool = { "mode": "effect", "preset": preset_id, "radius": 1.0 }
			_render_complex_toolbar(state)
			_apply_map_config(state, active_id, ctx)
		)
		_complex_toolbar.add_child(btn)

	var fog_btn := _make_tool_button("🌫️", true)
	fog_btn.tooltip_text = "Révéler brouillard (MJ)"
	fog_btn.button_pressed = _session_tool.get("mode") == "fog"
	fog_btn.pressed.connect(func():
		_session_tool = { "mode": "fog" }
		_render_complex_toolbar(state)
		_apply_map_config(state, active_id, ctx)
	)
	_complex_toolbar.add_child(fog_btn)

	var zone_btn := _make_tool_button("⭕", true)
	zone_btn.tooltip_text = "Zone (sort / piège)"
	zone_btn.button_pressed = _session_tool.get("mode") == "zone"
	zone_btn.pressed.connect(func():
		_session_tool = { "mode": "zone", "radius": 1.5, "label": "Zone" }
		_render_complex_toolbar(state)
		_apply_map_config(state, active_id, ctx)
	)
	_complex_toolbar.add_child(zone_btn)

	_snap_btn = Button.new()
	_snap_btn.text = "⊞ Grille"
	_snap_btn.toggle_mode = true
	_snap_btn.button_pressed = true
	_snap_btn.tooltip_text = "Accrochage à la grille"
	_snap_btn.pressed.connect(func():
		if _complex_engine.has_method("set_snap_to_grid"):
			_complex_engine.set_snap_to_grid(_snap_btn.button_pressed)
	)
	_complex_toolbar.add_child(_snap_btn)

	_trigger_btn = Button.new()
	_trigger_btn.text = "▶ Déclencher"
	_trigger_btn.tooltip_text = "Déclencher l'effet sélectionné"
	_trigger_btn.pressed.connect(_on_trigger_selected_effect)
	_complex_toolbar.add_child(_trigger_btn)

	var erase_btn := _make_tool_button("🧹", true)
	erase_btn.tooltip_text = "Effacer token"
	erase_btn.button_pressed = _session_tool.get("mode") == "erase"
	erase_btn.pressed.connect(func():
		_session_tool = { "mode": "erase" }
		_render_complex_toolbar(state)
		_apply_map_config(state, active_id, ctx)
	)
	_complex_toolbar.add_child(erase_btn)

func _make_tool_button(text: String, icon_only: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	if icon_only:
		btn.add_theme_font_size_override("font_size", TOOL_ICON_FONT_SIZE)
		btn.custom_minimum_size = TOOL_ICON_BUTTON_SIZE
	else:
		btn.add_theme_font_size_override("font_size", TOOL_TEXT_FONT_SIZE)
		btn.custom_minimum_size = Vector2(96, 44)
	return btn

func _render_active_map(state: Dictionary) -> void:
	var map_ids: Array = state.get("mapIds", [])
	var active_id := _get_active_map_id(map_ids)
	var ctx := GameData.get_session_display_map(active_id)
	var display_map: Dictionary = ctx.get("displayMap", {})
	var nav_ctx: Dictionary = ctx.get("navContext", {})

	if display_map.is_empty():
		_hint_lbl.text = ""
		return

	_title_lbl.text = "🗺️ Carte%s" % ("s" if map_ids.size() > 1 else "")
	_render_nav_bar(nav_ctx)
	_apply_map_config(state, active_id, ctx)

	if _current_mode == MapModeScript.COMPLEX:
		_hint_lbl.text = "Mode VTT : glisser tokens · effets 🔥💨✨ · brouillard 🌫️ · zones ⭕ · ▶ déclencher"
	elif nav_ctx.get("mode") == "local":
		_hint_lbl.text = "Clique sur la sortie 🚪 ou « Monde » pour revenir à la carte du monde."
	elif MapData.is_world_map(display_map) and nav_ctx.is_empty():
		_hint_lbl.text = "Mode simple — lieux 🌀 · glisser · molette zoom. Passe en Complexe pour battlemap VTT."
	else:
		_hint_lbl.text = "Glisser pour déplacer · molette ou +/− pour zoomer · ⟲ pour tout afficher."

func _render_nav_bar(nav_ctx: Dictionary) -> void:
	for child in _nav_bar.get_children():
		child.queue_free()
	if nav_ctx.is_empty() or nav_ctx.get("mode") != "local":
		_nav_bar.visible = false
		return
	_nav_bar.visible = true
	var back_btn := Button.new()
	back_btn.text = "← Monde"
	back_btn.pressed.connect(func():
		GameData.exit_to_world_map()
		refresh()
	)
	_nav_bar.add_child(back_btn)
	var crumb := Label.new()
	crumb.text = "%s › %s" % [nav_ctx.get("worldMap", {}).get("title", "Monde"), nav_ctx.get("localMap", {}).get("title", "Scène")]
	crumb.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_nav_bar.add_child(crumb)

func _apply_map_config(state: Dictionary, active_id: String, ctx: Dictionary) -> void:
	var display_map: Dictionary = ctx.get("displayMap", {})
	if display_map.is_empty():
		return
	var map_id: String = display_map.get("id", "")
	var party: Array = state.get("party", [])
	var is_gm := GameData.is_gm_view_for_map(map_id)

	var use_complex := _current_mode == MapModeScript.COMPLEX
	_simple_map.visible = not use_complex
	_complex_engine.visible = use_complex

	if use_complex:
		var tool := _complex_tool_dict()
		_complex_engine.configure(
			display_map,
			GameData.get_map_play_tokens(map_id),
			party,
			GameData.get_map_effects(map_id),
			GameData.get_map_zones(map_id),
			GameData.get_fog_revealed_cells(map_id),
			_readonly,
			is_gm,
			tool,
			GameData.get_map_view_state(map_id),
			GameData.get_selected_token_id(map_id),
		)
		_complex_engine.set_session_tool(tool)
	else:
		var tool := _simple_tool_dict()
		_simple_map.configure(
			display_map,
			GameData.get_map_play_tokens(map_id),
			party,
			GameData.get_explored_cells(map_id),
			state.get("questFormat", "oneshot"),
			_readonly,
			ctx.get("navContext", {}),
			GameData.get_revealed_markers(map_id),
			GameData.get_revealed_links(map_id),
		)
		_simple_map.set_session_tool(tool.get("mode", "member"), tool)

	_update_zoom_label()
	call_deferred("_sync_map_viewport_size")

func _simple_tool_dict() -> Dictionary:
	match _session_tool.get("mode", "member"):
		"erase":
			return { "mode": "erase" }
		"marker":
			return { "mode": "marker", "markerType": _session_tool.get("marker_type", "") }
		_:
			return { "mode": "member", "memberId": _session_tool.get("member_id", "") }

func _complex_tool_dict() -> Dictionary:
	var mode: String = _session_tool.get("mode", "member")
	var tool := { "mode": mode }
	match mode:
		"member":
			tool["memberId"] = _session_tool.get("member_id", "")
		"marker":
			tool["markerType"] = _session_tool.get("marker_type", "")
		"effect":
			tool["preset"] = _session_tool.get("preset", "fire")
			tool["radius"] = _session_tool.get("radius", 1.0)
		"zone":
			tool["radius"] = _session_tool.get("radius", 1.5)
			tool["label"] = _session_tool.get("label", "Zone")
	return tool

func _sync_map_viewport_size() -> void:
	if _map_frame == null:
		return
	var frame_h := int(_map_frame.size.y)
	var frame_w := int(_map_frame.size.x)
	if frame_h > 32 and frame_w > 32:
		var sz := Vector2(maxi(64, frame_w - 4), maxi(64, frame_h - 4))
		_simple_map.custom_minimum_size = sz
		_complex_engine.custom_minimum_size = sz

func _get_active_map_id(map_ids: Array) -> String:
	if map_ids.is_empty():
		return ""
	if not _active_map_id.is_empty() and map_ids.has(_active_map_id):
		return _active_map_id
	_active_map_id = map_ids[0]
	return _active_map_id

func _on_cell_clicked(x: int, y: int) -> void:
	var state := GameData.active_game
	var active_id := _get_active_map_id(state.get("mapIds", []))
	var ctx := GameData.get_session_display_map(active_id)
	var map_id: String = ctx.get("displayMap", {}).get("id", "")
	if map_id.is_empty():
		return
	GameData.apply_map_play_action(map_id, x, y, _simple_tool_dict())
	_apply_map_config(state, active_id, GameData.get_session_display_map(active_id))

func _on_complex_map_clicked(gx: float, gy: float, tool: Dictionary) -> void:
	var state := GameData.active_game
	var active_id := _get_active_map_id(state.get("mapIds", []))
	var map_id: String = GameData.get_session_display_map(active_id).get("displayMap", {}).get("id", "")
	if map_id.is_empty():
		return
	GameData.apply_complex_map_click(map_id, gx, gy, tool)
	_apply_map_config(state, active_id, GameData.get_session_display_map(active_id))

func _on_complex_token_moved(token_id: String, gx: float, gy: float) -> void:
	var state := GameData.active_game
	var active_id := _get_active_map_id(state.get("mapIds", []))
	var map_id: String = GameData.get_session_display_map(active_id).get("displayMap", {}).get("id", "")
	GameData.move_complex_token(map_id, token_id, gx, gy)
	if _complex_engine.has_method("get_view_state"):
		GameData.save_map_view_state(map_id, _complex_engine.get_view_state())

func _on_fog_revealed(cells: Array) -> void:
	var state := GameData.active_game
	var active_id := _get_active_map_id(state.get("mapIds", []))
	var map_id: String = GameData.get_session_display_map(active_id).get("displayMap", {}).get("id", "")
	GameData.reveal_fog_cells(map_id, cells)
	_apply_map_config(state, active_id, GameData.get_session_display_map(active_id))

func _on_token_selected(token_id: String) -> void:
	var state := GameData.active_game
	var active_id := _get_active_map_id(state.get("mapIds", []))
	var map_id: String = GameData.get_session_display_map(active_id).get("displayMap", {}).get("id", "")
	GameData.set_selected_token_id(map_id, token_id)

func _on_effect_trigger(effect_id: String) -> void:
	var state := GameData.active_game
	var active_id := _get_active_map_id(state.get("mapIds", []))
	var map_id: String = GameData.get_session_display_map(active_id).get("displayMap", {}).get("id", "")
	GameData.trigger_map_effect(map_id, effect_id)
	_apply_map_config(state, active_id, GameData.get_session_display_map(active_id))

func _on_trigger_selected_effect() -> void:
	var state := GameData.active_game
	var active_id := _get_active_map_id(state.get("mapIds", []))
	var map_id: String = GameData.get_session_display_map(active_id).get("displayMap", {}).get("id", "")
	var fx_id := GameData.get_selected_token_id(map_id)
	if fx_id.is_empty():
		for eff in GameData.get_map_effects(map_id):
			GameData.trigger_map_effect(map_id, str(eff.get("id", "")))
	else:
		GameData.trigger_map_effect(map_id, fx_id)
	if _complex_engine.has_method("trigger_effect"):
		for eff in GameData.get_map_effects(map_id):
			if bool(eff.get("triggered", false)):
				_complex_engine.trigger_effect(str(eff.get("id", "")))
	_apply_map_config(state, active_id, GameData.get_session_display_map(active_id))

func _on_navigation_requested(action: String, data: Dictionary) -> void:
	var state := GameData.active_game
	var active_id := _get_active_map_id(state.get("mapIds", []))
	if action == "enter_local":
		GameData.enter_local_map(active_id, data.get("x", 0), data.get("y", 0), data.get("targetMapId", ""))
	elif action == "exit_world":
		GameData.exit_to_world_map()
	refresh()

func _update_zoom_label() -> void:
	var renderer := _active_renderer()
	if renderer and "zoom" in renderer:
		_zoom_lbl.text = "%d%%" % int(round(renderer.zoom * 100.0))
