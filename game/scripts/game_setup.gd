extends Control

@onready var opt_scenario: OptionButton = %OptScenario
@onready var opt_mode: OptionButton = %OptMode
@onready var opt_gm: OptionButton = %OptGm
@onready var opt_main_char: OptionButton = %OptMainChar
@onready var spin_party_size: SpinBox = %SpinPartySize
@onready var bots_container: VBoxContainer = %BotsContainer
@onready var scenario_preview_lbl: RichTextLabel = %ScenarioPreview
@onready var joiner_panel: PanelContainer = %JoinerPanel
@onready var opt_joiner_char: OptionButton = %OptJoinerChar

var available_scenarios: Array = []
var available_chars: Array = []
var available_bots: Array = []
var selected_bot_ids: Array[String] = []
var _waiting_server_start: bool = false
var _is_joiner: bool = false

func _ready() -> void:
	%BtnBack.pressed.connect(_on_back_pressed)
	%BtnStartGame.pressed.connect(_on_start_game_pressed)
	%BtnJoinerRegister.pressed.connect(_on_joiner_register_pressed)
	
	_setup_options()
	_populate_data()
	_update_net_panel()
	_apply_host_joiner_ui()
	
	opt_scenario.item_selected.connect(_on_scenario_selected)
	spin_party_size.value_changed.connect(_on_party_size_changed)
	NetworkClient.connected.connect(func(_id, _name): _update_net_panel())
	NetworkClient.disconnected.connect(_update_net_panel)
	NetworkClient.game_started.connect(_on_game_started_from_server)
	NetworkClient.lobby_updated.connect(_on_lobby_updated)
	NetworkClient.error_received.connect(_on_server_error)

func _setup_options() -> void:
	opt_mode.clear()
	opt_mode.add_item("Solo (Joueur + Bots éventuels)", 0)
	opt_mode.set_item_metadata(0, "solo")
	opt_mode.add_item("Multijoueur (Local / Réseau)", 1)
	opt_mode.set_item_metadata(1, "multi")
	
	opt_gm.clear()
	opt_gm.add_item("🤖 Maître du Jeu IA (Adaptatif)", 0)
	opt_gm.set_item_metadata(0, "ai")
	opt_gm.add_item("👤 Maître du Jeu Humain", 1)
	opt_gm.set_item_metadata(1, "human")

func _populate_data() -> void:
	available_scenarios = GameData.get_scenarios()
	available_chars = GameData.get_characters()
	available_bots = GameData.get_bots()
	
	opt_scenario.clear()
	var preselected_id: String = ""
	if get_tree().has_meta("preselected_scenario_id"):
		preselected_id = get_tree().get_meta("preselected_scenario_id")
		get_tree().remove_meta("preselected_scenario_id")
		
	var selected_idx := 0
	for i in range(available_scenarios.size()):
		var s: Dictionary = available_scenarios[i]
		var title: String = s.get("title", "Sans titre")
		var qf: String = s.get("questFormat", "oneshot")
		var icon := "⚔️" if qf == "oneshot" else ("🏰" if qf == "long" else "🔍")
		opt_scenario.add_item("%s %s" % [icon, title], i)
		opt_scenario.set_item_metadata(i, s.get("id"))
		if s.get("id") == preselected_id:
			selected_idx = i
			
	if not available_scenarios.is_empty():
		opt_scenario.selected = selected_idx
		_on_scenario_selected(selected_idx)
		
	opt_main_char.clear()
	opt_joiner_char.clear()
	for i in range(available_chars.size()):
		var c: Dictionary = available_chars[i]
		var label := "%s (%s %s)" % [c.get("name"), c.get("race"), c.get("class")]
		opt_main_char.add_item(label, i)
		opt_main_char.set_item_metadata(i, c.get("id"))
		opt_joiner_char.add_item(label, i)
		opt_joiner_char.set_item_metadata(i, c.get("id"))
		
	_refresh_bots_checkboxes()

func _apply_host_joiner_ui() -> void:
	_is_joiner = NetworkClient.is_server_connected() and not NetworkClient.is_host()
	joiner_panel.visible = _is_joiner
	if _is_joiner:
		%BtnStartGame.visible = false
		opt_scenario.disabled = true
		opt_mode.disabled = true
		opt_gm.disabled = true
		spin_party_size.editable = false
		for child in bots_container.get_children():
			child.disabled = true
		%LblJoinerHint.text = "En attente que l'hôte lance la partie. Confirmez votre personnage ci-dessous."
	else:
		%BtnStartGame.visible = true

func _on_lobby_updated(_host_id: String, _players: Array) -> void:
	_apply_host_joiner_ui()
	_update_net_panel()

func _on_scenario_selected(idx: int) -> void:
	if idx < 0 or idx >= available_scenarios.size():
		scenario_preview_lbl.text = ""
		return
	var scn: Dictionary = available_scenarios[idx]
	var text := "[b]%s[/b]\n%s\n\n[color=#9a8870]Cadre : %s[/color]" % [
		scn.get("title", ""),
		scn.get("synopsis", ""),
		scn.get("setting", "")
	]
	scenario_preview_lbl.text = text

func _refresh_bots_checkboxes() -> void:
	for child in bots_container.get_children():
		child.queue_free()
		
	for b in available_bots:
		var check := CheckBox.new()
		check.text = "🤖 %s (%s %s) - %s" % [
			b.get("name", "Bot"),
			b.get("race", ""),
			b.get("class", ""),
			b.get("personality", "")
		]
		var bot_id: String = b.get("id", "")
		check.toggled.connect(func(toggled: bool):
			if toggled and not selected_bot_ids.has(bot_id):
				selected_bot_ids.append(bot_id)
			elif not toggled and selected_bot_ids.has(bot_id):
				selected_bot_ids.erase(bot_id)
		)
		bots_container.add_child(check)

func _on_party_size_changed(_val: float) -> void:
	pass

func _build_character_from_option(opt: OptionButton) -> Dictionary:
	if opt.item_count == 0 or opt.selected < 0:
		var blank := GameData.create_blank_character()
		blank["name"] = NetworkClient.player_name if NetworkClient.is_server_connected() else "Aventurier"
		blank["isPlayer"] = true
		blank["isHuman"] = true
		blank["isBot"] = false
		return blank
	var char_id: String = opt.get_item_metadata(opt.selected)
	var main_char := GameData.get_character_by_id(char_id)
	if main_char.is_empty():
		return _build_character_from_option(OptionButton.new())
	var member := main_char.duplicate(true)
	member["isPlayer"] = true
	member["isHuman"] = true
	member["isBot"] = false
	return member

func _on_joiner_register_pressed() -> void:
	if not NetworkClient.is_server_connected():
		return
	NetworkClient.register_character(_build_character_from_option(opt_joiner_char))
	%LblJoinerHint.text = "✓ Personnage enregistré — en attente du lancement par l'hôte."

func _on_start_game_pressed() -> void:
	if _is_joiner:
		return
	if available_scenarios.is_empty():
		return
	
	var scn_idx := opt_scenario.selected
	var scn_id: String = opt_scenario.get_item_metadata(scn_idx)
	var scn := GameData.get_scenario_by_id(scn_id)
	
	var mode_idx := opt_mode.selected
	var mode_val: String = opt_mode.get_item_metadata(mode_idx)
	
	var gm_idx := opt_gm.selected
	var gm_val: String = opt_gm.get_item_metadata(gm_idx)
	
	var party: Array = [_build_character_from_option(opt_main_char)]
		
	for bot_id in selected_bot_ids:
		var bot := GameData.get_bot_by_id(bot_id)
		if not bot.is_empty():
			var bot_member := bot.duplicate(true)
			bot_member["isPlayer"] = false
			bot_member["isHuman"] = false
			bot_member["isBot"] = true
			party.append(bot_member)
			
	var quest_format: String = scn.get("questFormat", "oneshot")
	var party_size := int(spin_party_size.value)
	
	if NetworkClient.is_server_connected():
		NetworkClient.register_character(party[0])
		_waiting_server_start = true
		%BtnStartGame.disabled = true
		%BtnStartGame.text = "⏳ Lancement via serveur..."
		NetworkClient.start_game(scn_id, party, mode_val, gm_val, quest_format, party_size)
		return
	
	_start_local_game(scn_id, mode_val, gm_val, quest_format, party)

func _start_local_game(scn_id: String, mode_val: String, gm_val: String, quest_format: String, party: Array) -> void:
	GameData.create_new_game(scn_id, mode_val, gm_val, quest_format, party)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _update_net_panel() -> void:
	if not has_node("%NetStatusLabel"):
		return
	if NetworkClient.is_server_connected():
		var role := "hôte" if NetworkClient.is_host() else "invité"
		%NetStatusLabel.text = "● Serveur (%s) : %s" % [role, NetworkClient.server_url]
		%NetStatusLabel.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		%NetStatusLabel.text = "○ Serveur non connecté — configurez l'URL depuis le menu principal"
		%NetStatusLabel.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)

func _on_game_started_from_server(_game_id: String, state: Dictionary) -> void:
	_waiting_server_start = false
	%BtnStartGame.disabled = false
	%BtnStartGame.text = "🚀 Lancer l'Aventure !"
	GameData.apply_server_state(state)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _on_server_error(msg: String) -> void:
	if _waiting_server_start:
		_waiting_server_start = false
		%BtnStartGame.disabled = false
		%BtnStartGame.text = "🚀 Lancer l'Aventure !"
	net_status_lbl_fallback(msg)

func net_status_lbl_fallback(msg: String) -> void:
	if has_node("%NetStatusLabel"):
		%NetStatusLabel.text = msg
		%NetStatusLabel.add_theme_color_override("font_color", ThemeColors.DANGER)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")
