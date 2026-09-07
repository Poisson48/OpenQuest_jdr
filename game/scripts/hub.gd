extends Control

const MapModeScript := preload("res://scripts/maps/map_mode.gd")
const MapCardScene := preload("res://scenes/hub/panels/map_card.tscn")
const BotCardScene := preload("res://scenes/hub/panels/bot_card.tscn")

@onready var tab_container: TabContainer = %TabContainer
@onready var tab_nav: HBoxContainer = %TabNav
@onready var bots_sections_root: VBoxContainer = %BotsSectionsRoot
@onready var bots_scroll: ScrollContainer = %BotsScroll
@onready var bots_filter: OptionButton = %BotsFilter
@onready var bots_count_lbl: Label = %BotsCountLabel
@onready var adv_summary_lbl: Label = %AdvSummaryLabel
@onready var inv_summary_lbl: Label = %InvSummaryLabel
@onready var maps_sections_root: VBoxContainer = %MapsSectionsRoot
@onready var maps_sort: OptionButton = %MapsSort
@onready var btn_home: Button = %BtnHome
@onready var btn_adv_new_char: Button = %BtnAdvNewChar
@onready var btn_adv_scenarios: Button = %BtnAdvScenarios
@onready var btn_adv_play: Button = %BtnAdvPlay
@onready var btn_inv_new_char: Button = %BtnInvNewChar
@onready var btn_inv_scenarios: Button = %BtnInvScenarios
@onready var btn_inv_play: Button = %BtnInvPlay
@onready var btn_new_map_world: Button = %BtnNewMapWorld
@onready var btn_new_map_adv: Button = %BtnNewMapAdv
@onready var btn_new_map_inv: Button = %BtnNewMapInv
@onready var confirm_delete_map: ConfirmationDialog = %ConfirmDeleteMap
@onready var confirm_delete_bot: ConfirmationDialog = %ConfirmDeleteBot

var _pending_delete_map_id: String = ""
var _pending_delete_bot_id: String = ""
var _last_bot_grid_cols: int = -1

func _ready() -> void:
	# @onready résout les % avant ce corps ; ne pas reparente les onglets avant les connexions.
	btn_home.pressed.connect(_on_home_pressed)
	MultiplayerManager.game_started.connect(_on_remote_game_started)

	btn_adv_new_char.pressed.connect(func(): GameData.go_to_character_editor("general"))
	btn_adv_scenarios.pressed.connect(func(): GameData.go_to_scenario_list("adventure"))
	btn_adv_play.pressed.connect(func(): GameData.go_to_game_setup("adventure"))

	btn_inv_new_char.pressed.connect(func(): GameData.go_to_character_editor("investigation"))
	btn_inv_scenarios.pressed.connect(func(): GameData.go_to_scenario_list("investigation"))
	btn_inv_play.pressed.connect(func(): GameData.go_to_game_setup("investigation"))

	btn_new_map_world.pressed.connect(func(): _create_map("general", "world"))
	btn_new_map_adv.pressed.connect(func(): _create_map("general", "local"))
	btn_new_map_inv.pressed.connect(func(): _create_map("investigation", "local"))
	btn_new_map_world.visible = false
	btn_new_map_adv.visible = false
	btn_new_map_inv.visible = false
	confirm_delete_map.confirmed.connect(_on_confirm_delete_map)
	confirm_delete_bot.confirmed.connect(_on_confirm_delete_bot)

	_ensure_tab_scroll(["Aventures", "Enquête", "Cartes", "Bots"])
	_setup_full_width_tabs()
	_apply_pending_hub_tab()
	MapData.maps_updated.connect(_render_maps_tab)
	GameData.bots_updated.connect(_render_bots)
	LocaleSettings.locale_changed.connect(_on_locale_changed)
	_setup_maps_sort()
	_setup_bots_filter()
	
	_populate_hub_data()

func _on_locale_changed(_locale: String) -> void:
	_setup_bots_filter()
	_render_bots()

func _apply_pending_hub_tab() -> void:
	if not get_tree().has_meta("hub_tab"):
		return
	var wanted := str(get_tree().get_meta("hub_tab"))
	get_tree().remove_meta("hub_tab")
	if wanted.is_empty():
		return
	for i in tab_container.get_tab_count():
		if tab_container.is_tab_hidden(i):
			continue
		if tab_container.get_tab_title(i) == wanted:
			tab_container.current_tab = i
			_sync_tab_nav(i)
			return

func _setup_bots_filter() -> void:
	var prev := _current_bots_filter_mode() if bots_filter.item_count > 0 else "all"
	bots_filter.clear()
	bots_filter.add_item(tr("Tous les modes"), 0)
	bots_filter.set_item_metadata(0, "all")
	bots_filter.add_item(tr("⚔️ Aventure & one-shots"), 1)
	bots_filter.set_item_metadata(1, "adventure")
	bots_filter.add_item(tr("🔍 Enquête"), 2)
	bots_filter.set_item_metadata(2, "investigation")
	if not bots_filter.item_selected.is_connected(_on_bots_filter_selected):
		bots_filter.item_selected.connect(_on_bots_filter_selected)
	for i in bots_filter.item_count:
		if str(bots_filter.get_item_metadata(i)) == prev:
			bots_filter.selected = i
			break
	if not bots_scroll.resized.is_connected(_on_bots_scroll_resized):
		bots_scroll.resized.connect(_on_bots_scroll_resized)

func _on_bots_filter_selected(_idx: int) -> void:
	_render_bots()

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
	var adventure := MapData.sort_maps(MapData.get_maps_by_category("adventure"), sort_mode)
	var simple_maps: Array = []
	var valbois_maps: Array = []
	for m in adventure:
		if str(m.get("renderMode", "simple")) == MapModeScript.COMPLEX:
			valbois_maps.append(m)
		else:
			simple_maps.append(m)
	_add_maps_section(
		"▦ Quête simple",
		"La Crypte Oubliée — carte tuilée classique.",
		simple_maps,
		"adventure"
	)
	_add_maps_section(
		"⚙️ Valbois",
		"Village illustré, Place du Marché et token Kael. Cliquez le lieu ⭐ pour zoomer.",
		valbois_maps,
		"adventure"
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
	desc.add_theme_font_size_override("font_size", 14)
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
			flow.add_child(_make_map_card(map_data, category))
		section.add_child(flow)

	maps_sections_root.add_child(section)

func _make_map_card(map_data: Dictionary, category: String) -> PanelContainer:
	var card := MapCardScene.instantiate()
	card.setup(map_data, category)
	card.preview_pressed.connect(_preview_map)
	card.edit_pressed.connect(_edit_map)
	card.delete_pressed.connect(_ask_delete_map)
	card.demo_pressed.connect(_play_valbois_demo)
	return card

func _play_valbois_demo() -> void:
	if not GameData.start_valbois_demo_session():
		return
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

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

func _add_vtt_map_button() -> void:
	var row: Node = get_node_or_null("%MapsCreateRow")
	if row == null:
		if btn_new_map_adv == null or btn_new_map_adv.get_parent() == null:
			return
		row = btn_new_map_adv.get_parent()
	var btn_vtt := Button.new()
	btn_vtt.text = "+ Battlemap 3D"
	btn_vtt.tooltip_text = "Crée une carte VTT complexe (tokens, brouillard, effets 3D)"
	btn_vtt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_vtt.custom_minimum_size = Vector2(0, 40)
	btn_vtt.pressed.connect(func(): _create_complex_map("general"))
	row.add_child(btn_vtt)
	var btn_vtt_inv := Button.new()
	btn_vtt_inv.text = "+ Battlemap enquête 3D"
	btn_vtt_inv.tooltip_text = "Battlemap VTT pour scénarios d'enquête"
	btn_vtt_inv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_vtt_inv.custom_minimum_size = Vector2(0, 40)
	btn_vtt_inv.pressed.connect(func(): _create_complex_map("investigation"))
	row.add_child(btn_vtt_inv)

func _create_complex_map(roster: String) -> void:
	var label := "Battlemap enquête" if roster == "investigation" else "Battlemap VTT"
	var map := MapData.create_complex_map(label, roster, "local", 24, 16)
	MapData.preview_map_id = map.get("id", "")
	MapData.editor_mode = "edit"
	get_tree().change_scene_to_file("res://scenes/map_viewer.tscn")

func _ask_delete_map(map_id: String, title: String) -> void:
	_pending_delete_map_id = map_id
	confirm_delete_map.dialog_text = "Supprimer la carte « %s » ?" % title
	confirm_delete_map.popup_centered()

func _on_confirm_delete_map() -> void:
	if _pending_delete_map_id.is_empty():
		return
	MapData.delete_map(_pending_delete_map_id)
	_pending_delete_map_id = ""
	_render_maps_tab()

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
				_add_bot_section(tr("⚔️ Aventure & one-shots"), adv_bots)
			if not inv_bots.is_empty():
				_add_bot_section(tr("🔍 Enquête"), inv_bots)
	else:
		var bots := _sorted_bots(_bots_for_mode(mode))
		total = bots.size()
		if bots.is_empty():
			_add_bots_empty_state()
		else:
			var title := tr("🔍 Enquête") if mode == "investigation" else tr("⚔️ Aventure & one-shots")
			_add_bot_section(title, bots)

	if total == 1:
		bots_count_lbl.text = tr("%d compagnon") % total
	else:
		bots_count_lbl.text = tr("%d compagnons") % total
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
	empty_lbl.text = tr("Aucun compagnon pour ce filtre.")
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	empty_lbl.add_theme_font_size_override("font_size", 14)
	bots_sections_root.add_child(empty_lbl)

func _add_bot_section(title: String, bots: Array) -> void:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "%s (%d)" % [title, bots.size()]
	header.add_theme_color_override("font_color", ThemeColors.GOLD)
	header.theme_type_variation = "HeaderMedium"
	header.add_theme_font_size_override("font_size", 16)
	section.add_child(header)

	var grid := GridContainer.new()
	grid.columns = _bot_grid_columns()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for b in bots:
		grid.add_child(_make_bot_card(b))
	section.add_child(grid)

	bots_sections_root.add_child(section)

func _make_bot_card(b: Dictionary) -> PanelContainer:
	var card := BotCardScene.instantiate()
	card.setup(b)
	card.delete_pressed.connect(_ask_delete_bot)
	return card

func _ask_delete_bot(bot_id: String, name: String) -> void:
	_pending_delete_bot_id = bot_id
	confirm_delete_bot.dialog_text = "Supprimer le compagnon bot « %s » ?" % name
	confirm_delete_bot.popup_centered()

func _on_confirm_delete_bot() -> void:
	if _pending_delete_bot_id.is_empty():
		return
	GameData.delete_bot(_pending_delete_bot_id)
	_pending_delete_bot_id = ""
	_render_bots()

func _setup_full_width_tabs() -> void:
	tab_container.tabs_visible = false
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var native_bar := tab_container.get_tab_bar()
	if native_bar:
		native_bar.visible = false
	tab_nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for child in tab_nav.get_children():
		child.queue_free()
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for i in tab_container.get_tab_count():
		if tab_container.is_tab_hidden(i):
			continue
		var btn := Button.new()
		btn.text = tab_container.get_tab_title(i)
		btn.toggle_mode = true
		btn.button_group = group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 44)
		btn.button_pressed = i == tab_container.current_tab
		btn.set_meta("tab_index", i)
		var idx := i
		btn.pressed.connect(func(): tab_container.current_tab = idx)
		tab_nav.add_child(btn)
	if not tab_container.tab_changed.is_connected(_sync_tab_nav):
		tab_container.tab_changed.connect(_sync_tab_nav)
	_sync_tab_nav(tab_container.current_tab)

func _sync_tab_nav(idx: int) -> void:
	for i in tab_nav.get_child_count():
		var btn := tab_nav.get_child(i) as Button
		if btn == null:
			continue
		var tab_idx: int = int(btn.get_meta("tab_index", i))
		btn.set_pressed_no_signal(tab_idx == idx)
		if tab_idx == idx:
			btn.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		else:
			btn.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)

func _ensure_tab_scroll(tab_names: Array) -> void:
	for tab_name in tab_names:
		var tab := tab_container.get_node_or_null(tab_name) as MarginContainer
		if tab == null or tab.get_child_count() == 0:
			continue
		var content := tab.get_child(0)
		if content is ScrollContainer:
			var existing := content as ScrollContainer
			existing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			existing.size_flags_vertical = Control.SIZE_EXPAND_FILL
			continue
		tab.remove_child(content)
		var scroll := ScrollContainer.new()
		scroll.name = "TabScroll"
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
