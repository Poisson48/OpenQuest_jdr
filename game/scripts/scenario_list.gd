extends Control

@onready var scenario_sections_root: VBoxContainer = %ScenarioSectionsRoot
@onready var list_scroll: ScrollContainer = %ListScroll
@onready var mode_filter: OptionButton = %ModeFilter
@onready var scenarios_count_lbl: Label = %ScenariosCountLabel
@onready var page_title: Label = $MainLayout/TopBar/Title
@onready var detail_panel: PanelContainer = %DetailPanel
@onready var detail_scroll: ScrollContainer = $MainLayout/ContentArea/DetailPanel/DetailScroll
@onready var detail_title: Label = %DetailTitle
@onready var detail_synopsis: RichTextLabel = %DetailSynopsis
@onready var detail_scenes: RichTextLabel = %DetailScenes
@onready var detail_npcs: RichTextLabel = %DetailNpcs

var selected_scenario_id: String = ""
var _pending_delete_scenario_id: String = ""
var _last_scenario_grid_cols: int = -1
var _locked_mode: String = ""

func _ready() -> void:
	%BtnBack.pressed.connect(_on_back_pressed)
	%BtnCloseDetail.pressed.connect(func(): detail_panel.visible = false)
	%BtnPlayDetail.pressed.connect(_on_play_selected_scenario)
	%BtnDeleteDetail.pressed.connect(_on_delete_selected_scenario)
	%ConfirmDeleteScenario.confirmed.connect(_on_confirm_delete_scenario)

	_setup_mode_filter()
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
	mode_filter.add_item("🔍 Enquête", 1)
	mode_filter.set_item_metadata(1, "investigation")
	mode_filter.add_item("🏰 Campagne longue", 2)
	mode_filter.set_item_metadata(2, "long")
	mode_filter.add_item("⚔️ One-shot", 3)
	mode_filter.set_item_metadata(3, "oneshot")

func _apply_entry_context() -> void:
	if get_tree().has_meta("preselected_scenario_mode"):
		_locked_mode = str(get_tree().get_meta("preselected_scenario_mode"))
		get_tree().remove_meta("preselected_scenario_mode")
	match _locked_mode:
		"investigation":
			page_title.text = "📜 Affaires d'Enquête"
			mode_filter.selected = 1
			mode_filter.disabled = true
		"long":
			page_title.text = "🏰 Campagnes Longues"
			mode_filter.selected = 2
			mode_filter.disabled = true
		"oneshot":
			page_title.text = "⚔️ One-shots"
			mode_filter.selected = 3
			mode_filter.disabled = true
		"adventure":
			page_title.text = "📜 Scénarios d'Aventure"
			mode_filter.selected = 0
			mode_filter.disabled = true

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
	if mode == "all" or mode == "adventure":
		var inv: Array = []
		if mode == "all":
			inv = _sorted_scenarios(_scenarios_for_mode("investigation"))
		var long := _sorted_scenarios(_scenarios_for_mode("long"))
		var one := _sorted_scenarios(_scenarios_for_mode("oneshot"))
		total = inv.size() + long.size() + one.size()
		if total == 0:
			_add_empty_state()
		else:
			if not inv.is_empty():
				_add_scenario_section("🔍 Enquête", inv)
			if not long.is_empty():
				_add_scenario_section("🏰 Campagnes longues", long)
			if not one.is_empty():
				_add_scenario_section("⚔️ One-shots", one)
	else:
		var list := _sorted_scenarios(_scenarios_for_mode(mode))
		total = list.size()
		if list.is_empty():
			_add_empty_state()
		else:
			var title := _mode_section_title(mode)
			_add_scenario_section(title, list)

	scenarios_count_lbl.text = "%d scénario%s" % [total, "s" if total != 1 else ""]
	_last_scenario_grid_cols = _scenario_grid_columns()

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
	match _locked_mode:
		"investigation":
			lbl.text = "Aucune affaire d'enquête pour le moment."
		"adventure":
			lbl.text = "Aucun scénario d'aventure (one-shot ou campagne) pour le moment."
		"long":
			lbl.text = "Aucune campagne longue pour le moment."
		"oneshot":
			lbl.text = "Aucun one-shot pour le moment."
		_:
			lbl.text = "Aucun scénario ne correspond à ce mode."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	scenario_sections_root.add_child(lbl)

func _add_scenario_section(title: String, scenarios: Array) -> void:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "%s (%d)" % [title, scenarios.size()]
	header.add_theme_color_override("font_color", ThemeColors.GOLD)
	header.theme_type_variation = "HeaderMedium"
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
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BG_CARD
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var title_lbl := Label.new()
	title_lbl.text = str(scn.get("title", "Sans titre"))
	title_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title_lbl)

	var badge := Label.new()
	var mode := GameData.get_scenario_mode_label(scn)
	match mode:
		"investigation":
			badge.text = "🔍 Enquête"
			badge.add_theme_color_override("font_color", ThemeColors.INVESTIGATION_ACCENT)
		"long":
			badge.text = "🏰 Campagne"
			badge.add_theme_color_override("font_color", ThemeColors.GOLD)
		_:
			badge.text = "⚔️ One-shot"
			badge.add_theme_color_override("font_color", ThemeColors.ONESHOT_ACCENT)
	vbox.add_child(badge)

	var syn_lbl := Label.new()
	var synopsis := str(scn.get("synopsis", "Pas de synopsis."))
	if synopsis.length() > 120:
		synopsis = synopsis.substr(0, 117) + "..."
	syn_lbl.text = synopsis
	syn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	syn_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	syn_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(syn_lbl)

	var scenes: Array = scn.get("scenes", [])
	var npcs: Array = scn.get("npcs", [])
	var meta_lbl := Label.new()
	meta_lbl.text = "📜 %d scènes · 👤 %d PNJ" % [scenes.size(), npcs.size()]
	meta_lbl.add_theme_font_size_override("font_size", 11)
	meta_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	vbox.add_child(meta_lbl)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)

	var btn_view := Button.new()
	btn_view.text = "Voir détails"
	btn_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_view.pressed.connect(func(): _show_scenario_details(scn))
	actions.add_child(btn_view)

	var btn_play := Button.new()
	btn_play.text = "🎮 Lancer"
	btn_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_play.pressed.connect(func(): _launch_game_with_scenario(scn.get("id", "")))
	actions.add_child(btn_play)

	var scn_id: String = scn.get("id", "")
	var scn_title: String = scn.get("title", "Scénario")
	var btn_delete := Button.new()
	btn_delete.text = "Supprimer"
	btn_delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_delete.pressed.connect(func(): _ask_delete_scenario(scn_id, scn_title))
	actions.add_child(btn_delete)

	vbox.add_child(actions)
	panel.add_child(vbox)
	return panel

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
	detail_panel.visible = true
	await get_tree().process_frame
	detail_scroll.scroll_vertical = 0
	_update_detail_text_widths()

func _on_play_selected_scenario() -> void:
	if not selected_scenario_id.is_empty():
		_launch_game_with_scenario(selected_scenario_id)

func _on_delete_selected_scenario() -> void:
	if selected_scenario_id.is_empty():
		return
	var scn := GameData.get_scenario_by_id(selected_scenario_id)
	_ask_delete_scenario(selected_scenario_id, scn.get("title", "Scénario"))

func _ask_delete_scenario(scenario_id: String, title: String) -> void:
	_pending_delete_scenario_id = scenario_id
	%ConfirmDeleteScenario.dialog_text = "Supprimer le scénario « %s » ?" % title
	%ConfirmDeleteScenario.popup_centered()

func _on_confirm_delete_scenario() -> void:
	if _pending_delete_scenario_id.is_empty():
		return
	if selected_scenario_id == _pending_delete_scenario_id:
		selected_scenario_id = ""
		detail_panel.visible = false
	GameData.delete_scenario(_pending_delete_scenario_id)
	_pending_delete_scenario_id = ""
	refresh_list()

func _launch_game_with_scenario(scenario_id: String) -> void:
	GameData.go_to_game_setup("", scenario_id)

func _update_detail_text_widths() -> void:
	var wrap_width := maxi(320, int(detail_scroll.size.x) - 24)
	for rtl in [detail_synopsis, detail_scenes, detail_npcs]:
		rtl.custom_minimum_size = Vector2(wrap_width, 0)
		rtl.reset_size()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")
