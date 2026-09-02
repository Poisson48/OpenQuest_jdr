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
@onready var btn_back_hub: Button = %BtnBackHub
@onready var btn_advance_scene: Button = %BtnAdvanceScene
@onready var btn_roll_custom: Button = %BtnRollCustom
@onready var btn_gm_send: Button = %BtnGmSend
@onready var btn_d4: Button = %BtnD4
@onready var btn_d6: Button = %BtnD6
@onready var btn_d8: Button = %BtnD8
@onready var btn_d10: Button = %BtnD10
@onready var btn_d12: Button = %BtnD12
@onready var btn_d20: Button = %BtnD20
@onready var btn_d100: Button = %BtnD100
@onready var btn_sugg_explore: Button = %BtnSuggExplore
@onready var btn_sugg_talk: Button = %BtnSuggTalk
@onready var btn_sugg_inspect: Button = %BtnSuggInspect
@onready var btn_sugg_combat: Button = %BtnSuggCombat

var session_seconds: int = 0
var timer_active: bool = true

func _configure_layout() -> void:
	var main_area: VBoxContainer = $MainLayout/ContentSplit/MainGameArea
	var log_panel: PanelContainer = main_area.get_node("LogPanel") as PanelContainer
	var dice_section: Control = main_area.get_node("DiceSection")
	var action_section: Control = main_area.get_node("ActionSection")

	_remove_legacy_middle_scroll(main_area, log_panel)
	_ensure_session_scroll(main_area)

	var session_scroll: ScrollContainer = main_area.get_node("SessionScroll") as ScrollContainer
	var session_vbox: VBoxContainer = session_scroll.get_node("SessionVBox") as VBoxContainer
	var ordered: Array = [map_panel, log_panel, dice_section, action_section]
	for i in range(ordered.size()):
		var node: Control = ordered[i] as Control
		if node.get_parent() != session_vbox:
			if node.get_parent():
				node.get_parent().remove_child(node)
			session_vbox.add_child(node)
		session_vbox.move_child(node, i)

	map_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	map_panel.custom_minimum_size = Vector2(0, 450)

	log_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	log_panel.size_flags_stretch_ratio = 0.0
	log_panel.custom_minimum_size = Vector2(0, 320)

	dice_section.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	action_section.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	_configure_log_readability()

func _ensure_session_scroll(main_area: VBoxContainer) -> void:
	if main_area.has_node("PlayScroll"):
		var play_scroll: ScrollContainer = main_area.get_node("PlayScroll")
		var play_vbox: VBoxContainer = play_scroll.get_node("PlayVBox")
		while play_vbox.get_child_count() > 0:
			var child: Node = play_vbox.get_child(0)
			play_vbox.remove_child(child)
			main_area.add_child(child)
		play_scroll.queue_free()

	if main_area.has_node("SessionScroll"):
		return

	var session_scroll := ScrollContainer.new()
	session_scroll.name = "SessionScroll"
	session_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	session_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	session_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var session_vbox := VBoxContainer.new()
	session_vbox.name = "SessionVBox"
	session_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_vbox.add_theme_constant_override("separation", 8)
	session_scroll.add_child(session_vbox)
	main_area.add_child(session_scroll)
	main_area.move_child(session_scroll, 0)

func _remove_legacy_middle_scroll(main_area: VBoxContainer, log_panel: PanelContainer) -> void:
	if not main_area.has_node("MiddleScroll"):
		return
	var scroll: ScrollContainer = main_area.get_node("MiddleScroll")
	var middle: VBoxContainer = scroll.get_node("MiddleVBox")
	if map_panel.get_parent() == middle:
		middle.remove_child(map_panel)
	if log_panel.get_parent() == middle:
		middle.remove_child(log_panel)
	scroll.queue_free()

func _configure_log_readability() -> void:
	var log_vbox := log_label.get_parent() as VBoxContainer
	if log_vbox:
		log_vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.scroll_active = false
	log_label.fit_content = false
	log_label.add_theme_font_size_override("normal_font_size", 15)
	log_label.add_theme_color_override("default_color", ThemeColors.TEXT)
	log_label.add_theme_constant_override("line_separation", 6)

	var log_panel_node: PanelContainer = log_label.get_parent().get_parent() as PanelContainer
	if log_panel_node:
		var style := StyleBoxFlat.new()
		style.bg_color = ThemeColors.BG_INPUT
		style.border_color = ThemeColors.BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 10
		style.content_margin_bottom = 12
		log_panel_node.add_theme_stylebox_override("panel", style)

	if log_vbox:
		var title_lbl := log_vbox.get_node_or_null("LblHistoire") as Label
		if title_lbl:
			title_lbl.add_theme_font_size_override("font_size", 15)

func _sync_log_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var content_h := int(log_label.get_content_height())
	var body_h := maxi(280, content_h + 28)
	log_label.custom_minimum_size = Vector2(0, body_h)
	var log_panel_node: PanelContainer = log_label.get_parent().get_parent() as PanelContainer
	if log_panel_node:
		log_panel_node.custom_minimum_size = Vector2(0, body_h + 52)

func _ready() -> void:
	if not GameData.has_active_game():
		_create_fallback_game()
	_refresh_session_ui()

	_configure_layout()

	btn_back_hub.pressed.connect(_on_leave_session_pressed)
	btn_advance_scene.pressed.connect(_on_advance_scene_pressed)
	btn_send_action.pressed.connect(_on_send_action_pressed)
	input_action.text_submitted.connect(func(_t): _on_send_action_pressed())

	btn_roll_custom.pressed.connect(_on_roll_custom_dice)
	custom_dice_input.text_submitted.connect(func(_t): _on_roll_custom_dice())

	btn_gm_send.pressed.connect(_on_gm_send_pressed)

	_configure_log_readability()
	_setup_quick_dice_buttons()
	_setup_suggestion_buttons()
	_connect_network_signals()
	_connect_game_data_signals()

	_refresh_session_ui()
	_update_net_status()

func _setup_quick_dice_buttons() -> void:
	btn_d4.pressed.connect(func(): _roll_dice_formula("1d4"))
	btn_d6.pressed.connect(func(): _roll_dice_formula("1d6"))
	btn_d8.pressed.connect(func(): _roll_dice_formula("1d8"))
	btn_d10.pressed.connect(func(): _roll_dice_formula("1d10"))
	btn_d12.pressed.connect(func(): _roll_dice_formula("1d12"))
	btn_d20.pressed.connect(func(): _roll_dice_formula("1d20"))
	btn_d100.pressed.connect(func(): _roll_dice_formula("1d100"))

func _setup_suggestion_buttons() -> void:
	btn_sugg_explore.pressed.connect(func(): _set_and_send_action("J'explore attentivement les environs à la recherche d'indices."))
	btn_sugg_talk.pressed.connect(func(): _set_and_send_action("J'engage la conversation avec les personnes présentes."))
	btn_sugg_inspect.pressed.connect(func(): _set_and_send_action("J'examine minutieusement cet endroit."))
	btn_sugg_combat.pressed.connect(func(): _set_and_send_action("Je dégaine mon arme et me prépare au combat !"))

func _connect_game_data_signals() -> void:
	if not GameData.active_game_updated.is_connected(_refresh_session_ui):
		GameData.active_game_updated.connect(_refresh_session_ui)

func _set_and_send_action(action_text: String) -> void:
	input_action.text = action_text
	_on_send_action_pressed()

func _connect_network_signals() -> void:
	NetworkClient.dice_result_received.connect(_on_net_dice_result)
	NetworkClient.gm_narration_received.connect(_on_net_gm_narration)
	NetworkClient.game_state_received.connect(_on_net_game_state)
	NetworkClient.connected.connect(func(_id, _name): _update_net_status())
	NetworkClient.disconnected.connect(func(): _update_net_status())

	MultiplayerManager.game_state_received.connect(_on_net_game_state)
	MultiplayerManager.dice_result_received.connect(_on_net_dice_result)
	MultiplayerManager.log_entry_received.connect(_on_p2p_log_entry)

func _process(delta: float) -> void:
	if timer_active:
		session_seconds = int(Time.get_ticks_msec() / 1000.0)
		var mins := session_seconds / 60
		var secs := session_seconds % 60
		timer_lbl.text = "⏱️ %02d:%02d" % [mins, secs]

func _update_net_status() -> void:
	if MultiplayerManager.is_p2p_active() and MultiplayerManager.is_in_room():
		var my_member := MultiplayerManager.get_my_party_member(GameData.active_game)
		var char_hint := ""
		if not my_member.is_empty():
			char_hint = " · %s" % my_member.get("name", "")
		var role := "MJ" if MultiplayerManager.is_p2p_host() else "joueur"
		net_status_lbl.text = "● P2P (%s%s)" % [role, char_hint]
		net_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	elif NetworkClient.is_server_connected():
		var my_member := NetworkClient.get_my_party_member(GameData.active_game)
		var char_hint := ""
		if not my_member.is_empty():
			char_hint = " · %s" % my_member.get("name", "")
		net_status_lbl.text = "● En ligne%s" % char_hint
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
	GameData.sync_active_game_scenario_metadata()
	var state := GameData.active_game
	scenario_title_lbl.text = "🗺️ " + GameData.get_scenario_display_title()
	
	var scenario := GameData.get_scenario_by_id(state.get("scenarioId", ""))
	var scenes: Array = scenario.get("scenes", [])
	var cur_idx: int = state.get("currentSceneIndex", 0)
	
	if not scenes.is_empty() and cur_idx < scenes.size():
		var cur_scene: Dictionary = scenes[cur_idx]
		scene_progress_lbl.text = "Scène %d/%d : %s" % [cur_idx + 1, scenes.size(), cur_scene.get("title", "")]
	else:
		scene_progress_lbl.text = "Épilogue"
		
	# Panneau MJ : mode humain uniquement, et seulement pour le MJ en ligne
	var show_gm := _is_human_gm_user()
	gm_panel.visible = show_gm
	btn_advance_scene.visible = show_gm
	btn_gm_send.visible = show_gm
	gm_input.editable = show_gm
	
	_render_party_list()
	_render_log()
	if map_panel and map_panel.has_method("refresh"):
		map_panel.refresh()

func _is_human_gm_user() -> bool:
	var state := GameData.active_game
	if state.get("gmType", "ai") != "human":
		return false
	if MultiplayerManager.is_p2p_active() and MultiplayerManager.is_in_room():
		return MultiplayerManager.is_mj() or MultiplayerManager.is_game_master()
	if NetworkClient.is_server_connected():
		return NetworkClient.is_host()
	return true

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
		if MultiplayerManager.is_p2p_active() and member.get("clientId", "") == MultiplayerManager.player_id:
			badge.text = "VOUS"
			badge.add_theme_color_override("font_color", ThemeColors.GOLD)
		elif member.get("clientId", "") == NetworkClient.get_player_id() and NetworkClient.is_server_connected():
			badge.text = "VOUS"
			badge.add_theme_color_override("font_color", ThemeColors.GOLD)
		elif member.get("isBot", false):
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
	var saved_scroll := _get_session_scroll()
	var log_entries: Array = GameData.active_game.get("log", [])
	var last_is_dice: bool = not log_entries.is_empty() and str(log_entries[-1].get("type", "")) == "dice"

	log_label.text = ""
	for entry in log_entries:
		_append_log_entry_bbcode(entry, false)
	call_deferred("_sync_log_layout")
	if last_is_dice:
		call_deferred("_restore_session_scroll", saved_scroll)
	else:
		call_deferred("_scroll_session_to_bottom")

func _get_session_scroll() -> float:
	var main_area: VBoxContainer = $MainLayout/ContentSplit/MainGameArea
	if not main_area.has_node("SessionScroll"):
		return 0.0
	var scroll: ScrollContainer = main_area.get_node("SessionScroll")
	var bar := scroll.get_v_scroll_bar()
	return bar.value if bar else 0.0

func _scroll_session_to_bottom() -> void:
	await get_tree().process_frame
	var main_area: VBoxContainer = $MainLayout/ContentSplit/MainGameArea
	if not main_area.has_node("SessionScroll"):
		return
	var scroll: ScrollContainer = main_area.get_node("SessionScroll")
	var bar := scroll.get_v_scroll_bar()
	if bar:
		bar.value = bar.max_value

func _restore_session_scroll(saved: float) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var main_area: VBoxContainer = $MainLayout/ContentSplit/MainGameArea
	if not main_area.has_node("SessionScroll"):
		return
	var scroll: ScrollContainer = main_area.get_node("SessionScroll")
	var bar := scroll.get_v_scroll_bar()
	if bar:
		bar.value = clampf(saved, 0.0, bar.max_value)

func _append_log_entry_bbcode(entry: Dictionary, auto_scroll: bool = true) -> void:
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
			
	var formatted := "[color=#%s][font_size=15][b]%s[/b][/font_size][/color] [color=#9a8870][font_size=12]%s[/font_size][/color]\n[font_size=15]%s[/font_size]\n\n" % [
		author_color, author, time, text
	]
	var is_dice := type == "dice"
	var saved_scroll := _get_session_scroll() if (auto_scroll and is_dice) else -1.0
	log_label.append_text(formatted)
	call_deferred("_sync_log_layout")
	if not auto_scroll:
		return
	if is_dice:
		call_deferred("_restore_session_scroll", saved_scroll)
	else:
		call_deferred("_scroll_session_to_bottom")

func _on_send_action_pressed() -> void:
	var action_text := input_action.text.strip_edges()
	if action_text.is_empty():
		return
	input_action.text = ""

	if MultiplayerManager.is_p2p_active() and GameData.has_active_game():
		MultiplayerManager.client_submit_action(action_text)
		return

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
	if GameData.try_auto_move_from_action(action_text):
		map_panel.refresh()
	if GameData.active_game.get("gmType", "ai") == "ai":
		GameData.maybe_reveal_investigation_from_action(action_text)
		map_panel.refresh()
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
	var saved_scroll := _get_session_scroll()
	if MultiplayerManager.is_p2p_active() and GameData.has_active_game():
		MultiplayerManager.client_request_dice_roll(formula)
		call_deferred("_restore_session_scroll", saved_scroll)
		return

	if NetworkClient.is_server_connected():
		NetworkClient.send_dice_roll(formula)
		call_deferred("_restore_session_scroll", saved_scroll)
		return
	
	var res := GameData.roll_dice(formula)
	if res.has("error"):
		dice_result_lbl.text = str(res["error"])
		call_deferred("_restore_session_scroll", saved_scroll)
		return
	var formatted := GameData.format_dice_result(res)
	dice_result_lbl.text = formatted
	
	GameData.add_log_entry("Dé", formatted, "dice")
	_append_log_entry_bbcode({
		"author": "Dé",
		"type": "dice",
		"text": formatted,
		"time": Time.get_time_string_from_system()
	}, false)
	call_deferred("_restore_session_scroll", saved_scroll)

func _on_roll_custom_dice() -> void:
	var f := custom_dice_input.text.strip_edges()
	if not f.is_empty():
		_roll_dice_formula(f)

func _on_gm_send_pressed() -> void:
	if not _is_human_gm_user():
		return
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
	if not _is_human_gm_user():
		return
	if MultiplayerManager.is_p2p_active():
		MultiplayerManager.client_advance_scene()
		_refresh_session_ui()
		return
	if NetworkClient.is_server_connected():
		NetworkClient.advance_scene()
		return
	var _advanced := GameData.advance_scene()
	_refresh_session_ui()

func _on_net_game_state(state: Dictionary) -> void:
	GameData.apply_server_state(state)
	_refresh_session_ui()

func _on_p2p_log_entry(entry: Dictionary) -> void:
	_append_log_entry_bbcode(entry)

func _on_net_dice_result(_res: Dictionary, formatted: String) -> void:
	if not formatted.is_empty():
		dice_result_lbl.text = formatted
	else:
		dice_result_lbl.text = GameData.format_dice_result(_res)

func _on_net_gm_narration(text: String) -> void:
	_append_log_entry_bbcode({
		"author": "MJ",
		"type": "gm",
		"text": text,
		"time": Time.get_time_string_from_system()
	})

func _on_leave_session_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")
