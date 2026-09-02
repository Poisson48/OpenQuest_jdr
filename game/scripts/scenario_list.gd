extends Control

@onready var scenario_container: VBoxContainer = %ScenarioList
@onready var format_filter: OptionButton = %FormatFilter
@onready var roster_filter: OptionButton = %RosterFilter
@onready var detail_panel: PanelContainer = %DetailPanel
@onready var detail_title: Label = %DetailTitle
@onready var detail_synopsis: RichTextLabel = %DetailSynopsis
@onready var detail_scenes: RichTextLabel = %DetailScenes
@onready var detail_npcs: RichTextLabel = %DetailNpcs

var selected_scenario_id: String = ""

func _ready() -> void:
	%BtnBack.pressed.connect(_on_back_pressed)
	%BtnCloseDetail.pressed.connect(func(): detail_panel.visible = false)
	%BtnPlayDetail.pressed.connect(_on_play_selected_scenario)
	
	_setup_filters()
	format_filter.item_selected.connect(func(_idx): refresh_list())
	roster_filter.item_selected.connect(func(_idx): refresh_list())
	
	GameData.scenarios_updated.connect(refresh_list)
	refresh_list()
	detail_panel.visible = false

func _setup_filters() -> void:
	format_filter.clear()
	format_filter.add_item("Tous les formats", 0)
	format_filter.add_item("Campagne longue", 1)
	format_filter.add_item("One-shot", 2)
	
	roster_filter.clear()
	roster_filter.add_item("Tous les univers", 0)
	roster_filter.add_item("Aventure", 1)
	roster_filter.add_item("Enquête", 2)

func refresh_list() -> void:
	for child in scenario_container.get_children():
		child.queue_free()
		
	var fmt_idx := format_filter.selected
	var fmt_val := ""
	if fmt_idx == 1:
		fmt_val = "long"
	elif fmt_idx == 2:
		fmt_val = "oneshot"
		
	var rst_idx := roster_filter.selected
	var rst_val := ""
	if rst_idx == 1:
		rst_val = "general"
	elif rst_idx == 2:
		rst_val = "investigation"
		
	var list := GameData.get_scenarios(fmt_val, rst_val)
	if list.is_empty():
		var lbl := Label.new()
		lbl.text = "Aucun scénario ne correspond aux critères sélectionnés."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		scenario_container.add_child(lbl)
		return
		
	for scn in list:
		var card := _create_scenario_card(scn)
		scenario_container.add_child(card)

func _create_scenario_card(scn: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BG_CARD
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	
	var header := HBoxContainer.new()
	var title_lbl := Label.new()
	title_lbl.text = str(scn.get("title", "Sans titre"))
	title_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	title_lbl.theme_type_variation = "HeaderMedium"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)
	
	var badge := Label.new()
	var qf: String = scn.get("questFormat", "oneshot")
	var is_inv: bool = scn.get("roster", "general") == "investigation"
	if is_inv:
		badge.text = "🔍 Enquête"
		badge.add_theme_color_override("font_color", ThemeColors.INVESTIGATION_ACCENT)
	elif qf == "long":
		badge.text = "🏰 Campagne"
		badge.add_theme_color_override("font_color", ThemeColors.GOLD)
	else:
		badge.text = "⚔️ One-shot"
		badge.add_theme_color_override("font_color", ThemeColors.ONESHOT_ACCENT)
	header.add_child(badge)
	vbox.add_child(header)
	
	var syn_lbl := Label.new()
	syn_lbl.text = str(scn.get("synopsis", "Pas de synopsis."))
	syn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	syn_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	vbox.add_child(syn_lbl)
	
	var scenes: Array = scn.get("scenes", [])
	var npcs: Array = scn.get("npcs", [])
	var meta_lbl := Label.new()
	meta_lbl.text = "📜 %d scènes | 👤 %d PNJ(s)" % [scenes.size(), npcs.size()]
	meta_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	vbox.add_child(meta_lbl)
	
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	
	var btn_view := Button.new()
	btn_view.text = "Voir détails"
	btn_view.pressed.connect(func(): _show_scenario_details(scn))
	actions.add_child(btn_view)
	
	var btn_play := Button.new()
	btn_play.text = "🎮 Lancer cette quête"
	btn_play.pressed.connect(func(): _launch_game_with_scenario(scn.get("id", "")))
	actions.add_child(btn_play)
	
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

func _on_play_selected_scenario() -> void:
	if not selected_scenario_id.is_empty():
		_launch_game_with_scenario(selected_scenario_id)

func _launch_game_with_scenario(scenario_id: String) -> void:
	GameData.go_to_game_setup("", scenario_id)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")
