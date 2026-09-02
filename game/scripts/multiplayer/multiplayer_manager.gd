extends Node

## Gestionnaire multijoueur P2P — ENet + coordination via serveur de pooling.

signal room_created(code: String, room: Dictionary)
signal room_joined(code: String, room: Dictionary)
signal room_left
signal room_closed(room_code: String, reason: String)
signal room_updated(room: Dictionary)
signal lobby_rooms_updated(rooms: Array)
signal p2p_connected(peer_id: int)
signal p2p_disconnected(peer_id: int)
signal p2p_host_started(address: String)
signal p2p_error(message: String)
signal game_started(game_id: String, state: Dictionary)
signal game_state_received(state: Dictionary)
signal log_entry_received(entry: Dictionary)
signal dice_result_received(result: Dictionary, formatted: String)

const ENET_PORT := 7777
const SETTINGS_PATH := "user://multiplayer_settings.cfg"

@export var pooling_url: String = "ws://127.0.0.1:8080"
@export var player_name: String = "Joueur"
@export var player_role: String = "player"  ## "gm" (MJ) ou "player" (joueur)

var player_id: String = ""
var room_code: String = ""
var last_room_code: String = ""
var current_room: Dictionary = {}
var is_room_host: bool = false
var is_gm: bool = false
var p2p_host_address: String = ""
var lobby_rooms: Array = []

var _socket: WebSocketPeer = WebSocketPeer.new()
var _is_pooling_connected: bool = false
var _enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var _is_p2p_active: bool = false

func _ready() -> void:
	load_settings()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		_apply_profile_role_default()
		return
	pooling_url = str(cfg.get_value("multiplayer", "pooling_url", pooling_url))
	player_name = str(cfg.get_value("multiplayer", "player_name", player_name))
	player_role = str(cfg.get_value("multiplayer", "player_role", player_role))
	last_room_code = str(cfg.get_value("multiplayer", "last_room_code", last_room_code))
	_normalize_player_role()

func _apply_profile_role_default() -> void:
	var user_dir := OS.get_user_data_dir()
	if user_dir.contains("OpenQuest_MJ"):
		player_role = "gm"
	elif user_dir.contains("OpenQuest_Player"):
		player_role = "player"

func _normalize_player_role() -> void:
	if player_role == "gm" or player_role == "player":
		return
	_apply_profile_role_default()
	save_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("multiplayer", "pooling_url", pooling_url)
	cfg.set_value("multiplayer", "player_name", player_name)
	cfg.set_value("multiplayer", "player_role", player_role)
	if not last_room_code.is_empty():
		cfg.set_value("multiplayer", "last_room_code", last_room_code)
	cfg.save(SETTINGS_PATH)

func set_player_role(role: String) -> void:
	player_role = "gm" if role == "gm" else "player"
	save_settings()

func is_mj() -> bool:
	return player_role == "gm"

func is_game_master() -> bool:
	return is_gm

func connect_pooling(url: String = "", name: String = "") -> void:
	if not url.is_empty():
		pooling_url = url.strip_edges()
	if not name.is_empty():
		player_name = name.strip_edges()
	save_settings()
	disconnect_pooling()
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(pooling_url)
	if err != OK:
		p2p_error.emit("Connexion pooling impossible (%s)" % pooling_url)

func disconnect_pooling() -> void:
	if _is_pooling_connected:
		leave_room()
		_socket.close()
		_is_pooling_connected = false
	stop_p2p()

func is_pooling_connected() -> bool:
	return _is_pooling_connected

func is_in_room() -> bool:
	return not room_code.is_empty()

func is_p2p_active() -> bool:
	return _is_p2p_active

func is_p2p_host() -> bool:
	return is_room_host and _is_p2p_active and multiplayer.is_server()

func get_room_players() -> Array:
	return current_room.get("players", [])

func get_my_party_member(state: Dictionary) -> Dictionary:
	for member in state.get("party", []):
		if member.get("clientId", "") == player_id:
			return member
	return {}

func create_room(room_name: String = "") -> void:
	if not is_mj():
		p2p_error.emit("Seul le MJ peut créer une partie.")
		return
	_send({
		"type": "create_room",
		"role": "gm",
		"roomName": room_name if not room_name.is_empty() else "Partie de %s" % player_name,
	})

func join_room(code: String) -> void:
	var normalized := code.strip_edges()
	last_room_code = normalized
	save_settings()
	_send({ "type": "join_room", "code": normalized })

func rejoin_room() -> void:
	if last_room_code.is_empty():
		p2p_error.emit("Aucun salon mémorisé pour reconnexion.")
		return
	_send({ "type": "rejoin_room", "code": last_room_code })

func leave_room() -> void:
	if is_in_room():
		_send({ "type": "leave_room" })
	_reset_room_state()
	room_left.emit()

func _reset_room_state() -> void:
	room_code = ""
	current_room = {}
	is_room_host = false
	is_gm = false
	p2p_host_address = ""
	stop_p2p()

func register_character(character: Dictionary) -> void:
	_send({ "type": "register_character", "character": character })

func list_rooms() -> void:
	_send({ "type": "list_rooms" })

func start_p2p_host() -> bool:
	stop_p2p()
	var err := _enet_peer.create_server(ENET_PORT, 8)
	if err != OK:
		p2p_error.emit("Impossible de démarrer l'hôte ENet (port %d)" % ENET_PORT)
		return false
	multiplayer.multiplayer_peer = _enet_peer
	_is_p2p_active = true
	var address := _detect_local_ip()
	p2p_host_address = "%s:%d" % [address, ENET_PORT]
	_send({ "type": "set_p2p_host", "address": p2p_host_address })
	p2p_host_started.emit(p2p_host_address)
	return true

func connect_p2p(address: String = "") -> bool:
	var target := address if not address.is_empty() else p2p_host_address
	if target.is_empty():
		p2p_error.emit("Aucune adresse P2P disponible.")
		return false
	stop_p2p()
	var host := target
	var port := ENET_PORT
	if ":" in target:
		var parts := target.split(":")
		host = parts[0]
		port = int(parts[1])
	var err := _enet_peer.create_client(host, port)
	if err != OK:
		p2p_error.emit("Connexion ENet impossible (%s:%d)" % [host, port])
		return false
	multiplayer.multiplayer_peer = _enet_peer
	_is_p2p_active = true
	return true

func stop_p2p() -> void:
	if _is_p2p_active:
		multiplayer.multiplayer_peer = null
		_enet_peer = ENetMultiplayerPeer.new()
		_is_p2p_active = false

# --- API client Phase 3 ---

func client_request_start_game(
	scenario_id: String,
	party: Array,
	mode: String,
	gm_type: String,
	quest_format: String,
	party_size: int,
	map_ids: Array = []
) -> void:
	if not is_p2p_active():
		p2p_error.emit("P2P non actif — rejoignez un salon d'abord.")
		return
	if is_p2p_host():
		_host_start_game(scenario_id, party, mode, gm_type, quest_format, party_size, map_ids)
	else:
		request_start_game.rpc_id(1, scenario_id, party, mode, gm_type, quest_format, party_size, map_ids, player_id)

func client_submit_action(action_text: String) -> void:
	if not is_p2p_active():
		return
	if is_p2p_host():
		_host_process_action(action_text, player_id)
	else:
		submit_action.rpc_id(1, action_text, player_id)

func client_request_dice_roll(formula: String) -> void:
	if not is_p2p_active():
		return
	if is_p2p_host():
		_host_process_dice_roll(formula, player_id)
	else:
		request_dice_roll.rpc_id(1, formula, player_id)

func client_advance_scene() -> void:
	if not is_p2p_host():
		return
	if GameData.advance_scene():
		broadcast_state()

func client_go_to_scene(scene_id: String, reason: String = "") -> void:
	if not is_p2p_host():
		return
	if GameData.go_to_scene(scene_id, reason):
		broadcast_state()

func client_complete_scenario(reason: String = "") -> void:
	if not is_p2p_host():
		return
	GameData.complete_scenario(reason)
	broadcast_state()

func client_gm_broadcast(author: String, text: String, log_type: String = "gm") -> void:
	if not is_p2p_active():
		return
	if is_p2p_host():
		_host_gm_broadcast(author, text, log_type)
	else:
		gm_broadcast.rpc_id(1, author, text, log_type, player_id)

func _host_gm_broadcast(author: String, text: String, log_type: String) -> void:
	if not is_p2p_host() or GameData.active_game.is_empty():
		return
	GameData.add_log_entry(author, text, log_type)
	GameData.set_waiting_for_gm(false)
	broadcast_state()

func broadcast_state() -> void:
	if not is_p2p_host() or GameData.active_game.is_empty():
		return
	var state := GameData.active_game.duplicate(true)
	sync_game_state.rpc(state)

func _process(_delta: float) -> void:
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _is_pooling_connected:
				_is_pooling_connected = true
				_send({ "type": "register_player", "playerName": player_name })
			_handle_incoming()
		WebSocketPeer.STATE_CLOSED:
			if _is_pooling_connected:
				_is_pooling_connected = false

func _send(data: Dictionary) -> void:
	if not _is_pooling_connected:
		return
	_socket.send_text(JSON.stringify(data))

func _handle_incoming() -> void:
	while _socket.get_available_packet_count() > 0:
		var raw := _socket.get_packet().get_string_from_utf8()
		var data = JSON.parse_string(raw)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		_handle_message(data)

func _handle_message(data: Dictionary) -> void:
	match data.get("type", ""):
		"welcome":
			player_id = data.get("playerId", "")
		"lobby_update":
			lobby_rooms = data.get("rooms", [])
			lobby_rooms_updated.emit(lobby_rooms)
		"room_update":
			var room: Dictionary = data.get("room", {})
			if room.is_empty() or room.get("code", "").is_empty():
				return
			current_room = room
			room_code = room.get("code", "")
			last_room_code = room_code
			save_settings()
			is_room_host = room.get("hostId", "") == player_id
			is_gm = room.get("gmId", "") == player_id
			p2p_host_address = room.get("p2pHost", "") if room.get("p2pHost") else ""
			room_updated.emit(room)
			if is_gm and not _is_p2p_active:
				start_p2p_host()
			elif not is_gm and not p2p_host_address.is_empty() and not _is_p2p_active:
				connect_p2p(p2p_host_address)
		"room_closed":
			var closed_code: String = data.get("roomCode", room_code)
			var reason: String = data.get("reason", "gm_left")
			_reset_room_state()
			room_closed.emit(closed_code, reason)
		"host_assigned":
			is_room_host = data.get("hostId", "") == player_id
			is_gm = is_room_host
			p2p_host_address = data.get("p2pHost", "") if data.get("p2pHost") else p2p_host_address
			if is_gm and not _is_p2p_active:
				start_p2p_host()
		"player_joined", "player_left":
			if is_in_room():
				pass
			list_rooms()
		"error":
			p2p_error.emit(data.get("message", "Erreur réseau"))

func _on_room_created_side_effects(room: Dictionary) -> void:
	room_code = room.get("code", "")
	current_room = room
	is_room_host = true
	room_created.emit(room_code, room)

func _on_room_joined_side_effects(room: Dictionary) -> void:
	room_code = room.get("code", "")
	current_room = room
	is_room_host = room.get("hostId", "") == player_id
	room_joined.emit(room_code, room)

func _detect_local_ip() -> String:
	var addresses := IP.get_local_addresses()
	for addr in addresses:
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
	for addr in addresses:
		if not addr.begins_with("127.") and addr.find(":") == -1:
			return addr
	return "127.0.0.1"

func _on_peer_connected(peer_id: int) -> void:
	p2p_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	p2p_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	p2p_connected.emit(multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	p2p_error.emit("Connexion P2P ENet échouée.")
	stop_p2p()

func _on_server_disconnected() -> void:
	stop_p2p()

# --- Logique hôte Phase 3 ---

func _host_start_game(
	scenario_id: String,
	party: Array,
	mode: String,
	gm_type: String,
	quest_format: String,
	_party_size: int,
	map_ids: Array = []
) -> void:
	if not is_p2p_host():
		return
	var final_party := _merge_party_with_room(party)
	GameData.create_new_game(scenario_id, mode, gm_type, quest_format, final_party, map_ids)
	if gm_type == "human":
		GameData.active_game["gmName"] = player_name if not player_name.is_empty() else "MJ"
		GameData.active_game["waitingForGm"] = false
		GameData.save_active_game()
	var state := GameData.active_game.duplicate(true)
	sync_game_state.rpc(state)
	game_started.emit(state.get("id", ""), state)

func _merge_party_with_room(host_party: Array) -> Array:
	if host_party.is_empty():
		return _build_party_from_room()
	var merged: Array = host_party.duplicate(true)
	for room_player in get_room_players():
		var pid: String = room_player.get("playerId", "")
		if room_player.get("isGm", false):
			continue
		var char_data: Dictionary = room_player.get("character", {})
		if char_data.is_empty():
			continue
		var already := false
		for m in merged:
			if m.get("clientId", "") == pid:
				already = true
				break
		if already:
			continue
		var member: Dictionary = char_data.duplicate(true)
		member["isPlayer"] = true
		member["isHuman"] = true
		member["isBot"] = false
		member["clientId"] = pid
		merged.append(member)
	return merged

func _build_party_from_room() -> Array:
	var party: Array = []
	for room_player in get_room_players():
		if room_player.get("isGm", false):
			continue
		var char_data: Dictionary = room_player.get("character", {})
		if char_data.is_empty():
			continue
		var member: Dictionary = char_data.duplicate(true)
		member["isPlayer"] = true
		member["isHuman"] = true
		member["isBot"] = false
		member["clientId"] = room_player.get("playerId", "")
		party.append(member)
	if party.is_empty() and not is_mj():
		var fallback := GameData.create_blank_character()
		fallback["name"] = player_name
		fallback["isPlayer"] = true
		fallback["isHuman"] = true
		fallback["isBot"] = false
		fallback["clientId"] = player_id
		party.append(fallback)
	return party

func _resolve_player_name(sender_player_id: String) -> String:
	for room_player in get_room_players():
		if room_player.get("playerId", "") == sender_player_id:
			var char_data = room_player.get("character")
			if char_data is Dictionary and not char_data.is_empty():
				return char_data.get("name", room_player.get("playerName", "Joueur"))
			return room_player.get("playerName", "Joueur")
	for member in GameData.active_game.get("party", []):
		if member.get("clientId", "") == sender_player_id:
			return member.get("name", "Joueur")
	return "Joueur"

func _host_process_action(action_text: String, sender_player_id: String) -> void:
	if not is_p2p_host() or GameData.active_game.is_empty():
		return
	if GameData.active_game.get("gmType", "ai") == "human":
		if not GameData.can_member_act(sender_player_id):
			return
	var author := _resolve_player_name(sender_player_id)
	GameData.add_log_entry(author, action_text, "player")
	if GameData.try_auto_move_from_action(action_text):
		pass
	GameData.maybe_reveal_investigation_from_action(action_text)
	if GameData.active_game.get("gmType", "ai") == "ai":
		_host_simulate_ai_response(action_text)
	else:
		GameData.set_waiting_for_gm(true)
		GameData.next_turn()
	broadcast_state()

func _host_simulate_ai_response(player_action: String) -> void:
	var gm_replies := [
		"Le Maître du Jeu écoute attentivement votre décision. Les ombres s'étirent et le vent murmure...",
		"Votre initiative porte ses fruits. La situation évolue et révèle de nouveaux détails.",
		"Vous observez l'environnement avec vigilance. Quelque chose attire votre attention...",
		"Une tension palpable s'installe. Le destin semble attendre l'issue de vos choix."
	]
	var gm_text: String = str(gm_replies[randi() % gm_replies.size()]) + "\n[i]« %s »[/i]" % player_action
	GameData.add_log_entry("MJ (IA)", gm_text, "gm")

	var party: Array = GameData.active_game.get("party", [])
	var bots_in_party: Array = []
	for member in party:
		if member.get("isBot", false):
			bots_in_party.append(member)
	if not bots_in_party.is_empty():
		var bot: Dictionary = bots_in_party[randi() % bots_in_party.size()]
		var bot_replies: Array[String] = [
			"approuve votre idée et couvre vos arrières.",
			"scrute les alentours l'arme au poing.",
			"prend des notes et garde le silence.",
			"prépare un sortilège en prévision du danger."
		]
		var b_text: String = "%s %s" % [bot.get("name", "Bot"), bot_replies[randi() % bot_replies.size()]]
		GameData.add_log_entry(bot.get("name", "Bot"), b_text, "bot")

func _host_process_dice_roll(formula: String, sender_player_id: String) -> void:
	if not is_p2p_host() or GameData.active_game.is_empty():
		return
	var res := GameData.roll_dice(formula)
	if res.has("error"):
		return
	var formatted := GameData.format_dice_result(res)
	var author := _resolve_player_name(sender_player_id)
	GameData.add_log_entry("Dé (%s)" % author, formatted, "dice")
	broadcast_state()
	sync_dice_result.rpc(res, formatted)

# --- RPC ENet Phase 3 ---

@rpc("any_peer", "call_remote", "reliable")
func request_start_game(
	scenario_id: String,
	party: Array,
	mode: String,
	gm_type: String,
	quest_format: String,
	party_size: int,
	map_ids: Array,
	sender_player_id: String
) -> void:
	if not is_p2p_host():
		return
	if sender_player_id != player_id and not _is_gm_peer(sender_player_id):
		return
	_host_start_game(scenario_id, party, mode, gm_type, quest_format, party_size, map_ids)

func _is_gm_peer(pid: String) -> bool:
	for room_player in get_room_players():
		if room_player.get("playerId", "") == pid and room_player.get("isGm", false):
			return true
	return pid == player_id and is_gm

@rpc("any_peer", "call_remote", "reliable")
func submit_action(action_text: String, sender_player_id: String) -> void:
	if not is_p2p_host():
		return
	_host_process_action(action_text, sender_player_id)

@rpc("any_peer", "call_remote", "reliable")
func request_dice_roll(formula: String, sender_player_id: String) -> void:
	if not is_p2p_host():
		return
	_host_process_dice_roll(formula, sender_player_id)

@rpc("any_peer", "call_remote", "reliable")
func gm_broadcast(author: String, text: String, log_type: String, sender_player_id: String) -> void:
	if not is_p2p_host():
		return
	if not _is_gm_peer(sender_player_id):
		return
	_host_gm_broadcast(author, text, log_type)

@rpc("authority", "call_local", "reliable")
func sync_game_state(state: Dictionary) -> void:
	var needs_launch := not GameData.has_active_game()
	GameData.apply_server_state(state)
	game_state_received.emit(state)
	if needs_launch:
		game_started.emit(state.get("id", ""), state)

@rpc("authority", "call_remote", "reliable")
func sync_log_entry(entry: Dictionary) -> void:
	if GameData.active_game.is_empty():
		return
	GameData.active_game["log"].append(entry)
	GameData.save_active_game()
	log_entry_received.emit(entry)

@rpc("authority", "call_local", "reliable")
func sync_dice_result(result: Dictionary, formatted: String) -> void:
	dice_result_received.emit(result, formatted)

func notify_room_created(room: Dictionary) -> void:
	_on_room_created_side_effects(room)

func notify_room_joined(room: Dictionary) -> void:
	_on_room_joined_side_effects(room)
