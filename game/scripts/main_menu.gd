extends Control

@onready var resume_panel: PanelContainer = %ResumePanel
@onready var resume_label: Label = %ResumeLabel
@onready var modes_panel: PanelContainer = %ModesPanel
@onready var server_url_input: LineEdit = %ServerUrlInput
@onready var player_name_input: LineEdit = %PlayerNameInput
@onready var net_status_lbl: Label = %NetStatusLabel
@onready var lobby_players_vbox: VBoxContainer = %LobbyPlayersVBox
@onready var opt_lobby_char: OptionButton = %OptLobbyChar

@onready var pooling_url_input: LineEdit = %PoolingUrlInput
@onready var pooling_status_lbl: Label = %PoolingStatusLabel
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var room_code_lbl: Label = %RoomCodeLabel
@onready var p2p_status_lbl: Label = %P2pStatusLabel
@onready var pooling_players_vbox: VBoxContainer = %PoolingPlayersVBox
@onready var opt_pooling_char: OptionButton = %OptPoolingChar
@onready var opt_pooling_role: OptionButton = %OptPoolingRole
@onready var btn_create_room: Button = %BtnCreateRoom
@onready var btn_join_room: Button = %BtnJoinRoom
@onready var btn_rejoin_room: Button = %BtnRejoinRoom
@onready var btn_launch_pooling: Button = %BtnLaunchPoolingGame
@onready var lbl_waiting_mj: Label = %LblWaitingMj

func _ready() -> void:
	%BtnPlay.pressed.connect(_on_play_pressed)
	%BtnModes.pressed.connect(_on_modes_pressed)
	%BtnDiscover.pressed.connect(_on_discover_pressed)
	%BtnResume.pressed.connect(_on_resume_pressed)
	%BtnCloseModes.pressed.connect(func(): modes_panel.visible = false)
	%BtnConnectServer.pressed.connect(_on_connect_server_pressed)
	%BtnRegisterChar.pressed.connect(_on_register_character_pressed)
	%BtnConnectPooling.pressed.connect(_on_connect_pooling_pressed)
	%BtnCreateRoom.pressed.connect(_on_create_room_pressed)
	%BtnJoinRoom.pressed.connect(_on_join_room_pressed)
	%BtnRejoinRoom.pressed.connect(_on_rejoin_room_pressed)
	%BtnLeaveRoom.pressed.connect(_on_leave_room_pressed)
	%BtnPoolingRegisterChar.pressed.connect(_on_pooling_register_char_pressed)
	opt_pooling_role.item_selected.connect(_on_pooling_role_changed)

	%BtnModeLong.pressed.connect(func(): _start_with_format("long"))
	%BtnModeOneshot.pressed.connect(func(): _start_with_format("oneshot"))
	%BtnModeInvestigation.pressed.connect(func(): _start_with_format("investigation"))

	NetworkClient.connected.connect(_on_net_connected)
	NetworkClient.disconnected.connect(_on_net_disconnected)
	NetworkClient.error_received.connect(_on_net_error)
	NetworkClient.game_started.connect(_on_remote_game_started)
	NetworkClient.lobby_updated.connect(_on_lobby_updated)

	MultiplayerManager.room_updated.connect(_on_pooling_room_updated)
	MultiplayerManager.room_left.connect(_on_pooling_room_left)
	MultiplayerManager.room_closed.connect(_on_pooling_room_closed)
	MultiplayerManager.lobby_rooms_updated.connect(_on_pooling_lobby_updated)
	MultiplayerManager.p2p_host_started.connect(_on_p2p_host_started)
	MultiplayerManager.p2p_connected.connect(_on_p2p_connected)
	MultiplayerManager.p2p_error.connect(_on_p2p_error)
	MultiplayerManager.game_started.connect(_on_pooling_game_started)

	btn_launch_pooling.pressed.connect(_on_launch_pooling_pressed)

	modes_panel.visible = false
	server_url_input.text = NetworkClient.server_url
	player_name_input.text = NetworkClient.player_name
	pooling_url_input.text = MultiplayerManager.pooling_url
	_setup_pooling_roles()
	_populate_lobby_characters()
	_populate_pooling_characters()
	_update_net_status()
	_update_pooling_status()
	_update_pooling_role_ui()
	_refresh_lobby_players()
	_refresh_pooling_players()
	_update_pooling_launch_ui()
	_check_resume_state()

func _setup_pooling_roles() -> void:
	opt_pooling_role.clear()
	opt_pooling_role.add_item("👑 Maître du Jeu (MJ)", 0)
	opt_pooling_role.set_item_metadata(0, "gm")
	opt_pooling_role.add_item("⚔️ Joueur", 1)
	opt_pooling_role.set_item_metadata(1, "player")
	opt_pooling_role.selected = 0 if MultiplayerManager.is_mj() else 1

func _on_pooling_role_changed(_idx: int) -> void:
	var role: String = opt_pooling_role.get_item_metadata(opt_pooling_role.selected)
	MultiplayerManager.set_player_role(role)
	_update_pooling_role_ui()

func _update_pooling_role_ui() -> void:
	var is_mj := MultiplayerManager.is_mj()
	var in_room := MultiplayerManager.is_in_room()
	btn_create_room.disabled = not is_mj or in_room or not MultiplayerManager.is_pooling_connected()
	btn_join_room.disabled = is_mj or in_room or not MultiplayerManager.is_pooling_connected()
	btn_rejoin_room.disabled = is_mj or in_room or MultiplayerManager.last_room_code.is_empty() or not MultiplayerManager.is_pooling_connected()
	room_code_input.editable = not is_mj and not in_room
	if not MultiplayerManager.last_room_code.is_empty() and room_code_input.text.is_empty():
		room_code_input.text = MultiplayerManager.last_room_code

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

func _populate_pooling_characters() -> void:
	opt_pooling_char.clear()
	var chars := GameData.get_characters()
	if chars.is_empty():
		opt_pooling_char.add_item("Aventurier (par défaut)", 0)
		opt_pooling_char.set_item_metadata(0, "")
	else:
		for i in range(chars.size()):
			var c: Dictionary = chars[i]
			opt_pooling_char.add_item("%s (%s %s)" % [c.get("name"), c.get("race"), c.get("class")], i)
			opt_pooling_char.set_item_metadata(i, c.get("id"))

func _selected_pooling_character() -> Dictionary:
	if opt_pooling_char.item_count == 0:
		return GameData.create_blank_character()
	var char_id: String = opt_pooling_char.get_item_metadata(opt_pooling_char.selected)
	if char_id.is_empty():
		var blank := GameData.create_blank_character()
		blank["name"] = MultiplayerManager.player_name
		return blank
	var main_char := GameData.get_character_by_id(char_id)
	if main_char.is_empty():
		return GameData.create_blank_character()
	var member := main_char.duplicate(true)
	member["isPlayer"] = true
	member["isHuman"] = true
	member["isBot"] = false
	return member

func _on_connect_pooling_pressed() -> void:
	MultiplayerManager.player_name = player_name_input.text.strip_edges()
	if MultiplayerManager.player_name.is_empty():
		MultiplayerManager.player_name = "Joueur"
	var role: String = opt_pooling_role.get_item_metadata(opt_pooling_role.selected)
	MultiplayerManager.set_player_role(role)
	MultiplayerManager.connect_pooling(pooling_url_input.text, MultiplayerManager.player_name)
	pooling_status_lbl.text = "Connexion pooling en cours..."
	pooling_status_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_update_pooling_role_ui()

func _on_create_room_pressed() -> void:
	if not MultiplayerManager.is_mj():
		pooling_status_lbl.text = "Seul le MJ peut créer une partie."
		return
	if not MultiplayerManager.is_pooling_connected():
		pooling_status_lbl.text = "Connectez-vous au pooling d'abord."
		return
	MultiplayerManager.create_room("Partie de %s" % MultiplayerManager.player_name)

func _on_join_room_pressed() -> void:
	if MultiplayerManager.is_mj():
		pooling_status_lbl.text = "Le MJ crée la partie — les joueurs rejoignent par code."
		return
	if not MultiplayerManager.is_pooling_connected():
		pooling_status_lbl.text = "Connectez-vous au pooling d'abord."
		return
	var code := room_code_input.text.strip_edges()
	if code.length() != 4:
		pooling_status_lbl.text = "Code à 4 chiffres requis."
		return
	MultiplayerManager.join_room(code)

func _on_rejoin_room_pressed() -> void:
	if MultiplayerManager.is_mj():
		return
	if not MultiplayerManager.is_pooling_connected():
		pooling_status_lbl.text = "Connectez-vous au pooling d'abord."
		return
	MultiplayerManager.rejoin_room()
	pooling_status_lbl.text = "Reconnexion au salon %s..." % MultiplayerManager.last_room_code

func _on_leave_room_pressed() -> void:
	MultiplayerManager.leave_room()

func _on_pooling_register_char_pressed() -> void:
	if not MultiplayerManager.is_in_room():
		pooling_status_lbl.text = "Rejoignez ou créez un salon d'abord."
		return
	var char_data := _selected_pooling_character()
	MultiplayerManager.register_character(char_data)
	pooling_status_lbl.text = "✓ Personnage enregistré : %s" % char_data.get("name", "?")
	pooling_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)

func _on_pooling_room_updated(room: Dictionary) -> void:
	_refresh_pooling_players()
	_update_pooling_status()
	_update_pooling_role_ui()
	_update_pooling_launch_ui()
	if MultiplayerManager.is_gm:
		room_code_lbl.text = "👑 Code à partager : %s" % room.get("code", "????")
	else:
		room_code_lbl.text = "🔗 Partie : %s" % room.get("code", "????")
	if MultiplayerManager.is_in_room() and opt_pooling_char.item_count > 0 and not MultiplayerManager.is_mj():
		_on_pooling_register_char_pressed()

func _on_pooling_room_left() -> void:
	room_code_lbl.text = ""
	p2p_status_lbl.text = ""
	_refresh_pooling_players()
	_update_pooling_status()
	_update_pooling_role_ui()
	_update_pooling_launch_ui()

func _on_pooling_room_closed(closed_code: String, reason: String) -> void:
	room_code_lbl.text = ""
	p2p_status_lbl.text = ""
	_refresh_pooling_players()
	_update_pooling_status()
	_update_pooling_role_ui()
	_update_pooling_launch_ui()
	var msg := "Le MJ a quitté — salon %s fermé." % closed_code
	if reason == "gm_disconnected":
		msg = "Le MJ s'est déconnecté — salon %s fermé." % closed_code
	pooling_status_lbl.text = msg
	pooling_status_lbl.add_theme_color_override("font_color", ThemeColors.DANGER)
	if not MultiplayerManager.is_mj() and not closed_code.is_empty():
		room_code_input.text = closed_code

func _on_pooling_lobby_updated(_rooms: Array) -> void:
	_update_pooling_status()
	_update_pooling_role_ui()

func _on_p2p_host_started(address: String) -> void:
	p2p_status_lbl.text = "● Hôte ENet actif — %s" % address
	p2p_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	_update_pooling_launch_ui()

func _on_p2p_connected(_peer_id: int) -> void:
	if not MultiplayerManager.is_p2p_host():
		p2p_status_lbl.text = "● Connecté P2P (ENet)"
		p2p_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	_update_pooling_launch_ui()

func _on_p2p_error(message: String) -> void:
	p2p_status_lbl.text = message
	p2p_status_lbl.add_theme_color_override("font_color", ThemeColors.DANGER)

func _update_pooling_launch_ui() -> void:
	var in_room := MultiplayerManager.is_in_room()
	var p2p_ready := MultiplayerManager.is_p2p_active()
	var is_mj := MultiplayerManager.is_game_master() and MultiplayerManager.is_mj()
	btn_launch_pooling.visible = in_room and p2p_ready and is_mj and MultiplayerManager.is_p2p_host()
	lbl_waiting_mj.visible = in_room and p2p_ready and not is_mj

func _on_launch_pooling_pressed() -> void:
	if not MultiplayerManager.is_p2p_host():
		return
	get_tree().set_meta("pooling_p2p_host", true)
	get_tree().change_scene_to_file("res://scenes/game_setup.tscn")

func _on_pooling_game_started(_game_id: String, state: Dictionary) -> void:
	GameData.apply_server_state(state)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _update_pooling_status() -> void:
	if MultiplayerManager.is_pooling_connected():
		var role_hint := " [MJ]" if MultiplayerManager.is_mj() else ""
		var room_hint := " — salon %s" % MultiplayerManager.room_code if MultiplayerManager.is_in_room() else ""
		pooling_status_lbl.text = "● Pooling connecté (%s%s%s)" % [MultiplayerManager.player_name, role_hint, room_hint]
		pooling_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		pooling_status_lbl.text = "○ Non connecté — lancez npm run dev dans server/"
		pooling_status_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_update_pooling_role_ui()

func _refresh_pooling_players() -> void:
	for child in pooling_players_vbox.get_children():
		child.queue_free()

	if not MultiplayerManager.is_in_room():
		var empty_lbl := Label.new()
		if MultiplayerManager.is_mj():
			empty_lbl.text = "Créez une partie pour obtenir le code à partager."
		else:
			empty_lbl.text = "Rejoignez une partie avec le code du MJ."
		empty_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		pooling_players_vbox.add_child(empty_lbl)
		return

	for player in MultiplayerManager.get_room_players():
		var p: Dictionary = player
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		var tags := ""
		if p.get("isGm", false):
			tags += " [MJ]"
		elif p.get("isHost", false):
			tags += " [Hôte]"
		var char_name := ""
		var character = p.get("character")
		if character is Dictionary and not character.is_empty():
			char_name = " — %s" % character.get("name", "?")
		name_lbl.text = "• %s%s%s" % [p.get("playerName", "?"), tags, char_name]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if p.get("playerId", "") == MultiplayerManager.player_id:
			name_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		else:
			name_lbl.add_theme_color_override("font_color", ThemeColors.TEXT)
		row.add_child(name_lbl)
		pooling_players_vbox.add_child(row)

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
		empty_lbl.text = "Connectez-vous pour voir le lobby (mode legacy LAN)."
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
		net_status_lbl.text = "● Connecté legacy %s (%s%s)" % [NetworkClient.server_url, NetworkClient.player_name, host_hint]
		net_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		net_status_lbl.text = "○ Legacy hors ligne — LEGACY_MODE=1 sur le serveur"
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
