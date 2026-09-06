extends Control

const QuestNavigation = preload("res://scripts/quest_navigation.gd")
const CharacterSheetScript = preload("res://scripts/ui/character_sheet.gd")
const PlayerSessionHudScript = preload("res://scripts/ui/player_session_hud.gd")

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
@onready var dice_section: PanelContainer = %DiceSection
@onready var action_section: PanelContainer = %ActionSection
@onready var suggestions_scroll: ScrollContainer = %SuggestionsScroll
@onready var action_input_row: HBoxContainer = %ActionInputHBox
@onready var chk_secret_dice: CheckBox = %ChkSecretDice
@onready var net_status_lbl: Label = %NetStatusLabel
@onready var map_panel: PanelContainer = %MapPanel
@onready var main_layout: VBoxContainer = %MainLayout
@onready var header_bar: PanelContainer = %HeaderBar
@onready var top_band: HBoxContainer = %TopBand
@onready var log_panel: PanelContainer = %LogPanel
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

const MAP_PANEL_MIN_HEIGHT := 220.0

var session_seconds: int = 0
var timer_active: bool = true
var _session_start_msec: int = 0
var _character_sheet: Control = null
var _player_hud: Control = null
var _immersive_player: bool = false
var _cached_log_len: int = -1
var _log_stick_bottom: bool = true
var _confirm_dialog: ConfirmationDialog = null

# La structure de la page vit dans session.tscn — le script ne fait que styler
# et brancher, il ne crée aucun conteneur à l'exécution :
#
#   MainLayout (VBox, plein écran)
#     ├─ HeaderBar                     hauteur du contenu
#     ├─ TopBand (HBox, expand)        bande haute : les deux colonnes partagent
#     │    │                           forcément la même hauteur
#     │    ├─ Sidebar    : PartyPanel (hauteur fixe, scroll) + GmPanel (remplit
#     │    │               le reste, clippé, sans ScrollContainer)
#     │    └─ MainGameArea : LogPanel (expand, scroll interne du RichTextLabel)
#     │                      + DiceSection + ActionSection (hauteur du contenu)
#     └─ MapPanel (expand)             carte pleine largeur
#
# Toutes les hauteurs sont pilotées par des tailles minimales constantes : aucune
# saisie, aucun jet de dés et aucun clic carte ne peut faire bouger la bande.

func _configure_layout() -> void:
	_configure_log_readability()
	_bind_gm_shortcuts()

func _bind_gm_shortcuts() -> void:
	if gm_input and not gm_input.gui_input.is_connected(_on_gm_input_gui):
		gm_input.gui_input.connect(_on_gm_input_gui)
	if gm_npc_input and not gm_npc_input.gui_input.is_connected(_on_gm_npc_input_gui):
		gm_npc_input.gui_input.connect(_on_gm_npc_input_gui)

func _on_gm_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
			_on_gm_send_pressed()
			gm_input.accept_event()

func _on_gm_npc_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
			_on_gm_npc_send_pressed()
			gm_npc_input.accept_event()

func _configure_log_readability() -> void:
	# Le journal scrolle en interne (fit_content off) : le cadre garde sa hauteur
	# quelle que soit la longueur de l'histoire.
	log_label.fit_content = false
	log_label.scroll_active = true
	log_label.scroll_following = true
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("normal_font_size", 15)
	log_label.add_theme_color_override("default_color", ThemeColors.TEXT)
	log_label.add_theme_constant_override("line_separation", 6)

	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BG_INPUT
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	log_panel.add_theme_stylebox_override("panel", style)

func _sync_log_layout() -> void:
	await get_tree().process_frame
	if not _log_stick_bottom or log_label == null:
		return
	var lines := log_label.get_line_count()
	if lines > 0:
		log_label.scroll_to_line(maxi(0, lines - 1))

func _is_log_at_bottom() -> bool:
	if log_label == null or not log_label.scroll_active:
		return true
	var bar := log_label.get_v_scroll_bar()
	if bar == null:
		return true
	return bar.value >= bar.max_value - 24.0

func _ready() -> void:
	_session_start_msec = Time.get_ticks_msec()
	if not GameData.has_active_game():
		_create_fallback_game()
	_configure_layout()
	_refresh_session_ui()

	_character_sheet = CharacterSheetScript.new()
	add_child(_character_sheet)

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
	btn_gm_complete_scenario.add_theme_color_override("font_color", ThemeColors.DANGER)
	btn_back_hub.add_theme_color_override("font_color", ThemeColors.DANGER)

	_setup_quick_dice_buttons()
	_setup_suggestion_buttons()
	_connect_network_signals()
	_connect_game_data_signals()

	_refresh_session_ui()
	_update_net_status()
	_apply_role_ui()
	if OS.is_debug_build():
		_print_session_debug()
		print("[SESSION DEBUG] role human_gm=%s mj=%s player_view=%s action_vis=%s" % [
			_is_human_gm_mode(), _is_mj_controller(), _is_player_view(), action_section.visible
		])

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
	# Solo / local : le rôle choisi (gm vs player) pilote la vue.
	return MultiplayerManager.is_mj() or MultiplayerManager.is_gm

func _local_client_id() -> String:
	if MultiplayerManager.is_p2p_active():
		return MultiplayerManager.player_id
	return ""

func _is_player_view() -> bool:
	# Vue immersive carte : joueur (pas MJ), y compris solo forcé en player.
	if bool(GameData.active_game.get("forcePlayerView", false)):
		return true
	if not _is_human_gm_mode():
		# MJ IA : le joueur local joue — carte immersive.
		return true
	return not _is_mj_controller()

func _ensure_player_hud() -> void:
	if _player_hud != null:
		return
	_player_hud = PlayerSessionHudScript.new()
	add_child(_player_hud)
	_player_hud.leave_pressed.connect(_on_leave_session_pressed)
	_player_hud.open_character.connect(_open_character_sheet)
	_player_hud.action_submitted.connect(func(t: String):
		input_action.text = t
		_on_send_action_pressed()
	)
	_player_hud.roll_requested.connect(func(formula: String):
		custom_dice_input.text = formula
		_on_roll_custom_dice()
	)

func _apply_immersive_player_layout(on: bool) -> void:
	# Vue joueur : on masque l'en-tête et toute la bande haute, la carte prend
	# alors la totalité de MainLayout. Aucun nœud n'est déplacé.
	_immersive_player = on
	_ensure_player_hud()
	_player_hud.visible = on

	header_bar.visible = not on
	top_band.visible = not on

	map_panel.custom_minimum_size = Vector2.ZERO if on else Vector2(0, MAP_PANEL_MIN_HEIGHT)
	if on:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.02, 0.02, 0.02, 1.0)
		flat.set_border_width_all(0)
		flat.set_corner_radius_all(0)
		flat.content_margin_left = 0
		flat.content_margin_right = 0
		flat.content_margin_top = 0
		flat.content_margin_bottom = 0
		map_panel.add_theme_stylebox_override("panel", flat)
	else:
		map_panel.remove_theme_stylebox_override("panel")
	if map_panel.has_method("set_immersive"):
		map_panel.set_immersive(on)
	# Un seul refresh : éviter le double configure qui reset le cadrage.
	if on and map_panel.has_method("refresh"):
		map_panel.call_deferred("refresh")

	if on:
		_player_hud.set_title(GameData.get_scenario_display_title())
		_player_hud.set_party(GameData.active_game.get("party", []))
		var log_entries: Array = GameData.active_game.get("log", [])
		if not log_entries.is_empty():
			var last: Dictionary = log_entries[-1]
			_player_hud.show_toast("%s — %s" % [last.get("speaker", last.get("author", "")), last.get("text", "")])

func _apply_role_ui() -> void:
	var human_gm: bool = _is_human_gm_mode()
	var mj: bool = _is_mj_controller()
	var completed: bool = str(GameData.active_game.get("status", "")) == "completed"
	var player_view := _is_player_view() and not completed
	var gm_view := human_gm and mj and not player_view

	gm_panel.visible = gm_view and not completed
	# Cadre « action joueur » toujours visible hors immersif (maquette) : le MJ
	# garde les libellés de tour, seules les commandes joueur disparaissent.
	action_section.visible = not player_view and not completed
	suggestions_scroll.visible = not gm_view
	action_input_row.visible = not gm_view
	btn_advance_scene.visible = not player_view and not (human_gm and mj)
	chk_secret_dice.visible = gm_view and not completed

	if gm_view:
		_populate_gm_npcs()
		_update_gm_wait_label()
		_refresh_scene_navigation_ui()

	_apply_immersive_player_layout(player_view)
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
		_style_gm_panel_waiting(true)
	else:
		lbl_gm_wait.text = "En attente d'une action joueur..."
		lbl_gm_wait.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		_style_gm_panel_waiting(false)

func _style_gm_panel_waiting(waiting: bool) -> void:
	if gm_panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BG_CARD
	style.border_color = ThemeColors.GOLD if waiting else ThemeColors.BORDER
	style.set_border_width_all(2 if waiting else 1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	gm_panel.add_theme_stylebox_override("panel", style)

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

func _process(_delta: float) -> void:
	if timer_active:
		session_seconds = int((Time.get_ticks_msec() - _session_start_msec) / 1000.0)
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
	var scn_id: String = scns[0].get("id", "demo-crypte") if not scns.is_empty() else "demo-crypte"
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
	var progress_text := QuestNavigation.format_progress_label(scenario, state)
	scene_progress_lbl.text = progress_text
	scene_progress_lbl.tooltip_text = progress_text

	_render_party_list()
	# Ne reconstruit le journal que s'il a changé (un clic carte ne doit rien toucher).
	var log_entries: Array = state.get("log", [])
	var log_len := log_entries.size()
	if log_len != _cached_log_len:
		_render_log()
		_cached_log_len = log_len
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
	for member_variant in party:
		var member: Dictionary = member_variant
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		var is_active_turn: bool = _is_human_gm_mode() and not active_id.is_empty() and str(member.get("id", "")) == active_id
		style.bg_color = ThemeColors.BG_CARD if is_active_turn else ThemeColors.BG_INPUT
		style.border_color = ThemeColors.GOLD if is_active_turn else ThemeColors.BORDER
		style.set_border_width_all(2 if is_active_turn else 1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", style)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.tooltip_text = "Ouvrir la fiche de %s" % member.get("name", "ce personnage")
		var captured: Dictionary = member.duplicate(true)
		panel.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_open_character_sheet(captured)
		)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		panel.add_child(row)

		var ppath := str(member.get("portrait", member.get("image", ""))).strip_edges()
		var cut: Texture2D = null
		if not ppath.is_empty():
			cut = MapData.load_token_cutout(ppath, 64)
		if cut != null:
			var thumb := TextureRect.new()
			thumb.custom_minimum_size = Vector2(24, 24)
			thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			thumb.texture = cut
			row.add_child(thumb)
		else:
			var initial := Label.new()
			initial.text = str(member.get("name", "?")).substr(0, 1).to_upper()
			initial.custom_minimum_size = Vector2(24, 24)
			initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			initial.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
			initial.add_theme_font_size_override("font_size", 12)
			initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(initial)

		var name_lbl := Label.new()
		name_lbl.text = "%s · PV %d · CA %d" % [
			member.get("name", "Aventurier"),
			member.get("hp", 10),
			member.get("ac", 10)
		]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.clip_text = true
		row.add_child(name_lbl)

		var badge := Label.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override("font_size", 11)
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
			badge.text = "J"
			badge.add_theme_color_override("font_color", ThemeColors.SUCCESS)
		row.add_child(badge)

		party_container.add_child(panel)

func _open_character_sheet(member: Dictionary) -> void:
	if _character_sheet == null:
		_character_sheet = CharacterSheetScript.new()
		add_child(_character_sheet)
	_character_sheet.open(member)

func _render_log() -> void:
	_log_stick_bottom = _is_log_at_bottom()
	var log_entries: Array = GameData.active_game.get("log", [])

	log_label.text = ""
	for entry in log_entries:
		_append_log_entry_bbcode(entry, false)
	call_deferred("_sync_log_layout")

	if _immersive_player and _player_hud != null and not log_entries.is_empty():
		var last: Dictionary = log_entries[-1]
		_player_hud.show_toast("%s — %s" % [last.get("speaker", last.get("author", "")), last.get("text", "")])

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
			
	var formatted := "[color=#%s][font_size=15][b]%s[/b][/font_size][/color] [color=#9a8870][font_size=12]%s[/font_size][/color]\n[font_size=15]%s[/font_size]\n" % [
		author_color, author, time, text
	]
	log_label.append_text(formatted)
	if auto_scroll:
		_log_stick_bottom = true
		call_deferred("_sync_log_layout")

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

func _roll_dice_formula(formula: String) -> void:
	if MultiplayerManager.is_p2p_active() and GameData.has_active_game():
		MultiplayerManager.client_request_dice_roll(formula)
		return

	var res := GameData.roll_dice(formula)
	if res.has("error"):
		dice_result_lbl.text = str(res["error"])
		return
	var formatted := GameData.format_dice_result(res)
	# Le bandeau dés est un Label : on retire le BBCode du texte partagé.
	var plain := formatted.replace("[b]", "").replace("[/b]", "")
	dice_result_lbl.text = plain
	# Jet secret MJ : visible localement uniquement.
	if chk_secret_dice.button_pressed and _is_mj_controller():
		dice_result_lbl.text = "🤫 %s" % plain
		return
	GameData.add_log_entry("Dé", formatted, "dice")

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
	# add_log_entry → save → active_game_updated → _render_log : une seule fois.
	GameData.add_log_entry(author, text, log_type)
	GameData.set_waiting_for_gm(false)
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
	_ask_confirm(
		"Clore l'aventure ?",
		"Cette action est définitive. La session passera en statut terminé.",
		func():
			if MultiplayerManager.is_p2p_active():
				MultiplayerManager.client_complete_scenario("Clôture par le MJ")
			else:
				GameData.complete_scenario("Clôture par le MJ")
			_refresh_session_ui()
	)

func _ask_confirm(title: String, body: String, on_ok: Callable) -> void:
	if _confirm_dialog == null:
		_confirm_dialog = ConfirmationDialog.new()
		_confirm_dialog.ok_button_text = "Confirmer"
		_confirm_dialog.cancel_button_text = "Annuler"
		add_child(_confirm_dialog)
	for c in _confirm_dialog.confirmed.get_connections():
		_confirm_dialog.confirmed.disconnect(c.callable)
	_confirm_dialog.title = title
	_confirm_dialog.dialog_text = body
	_confirm_dialog.confirmed.connect(on_ok, CONNECT_ONE_SHOT)
	_confirm_dialog.popup_centered()

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
	# Le state réseau peut aussi rafraîchir le journal ; on évite un doublon local.
	_log_stick_bottom = _is_log_at_bottom()
	_append_log_entry_bbcode(entry, _log_stick_bottom)
	_apply_role_ui()

func _on_net_dice_result(_res: Dictionary, formatted: String) -> void:
	var text := formatted if not formatted.is_empty() else GameData.format_dice_result(_res)
	dice_result_lbl.text = text.replace("[b]", "").replace("[/b]", "")


func _on_leave_session_pressed() -> void:
	_ask_confirm(
		"Quitter la session ?",
		"Vous quittez la table et retournez au hub.",
		func():
			get_tree().change_scene_to_file("res://scenes/hub.tscn")
	)
