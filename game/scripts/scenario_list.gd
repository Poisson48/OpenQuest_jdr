extends Control

const ScenarioCardScene := preload("res://scenes/hub/panels/scenario_card.tscn")

@onready var scenario_sections_root: VBoxContainer = %ScenarioSectionsRoot
@onready var list_scroll: ScrollContainer = %ListScroll
@onready var mode_filter: OptionButton = %ModeFilter
@onready var scenarios_count_lbl: Label = %ScenariosCountLabel
@onready var library_tabs: HBoxContainer = %LibraryTabs
@onready var page_title: Label = $MainLayout/TopBar/Title
@onready var detail_panel: PanelContainer = %DetailPanel
@onready var detail_scroll: ScrollContainer = $MainLayout/ContentArea/DetailPanel/DetailScroll
@onready var detail_title: Label = %DetailTitle
@onready var detail_synopsis: RichTextLabel = %DetailSynopsis
@onready var detail_scenes: RichTextLabel = %DetailScenes
@onready var detail_npcs: RichTextLabel = %DetailNpcs

var selected_scenario_id: String = ""
var _pending_delete_scenario_id: String = ""
var _pending_publish_scenario_id: String = ""
var _last_scenario_grid_cols: int = -1
var _locked_mode: String = ""
var _library_tab: String = "catalog" # catalog | draft
var _library_tab_group: ButtonGroup

func _ready() -> void:
	%BtnBack.pressed.connect(_on_back_pressed)
	%BtnNewScenario.pressed.connect(_on_new_scenario_pressed)
	%BtnCloseDetail.pressed.connect(func(): detail_panel.visible = false)
	%BtnPlayDetail.pressed.connect(_on_play_selected_scenario)
	%BtnEditDetail.pressed.connect(_on_edit_selected_scenario)
	%BtnDeleteDetail.pressed.connect(_on_delete_selected_scenario)
	%BtnPublishDetail.pressed.connect(_on_publish_selected_scenario)
	%BtnUnpublishDetail.pressed.connect(_on_unpublish_selected_scenario)
	%ConfirmDeleteScenario.confirmed.connect(_on_confirm_delete_scenario)
	%ConfirmPublishScenario.confirmed.connect(_on_confirm_publish_scenario)

	_setup_mode_filter()
	_setup_library_tabs()
	_apply_entry_context()
	mode_filter.item_selected.connect(func(_idx): refresh_list())
	if not list_scroll.resized.is_connected(_on_list_scroll_resized):
		list_scroll.resized.connect(_on_list_scroll_resized)

	GameData.scenarios_updated.connect(refresh_list)
	_configure_detail_panel()
	refresh_list()
	detail_panel.visible = false

func _setup_mode_filter() -> void:
	mode_filter.clear()
	mode_filter.add_item("Tous les modes", 0)
	mode_filter.set_item_metadata(0, "all")
	mode_filter.add_item("⚔️ Aventure", 1)
	mode_filter.set_item_metadata(1, "adventure")
	mode_filter.add_item("🔍 Enquête", 2)
	mode_filter.set_item_metadata(2, "investigation")

func _setup_library_tabs() -> void:
	for child in library_tabs.get_children():
		child.queue_free()
	_library_tab_group = ButtonGroup.new()
	_library_tab_group.allow_unpress = false
	_add_library_tab_button("Catalogue", "catalog")
	_add_library_tab_button("Brouillons", "draft")
	_sync_library_tab_buttons()

func _add_library_tab_button(label: String, tab_id: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.button_group = _library_tab_group
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 40)
	btn.set_meta("tab_id", tab_id)
	btn.pressed.connect(func(): _set_library_tab(tab_id))
	library_tabs.add_child(btn)

func _set_library_tab(tab_id: String) -> void:
	if _library_tab == tab_id:
		_sync_library_tab_buttons()
		return
	_library_tab = tab_id
	detail_panel.visible = false
	_sync_library_tab_buttons()
	refresh_list()

func _sync_library_tab_buttons() -> void:
	for child in library_tabs.get_children():
		var btn := child as Button
		if btn == null:
			continue
		var tab_id := str(btn.get_meta("tab_id", ""))
		btn.set_pressed_no_signal(tab_id == _library_tab)
		if tab_id == _library_tab:
			btn.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		else:
			btn.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)

func _apply_entry_context() -> void:
	if get_tree().has_meta("preselected_scenario_mode"):
		_locked_mode = str(get_tree().get_meta("preselected_scenario_mode"))
		get_tree().remove_meta("preselected_scenario_mode")
	match _locked_mode:
		"investigation":
			page_title.text = "📜 Affaires d'Enquête"
			mode_filter.selected = 2
			mode_filter.disabled = true
		"long", "oneshot", "adventure":
			page_title.text = "📜 Scénarios d'Aventure"
			mode_filter.selected = 1
			mode_filter.disabled = true
			_locked_mode = "adventure"

func _current_mode_filter() -> String:
	if not _locked_mode.is_empty():
		return _locked_mode
	var idx := mode_filter.selected
	if idx >= 0 and idx < mode_filter.item_count:
		return str(mode_filter.get_item_metadata(idx))
	return "all"

func _configure_detail_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.121569, 0.0980392, 0.0784314, 0.98)
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	detail_panel.add_theme_stylebox_override("panel", style)

	for rtl in [detail_synopsis, detail_scenes, detail_npcs]:
		rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rtl.scroll_active = false
		rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rtl.fit_content = true

	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

func refresh_list() -> void:
	for child in scenario_sections_root.get_children():
		child.queue_free()

	var mode := _current_mode_filter()
	var total := 0
	if _library_tab == "draft":
		total = _add_draft_sections(mode)
		if total == 0:
			_add_empty_state()
	elif mode == "all":
		total += _add_roster_duration_sections("adventure")
		total += _add_roster_duration_sections("investigation")
		if total == 0:
			_add_empty_state()
	elif mode == "adventure" or mode == "investigation":
		total = _add_roster_duration_sections(mode)
		if total == 0:
			_add_empty_state()
	else:
		var list := _sorted_scenarios(_scenarios_for_mode(mode))
		total = list.size()
		if list.is_empty():
			_add_empty_state()
		else:
			var title := _mode_section_title(mode)
			_add_scenario_section(title, list)

	var noun := "brouillon" if _library_tab == "draft" else "scénario"
	scenarios_count_lbl.text = "%d %s%s" % [total, noun, "s" if total != 1 else ""]
	_last_scenario_grid_cols = _scenario_grid_columns()

func _add_roster_duration_sections(roster_mode: String) -> int:
	var scenarios := _scenarios_for_mode(roster_mode)
	var split := _split_by_duration(scenarios)
	var short_list := _sorted_scenarios(split["short"])
	var long_list := _sorted_scenarios(split["long"])
	var count := short_list.size() + long_list.size()
	if count == 0:
		return 0

	var short_title := "⚔️ Aventures courtes" if roster_mode == "adventure" else "🔍 Enquêtes courtes"
	var long_title := "🏰 Aventures longues" if roster_mode == "adventure" else "🔍 Enquêtes longues"
	if not short_list.is_empty():
		_add_scenario_section(short_title, short_list)
	if not long_list.is_empty():
		_add_scenario_section(long_title, long_list)
	return count

func _add_draft_sections(mode: String) -> int:
	if mode == "all":
		var total := 0
		total += _add_draft_roster_section("adventure")
		total += _add_draft_roster_section("investigation")
		return total
	if mode == "adventure" or mode == "investigation":
		return _add_draft_roster_section(mode)
	var list := _sorted_scenarios(_drafts_for_mode(mode))
	if list.is_empty():
		return 0
	_add_scenario_section("📝 Brouillons", list)
	return list.size()

func _add_draft_roster_section(roster_mode: String) -> int:
	var drafts := _sorted_scenarios(_drafts_for_mode(roster_mode))
	if drafts.is_empty():
		return 0
	var split := _split_by_duration(drafts)
	var short_list: Array = split["short"]
	var long_list: Array = split["long"]
	var short_title := "📝 Brouillons — aventures courtes" if roster_mode == "adventure" else "📝 Brouillons — enquêtes courtes"
	var long_title := "📝 Brouillons — aventures longues" if roster_mode == "adventure" else "📝 Brouillons — enquêtes longues"
	var title := "📝 Brouillons — aventures" if roster_mode == "adventure" else "📝 Brouillons — enquêtes"
	if not short_list.is_empty() and not long_list.is_empty():
		_add_scenario_section(short_title, short_list)
		_add_scenario_section(long_title, long_list)
	elif not short_list.is_empty():
		_add_scenario_section(title if long_list.is_empty() else short_title, short_list)
	elif not long_list.is_empty():
		_add_scenario_section(long_title, long_list)
	return drafts.size()

func _split_by_duration(scenarios: Array) -> Dictionary:
	var short: Array = []
	var long: Array = []
	for scn in scenarios:
		if scn.get("questFormat", "oneshot") == "long":
			long.append(scn)
		else:
			short.append(scn)
	return {"short": short, "long": long}

func _on_list_scroll_resized() -> void:
	if scenario_sections_root.get_child_count() == 0:
		return
	var cols := _scenario_grid_columns()
	if cols != _last_scenario_grid_cols:
		refresh_list()

func _scenarios_for_mode(mode: String) -> Array:
	match mode:
		"investigation", "long", "oneshot":
			return GameData.get_scenarios_for_quest_format(mode)
		"adventure":
			var result: Array = []
			result.append_array(GameData.get_scenarios_for_quest_format("long"))
			result.append_array(GameData.get_scenarios_for_quest_format("oneshot"))
			return result
		_:
			return GameData.get_scenarios()

func _drafts_for_mode(mode: String) -> Array:
	match mode:
		"investigation", "long", "oneshot", "adventure":
			return GameData.get_draft_scenarios(mode)
		_:
			return GameData.get_draft_scenarios()

func _sorted_scenarios(list: Array) -> Array:
	var copy: Array = list.duplicate()
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")).to_lower() < str(b.get("title", "")).to_lower()
	)
	return copy

func _mode_section_title(mode: String) -> String:
	match mode:
		"investigation":
			return "🔍 Enquête"
		"long":
			return "🏰 Campagnes longues"
		"oneshot":
			return "⚔️ One-shots"
		_:
			return "Scénarios"

func _scenario_grid_columns() -> int:
	var available := int(list_scroll.size.x)
	if available < 320:
		available = int(get_viewport().get_visible_rect().size.x) - 96
	return clampi(available / 240, 4, 5)

func _add_empty_state() -> void:
	var lbl := Label.new()
	if _library_tab == "draft":
		match _locked_mode:
			"investigation":
				lbl.text = "Aucun brouillon d'enquête — crée-en un avec « + Nouveau scénario »."
			"adventure":
				lbl.text = "Aucun brouillon d'aventure — crée-en un avec « + Nouveau scénario »."
			_:
				lbl.text = "Aucun brouillon — crée-en un avec « + Nouveau scénario »."
	else:
		match _locked_mode:
			"investigation":
				lbl.text = "Aucune affaire d'enquête pour le moment."
			"adventure":
				lbl.text = "Aucun scénario d'aventure (one-shot ou campagne) pour le moment."
			_:
				lbl.text = "Aucun scénario ne correspond à ce mode."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scenario_sections_root.add_child(lbl)

func _add_scenario_section(title: String, scenarios: Array) -> void:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "%s (%d)" % [title, scenarios.size()]
	header.add_theme_color_override("font_color", ThemeColors.GOLD)
	header.theme_type_variation = "HeaderMedium"
	header.add_theme_font_size_override("font_size", 18)
	section.add_child(header)

	var grid := GridContainer.new()
	grid.columns = _scenario_grid_columns()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for scn in scenarios:
		grid.add_child(_create_scenario_card(scn))
	section.add_child(grid)

	scenario_sections_root.add_child(section)

func _create_scenario_card(scn: Dictionary) -> PanelContainer:
	var card := ScenarioCardScene.instantiate()
	card.setup(scn)
	card.edit_pressed.connect(func(id: String): GameData.go_to_scenario_editor(id))
	card.view_pressed.connect(_show_scenario_details)
	card.play_pressed.connect(_launch_game_with_scenario)
	card.delete_pressed.connect(_ask_delete_scenario)
	card.publish_pressed.connect(_ask_publish_scenario)
	card.unpublish_pressed.connect(_on_unpublish_scenario)
	return card

func _show_scenario_details(scn: Dictionary) -> void:
	selected_scenario_id = scn.get("id", "")
	detail_title.text = "📖 " + scn.get("title", "")

	var syn_text := "[b]Synopsis :[/b]\n%s\n\n[b]Cadre :[/b]\n%s" % [
		scn.get("synopsis", "Non spécifié"),
		scn.get("setting", "Non spécifié")
	]
	detail_synopsis.text = syn_text

	var scenes: Array = scn.get("scenes", [])
	var scene_text := "[b]Scènes (%d) :[/b]\n" % scenes.size()
	for i in range(scenes.size()):
		var s: Dictionary = scenes[i]
		scene_text += "[color=#e8c547]%d. %s[/color]\n%s\n\n" % [i + 1, s.get("title", "Scène"), s.get("content", "")]
	detail_scenes.text = scene_text

	var npcs: Array = scn.get("npcs", [])
	var npcs_text := "[b]Personnages Non-Joueurs (%d) :[/b]\n" % npcs.size()
	if npcs.is_empty():
		npcs_text += "Aucun PNJ défini."
	else:
		for n in npcs:
			npcs_text += "• [color=#c9a227]%s[/color] (%s) : %s\n" % [
				n.get("name", "PNJ"),
				n.get("role", "Rôle"),
				n.get("description", "")
			]
	detail_npcs.text = npcs_text
	_update_detail_publish_buttons(scn)
	detail_panel.visible = true
	await get_tree().process_frame
	detail_scroll.scroll_vertical = 0
	_update_detail_text_widths()

func _update_detail_publish_buttons(scn: Dictionary) -> void:
	var is_draft := GameData.is_draft_scenario(scn)
	var can_unpublish := GameData.is_catalog_scenario(scn) and not GameData.DEMO_SCENARIO_IDS.has(str(scn.get("id", "")))
	%BtnPlayDetail.visible = not is_draft
	%BtnPublishDetail.visible = is_draft
	%BtnUnpublishDetail.visible = can_unpublish

func _on_edit_selected_scenario() -> void:
	if not selected_scenario_id.is_empty():
		GameData.go_to_scenario_editor(selected_scenario_id)

func _on_play_selected_scenario() -> void:
	if not selected_scenario_id.is_empty():
		_launch_game_with_scenario(selected_scenario_id)

func _on_delete_selected_scenario() -> void:
	if selected_scenario_id.is_empty():
		return
	var scn := GameData.get_scenario_by_id(selected_scenario_id)
	_ask_delete_scenario(selected_scenario_id, scn.get("title", "Scénario"))

func _on_publish_selected_scenario() -> void:
	if selected_scenario_id.is_empty():
		return
	var scn := GameData.get_scenario_by_id(selected_scenario_id)
	_ask_publish_scenario(selected_scenario_id, scn.get("title", "Scénario"))

func _on_unpublish_selected_scenario() -> void:
	if selected_scenario_id.is_empty():
		return
	var scn := GameData.get_scenario_by_id(selected_scenario_id)
	_on_unpublish_scenario(selected_scenario_id, scn.get("title", "Scénario"))

func _ask_delete_scenario(scenario_id: String, title: String) -> void:
	_pending_delete_scenario_id = scenario_id
	%ConfirmDeleteScenario.dialog_text = "Supprimer le scénario « %s » ?" % title
	%ConfirmDeleteScenario.popup_centered()

func _ask_publish_scenario(scenario_id: String, title: String) -> void:
	_pending_publish_scenario_id = scenario_id
	%ConfirmPublishScenario.dialog_text = "Publier « %s » dans le catalogue ?\nIl quittera les brouillons." % title
	%ConfirmPublishScenario.popup_centered()

func _on_confirm_delete_scenario() -> void:
	if _pending_delete_scenario_id.is_empty():
		return
	if selected_scenario_id == _pending_delete_scenario_id:
		selected_scenario_id = ""
		detail_panel.visible = false
	GameData.delete_scenario(_pending_delete_scenario_id)
	_pending_delete_scenario_id = ""
	refresh_list()

func _on_confirm_publish_scenario() -> void:
	if _pending_publish_scenario_id.is_empty():
		return
	var sid := _pending_publish_scenario_id
	_pending_publish_scenario_id = ""
	if not GameData.publish_scenario(sid):
		return
	detail_panel.visible = false
	_set_library_tab("catalog")

func _on_unpublish_scenario(scenario_id: String, _title: String) -> void:
	if not GameData.unpublish_scenario(scenario_id):
		return
	if selected_scenario_id == scenario_id:
		detail_panel.visible = false
	_set_library_tab("draft")

func _launch_game_with_scenario(scenario_id: String) -> void:
	GameData.go_to_game_setup("", scenario_id)

func _update_detail_text_widths() -> void:
	var wrap_width := maxi(320, int(detail_scroll.size.x) - 24)
	for rtl in [detail_synopsis, detail_scenes, detail_npcs]:
		rtl.custom_minimum_size = Vector2(wrap_width, 0)
		rtl.reset_size()

func _on_new_scenario_pressed() -> void:
	var mode := _current_mode_filter()
	var roster := "general"
	var fmt := "oneshot"
	match mode:
		"investigation":
			roster = "investigation"
			fmt = "investigation"
		"adventure", "long", "oneshot":
			fmt = "oneshot"
	# Les nouveaux scénarios apparaissent dans l'onglet Brouillons.
	_library_tab = "draft"
	_sync_library_tab_buttons()
	GameData.go_to_scenario_editor("", roster, fmt)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")
