extends PanelContainer

## Panneau de salon multijoueur (P2P pooling).
## Scène autonome — peut être instanciée dans le Hub ou ailleurs.

@onready var player_name_input: LineEdit = %PlayerNameInput
@onready var pooling_url_input: LineEdit = %PoolingUrlInput
@onready var pooling_status_lbl: Label = %PoolingStatusLabel
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var room_code_lbl: Label = %RoomCodeLabel
@onready var p2p_status_lbl: Label = %P2pStatusLabel
@onready var pooling_players_vbox: VBoxContainer = %PoolingPlayersVbox
@onready var opt_pooling_char: OptionButton = %OptPoolingChar
@onready var opt_pooling_role: OptionButton = %OptPoolingRole
@onready var btn_pooling_register_char: Button = %BtnPoolingRegisterChar
@onready var btn_create_room: Button = %BtnCreateRoom
@onready var btn_join_room: Button = %BtnJoinRoom
@onready var btn_rejoin_room: Button = %BtnRejoinRoom
@onready var btn_launch_pooling: Button = %BtnLaunchPoolingGame
@onready var lbl_waiting_mj: Label = %LblWaitingMj

var _pooling_char_registered := false

func _ready() -> void:
	%BtnConnectPooling.pressed.connect(_on_connect_pooling_pressed)
	%BtnCreateRoom.pressed.connect(_on_create_room_pressed)
	%BtnJoinRoom.pressed.connect(_on_join_room_pressed)
	%BtnRejoinRoom.pressed.connect(_on_rejoin_room_pressed)
	%BtnLeaveRoom.pressed.connect(_on_leave_room_pressed)
	%BtnPoolingRegisterChar.pressed.connect(_on_pooling_register_char_pressed)
	btn_launch_pooling.pressed.connect(_on_launch_pooling_pressed)

	MultiplayerManager.room_updated.connect(_on_pooling_room_updated)
	MultiplayerManager.room_left.connect(_on_pooling_room_left)
	MultiplayerManager.room_closed.connect(_on_pooling_room_closed)
	MultiplayerManager.lobby_rooms_updated.connect(_on_pooling_lobby_updated)
	MultiplayerManager.p2p_host_started.connect(_on_p2p_host_started)
	MultiplayerManager.p2p_connected.connect(_on_p2p_connected)
	MultiplayerManager.p2p_error.connect(_on_p2p_error)
	MultiplayerManager.game_started.connect(_on_pooling_game_started)

	player_name_input.text = MultiplayerManager.player_name
	pooling_url_input.text = MultiplayerManager.pooling_url
	_configure_pooling_dropdown(opt_pooling_role)
	opt_pooling_role.item_selected.connect(_on_pooling_role_changed)
	_setup_pooling_roles()
	_populate_pooling_characters()
	_update_pooling_status()
	_update_pooling_role_ui()
	_refresh_pooling_players()
	_update_pooling_launch_ui()

# ---------------------------------------------------------------------------
# Rôle
# ---------------------------------------------------------------------------

func _get_pooling_role_from_ui() -> String:
	if opt_pooling_role.item_count == 0:
		return MultiplayerManager.player_role
	var role: Variant = opt_pooling_role.get_item_metadata(opt_pooling_role.selected)
	return "gm" if str(role) == "gm" else "player"

func _sync_pooling_role_from_ui() -> void:
	MultiplayerManager.set_player_role(_get_pooling_role_from_ui())

func _configure_pooling_dropdown(dropdown: OptionButton) -> void:
	dropdown.get_popup().popup_window = true

func _role_index_for_saved_role() -> int:
	return 0 if MultiplayerManager.player_role == "gm" else 1

func _setup_pooling_roles() -> void:
	opt_pooling_role.set_block_signals(true)
	opt_pooling_role.clear()
	opt_pooling_role.add_item(tr("👑 Maître du Jeu (MJ)"), 0)
	opt_pooling_role.set_item_metadata(0, "gm")
	opt_pooling_role.add_item(tr("⚔️ Joueur"), 1)
	opt_pooling_role.set_item_metadata(1, "player")
	opt_pooling_role.selected = _role_index_for_saved_role()
	opt_pooling_role.set_block_signals(false)
	_sync_pooling_role_from_ui()

func _on_pooling_role_changed(_idx: int) -> void:
	_sync_pooling_role_from_ui()
	_update_pooling_role_ui()

func _update_pooling_role_ui() -> void:
	var is_mj := _get_pooling_role_from_ui() == "gm"
	var in_room := MultiplayerManager.is_in_room()
	var connected := MultiplayerManager.is_pooling_connected()
	opt_pooling_role.disabled = in_room
	btn_create_room.disabled = not is_mj or in_room or not connected
	btn_join_room.disabled = is_mj or in_room or not connected
	btn_rejoin_room.disabled = is_mj or in_room or MultiplayerManager.last_room_code.is_empty() or not connected
	room_code_input.editable = not is_mj and not in_room
	opt_pooling_char.get_parent().visible = not is_mj
	btn_pooling_register_char.visible = not is_mj
	if not MultiplayerManager.last_room_code.is_empty() and room_code_input.text.is_empty():
		room_code_input.text = MultiplayerManager.last_room_code

# ---------------------------------------------------------------------------
# Personnages
# ---------------------------------------------------------------------------

func _populate_pooling_characters() -> void:
	opt_pooling_char.clear()
	var chars := GameData.get_characters()
	if chars.is_empty():
		opt_pooling_char.add_item(tr("Aventurier (par défaut)"), 0)
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

# ---------------------------------------------------------------------------
# Connexion & salons
# ---------------------------------------------------------------------------

func _on_connect_pooling_pressed() -> void:
	MultiplayerManager.player_name = player_name_input.text.strip_edges()
	if MultiplayerManager.player_name.is_empty():
		MultiplayerManager.player_name = "Joueur"
	_sync_pooling_role_from_ui()
	MultiplayerManager.connect_pooling(pooling_url_input.text, MultiplayerManager.player_name)
	pooling_status_lbl.text = tr("Connexion pooling en cours...")
	pooling_status_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_update_pooling_role_ui()

func _on_create_room_pressed() -> void:
	_sync_pooling_role_from_ui()
	if not MultiplayerManager.is_mj():
		pooling_status_lbl.text = tr("Seul le MJ peut créer une partie.")
		return
	if not MultiplayerManager.is_pooling_connected():
		pooling_status_lbl.text = tr("Connectez-vous au pooling d'abord.")
		return
	MultiplayerManager.create_room(tr("Partie de %s") % MultiplayerManager.player_name)

func _on_join_room_pressed() -> void:
	_sync_pooling_role_from_ui()
	if MultiplayerManager.is_mj():
		pooling_status_lbl.text = tr("Le MJ crée la partie — les joueurs rejoignent par code.")
		return
	if not MultiplayerManager.is_pooling_connected():
		pooling_status_lbl.text = tr("Connectez-vous au pooling d'abord.")
		return
	var code := room_code_input.text.strip_edges()
	if code.length() != 4:
		pooling_status_lbl.text = tr("Code à 4 chiffres requis.")
		return
	MultiplayerManager.join_room(code)

func _on_rejoin_room_pressed() -> void:
	if MultiplayerManager.is_mj():
		return
	if not MultiplayerManager.is_pooling_connected():
		pooling_status_lbl.text = tr("Connectez-vous au pooling d'abord.")
		return
	MultiplayerManager.rejoin_room()
	pooling_status_lbl.text = tr("Reconnexion au salon %s...") % MultiplayerManager.last_room_code

func _on_leave_room_pressed() -> void:
	MultiplayerManager.leave_room()

func _on_pooling_register_char_pressed() -> void:
	if not MultiplayerManager.is_in_room():
		pooling_status_lbl.text = tr("Rejoignez ou créez un salon d'abord.")
		return
	var char_data := _selected_pooling_character()
	MultiplayerManager.register_character(char_data)
	pooling_status_lbl.text = tr("✓ Personnage enregistré : %s") % char_data.get("name", "?")
	pooling_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)

# ---------------------------------------------------------------------------
# Callbacks réseau
# ---------------------------------------------------------------------------

func _on_pooling_room_updated(room: Dictionary) -> void:
	_refresh_pooling_players()
	_update_pooling_status()
	_update_pooling_role_ui()
	_update_pooling_launch_ui()
	if MultiplayerManager.is_gm:
		room_code_lbl.text = tr("👑 Code à partager : %s") % room.get("code", "????")
	else:
		room_code_lbl.text = tr("🔗 Partie : %s") % room.get("code", "????")

func _on_pooling_room_left() -> void:
	_pooling_char_registered = false
	room_code_lbl.text = ""
	p2p_status_lbl.text = ""
	_refresh_pooling_players()
	_update_pooling_status()
	_update_pooling_role_ui()
	_update_pooling_launch_ui()

func _on_pooling_room_closed(closed_code: String, reason: String) -> void:
	_pooling_char_registered = false
	room_code_lbl.text = ""
	p2p_status_lbl.text = ""
	_refresh_pooling_players()
	_update_pooling_status()
	_update_pooling_role_ui()
	_update_pooling_launch_ui()
	var msg := tr("Le MJ a quitté — salon %s fermé.") % closed_code
	if reason == "gm_disconnected":
		msg = tr("Le MJ s'est déconnecté — salon %s fermé.") % closed_code
	pooling_status_lbl.text = msg
	pooling_status_lbl.add_theme_color_override("font_color", ThemeColors.DANGER)
	if not MultiplayerManager.is_mj() and not closed_code.is_empty():
		room_code_input.text = closed_code

func _on_pooling_lobby_updated(_rooms: Array) -> void:
	_update_pooling_status()
	_update_pooling_role_ui()

func _on_p2p_host_started(address: String) -> void:
	p2p_status_lbl.text = tr("● Hôte ENet actif — %s") % address
	p2p_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	_update_pooling_launch_ui()

func _on_p2p_connected(_peer_id: int) -> void:
	if not MultiplayerManager.is_p2p_host():
		p2p_status_lbl.text = tr("● Connecté P2P (ENet)")
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
		var role_hint := (" [%s]" % tr("MJ")) if MultiplayerManager.is_mj() else ""
		var room_hint := (" — %s" % (tr("salon %s") % MultiplayerManager.room_code)) if MultiplayerManager.is_in_room() else ""
		pooling_status_lbl.text = tr("● Pooling connecté (%s%s%s)") % [MultiplayerManager.player_name, role_hint, room_hint]
		pooling_status_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		pooling_status_lbl.text = tr("○ Non connecté — lancez npm run dev dans server/")
		pooling_status_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_update_pooling_role_ui()

func _refresh_pooling_players() -> void:
	for child in pooling_players_vbox.get_children():
		child.queue_free()

	if not MultiplayerManager.is_in_room():
		var empty_lbl := Label.new()
		if MultiplayerManager.is_mj():
			empty_lbl.text = tr("Créez une partie pour obtenir le code à partager.")
		else:
			empty_lbl.text = tr("Rejoignez une partie avec le code du MJ.")
		empty_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		pooling_players_vbox.add_child(empty_lbl)
		return

	for player in MultiplayerManager.get_room_players():
		var p: Dictionary = player
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		var tags := ""
		if p.get("isGm", false):
			tags += " [%s]" % tr("MJ")
		elif p.get("isHost", false):
			tags += " [%s]" % tr("Hôte")
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