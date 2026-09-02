extends Node

## Gestionnaire multijoueur P2P — ENet + coordination via serveur de pooling.

signal room_created(code: String, room: Dictionary)
signal room_joined(code: String, room: Dictionary)
signal room_left
signal room_updated(room: Dictionary)
signal lobby_rooms_updated(rooms: Array)
signal p2p_connected(peer_id: int)
signal p2p_disconnected(peer_id: int)
signal p2p_host_started(address: String)
signal p2p_error(message: String)

const ENET_PORT := 7777
const SETTINGS_PATH := "user://multiplayer_settings.cfg"

@export var pooling_url: String = "ws://127.0.0.1:8080"
@export var player_name: String = "Joueur"

var player_id: String = ""
var room_code: String = ""
var current_room: Dictionary = {}
var is_room_host: bool = false
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
		return
	pooling_url = str(cfg.get_value("multiplayer", "pooling_url", pooling_url))
	player_name = str(cfg.get_value("multiplayer", "player_name", player_name))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("multiplayer", "pooling_url", pooling_url)
	cfg.set_value("multiplayer", "player_name", player_name)
	cfg.save(SETTINGS_PATH)

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

func is_p2p_host() -> bool:
	return is_room_host and _is_p2p_active and multiplayer.is_server()

func get_room_players() -> Array:
	return current_room.get("players", [])

func create_room(room_name: String = "") -> void:
	_send({ "type": "create_room", "roomName": room_name if not room_name.is_empty() else "Salon de %s" % player_name })

func join_room(code: String) -> void:
	_send({ "type": "join_room", "code": code.strip_edges() })

func leave_room() -> void:
	if is_in_room():
		_send({ "type": "leave_room" })
	room_code = ""
	current_room = {}
	is_room_host = false
	p2p_host_address = ""
	stop_p2p()
	room_left.emit()

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
			is_room_host = room.get("hostId", "") == player_id
			p2p_host_address = room.get("p2pHost", "") if room.get("p2pHost") else ""
			room_updated.emit(room)
			if is_room_host and not _is_p2p_active:
				start_p2p_host()
			elif not is_room_host and not p2p_host_address.is_empty() and not _is_p2p_active:
				connect_p2p(p2p_host_address)
		"host_assigned":
			is_room_host = data.get("hostId", "") == player_id
			p2p_host_address = data.get("p2pHost", "") if data.get("p2pHost") else p2p_host_address
			if is_room_host and not _is_p2p_active:
				start_p2p_host()
		"player_joined", "player_left":
			if is_in_room():
				_send({ "type": "get_lobby" })
			else:
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

# --- RPC ENet Phase 1 (stubs — sync gameplay Phase 3) ---

@rpc("any_peer", "call_remote", "reliable")
func submit_action(action: String, sender_player_id: String) -> void:
	if not is_p2p_host():
		return
	# TODO Phase 3 : valider action côté hôte, puis sync_game_state

@rpc("authority", "call_remote", "reliable")
func sync_game_state(_state: Dictionary) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func request_dice_roll(formula: String, sender_player_id: String) -> void:
	if not is_p2p_host():
		return
	# TODO Phase 3 : jet côté hôte, sync_log_entry + sync_game_state

@rpc("authority", "call_remote", "reliable")
func sync_log_entry(_entry: Dictionary) -> void:
	pass

## Appelé par main_menu après création réussie (room_update reçu en tant qu'hôte).
func notify_room_created(room: Dictionary) -> void:
	_on_room_created_side_effects(room)

## Appelé par main_menu après join réussi.
func notify_room_joined(room: Dictionary) -> void:
	_on_room_joined_side_effects(room)
