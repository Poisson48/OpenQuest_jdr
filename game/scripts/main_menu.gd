extends Control

const SavedGameRowScene := preload("res://scenes/hub/panels/saved_game_row.tscn")

@onready var home_page: VBoxContainer = %HomePage
@onready var ongoing_page: PanelContainer = %OngoingPage
@onready var play_status_lbl: Label = %PlayStatusLabel
@onready var saved_games_list: VBoxContainer = %SavedGamesList
@onready var player_name_input: LineEdit = %PlayerNameInput

@onready var pooling_url_input: LineEdit = %PoolingUrlInput
@onready var pooling_status_lbl: Label = %PoolingStatusLabel
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var room_code_lbl: Label = %RoomCodeLabel
@onready var p2p_status_lbl: Label = %P2pStatusLabel
@onready var pooling_players_vbox: VBoxContainer = %PoolingPlayersVBox
@onready var opt_pooling_char: OptionButton = %OptPoolingChar
@onready var opt_pooling_role: OptionButton = %OptPoolingRole
@onready var btn_pooling_register_char: Button = %BtnPoolingRegisterChar
@onready var btn_create_room: Button = %BtnCreateRoom
@onready var btn_join_room: Button = %BtnJoinRoom
@onready var btn_rejoin_room: Button = %BtnRejoinRoom
@onready var btn_launch_pooling: Button = %BtnLaunchPoolingGame
@onready var lbl_waiting_mj: Label = %LblWaitingMj
@onready var opt_language: OptionButton = %OptLanguage

var _pending_delete_id: String = ""
var _updating_language_ui := false

const DISCORD_INVITE_URL := "https://discord.gg/nqYfxpbNC"

func _ready() -> void:
	%BtnPlay.pressed.connect(_on_play_pressed)
	%BtnOngoing.pressed.connect(_on_ongoing_pressed)
	%BtnDiscover.pressed.connect(_on_discover_pressed)
	%BtnDiscord.pressed.connect(_on_discord_pressed)
	%BtnBackHome.pressed.connect(_on_back_home_pressed)
	%BtnPlayNew.pressed.connect(_on_play_pressed)
	%ConfirmDeleteResume.confirmed.connect(_on_confirm_delete_resume)
	%BtnConnectPooling.pressed.connect(_on_connect_pooling_pressed)
	%BtnCreateRoom.pressed.connect(_on_create_room_pressed)
	%BtnJoinRoom.pressed.connect(_on_join_room_pressed)
	%BtnRejoinRoom.pressed.connect(_on_rejoin_room_pressed)
	%BtnLeaveRoom.pressed.connect(_on_leave_room_pressed)
	%BtnPoolingRegisterChar.pressed.connect(_on_pooling_register_char_pressed)

	MultiplayerManager.room_updated.connect(_on_pooling_room_updated)
	MultiplayerManager.room_left.connect(_on_pooling_room_left)
	MultiplayerManager.room_closed.connect(_on_pooling_room_closed)
	MultiplayerManager.lobby_rooms_updated.connect(_on_pooling_lobby_updated)
	MultiplayerManager.p2p_host_started.connect(_on_p2p_host_started)
	MultiplayerManager.p2p_connected.connect(_on_p2p_connected)
	MultiplayerManager.p2p_error.connect(_on_p2p_error)
	MultiplayerManager.game_started.connect(_on_pooling_game_started)
	LocaleSettings.locale_changed.connect(_on_locale_changed)

	btn_launch_pooling.pressed.connect(_on_launch_pooling_pressed)

	player_name_input.text = MultiplayerManager.player_name
	pooling_url_input.text = MultiplayerManager.pooling_url
	_setup_language_selector()
	_configure_pooling_dropdown(opt_language)
	_setup_pooling_roles()
	_configure_pooling_dropdown(opt_pooling_role)
	opt_pooling_role.item_selected.connect(_on_pooling_role_changed)
	_populate_pooling_characters()
	_update_pooling_status()
	_update_pooling_role_ui()
	_refresh_pooling_players()
	_update_pooling_launch_ui()
	_apply_static_translations()
	_show_home_page()
	_render_saved_games()
	_highlight_nav("home")

func _setup_language_selector() -> void:
	_updating_language_ui = true
	opt_language.clear()
	var selected := 0
	for i in LocaleSettings.SUPPORTED_LOCALES.size():
		var code: String = LocaleSettings.SUPPORTED_LOCALES[i]
		opt_language.add_item(LocaleSettings.locale_display_name(code), i)
		opt_language.set_item_metadata(i, code)
		if code == LocaleSettings.locale:
			selected = i
	opt_language.selected = selected
	if not opt_language.item_selected.is_connected(_on_language_selected):
		opt_language.item_selected.connect(_on_language_selected)
	_updating_language_ui = false

func _on_language_selected(idx: int) -> void:
	if _updating_language_ui:
		return
	var code := str(opt_language.get_item_metadata(idx))
	LocaleSettings.apply_locale(code)

func _on_locale_changed(_locale: String) -> void:
	_setup_language_selector()
	_setup_pooling_roles()
	_populate_pooling_characters()
	_apply_static_translations()
	_update_pooling_status()
	_refresh_pooling_players()
	_render_saved_games()
	get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)

func _apply_static_translations() -> void:
	player_name_input.placeholder_text = tr("Votre pseudo")
	%ConfirmDeleteResume.title = tr("Effacer la partie")
	%ConfirmDeleteResume.ok_button_text = tr("Effacer")
	%ConfirmDeleteResume.cancel_button_text = tr("Annuler")
	%ConfirmDeleteResume.dialog_text = tr("Effacer cette partie ? Toute la progression sera perdue.")

func _get_pooling_role_from_ui() -> String:
	if opt_pooling_role.item_count == 0:
		return MultiplayerManager.player_role
	var role: Variant = opt_pooling_role.get_item_metadata(opt_pooling_role.selected)
	return "gm" if str(role) == "gm" else "player"

func _sync_pooling_role_from_ui() -> void:
	MultiplayerManager.set_player_role(_get_pooling_role_from_ui())

func _configure_pooling_dropdown(dropdown: OptionButton) -> void:
	# PopupWindow évite le clipping du menu dans ScrollContainer.
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
	# Verrouiller seulement une fois dans un salon — le MJ se connecte souvent au pooling
	# local avant de choisir / changer de rôle (workflow hôte + rechargement éditeur).
	opt_pooling_role.disabled = in_room
	btn_create_room.disabled = not is_mj or in_room or not connected
	btn_join_room.disabled = is_mj or in_room or not connected
	btn_rejoin_room.disabled = is_mj or in_room or MultiplayerManager.last_room_code.is_empty() or not connected
	room_code_input.editable = not is_mj and not in_room
	opt_pooling_char.get_parent().visible = not is_mj
	btn_pooling_register_char.visible = not is_mj
	if not MultiplayerManager.last_room_code.is_empty() and room_code_input.text.is_empty():
		room_code_input.text = MultiplayerManager.last_room_code

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

func _on_pooling_room_updated(room: Dictionary) -> void:
	_refresh_pooling_players()
	_update_pooling_status()
	_update_pooling_role_ui()
	_update_pooling_launch_ui()
	if MultiplayerManager.is_gm:
		room_code_lbl.text = tr("👑 Code à partager : %s") % room.get("code", "????")
	else:
		room_code_lbl.text = tr("🔗 Partie : %s") % room.get("code", "????")
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

func _on_play_pressed() -> void:
	GameData.go_to_game_setup()

func _on_ongoing_pressed() -> void:
	_show_ongoing_page()
	_highlight_nav("ongoing")

func _on_back_home_pressed() -> void:
	_show_home_page()
	_highlight_nav("home")

func _on_discover_pressed() -> void:
	GameData.go_to_hub()

func _on_discord_pressed() -> void:
	# Navigateur par défaut uniquement (HTTPS). Pas de discord:// : sans client
	# Discord, xdg-open reste bloqué et n'ouvre rien.
	if not _open_url_detached(DISCORD_INVITE_URL):
		push_warning("Impossible d'ouvrir l'invitation Discord.")

func _open_url_detached(url: String) -> bool:
	## Ouvre l'URL avec le gestionnaire système, sans bloquer l'UI.
	match OS.get_name():
		"Linux":
			var quoted := "'%s'" % url.replace("'", "'\\''")
			# Détaché : xdg-open / gio respectent le navigateur par défaut.
			if FileAccess.file_exists("/usr/bin/gio"):
				if OS.create_process("/bin/sh", [
					"-c",
					"gio open %s >/dev/null 2>&1 &" % quoted,
				]) >= 0:
					return true
			return OS.create_process("/bin/sh", [
				"-c",
				"xdg-open %s >/dev/null 2>&1 &" % quoted,
			]) >= 0
		"macOS":
			return OS.create_process("open", [url]) >= 0
		"Windows":
			return OS.create_process("cmd", ["/C", "start", "", url]) >= 0
		_:
			OS.shell_open(url)
			return true

func _show_home_page() -> void:
	home_page.visible = true
	ongoing_page.visible = false

func _show_ongoing_page() -> void:
	home_page.visible = false
	ongoing_page.visible = true
	_render_saved_games()

func _highlight_nav(which: String) -> void:
	var gold := ThemeColors.GOLD_LIGHT
	var muted := ThemeColors.TEXT_MUTED
	%BtnOngoing.add_theme_color_override("font_color", gold if which == "ongoing" else muted)

func _render_saved_games() -> void:
	for child in saved_games_list.get_children():
		child.queue_free()
	var games: Array = GameData.get_playing_games()
	if games.is_empty():
		play_status_lbl.text = tr("Aucune partie en cours")
		return
	play_status_lbl.text = tr("%d partie(s) en cours") % games.size()
	for game in games:
		saved_games_list.add_child(_make_saved_game_row(game))

func _make_saved_game_row(game: Dictionary) -> PanelContainer:
	var row := SavedGameRowScene.instantiate()
	row.setup(game)
	row.resume_pressed.connect(_resume_game)
	row.delete_pressed.connect(_ask_delete_game)
	return row

func _resume_game(game_id: String) -> void:
	if not GameData.load_game_by_id(game_id):
		_render_saved_games()
		return
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _ask_delete_game(game_id: String, title: String) -> void:
	_pending_delete_id = game_id
	%ConfirmDeleteResume.dialog_text = tr("Effacer la partie « %s » ? Toute la progression sera perdue.") % title
	%ConfirmDeleteResume.popup_centered()

func _on_confirm_delete_resume() -> void:
	if _pending_delete_id.is_empty():
		return
	GameData.delete_game(_pending_delete_id)
	_pending_delete_id = ""
	_render_saved_games()
