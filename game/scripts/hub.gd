extends Control

@onready var tab_container: TabContainer = %TabContainer
@onready var bots_sections_root: VBoxContainer = %BotsSectionsRoot
@onready var bots_scroll: ScrollContainer = %BotsScroll
@onready var bots_filter: OptionButton = %BotsFilter
@onready var bots_count_lbl: Label = %BotsCountLabel
@onready var adv_summary_lbl: Label = %AdvSummaryLabel
@onready var inv_summary_lbl: Label = %InvSummaryLabel
@onready var play_status_lbl: Label = %PlayStatusLabel
@onready var saved_games_list: VBoxContainer = %SavedGamesList
@onready var maps_sections_root: VBoxContainer = %MapsSectionsRoot
@onready var maps_sort: OptionButton = %MapsSort

var _pending_delete_id: String = ""
var _pending_delete_map_id: String = ""
var _pending_delete_bot_id: String = ""
var _last_bot_grid_cols: int = -1

func _ready() -> void:
	%BtnHome.pressed.connect(_on_home_pressed)
	MultiplayerManager.game_started.connect(_on_remote_game_started)
	
	# Onglet Aventures
	%BtnAdvNewChar.pressed.connect(func(): GameData.go_to_character_editor("general"))
	%BtnAdvScenarios.pressed.connect(func(): GameData.go_to_scenario_list("adventure"))
	%BtnAdvPlay.pressed.connect(func(): GameData.go_to_game_setup("adventure"))

	# Onglet Enquête
	%BtnInvNewChar.pressed.connect(func(): GameData.go_to_character_editor("investigation"))
	%BtnInvScenarios.pressed.connect(func(): GameData.go_to_scenario_list("investigation"))
	%BtnInvPlay.pressed.connect(func(): GameData.go_to_game_setup("investigation"))

	# Onglet Jouer
	%BtnPlayNew.pressed.connect(func(): GameData.go_to_game_setup())
	%ConfirmDeleteSession.confirmed.connect(_on_confirm_delete_session)
	
	# Onglet Cartes
	%BtnNewMapWorld.pressed.connect(func(): _create_map("general", "world"))
	%BtnNewMapAdv.pressed.connect(func(): _create_map("general", "local"))
	%BtnNewMapInv.pressed.connect(func(): _create_map("investigation", "local"))
	%ConfirmDeleteMap.confirmed.connect(_on_confirm_delete_map)
	%ConfirmDeleteBot.confirmed.connect(_on_confirm_delete_bot)
	MapData.maps_updated.connect(_render_maps_tab)
	GameData.bots_updated.connect(_render_bots)
	_setup_maps_sort()
	_setup_bots_filter()
	
	_populate_hub_data()
	_wrap_tab_scroll(["Aventures", "Enquête", "Jouer"])

func _setup_bots_filter() -> void:
	bots_filter.clear()
	bots_filter.add_item("Tous les modes", 0)
	bots_filter.set_item_metadata(0, "all")
	bots_filter.add_item("⚔️ Aventure & one-shots", 1)
	bots_filter.set_item_metadata(1, "adventure")
	bots_filter.add_item("🔍 Enquête", 2)
	bots_filter.set_item_metadata(2, "investigation")
	bots_filter.item_selected.connect(func(_idx): _render_bots())
	if not bots_scroll.resized.is_connected(_on_bots_scroll_resized):
		bots_scroll.resized.connect(_on_bots_scroll_resized)

func _on_bots_scroll_resized() -> void:
	if bots_sections_root.get_child_count() == 0:
		return
	var cols := _bot_grid_columns()
	if cols != _last_bot_grid_cols:
		_render_bots()

func _current_bots_filter_mode() -> String:
	var idx := bots_filter.selected
	if idx >= 0 and idx < bots_filter.item_count:
		return str(bots_filter.get_item_metadata(idx))
	return "all"

func _populate_hub_data() -> void:
	# Stats aventures
	var gen_chars := GameData.get_characters("general")
	var gen_scns := GameData.get_scenarios("", "general")
	adv_summary_lbl.text = "👥 %d héros créés · 📜 %d scénarios d'aventure disponibles" % [gen_chars.size(), gen_scns.size()]
	
	# Stats enquêtes
	var inv_chars := GameData.get_characters("investigation")
	var inv_scns := GameData.get_scenarios("", "investigation")
	inv_summary_lbl.text = "🔍 %d enquêteurs · 📁 %d dossiers d'enquête disponibles" % [inv_chars.size(), inv_scns.size()]
	
	_render_saved_games()
	_render_bots()
	_render_maps_tab()

func _setup_maps_sort() -> void:
	maps_sort.clear()
	maps_sort.add_item("Titre (A → Z)", 0)
	maps_sort.add_item("Titre (Z → A)", 1)
	maps_sort.add_item("Taille (grande → petite)", 2)
	maps_sort.add_item("Scénario lié", 3)
	maps_sort.item_selected.connect(func(_idx): _render_maps_tab())

func _current_maps_sort_mode() -> String:
	match maps_sort.selected:
		1: return "title_desc"
		2: return "size_desc"
		3: return "scenario"
		_: return "title_asc"

func _render_maps_tab() -> void:
	if maps_sections_root == null:
		return
	for child in maps_sections_root.get_children():
		child.queue_free()
	var sort_mode := _current_maps_sort_mode()
	_add_maps_section(
		"🌍 Cartes du monde",
		"Continents, royaumes et villes pour les campagnes longues.",
		MapData.sort_maps(MapData.get_maps_by_category("world"), sort_mode),
		"world"
	)
	_add_maps_section(
		"⚔️ Scènes aventure",
		"Donjons, tavernes et zones d'exploration locales.",
		MapData.sort_maps(MapData.get_maps_by_category("adventure"), sort_mode),
		"adventure"
	)
	_add_maps_section(
		"🔍 Scènes enquête",
		"Quartiers, commissariats et lieux de crime.",
		MapData.sort_maps(MapData.get_maps_by_category("investigation"), sort_mode),
		"investigation"
	)

func _add_maps_section(title: String, hint: String, map_list: Array, category: String) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := Label.new()
	header.text = title
	header.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	header.add_theme_font_size_override("font_size", 16)
	section.add_child(header)

	var desc := Label.new()
	desc.text = hint
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	desc.add_theme_font_size_override("font_size", 12)
	section.add_child(desc)

	if map_list.is_empty():
		var empty := Label.new()
		empty.text = "Aucune carte — utilise les boutons « + » ci-dessus pour en créer une."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		section.add_child(empty)
	else:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 12)
		flow.add_theme_constant_override("v_separation", 12)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for map_data in map_list:
			flow.add_child(_build_map_card(map_data, category))
		section.add_child(flow)

	maps_sections_root.add_child(section)

func _build_map_card(map_data: Dictionary, category: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BG_CARD
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var badge := Label.new()
	var w: int = int(map_data.get("width", 0))
	var h: int = int(map_data.get("height", 0))
	var badge_icon := "🌍" if category == "world" else ("🔍" if category == "investigation" else "⚔️")
	badge.text = "%s %d×%d · %d carrés" % [badge_icon, w, h, w * h]
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", ThemeColors.GOLD)
	vbox.add_child(badge)

	var title_lbl := Label.new()
	title_lbl.text = map_data.get("title", "Sans titre")
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	vbox.add_child(title_lbl)

	var scenario_id: String = map_data.get("scenarioId", "")
	if not scenario_id.is_empty():
		var scn_lbl := Label.new()
		scn_lbl.text = "Scénario : %s" % scenario_id
		scn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scn_lbl.add_theme_font_size_override("font_size", 11)
		scn_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		vbox.add_child(scn_lbl)

	var desc_text: String = map_data.get("description", "")
	if not desc_text.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = desc_text
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		vbox.add_child(desc_lbl)

	var map_id: String = map_data.get("id", "")

	var meta := Label.new()
	var link_count: int = map_data.get("locationLinks", []).size()
	if category == "world" and link_count > 0:
		meta.text = "%d marqueur(s) · %d scène(s) liée(s)" % [map_data.get("markers", []).size(), link_count]
	elif category != "world":
		var world_links: Array = MapData.get_world_links_to_map(map_id)
		if world_links.is_empty():
			meta.text = "%d marqueur(s) · non liée au monde" % map_data.get("markers", []).size()
		else:
			meta.text = "%d marqueur(s) · intégrée dans %d carte(s) monde" % [map_data.get("markers", []).size(), world_links.size()]
	else:
		meta.text = "%d marqueur(s)" % map_data.get("markers", []).size()
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	vbox.add_child(meta)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)

	var btn_preview := Button.new()
	btn_preview.text = "Aperçu"
	btn_preview.pressed.connect(func(): _preview_map(map_id))
	actions.add_child(btn_preview)

	var btn_edit := Button.new()
	btn_edit.text = "Modifier"
	btn_edit.pressed.connect(func(): _edit_map(map_id))
	actions.add_child(btn_edit)

	var btn_delete := Button.new()
	btn_delete.text = "Supprimer"
	btn_delete.pressed.connect(func(): _ask_delete_map(map_id, map_data.get("title", "Sans titre")))
	actions.add_child(btn_delete)

	vbox.add_child(actions)
	card.add_child(vbox)
	return card

func _preview_map(map_id: String) -> void:
	MapData.preview_map_id = map_id
	MapData.editor_mode = "preview"
	get_tree().change_scene_to_file("res://scenes/map_viewer.tscn")

func _edit_map(map_id: String) -> void:
	MapData.preview_map_id = map_id
	MapData.editor_mode = "edit"
	get_tree().change_scene_to_file("res://scenes/map_viewer.tscn")

func _create_map(roster: String, map_kind: String) -> void:
	var kind_label := "monde" if map_kind == "world" else ("enquête" if roster == "investigation" else "aventure")
	var map := MapData.create_blank_map("Nouvelle carte %s" % kind_label, roster, map_kind)
	MapData.preview_map_id = map.get("id", "")
	MapData.editor_mode = "edit"
	get_tree().change_scene_to_file("res://scenes/map_viewer.tscn")

func _ask_delete_map(map_id: String, title: String) -> void:
	_pending_delete_map_id = map_id
	%ConfirmDeleteMap.dialog_text = "Supprimer la carte « %s » ?" % title
	%ConfirmDeleteMap.popup_centered()

func _on_confirm_delete_map() -> void:
	if _pending_delete_map_id.is_empty():
		return
	MapData.delete_map(_pending_delete_map_id)
	_pending_delete_map_id = ""
	_render_maps_tab()

func _render_saved_games() -> void:
	for child in saved_games_list.get_children():
		child.queue_free()
	
	var games: Array = GameData.get_playing_games()
	if games.is_empty():
		play_status_lbl.text = "Aucune partie en cours."
		return
	
	play_status_lbl.text = "%d partie(s) en cours" % games.size()
	for game in games:
		saved_games_list.add_child(_build_saved_game_row(game))

func _build_saved_game_row(game: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BG_CARD
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	
	var title_lbl := Label.new()
	title_lbl.text = "« %s »" % GameData.get_scenario_display_title(game.get("scenarioId", ""))
	title_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	info.add_child(title_lbl)
	
	var meta_lbl := Label.new()
	meta_lbl.text = GameData.get_game_party_summary(game)
	meta_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	meta_lbl.add_theme_font_size_override("font_size", 12)
	info.add_child(meta_lbl)
	
	row.add_child(info)
	
	var game_id: String = game.get("id", "")
	
	var btn_resume := Button.new()
	btn_resume.text = "▶ Reprendre"
	btn_resume.pressed.connect(func(): _resume_game(game_id))
	row.add_child(btn_resume)
	
	var btn_delete := Button.new()
	btn_delete.text = "🗑 Effacer la partie"
	btn_delete.pressed.connect(func(): _ask_delete_game(game_id, game.get("scenarioTitle", "Aventure")))
	row.add_child(btn_delete)
	
	card.add_child(row)
	return card

func _resume_game(game_id: String) -> void:
	if not GameData.load_game_by_id(game_id):
		_render_saved_games()
		return
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _ask_delete_game(game_id: String, title: String) -> void:
	_pending_delete_id = game_id
	%ConfirmDeleteSession.dialog_text = "Effacer la partie « %s » ? Toute la progression sera perdue." % title
	%ConfirmDeleteSession.popup_centered()

func _on_confirm_delete_session() -> void:
	if _pending_delete_id.is_empty():
		return
	GameData.delete_game(_pending_delete_id)
	_pending_delete_id = ""
	_populate_hub_data()

func _render_bots() -> void:
	for child in bots_sections_root.get_children():
		child.queue_free()

	var mode := _current_bots_filter_mode()
	var total := 0
	if mode == "all":
		var adv_bots := _sorted_bots(_bots_for_mode("adventure"))
		var inv_bots := _sorted_bots(_bots_for_mode("investigation"))
		total = adv_bots.size() + inv_bots.size()
		if total == 0:
			_add_bots_empty_state()
		else:
			if not adv_bots.is_empty():
				_add_bot_section("⚔️ Aventure & one-shots", adv_bots)
			if not inv_bots.is_empty():
				_add_bot_section("🔍 Enquête", inv_bots)
	else:
		var bots := _sorted_bots(_bots_for_mode(mode))
		total = bots.size()
		if bots.is_empty():
			_add_bots_empty_state()
		else:
			var title := "🔍 Enquête" if mode == "investigation" else "⚔️ Aventure & one-shots"
			_add_bot_section(title, bots)

	bots_count_lbl.text = "%d compagnon%s" % [total, "s" if total != 1 else ""]
	_last_bot_grid_cols = _bot_grid_columns()

func _bots_for_mode(mode: String) -> Array:
	match mode:
		"investigation":
			return GameData.get_bots_for_quest_format("investigation")
		"adventure":
			return GameData.get_bots_for_quest_format("oneshot")
		_:
			return GameData.get_bots()

func _sorted_bots(bots: Array) -> Array:
	var copy: Array = bots.duplicate()
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
	)
	return copy

func _bot_grid_columns() -> int:
	var available := int(bots_scroll.size.x)
	if available < 320:
		available = int(get_viewport().get_visible_rect().size.x) - 96
	var cols := clampi(available / 210, 4, 5)
	return cols

func _add_bots_empty_state() -> void:
	var empty_lbl := Label.new()
	empty_lbl.text = "Aucun compagnon bot pour ce mode."
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	bots_sections_root.add_child(empty_lbl)

func _add_bot_section(title: String, bots: Array) -> void:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "%s (%d)" % [title, bots.size()]
	header.add_theme_color_override("font_color", ThemeColors.GOLD)
	header.theme_type_variation = "HeaderMedium"
	section.add_child(header)

	var grid := GridContainer.new()
	grid.columns = _bot_grid_columns()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for b in bots:
		grid.add_child(_build_bot_card(b))
	section.add_child(grid)

	bots_sections_root.add_child(section)

func _build_bot_card(b: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BG_CARD
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_lbl := Label.new()
	name_lbl.text = "🤖 " + b.get("name", "Bot")
	name_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_lbl)

	var mode_lbl := Label.new()
	if GameData.is_investigation_bot(b):
		mode_lbl.text = "🔍 Enquête"
		mode_lbl.add_theme_color_override("font_color", ThemeColors.INVESTIGATION_ACCENT)
	else:
		mode_lbl.text = "⚔️ Aventure"
		mode_lbl.add_theme_color_override("font_color", ThemeColors.ONESHOT_ACCENT)
	vbox.add_child(mode_lbl)

	var meta_lbl := Label.new()
	meta_lbl.text = "%s · %s" % [b.get("race", ""), b.get("class", "")]
	meta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	meta_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(meta_lbl)

	var bot_tag := Label.new()
	bot_tag.text = str(b.get("personality", "")).to_upper()
	bot_tag.add_theme_color_override("font_color", ThemeColors.BOT_ACCENT)
	bot_tag.add_theme_font_size_override("font_size", 11)
	vbox.add_child(bot_tag)

	var traits: Array = b.get("traits", [])
	if not traits.is_empty():
		var traits_lbl := Label.new()
		traits_lbl.text = ", ".join(traits)
		traits_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		traits_lbl.add_theme_font_size_override("font_size", 11)
		traits_lbl.add_theme_color_override("font_color", ThemeColors.TEXT)
		vbox.add_child(traits_lbl)

	var stats: Dictionary = b.get("stats", {})
	var stats_lbl := Label.new()
	stats_lbl.text = "PV %d · CA %d · FOR %d" % [b.get("hp", 10), b.get("ac", 10), stats.get("str", 10)]
	stats_lbl.add_theme_font_size_override("font_size", 11)
	stats_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	vbox.add_child(stats_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(spacer)

	var bot_id: String = b.get("id", "")
	var bot_name: String = b.get("name", "Bot")
	var btn_delete := Button.new()
	btn_delete.text = "Supprimer"
	btn_delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_delete.pressed.connect(func(): _ask_delete_bot(bot_id, bot_name))
	vbox.add_child(btn_delete)

	card.add_child(vbox)
	return card

func _ask_delete_bot(bot_id: String, name: String) -> void:
	_pending_delete_bot_id = bot_id
	%ConfirmDeleteBot.dialog_text = "Supprimer le compagnon bot « %s » ?" % name
	%ConfirmDeleteBot.popup_centered()

func _on_confirm_delete_bot() -> void:
	if _pending_delete_bot_id.is_empty():
		return
	GameData.delete_bot(_pending_delete_bot_id)
	_pending_delete_bot_id = ""
	_render_bots()

func _wrap_tab_scroll(tab_names: Array) -> void:
	for tab_name in tab_names:
		var tab := tab_container.get_node_or_null(tab_name) as MarginContainer
		if tab == null or tab.get_child_count() == 0:
			continue
		var content := tab.get_child(0)
		if content is ScrollContainer:
			continue
		tab.remove_child(content)
		var scroll := ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.add_child(content)
		tab.add_child(scroll)

func _on_home_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_remote_game_started(_game_id: String, state: Dictionary) -> void:
	GameData.apply_server_state(state)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")
