extends Control

@onready var saved_games_section: PanelContainer = %SavedGamesSection
@onready var saved_games_list: VBoxContainer = %SavedGamesList
@onready var modes_panel: PanelContainer = %ModesPanel

var _pending_delete_id: String = ""

func _ready() -> void:
	%BtnPlay.pressed.connect(_on_play_pressed)
	%BtnModes.pressed.connect(_on_modes_pressed)
	%BtnDiscover.pressed.connect(_on_discover_pressed)
	%ConfirmDeleteResume.confirmed.connect(_on_confirm_delete_resume)
	%BtnCloseModes.pressed.connect(func(): modes_panel.visible = false)
	
	%BtnModeLong.pressed.connect(func(): _start_with_format("long"))
	%BtnModeOneshot.pressed.connect(func(): _start_with_format("oneshot"))
	%BtnModeInvestigation.pressed.connect(func(): _start_with_format("investigation"))
	
	modes_panel.visible = false
	_render_saved_games()

func _render_saved_games() -> void:
	for child in saved_games_list.get_children():
		child.queue_free()
	
	var games: Array = GameData.get_playing_games()
	saved_games_section.visible = not games.is_empty()
	if games.is_empty():
		return
	
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
	btn_delete.tooltip_text = "Effacer cette sauvegarde et toute sa progression"
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
	%ConfirmDeleteResume.dialog_text = "Effacer la partie « %s » ? Toute la progression sera perdue." % title
	%ConfirmDeleteResume.popup_centered()

func _on_confirm_delete_resume() -> void:
	if _pending_delete_id.is_empty():
		return
	GameData.delete_game(_pending_delete_id)
	_pending_delete_id = ""
	_render_saved_games()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game_setup.tscn")

func _on_modes_pressed() -> void:
	modes_panel.visible = true

func _on_discover_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")

func _start_with_format(quest_format: String) -> void:
	var scns := GameData.get_scenarios(quest_format if quest_format != "investigation" else "", "investigation" if quest_format == "investigation" else "")
	if not scns.is_empty():
		get_tree().set_meta("preselected_scenario_id", scns[0].get("id"))
	get_tree().change_scene_to_file("res://scenes/game_setup.tscn")
