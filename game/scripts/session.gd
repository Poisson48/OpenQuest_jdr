extends Control

@onready var log_label: RichTextLabel = %GameLog
@onready var input_action: LineEdit = %InputAction
@onready var btn_send_action: Button = %BtnSendAction
@onready var party_container: VBoxContainer = %PartyContainer
@onready var scene_progress_lbl: Label = %SceneProgress
@onready var scenario_title_lbl: Label = %ScenarioTitle
@onready var timer_lbl: Label = %TimerLabel
@onready var dice_result_lbl: Label = %DiceResultLabel
@onready var custom_dice_input: LineEdit = %CustomDiceInput
@onready var gm_panel: PanelContainer = %GmPanel
@onready var gm_input: TextEdit = %GmInput
@onready var net_status_lbl: Label = %NetStatusLabel
@onready var map_panel: PanelContainer = %MapPanel

var session_seconds: int = 0
var timer_active: bool = true

func _configure_layout() -> void:
	var main_area: VBoxContainer = $MainLayout/ContentSplit/MainGameArea
	var log_panel: PanelContainer = main_area.get_node("LogPanel") as PanelContainer
	var dice_section: Control = main_area.get_node("DiceSection")
	var action_section: Control = main_area.get_node("ActionSection")

	if main_area.has_node("MiddleScroll"):
		return

	var scroll := ScrollContainer.new()
	scroll.name = "MiddleScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var middle := VBoxContainer.new()
	middle.name = "MiddleVBox"
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 8)
	scroll.add_child(middle)

	main_area.remove_child(log_panel)
	main_area.remove_child(map_panel)
	middle.add_child(log_panel)
	middle.add_child(map_panel)

	main_area.add_child(scroll)
	main_area.move_child(scroll, 0)

	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_panel.custom_minimum_size = Vector2(0, 120)
	map_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	map_panel.custom_maximum_size = Vector2(100000, 220)

	dice_section.size_flags_vertical = Control.SIZE_SHRINK_END
	action_section.size_flags_vertical = Control.SIZE_SHRINK_END

func _ready() -> void:
	_configure_layout()
	%BtnBackHub.pressed.connect(_on_leave_session_pressed)
	%BtnAdvanceScene.pressed.connect(_on_advance_scene_pressed)
	btn_send_action.pressed.connect(_on_send_action_pressed)
	input_action.text_submitted.connect(func(_t): _on_send_action_pressed())
	
	%BtnRollCustom.pressed.connect(_on_roll_custom_dice)
	custom_dice_input.text_submitted.connect(func(_t): _on_roll_custom_dice())
	
	%BtnGmSend.pressed.connect(_on_gm_send_pressed)
	
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.scroll_active = true
	log_label.add_theme_constant_override("line_separation", 4)
	
	var log_panel: PanelContainer = log_label.get_parent().get_parent() as PanelContainer
	if log_panel:
		var style := StyleBoxFlat.new()
		style.bg_color = ThemeColors.BG_INPUT
		style.border_color = ThemeColors.BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		log_panel.add_theme_stylebox_override("panel", style)
	
	_setup_quick_dice_buttons()
	_setup_suggestion_buttons()
	_connect_network_signals()
	
	if not GameData.has_active_game():
		_create_fallback_game()
		
	_refresh_session_ui()
	_update_net_status()

func _setup_quick_dice_buttons() -> void:
	%BtnD4.pressed.connect(func(): _roll_dice_formula("1d4"))
	%BtnD6.pressed.connect(func(): _roll_dice_formula("1d6"))
	%BtnD8.pressed.connect(func(): _roll_dice_formula("1d8"))
	%BtnD10.pressed.connect(func(): _roll_dice_formula("1d10"))
	%BtnD12.pressed.connect(func(): _roll_dice_formula("1d12"))
	%BtnD20.pressed.connect(func(): _roll_dice_formula("1d20"))
	%BtnD100.pressed.connect(func(): _roll_dice_formula("1d100"))

func _setup_suggestion_buttons() -> void:
	%BtnSuggExplore.pressed.connect(func(): _set_and_send_action("J'explore attentivement les environs à la recherche d'indices."))
	%BtnSuggTalk.pressed.connect(func(): _set_and_send_action("J'engage la conversation avec les personnes présentes."))
	%BtnSuggInspect.pressed.connect(func(): _set_and_send_action("J'examine minutieusement cet endroit."))
	%BtnSuggCombat.pressed.connect(func(): _set_and_send_action("Je dégaine mon arme et me prépare au combat !"))

func _set_and_send_action(action_text: String) -> void:
	input_action.text = action_text
	_on_send_action_pressed()

func _connect_network_signals() -> void:
	NetworkClient.log_entry_received.connect(_on_net_log_entry)
	NetworkClient.dice_result_received.connect(_on_net_dice_result)
	NetworkClient.gm_narration_received.connect(_on_net_gm_narration)
	NetworkClient.game_state_received.connect(_on_net_game_state)
	NetworkClient.connected.connect(func(_id, _name): _update_net_status())
	NetworkClient.disconnected.connect(func(): _update_net_status())

func _process(delta: float) -> void:
	if timer_active:
		session_seconds = int(Time.get_ticks_msec() / 1000.0)
		var mins := session_seconds / 60
		var secs := session_seconds % 60
		timer_lbl.text = "⏱️ %02d:%02d" % [mins, secs]

func _update_net_status() -> void:
	if NetworkClient.is_server_connected():
		net_status_lbl.text = "● En ligne (MJ IA serveur)"
		net_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		net_status_lbl.text = "○ Mode Local"
		net_status_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)

func _create_fallback_game() -> void:
	var scns: Array = GameData.get_scenarios()
	var scn_id: String = scns[0].get("id", "demo-kharak") if not scns.is_empty() else "demo-kharak"
	var default_party: Array = [
		{ "id": "char-fallback-1", "name": "Aria", "race": "Elfe", "class": "Rôdeuse", "hp": 12, "ac": 14, "isPlayer": true, "isBot": false },
		{ "id": "bot-fallback-1", "name": "Kael", "race": "Nain", "class": "Guerrier", "hp": 14, "ac": 16, "isPlayer": false, "isBot": true }
	]
	GameData.create_new_game(scn_id, "solo", "ai", "oneshot", default_party)

func _refresh_session_ui() -> void:
	var state := GameData.active_game
	scenario_title_lbl.text = "🗺️ " + state.get("scenarioTitle", "Aventure")
	
	var scenario := GameData.get_scenario_by_id(state.get("scenarioId", ""))
	var scenes: Array = scenario.get("scenes", [])
	var cur_idx: int = state.get("currentSceneIndex", 0)
	
	if not scenes.is_empty() and cur_idx < scenes.size():
		var cur_scene: Dictionary = scenes[cur_idx]
		scene_progress_lbl.text = "Scène %d/%d : %s" % [cur_idx + 1, scenes.size(), cur_scene.get("title", "")]
	else:
		scene_progress_lbl.text = "Épilogue"
		
	# Affiche le GM panel uniquement si mode GM humain
	gm_panel.visible = state.get("gmType", "ai") == "human"
	
	_render_party_list()
	_render_log()
	if map_panel and map_panel.has_method("refresh"):
		map_panel.refresh()

func _render_party_list() -> void:
	for child in party_container.get_children():
		child.queue_free()
		
	var party: Array = GameData.active_game.get("party", [])
	for member in party:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = ThemeColors.BG_INPUT
		style.border_color = ThemeColors.BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		panel.add_theme_stylebox_override("panel", style)
		
		var vbox := VBoxContainer.new()
		var name_row := HBoxContainer.new()
		
		var name_lbl := Label.new()
		name_lbl.text = member.get("name", "Aventurier")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		name_row.add_child(name_lbl)
		
		var badge := Label.new()
		if member.get("isBot", false):
			badge.text = "BOT"
			badge.add_theme_color_override("font_color", ThemeColors.BOT_ACCENT)
		else:
			badge.text = "JOUEUR"
			badge.add_theme_color_override("font_color", ThemeColors.SUCCESS)
		name_row.add_child(badge)
		vbox.add_child(name_row)
		
		var stats_lbl := Label.new()
		stats_lbl.text = "%s %s · PV %d · CA %d" % [
			member.get("race", ""),
			member.get("class", ""),
			member.get("hp", 10),
			member.get("ac", 10)
		]
		stats_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		vbox.add_child(stats_lbl)
		
		panel.add_child(vbox)
		party_container.add_child(panel)

func _render_log() -> void:
	log_label.text = ""
	var log_entries: Array = GameData.active_game.get("log", [])
	for entry in log_entries:
		_append_log_entry_bbcode(entry)
	
	# Fait défiler jusqu'en bas
	await get_tree().process_frame
	var v_scroll = log_label.get_v_scroll_bar()
	if v_scroll:
		v_scroll.value = v_scroll.max_value

func _append_log_entry_bbcode(entry: Dictionary) -> void:
	var author: String = entry.get("author", "Inconnu")
	var type: String = entry.get("type", "player")
	var text: String = entry.get("text", "")
	var time: String = entry.get("time", "")
	
	var author_color: String = ThemeColors.get_bbcode_color(ThemeColors.GOLD_LIGHT)
	match type:
		"gm":
			author_color = ThemeColors.get_bbcode_color(ThemeColors.GOLD)
		"bot":
			author_color = ThemeColors.get_bbcode_color(ThemeColors.BOT_ACCENT)
		"player":
			author_color = ThemeColors.get_bbcode_color(ThemeColors.TEXT)
		"system":
			author_color = ThemeColors.get_bbcode_color(ThemeColors.TEXT_MUTED)
		"dice":
			author_color = ThemeColors.get_bbcode_color(ThemeColors.GOLD_LIGHT)
			
	var formatted := "[color=#%s][b]%s[/b][/color] [color=#9a8870][font_size=12]%s[/font_size][/color]\n%s\n\n" % [
		author_color, author, time, text
	]
	log_label.append_text(formatted)

func _on_send_action_pressed() -> void:
	var action_text := input_action.text.strip_edges()
	if action_text.is_empty():
		return
	input_action.text = ""
	
	if NetworkClient.is_server_connected():
		NetworkClient.send_action(action_text)
		return
	# Mode local
	var party: Array = GameData.active_game.get("party", [])
	var player_name := "Joueur"
	for p in party:
		if p.get("isPlayer", false):
			player_name = p.get("name", "Joueur")
			break
	GameData.add_log_entry(player_name, action_text, "player")
	_append_log_entry_bbcode({
		"author": player_name,
		"type": "player",
		"text": action_text,
		"time": Time.get_time_string_from_system()
	})
	if GameData.active_game.get("gmType", "ai") == "ai":
		_simulate_ai_response(action_text)

func _simulate_ai_response(player_action: String) -> void:
	# Simule la réaction du MJ IA selon les règles du jeu
	await get_tree().create_timer(0.6).timeout
	var gm_replies := [
		"Le Maître du Jeu écoute attentivement votre décision. Les ombres s'étirent et le vent murmure...",
		"Votre initiative porte ses fruits. La situation évolue et révèle de nouveaux détails.",
		"Vous observez l'environnement avec vigilance. Quelque chose attire votre attention...",
		"Une tension palpable s'installe. Le destin semble attendre l'issue de vos choix."
	]
	var gm_text: String = str(gm_replies[randi() % gm_replies.size()]) + "\n[i]« %s »[/i]" % player_action
	
	GameData.add_log_entry("MJ (IA)", gm_text, "gm")
	_append_log_entry_bbcode({
		"author": "MJ (IA)",
		"type": "gm",
		"text": gm_text,
		"time": Time.get_time_string_from_system()
	})
	
	# Réaction d'un bot s'il y en a dans le groupe
	var party: Array = GameData.active_game.get("party", [])
	var bots_in_party: Array = []
	for member in party:
		if member.get("isBot", false):
			bots_in_party.append(member)
			
	if not bots_in_party.is_empty():
		await get_tree().create_timer(0.5).timeout
		var bot: Dictionary = bots_in_party[randi() % bots_in_party.size()]
		var bot_replies: Array[String] = [
			"approuve votre idée et couvre vos arrières.",
			"scrute les alentours l'arme au poing.",
			"prend des notes et garde le silence.",
			"prépare un sortilège en prévision du danger."
		]
		var b_text: String = "%s %s" % [bot.get("name", "Bot"), bot_replies[randi() % bot_replies.size()]]
		GameData.add_log_entry(bot.get("name", "Bot"), b_text, "bot")
		_append_log_entry_bbcode({
			"author": bot.get("name", "Bot"),
			"type": "bot",
			"text": b_text,
			"time": Time.get_time_string_from_system()
		})

func _roll_dice_formula(formula: String) -> void:
	var res := GameData.roll_dice(formula)
	if res.has("error"):
		dice_result_lbl.text = str(res["error"])
		return
	var formatted := GameData.format_dice_result(res)
	dice_result_lbl.text = formatted
	
	GameData.add_log_entry("Dé", formatted, "dice")
	_append_log_entry_bbcode({
		"author": "Dé",
		"type": "dice",
		"text": formatted,
		"time": Time.get_time_string_from_system()
	})
	
	if NetworkClient.is_server_connected():
		NetworkClient.send_dice_roll(formula)

func _on_roll_custom_dice() -> void:
	var f := custom_dice_input.text.strip_edges()
	if not f.is_empty():
		_roll_dice_formula(f)

func _on_gm_send_pressed() -> void:
	var text := gm_input.text.strip_edges()
	if text.is_empty():
		return
	gm_input.text = ""
	
	GameData.add_log_entry("MJ", text, "gm")
	_append_log_entry_bbcode({
		"author": "MJ",
		"type": "gm",
		"text": text,
		"time": Time.get_time_string_from_system()
	})

func _on_advance_scene_pressed() -> void:
	if NetworkClient.is_server_connected():
		NetworkClient.advance_scene()
		return
	var _advanced := GameData.advance_scene()
	_refresh_session_ui()

func _on_net_game_state(state: Dictionary) -> void:
	GameData.apply_server_state(state)
	_refresh_session_ui()

func _on_net_log_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	_append_log_entry_bbcode(entry)

func _on_net_dice_result(res: Dictionary) -> void:
	var formatted := GameData.format_dice_result(res)
	dice_result_lbl.text = formatted

func _on_net_gm_narration(text: String) -> void:
	_append_log_entry_bbcode({
		"author": "MJ",
		"type": "gm",
		"text": text,
		"time": Time.get_time_string_from_system()
	})

func _on_leave_session_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")
