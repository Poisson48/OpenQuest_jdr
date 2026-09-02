extends Control

@onready var resume_panel: PanelContainer = %ResumePanel
@onready var resume_label: Label = %ResumeLabel
@onready var modes_panel: PanelContainer = %ModesPanel
@onready var server_url_input: LineEdit = %ServerUrlInput
@onready var player_name_input: LineEdit = %PlayerNameInput
@onready var net_status_lbl: Label = %NetStatusLabel
@onready var lobby_players_vbox: VBoxContainer = %LobbyPlayersVBox
@onready var opt_lobby_char: OptionButton = %OptLobbyChar

func _ready() -> void:
	%BtnPlay.pressed.connect(_on_play_pressed)
	%BtnModes.pressed.connect(_on_modes_pressed)
	%BtnDiscover.pressed.connect(_on_discover_pressed)
	%BtnResume.pressed.connect(_on_resume_pressed)
	%BtnCloseModes.pressed.connect(func(): modes_panel.visible = false)
	%BtnConnectServer.pressed.connect(_on_connect_server_pressed)
	%BtnRegisterChar.pressed.connect(_on_register_character_pressed)
	
	%BtnModeLong.pressed.connect(func(): _start_with_format("long"))
	%BtnModeOneshot.pressed.connect(func(): _start_with_format("oneshot"))
	%BtnModeInvestigation.pressed.connect(func(): _start_with_format("investigation"))
	
	NetworkClient.connected.connect(_on_net_connected)
	NetworkClient.disconnected.connect(_on_net_disconnected)
	NetworkClient.error_received.connect(_on_net_error)
	NetworkClient.game_started.connect(_on_remote_game_started)
	NetworkClient.lobby_updated.connect(_on_lobby_updated)
	
	modes_panel.visible = false
	server_url_input.text = NetworkClient.server_url
	player_name_input.text = NetworkClient.player_name
	_populate_lobby_characters()
	_update_net_status()
	_refresh_lobby_players()
	_check_resume_state()

func _populate_lobby_characters() -> void:
	opt_lobby_char.clear()
	var chars := GameData.get_characters()
	if chars.is_empty():
		opt_lobby_char.add_item("Aventurier (par défaut)", 0)
		opt_lobby_char.set_item_metadata(0, "")
	else:
		for i in range(chars.size()):
			var c: Dictionary = chars[i]
			opt_lobby_char.add_item("%s (%s %s)" % [c.get("name"), c.get("race"), c.get("class")], i)
			opt_lobby_char.set_item_metadata(i, c.get("id"))

func _on_register_character_pressed() -> void:
	if not NetworkClient.is_server_connected():
		return
	var char_data := _selected_lobby_character()
	NetworkClient.register_character(char_data)
	net_status_lbl.text = "✓ Personnage enregistré : %s" % char_data.get("name", "?")
	net_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)

func _selected_lobby_character() -> Dictionary:
	if opt_lobby_char.item_count == 0:
		return GameData.create_blank_character()
	var char_id: String = opt_lobby_char.get_item_metadata(opt_lobby_char.selected)
	if char_id.is_empty():
		var blank := GameData.create_blank_character()
		blank["name"] = NetworkClient.player_name
		return blank
	var main_char := GameData.get_character_by_id(char_id)
	if main_char.is_empty():
		return GameData.create_blank_character()
	var member := main_char.duplicate(true)
	member["isPlayer"] = true
	member["isHuman"] = true
	member["isBot"] = false
	return member

func _on_connect_server_pressed() -> void:
	NetworkClient.connect_to_server(server_url_input.text, player_name_input.text)
	net_status_lbl.text = "Connexion en cours..."
	net_status_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)

func _on_net_connected(_player_id: String, _player_name: String) -> void:
	_update_net_status()
	_register_character_if_needed()

func _on_net_disconnected() -> void:
	_update_net_status()
	_refresh_lobby_players()

func _register_character_if_needed() -> void:
	if opt_lobby_char.item_count > 0:
		_on_register_character_pressed()

func _on_net_error(message: String) -> void:
	net_status_lbl.text = message
	net_status_lbl.add_theme_color_override("font_color", ThemeColors.DANGER)

func _on_lobby_updated(_host_id: String, _players: Array) -> void:
	_refresh_lobby_players()

func _refresh_lobby_players() -> void:
	for child in lobby_players_vbox.get_children():
		child.queue_free()
	
	if not NetworkClient.is_server_connected():
		var empty_lbl := Label.new()
		empty_lbl.text = "Connectez-vous pour voir le lobby."
		empty_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		lobby_players_vbox.add_child(empty_lbl)
		return
	
	if NetworkClient.lobby_players.is_empty():
		var solo_lbl := Label.new()
		solo_lbl.text = "En attente d'autres joueurs..."
		solo_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		lobby_players_vbox.add_child(solo_lbl)
	
	for player in NetworkClient.lobby_players:
		var p: Dictionary = player
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		var host_tag := " [Hôte]" if p.get("isHost", false) else ""
		var char_name := ""
		var character = p.get("character")
		if character is Dictionary and not character.is_empty():
			char_name = " — %s" % character.get("name", "?")
		name_lbl.text = "• %s%s%s" % [p.get("playerName", "?"), host_tag, char_name]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if p.get("playerId", "") == NetworkClient.get_player_id():
			name_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		else:
			name_lbl.add_theme_color_override("font_color", ThemeColors.TEXT)
		row.add_child(name_lbl)
		lobby_players_vbox.add_child(row)

func _update_net_status() -> void:
	if NetworkClient.is_server_connected():
		var host_hint := " (hôte)" if NetworkClient.is_host() else ""
		net_status_lbl.text = "● Connecté à %s (%s%s)" % [NetworkClient.server_url, NetworkClient.player_name, host_hint]
		net_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		net_status_lbl.text = "○ Hors ligne — lancez le serveur puis connectez-vous"
		net_status_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)

func _on_remote_game_started(_game_id: String, state: Dictionary) -> void:
	GameData.apply_server_state(state)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _check_resume_state() -> void:
	if GameData.has_active_game():
		var scn_title: String = GameData.active_game.get("scenarioTitle", "Partie en cours")
		resume_label.text = "Une partie est en cours sur « %s »." % scn_title
		resume_panel.visible = true
	else:
		resume_panel.visible = false

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game_setup.tscn")

func _on_modes_pressed() -> void:
	modes_panel.visible = true

func _on_discover_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")

func _on_resume_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _start_with_format(quest_format: String) -> void:
	var scns := GameData.get_scenarios(quest_format if quest_format != "investigation" else "", "investigation" if quest_format == "investigation" else "")
	if not scns.is_empty():
		get_tree().set_meta("preselected_scenario_id", scns[0].get("id"))
	get_tree().change_scene_to_file("res://scenes/game_setup.tscn")
