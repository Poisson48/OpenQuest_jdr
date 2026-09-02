extends Control

@onready var tab_container: TabContainer = %TabContainer
@onready var bots_grid: GridContainer = %BotsGrid
@onready var adv_summary_lbl: Label = %AdvSummaryLabel
@onready var inv_summary_lbl: Label = %InvSummaryLabel
@onready var play_status_lbl: Label = %PlayStatusLabel
@onready var saved_games_list: VBoxContainer = %SavedGamesList

var _pending_delete_id: String = ""

func _ready() -> void:
	%BtnHome.pressed.connect(_on_home_pressed)
	
	# Onglet Aventures
	%BtnAdvNewChar.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/character_editor.tscn"))
	%BtnAdvAllChars.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/character_editor.tscn"))
	%BtnAdvScenarios.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/scenario_list.tscn"))
	%BtnAdvPlay.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/game_setup.tscn"))
	
	# Onglet Enquête
	%BtnInvNewChar.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/character_editor.tscn"))
	%BtnInvScenarios.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/scenario_list.tscn"))
	%BtnInvPlay.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/game_setup.tscn"))
	
	# Onglet Jouer
	%BtnPlayNew.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/game_setup.tscn"))
	%ConfirmDeleteSession.confirmed.connect(_on_confirm_delete_session)
	
	# Onglet Cartes
	%BtnMapsViewer.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/map_viewer.tscn"))
	
	_populate_hub_data()

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
	title_lbl.text = "« %s »" % game.get("scenarioTitle", "Aventure")
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
	for child in bots_grid.get_children():
		child.queue_free()
		
	var bots := GameData.get_bots()
	for b in bots:
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
		
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		
		var header := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = "🤖 " + b.get("name", "Bot")
		name_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(name_lbl)
		
		var bot_tag := Label.new()
		bot_tag.text = b.get("personality", "").to_upper()
		bot_tag.add_theme_color_override("font_color", ThemeColors.BOT_ACCENT)
		header.add_child(bot_tag)
		vbox.add_child(header)
		
		var meta_lbl := Label.new()
		meta_lbl.text = "%s · %s" % [b.get("race", ""), b.get("class", "")]
		meta_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		vbox.add_child(meta_lbl)
		
		var traits: Array = b.get("traits", [])
		if not traits.is_empty():
			var traits_lbl := Label.new()
			traits_lbl.text = "Traits : " + ", ".join(traits)
			traits_lbl.add_theme_color_override("font_color", ThemeColors.TEXT)
			traits_lbl.add_theme_font_size_override("font_size", 12)
			vbox.add_child(traits_lbl)
			
		var stats: Dictionary = b.get("stats", {})
		var stats_lbl := Label.new()
		stats_lbl.text = "PV %d · CA %d · FOR %d DEX %d INT %d" % [
			b.get("hp", 10), b.get("ac", 10),
			stats.get("str", 10), stats.get("dex", 10), stats.get("int", 10)
		]
		stats_lbl.add_theme_font_size_override("font_size", 12)
		stats_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		vbox.add_child(stats_lbl)
		
		card.add_child(vbox)
		bots_grid.add_child(card)

func _on_home_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
