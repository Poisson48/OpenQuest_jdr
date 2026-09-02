extends PanelContainer

signal map_changed

const TOOL_ICON_FONT_SIZE := 22
const TOOL_ICON_BUTTON_SIZE := Vector2(48, 44)
const TOOL_TEXT_FONT_SIZE := 14

const InteractiveMapScript := preload("res://scripts/interactive_map.gd")

var _active_map_id: String = ""
var _session_tool: Dictionary = { "mode": "member", "member_id": "" }
var _toolbar_container: HBoxContainer
var _tabs_container: HBoxContainer
var _nav_bar: HBoxContainer
var _map_frame: PanelContainer
var _interactive_map: Control
var _title_lbl: Label
var _hint_lbl: Label
var _zoom_lbl: Label
var _readonly: bool = false

func _ready() -> void:
	_build_ui()
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
	map_frame.custom_minimum_size = Vector2(0, 320)
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(map_frame)

	_interactive_map = InteractiveMapScript.new()
	_interactive_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_interactive_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_interactive_map.custom_minimum_size = Vector2(280, 300)
	_interactive_map.cell_clicked.connect(_on_cell_clicked)
	_interactive_map.navigation_requested.connect(_on_navigation_requested)
	_interactive_map.zoom_changed.connect(func(_z): _update_zoom_label())
	map_frame.add_child(_interactive_map)

func _build_zoom_controls(parent: HBoxContainer) -> void:
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 4)
	zoom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(zoom_row)

	var btn_zoom_out := Button.new()
	btn_zoom_out.text = "−"
	btn_zoom_out.custom_minimum_size = Vector2(28, 26)
	btn_zoom_out.add_theme_font_size_override("font_size", 14)
	btn_zoom_out.tooltip_text = "Dézoomer"
	btn_zoom_out.pressed.connect(func(): _interactive_map.zoom_out())
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
	btn_zoom_in.add_theme_font_size_override("font_size", 14)
	btn_zoom_in.tooltip_text = "Zoomer"
	btn_zoom_in.pressed.connect(func(): _interactive_map.zoom_in())
	zoom_row.add_child(btn_zoom_in)

	var btn_zoom_reset := Button.new()
	btn_zoom_reset.text = "⟲"
	btn_zoom_reset.custom_minimum_size = Vector2(28, 26)
	btn_zoom_reset.add_theme_font_size_override("font_size", 14)
	btn_zoom_reset.tooltip_text = "Réinitialiser le zoom"
	btn_zoom_reset.pressed.connect(func(): _interactive_map.reset_zoom())
	zoom_row.add_child(btn_zoom_reset)

func refresh() -> void:
	var state := GameData.active_game
	var map_ids: Array = state.get("mapIds", [])
	visible = not map_ids.is_empty()
	if map_ids.is_empty():
		return

	_readonly = state.get("status") == "completed"
	_init_session_tool(state)
	_render_tabs(map_ids)
	_render_toolbar(state)
	_render_active_map(state)
	map_changed.emit()

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
		btn.add_theme_font_size_override("font_size", 13)
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

	if _readonly:
		_toolbar_container.visible = false
		return
	_toolbar_container.visible = true

	var party: Array = state.get("party", [])
	var quest_format: String = state.get("questFormat", "oneshot")
	var active_id := _get_active_map_id(state.get("mapIds", []))
	var ctx := GameData.get_session_display_map(active_id)
	var display_map: Dictionary = ctx.get("displayMap", {})

	for member in party:
		var mid: String = member.get("id", "")
		var em := _member_emoji(member, quest_format)
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
		var em := MapData.get_marker_emoji(marker_type)
		var btn := _make_tool_button(em, true)
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

	var quest_format: String = state.get("questFormat", "oneshot")
	var map_count := map_ids.size()
	_title_lbl.text = "🗺️ Carte%s" % ("s" if map_count > 1 else "")

	_render_nav_bar(nav_ctx)
	_apply_map_config(state, active_id, ctx)

	var is_world := MapData.is_world_map(display_map) and nav_ctx.is_empty()
	if nav_ctx.get("mode") == "local":
		_hint_lbl.text = "Clique sur la sortie 🚪 ou « Monde » pour revenir à la carte du monde."
	elif is_world:
		if quest_format == "investigation":
			_hint_lbl.text = "Les lieux d'intérêt se dévoilent au fil de l'enquête · clique sur une ville liée 🌀 pour entrer."
		else:
			_hint_lbl.text = "Clique sur une ville liée 🌀 pour entrer · glisser pour déplacer · molette ou +/− pour zoomer."
	elif quest_format == "investigation" or display_map.get("roster", "") == "investigation":
		_hint_lbl.text = "Les indices et points d'intérêt apparaissent progressivement — explore et interroge pour les révéler."
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
	var world_title: String = nav_ctx.get("worldMap", {}).get("title", "Monde")
	var local_title: String = nav_ctx.get("localMap", {}).get("title", "Scène")
	var crumb := Label.new()
	crumb.text = "%s › %s" % [world_title, local_title]
	crumb.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_nav_bar.add_child(crumb)

func _apply_map_config(state: Dictionary, active_id: String, ctx: Dictionary) -> void:
	var display_map: Dictionary = ctx.get("displayMap", {})
	if display_map.is_empty():
		return
	var map_id: String = display_map.get("id", "")
	var party: Array = state.get("party", [])
	var tokens: Array = GameData.get_map_play_tokens(map_id)
	var explored: Array = GameData.get_explored_cells(map_id)
	var nav_ctx: Dictionary = ctx.get("navContext", {})

	var tool := {}
	match _session_tool.get("mode", "member"):
		"erase":
			tool = { "mode": "erase" }
		"member":
			tool = { "mode": "member", "memberId": _session_tool.get("member_id", "") }
		"marker":
			tool = { "mode": "marker", "markerType": _session_tool.get("marker_type", "") }

	_interactive_map.configure(
		display_map,
		tokens,
		party,
		explored,
		state.get("questFormat", "oneshot"),
		_readonly,
		nav_ctx,
		GameData.get_revealed_markers(map_id),
		GameData.get_revealed_links(map_id)
	)
	_interactive_map.set_session_tool(tool.get("mode", "member"), tool)
	_update_zoom_label()
	call_deferred("_sync_map_viewport_size")

func _sync_map_viewport_size() -> void:
	if _interactive_map == null or _map_frame == null:
		return
	var frame_h := int(_map_frame.size.y)
	var frame_w := int(_map_frame.size.x)
	if frame_h > 32 and frame_w > 32:
		_interactive_map.custom_minimum_size = Vector2(maxi(280, frame_w - 4), maxi(300, frame_h - 4))

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
	var display_map: Dictionary = ctx.get("displayMap", {})
	var map_id: String = display_map.get("id", "")
	if map_id.is_empty():
		return

	var tool := {}
	match _session_tool.get("mode", "member"):
		"erase":
			tool = { "mode": "erase" }
		"member":
			tool = { "mode": "member", "memberId": _session_tool.get("member_id", "") }
		"marker":
			tool = { "mode": "marker", "markerType": _session_tool.get("marker_type", "") }

	GameData.apply_map_play_action(map_id, x, y, tool)
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
	if _interactive_map:
		_zoom_lbl.text = "%d%%" % int(round(_interactive_map.zoom * 100.0))

func _member_emoji(member: Dictionary, quest_format: String) -> String:
	if member.get("isBot", false):
		return "🤖"
	return "🔍" if quest_format == "investigation" else "⚔️"
