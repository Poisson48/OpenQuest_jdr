extends Control

const QuestNavigation = preload("res://scripts/quest_navigation.gd")

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
@onready var lbl_gm_wait: Label = %LblGmWait
@onready var opt_gm_npc: OptionButton = %OptGmNpc
@onready var gm_npc_input: TextEdit = %GmNpcInput
@onready var btn_gm_npc_send: Button = %BtnGmNpcSend
@onready var btn_gm_advance_scene: Button = %BtnGmAdvanceScene
@onready var opt_gm_scene: OptionButton = %OptGmScene
@onready var btn_gm_go_to_scene: Button = %BtnGmGoToScene
@onready var gm_transitions_vbox: VBoxContainer = %GmTransitionsVBox
@onready var btn_gm_complete_scenario: Button = %BtnGmCompleteScenario
@onready var lbl_turn_indicator: Label = %LblTurnIndicator
@onready var lbl_action_hint: Label = %LblActionHint
@onready var dice_section: PanelContainer = $MainLayout/ContentSplit/MainGameArea/DiceSection
@onready var action_section: PanelContainer = $MainLayout/ContentSplit/MainGameArea/ActionSection
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
	_unwrap_session_scroll(main_area, [map_panel, log_panel, dice_section, action_section])

	main_area.size_flags_vertical = Control.SIZE_EXPAND_FILL

	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_stretch_ratio = 1.2
	map_panel.custom_minimum_size = Vector2.ZERO

	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_panel.size_flags_stretch_ratio = 1.0
	log_panel.custom_minimum_size = Vector2.ZERO

	dice_section.size_flags_vertical = Control.SIZE_SHRINK_END
	action_section.size_flags_vertical = Control.SIZE_SHRINK_END

	var content_split: HSplitContainer = $MainLayout/ContentSplit
	content_split.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var party_scroll: ScrollContainer = $MainLayout/ContentSplit/Sidebar/PartyPanel/PartyScroll
	party_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_configure_sidebar_scroll()
	_configure_log_readability()

func _configure_sidebar_scroll() -> void:
	var split: HSplitContainer = $MainLayout/ContentSplit
	if split.has_node("SidebarScroll"):
		return
	var sidebar: VBoxContainer = split.get_node("Sidebar")
	split.remove_child(sidebar)
	var scroll := ScrollContainer.new()
	scroll.name = "SidebarScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.add_child(sidebar)
	split.add_child(scroll)
	split.move_child(scroll, 0)

func _unwrap_session_scroll(main_area: VBoxContainer, ordered: Array) -> void:
	if main_area.has_node("PlayScroll"):
		var play_scroll: ScrollContainer = main_area.get_node("PlayScroll")
		var play_vbox: VBoxContainer = play_scroll.get_node("PlayVBox")
		while play_vbox.get_child_count() > 0:
			var child: Node = play_vbox.get_child(0)
			play_vbox.remove_child(child)
			main_area.add_child(child)
		play_scroll.queue_free()

	if not main_area.has_node("SessionScroll"):
		return

	var session_scroll: ScrollContainer = main_area.get_node("SessionScroll")
	var session_vbox: VBoxContainer = session_scroll.get_node("SessionVBox")
	for node in ordered:
		var control_node: Control = node as Control
		if control_node.get_parent() == session_vbox:
			session_vbox.remove_child(control_node)
			main_area.add_child(control_node)
	for i in range(ordered.size()):
		var control_node: Control = ordered[i] as Control
		main_area.move_child(control_node, i)
	session_scroll.queue_free()

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
	var log_vbox := log_label.get_parent().get_parent() as VBoxContainer
	if log_vbox:
		log_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var log_scroll := log_label.get_parent() as ScrollContainer
	if log_scroll:
		log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		log_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.scroll_active = false
	log_label.fit_content = true
	log_label.add_theme_font_size_override("normal_font_size", 15)
	log_label.add_theme_color_override("default_color", ThemeColors.TEXT)
	log_label.add_theme_constant_override("line_separation", 6)

	var log_panel_node: PanelContainer = log_vbox.get_parent() as PanelContainer if log_vbox else null
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
	var log_scroll := log_label.get_parent()
	if log_scroll is ScrollContainer:
		var bar := (log_scroll as ScrollContainer).get_v_scroll_bar()
		if bar:
			bar.value = bar.max_value

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
	btn_gm_npc_send.pressed.connect(_on_gm_npc_send_pressed)
	btn_gm_advance_scene.pressed.connect(_on_advance_scene_pressed)
	btn_gm_go_to_scene.pressed.connect(_on_gm_go_to_scene_pressed)
	btn_gm_complete_scenario.pressed.connect(_on_gm_complete_scenario_pressed)

	_configure_log_readability()
	_setup_quick_dice_buttons()
	_setup_suggestion_buttons()
	_connect_network_signals()
	_connect_game_data_signals()

	_refresh_session_ui()
	_update_net_status()
	_apply_role_ui()
	_print_session_debug()

func _print_session_debug() -> void:
	var state := GameData.active_game
	var lines: PackedStringArray = [
		"scene=session.tscn",
		"scenario=%s" % state.get("scenarioId", "?"),
		"gmType=%s" % state.get("gmType", "?"),
		"mode=%s" % state.get("mode", "?"),
		"status=%s" % state.get("status", "?"),
		"mj_controller=%s" % _is_mj_controller(),
		"waitingForGm=%s" % GameData.is_waiting_for_gm(),
		"turnIndex=%s" % state.get("turnIndex", 0),
		"active=%s" % GameData.get_active_member().get("name", "?"),
		"gm_panel=%s" % gm_panel.visible,
		"action_section=%s" % action_section.visible,
		"btn_advance=%s" % btn_advance_scene.visible,
	]
	for line in lines:
		print("[SESSION DEBUG] ", line)
	var log_path := ProjectSettings.globalize_path("user://session-debug.txt")
	var file := FileAccess.open(log_path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines))
		file.close()
		print("[SESSION DEBUG] log_file=", log_path)

func _is_human_gm_mode() -> bool:
	return GameData.active_game.get("gmType", "ai") == "human"

func _is_mj_controller() -> bool:
	if not _is_human_gm_mode():
		return false
	if MultiplayerManager.is_p2p_active():
		return MultiplayerManager.is_p2p_host() and MultiplayerManager.is_mj()
	return true

func _local_client_id() -> String:
	if MultiplayerManager.is_p2p_active():
		return MultiplayerManager.player_id
	return ""

func _apply_role_ui() -> void:
	var human_gm: bool = _is_human_gm_mode()
	var mj: bool = _is_mj_controller()
	var completed: bool = str(GameData.active_game.get("status", "")) == "completed"

	gm_panel.visible = human_gm and mj and not completed
	action_section.visible = not mj or not human_gm
	btn_advance_scene.visible = not human_gm or not mj

	if human_gm and mj:
		_populate_gm_npcs()
		_update_gm_wait_label()
		_refresh_scene_navigation_ui()

	_render_turn_ui()
	_update_player_controls()

func _populate_gm_npcs() -> void:
	opt_gm_npc.clear()
	opt_gm_npc.add_item("— Choisir un PNJ —", 0)
	opt_gm_npc.set_item_metadata(0, "")
	var idx := 1
	for npc in GameData.get_scenario_npcs():
		var npc_name: String = npc.get("name", "PNJ")
		var role: String = npc.get("role", "")
		var label := npc_name if role.is_empty() else "%s (%s)" % [npc_name, role]
		opt_gm_npc.add_item(label, idx)
		opt_gm_npc.set_item_metadata(idx, npc_name)
		idx += 1
	opt_gm_npc.add_item("✏️ PNJ personnalisé...", idx)
	opt_gm_npc.set_item_metadata(idx, "__custom__")

func _update_gm_wait_label() -> void:
	if GameData.is_waiting_for_gm():
		lbl_gm_wait.text = "⚡ Action reçue — répondez (narration ou PNJ) pour relancer le tour."
		lbl_gm_wait.add_theme_color_override("font_color", ThemeColors.GOLD)
	else:
		lbl_gm_wait.text = "En attente d'une action joueur..."
		lbl_gm_wait.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)

func _render_turn_ui() -> void:
	var state := GameData.active_game
	if state.is_empty() or state.get("status") == "completed":
		lbl_turn_indicator.text = "🏁 Aventure terminée"
		lbl_action_hint.text = "Consultez le journal ou quittez la session."
		return

	var actor := GameData.get_active_member()
	var actor_name: String = str(actor.get("name", "?")) if not actor.is_empty() else "?"
	var playable := GameData.get_playable_members()
	var mode: String = state.get("mode", "solo")

	if not _is_human_gm_mode():
		lbl_turn_indicator.text = "🎯 À vous de jouer — %s" % actor_name
		lbl_action_hint.text = "Décrivez votre action. Les bots joueront ensuite."
		return

	if _is_mj_controller():
		if GameData.is_waiting_for_gm():
			lbl_turn_indicator.text = "👑 Votre tour de MJ"
			lbl_action_hint.text = "Les joueurs attendent votre réponse dans le panneau doré."
		elif playable.size() <= 1:
			lbl_turn_indicator.text = "👑 Table MJ — %s" % actor_name
			lbl_action_hint.text = "Vous pilotez l'aventure. Les joueurs agissent via leurs clients."
		else:
			lbl_turn_indicator.text = "👑 Table MJ — tour de %s" % actor_name
			lbl_action_hint.text = "Le joueur actif doit agir. Vous narrerez ensuite."
		return

	if GameData.is_waiting_for_gm():
		lbl_turn_indicator.text = "⏳ En attente du MJ"
		lbl_action_hint.text = "Le MJ %s prépare la suite..." % GameData.get_gm_display_name()
	elif not GameData.can_member_act(_local_client_id()):
		lbl_turn_indicator.text = "⏳ Tour de %s" % actor_name
		lbl_action_hint.text = "Ce n'est pas encore votre tour — patientez."
	else:
		if mode == "multi":
			lbl_turn_indicator.text = "🎯 Votre tour — %s" % actor_name
		else:
			lbl_turn_indicator.text = "🎯 Tour de %s" % actor_name
		lbl_action_hint.text = "Décrivez l'action de votre personnage."

func _update_player_controls() -> void:
	var completed: bool = str(GameData.active_game.get("status", "")) == "completed"
	var can_act: bool = not completed and _can_submit_action()
	var mj_can_roll: bool = _is_mj_controller() and _is_human_gm_mode() and not completed
	input_action.editable = can_act
	btn_send_action.disabled = not can_act
	custom_dice_input.editable = can_act or mj_can_roll
	btn_roll_custom.disabled = not can_act and not mj_can_roll
	for btn in [btn_d4, btn_d6, btn_d8, btn_d10, btn_d12, btn_d20, btn_d100]:
		btn.disabled = not can_act and not mj_can_roll
	for btn in [btn_sugg_explore, btn_sugg_talk, btn_sugg_inspect, btn_sugg_combat]:
		btn.disabled = not can_act

func _can_submit_action() -> bool:
	if _is_mj_controller() and _is_human_gm_mode():
		return false
	if MultiplayerManager.is_p2p_active():
		return GameData.can_member_act(_local_client_id())
	return GameData.can_member_act("")

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
	scene_progress_lbl.text = QuestNavigation.format_progress_label(scenario, state)

	_render_party_list()
	_render_log()
	_refresh_scene_navigation_ui()
	if map_panel and map_panel.has_method("refresh"):
		map_panel.refresh()
	_apply_role_ui()

func _is_human_gm_user() -> bool:
	var state := GameData.active_game
	if state.get("gmType", "ai") != "human":
		return false
	if MultiplayerManager.is_p2p_active() and MultiplayerManager.is_in_room():
		return MultiplayerManager.is_mj() or MultiplayerManager.is_game_master()
	return true

func _render_party_list() -> void:
	for child in party_container.get_children():
		child.queue_free()
		
	var party: Array = GameData.active_game.get("party", [])
	var active := GameData.get_active_member()
	var active_id: String = active.get("id", "")
	for member in party:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		var is_active_turn: bool = _is_human_gm_mode() and not active_id.is_empty() and str(member.get("id", "")) == active_id
		style.bg_color = ThemeColors.BG_CARD if is_active_turn else ThemeColors.BG_INPUT
		style.border_color = ThemeColors.GOLD if is_active_turn else ThemeColors.BORDER
		style.set_border_width_all(2 if is_active_turn else 1)
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
		if is_active_turn and _is_human_gm_mode():
			badge.text = "TOUR"
			badge.add_theme_color_override("font_color", ThemeColors.GOLD)
		elif MultiplayerManager.is_p2p_active() and member.get("clientId", "") == MultiplayerManager.player_id:
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
	call_deferred("_sync_log_layout")

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
		"npc":
			author_color = ThemeColors.get_bbcode_color(ThemeColors.BOT_ACCENT)
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
	if not _can_submit_action():
		return
	input_action.text = ""

	if MultiplayerManager.is_p2p_active() and GameData.has_active_game():
		MultiplayerManager.client_submit_action(action_text)
		return
	_process_local_player_action(action_text)

func _process_local_player_action(action_text: String) -> void:
	var actor := GameData.get_active_member()
	var player_name: String = str(actor.get("name", "Joueur")) if not actor.is_empty() else "Joueur"
	GameData.add_log_entry(player_name, action_text, "player")
	_append_log_entry_bbcode({
		"author": player_name,
		"type": "player",
		"text": action_text,
		"time": Time.get_time_string_from_system()
	})
	if GameData.try_auto_move_from_action(action_text):
		map_panel.refresh()
	GameData.maybe_reveal_investigation_from_action(action_text)
	map_panel.refresh()
	if GameData.active_game.get("gmType", "ai") == "ai":
		_simulate_ai_response(action_text)
	else:
		GameData.set_waiting_for_gm(true)
		GameData.next_turn()
	_apply_role_ui()

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
	_broadcast_gm_message(GameData.get_gm_display_name(), text, "gm")

func _on_gm_npc_send_pressed() -> void:
	var text := gm_npc_input.text.strip_edges()
	if text.is_empty() or opt_gm_npc.selected < 0:
		return
	var meta: String = str(opt_gm_npc.get_item_metadata(opt_gm_npc.selected))
	if meta.is_empty():
		return
	var npc_name := "PNJ"
	if meta == "__custom__":
		if text.contains(":"):
			var parts := text.split(":", false, 1)
			npc_name = parts[0].strip_edges()
			text = parts[1].strip_edges()
			if text.is_empty():
				return
	else:
		npc_name = meta
	gm_npc_input.text = ""
	_broadcast_gm_message(npc_name, "« %s »" % text, "npc")

func _broadcast_gm_message(author: String, text: String, log_type: String) -> void:
	if MultiplayerManager.is_p2p_active() and GameData.has_active_game():
		MultiplayerManager.client_gm_broadcast(author, text, log_type)
		return
	GameData.add_log_entry(author, text, log_type)
	GameData.set_waiting_for_gm(false)
	_append_log_entry_bbcode({
		"author": author,
		"type": log_type,
		"text": text,
		"time": Time.get_time_string_from_system()
	})
	_apply_role_ui()

func _refresh_scene_navigation_ui() -> void:
	var show_nav: bool = _is_human_gm_mode() and _is_mj_controller() and str(GameData.active_game.get("status", "")) == "playing"
	opt_gm_scene.visible = show_nav
	btn_gm_go_to_scene.visible = show_nav
	gm_transitions_vbox.visible = show_nav
	btn_gm_advance_scene.visible = show_nav
	btn_gm_complete_scenario.visible = show_nav
	if not show_nav:
		return

	var scenario := GameData.get_scenario_by_id(GameData.active_game.get("scenarioId", ""))
	var nav := GameData.get_scene_navigation_summary()
	var current_id: String = str(nav.get("currentSceneId", ""))
	var visited: Array = nav.get("visitedSceneIds", [])

	opt_gm_scene.clear()
	for scene in scenario.get("scenes", []):
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var scene_id := str(scene.get("id", ""))
		var label := QuestNavigation.format_picker_label(scene, scene_id == current_id, visited.has(scene_id))
		opt_gm_scene.add_item(label)
		var item_idx := opt_gm_scene.item_count - 1
		opt_gm_scene.set_item_metadata(item_idx, scene_id)
		if scene_id == current_id:
			opt_gm_scene.select(item_idx)

	for child in gm_transitions_vbox.get_children():
		child.queue_free()
	var transitions: Array = nav.get("transitions", [])
	for transition in transitions:
		if typeof(transition) != TYPE_DICTIONARY:
			continue
		var to_id := str(transition.get("to", ""))
		if to_id.is_empty():
			continue
		var btn := Button.new()
		var label := str(transition.get("label", to_id))
		if transition.get("default", false):
			label += " ★"
		btn.text = "→ %s" % label
		btn.pressed.connect(_on_gm_transition_pressed.bind(to_id, label))
		gm_transitions_vbox.add_child(btn)

	if transitions.is_empty():
		var hint := Label.new()
		hint.text = "Scène terminale — clore l'aventure ou sauter ailleurs."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		hint.add_theme_font_size_override("font_size", 11)
		gm_transitions_vbox.add_child(hint)

func _on_gm_go_to_scene_pressed() -> void:
	if opt_gm_scene.selected < 0:
		return
	var scene_id := str(opt_gm_scene.get_item_metadata(opt_gm_scene.selected))
	_execute_scene_navigation(scene_id, "Choix du MJ")

func _on_gm_transition_pressed(to_id: String, label: String) -> void:
	_execute_scene_navigation(to_id, label)

func _on_gm_complete_scenario_pressed() -> void:
	if MultiplayerManager.is_p2p_active():
		MultiplayerManager.client_complete_scenario("Clôture par le MJ")
	else:
		GameData.complete_scenario("Clôture par le MJ")
	_refresh_session_ui()

func _execute_scene_navigation(scene_id: String, reason: String) -> void:
	if MultiplayerManager.is_p2p_active():
		MultiplayerManager.client_go_to_scene(scene_id, reason)
	else:
		GameData.go_to_scene(scene_id, reason)
	_refresh_session_ui()

func _on_advance_scene_pressed() -> void:
	if not _is_human_gm_user():
		return
	if MultiplayerManager.is_p2p_active():
		MultiplayerManager.client_advance_scene()
		_refresh_session_ui()
		return
	var _advanced := GameData.advance_scene()
	_refresh_session_ui()

func _on_net_game_state(state: Dictionary) -> void:
	GameData.apply_server_state(state)
	_refresh_session_ui()

func _on_p2p_log_entry(entry: Dictionary) -> void:
	_append_log_entry_bbcode(entry)
	_apply_role_ui()

func _on_net_dice_result(_res: Dictionary, formatted: String) -> void:
	if not formatted.is_empty():
		dice_result_lbl.text = formatted
	else:
		dice_result_lbl.text = GameData.format_dice_result(_res)


func _on_leave_session_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")
