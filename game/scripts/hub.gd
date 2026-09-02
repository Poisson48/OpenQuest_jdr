extends Control

@onready var tab_container: TabContainer = %TabContainer
@onready var bots_grid: GridContainer = %BotsGrid
@onready var adv_summary_lbl: Label = %AdvSummaryLabel
@onready var inv_summary_lbl: Label = %InvSummaryLabel
@onready var play_resume_btn: Button = %BtnPlayResume
@onready var play_status_lbl: Label = %PlayStatusLabel

func _ready() -> void:
	%BtnHome.pressed.connect(_on_home_pressed)
	NetworkClient.game_started.connect(_on_remote_game_started)
	
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
	play_resume_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/session/session.tscn"))
	
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
	
	# Statut jeu en cours
	if GameData.has_active_game():
		var scn_title: String = GameData.active_game.get("scenarioTitle", "Partie active")
		play_status_lbl.text = "Partie en cours : « %s »" % scn_title
		play_resume_btn.disabled = false
	else:
		play_status_lbl.text = "Aucune session active actuellement."
		play_resume_btn.disabled = true
		
	_render_bots()

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
		stats_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		stats_lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(stats_lbl)
		
		card.add_child(vbox)
		bots_grid.add_child(card)

func _on_home_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_remote_game_started(_game_id: String, state: Dictionary) -> void:
	GameData.apply_server_state(state)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")
