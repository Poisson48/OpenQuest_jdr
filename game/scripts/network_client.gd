extends Node

signal connected(player_id: String, player_name: String)
signal disconnected
signal game_state_received(state: Dictionary)
signal game_started(game_id: String, state: Dictionary)
signal scenarios_list_received(scenarios: Array)
signal log_entry_received(entry: Dictionary)
signal dice_result_received(result: Dictionary, formatted: String)
signal gm_narration_received(text: String)
signal error_received(message: String)
signal lobby_updated(host_id: String, players: Array)
signal room_updated(room: Dictionary)
signal host_assigned(host_id: String, p2p_host: String)
signal player_joined(player_id: String, player_name: String)
signal player_left(player_id: String)

const SETTINGS_PATH := "user://network_settings.cfg"

@export var server_url: String = "ws://127.0.0.1:8080"
@export var player_name: String = "Joueur"
@export var auto_connect: bool = false

var _socket: WebSocketPeer = WebSocketPeer.new()
var _player_id: String = ""
var _game_id: String = ""
var _is_socket_connected: bool = false
var lobby_host_id: String = ""
var lobby_players: Array = []
var lobby_rooms: Array = []
var current_room: Dictionary = {}

func _ready() -> void:
	load_settings()
	if auto_connect:
		connect_to_server()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	server_url = str(cfg.get_value("network", "server_url", server_url))
	player_name = str(cfg.get_value("network", "player_name", player_name))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("network", "server_url", server_url)
	cfg.set_value("network", "player_name", player_name)
	cfg.save(SETTINGS_PATH)

func connect_to_server(url: String = "", custom_name: String = "") -> void:
	if not url.is_empty():
		server_url = url.strip_edges()
	if not custom_name.is_empty():
		player_name = custom_name.strip_edges()
	save_settings()
	disconnect_from_server()
	lobby_players.clear()
	lobby_host_id = ""
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(server_url)
	if err != OK:
		error_received.emit("Connexion impossible (%s)" % server_url)

func _send_join() -> void:
	send_message({ "type": "join", "playerName": player_name })

func disconnect_from_server() -> void:
	if _is_socket_connected:
		_socket.close()
		_is_socket_connected = false
		disconnected.emit()

func _process(_delta: float) -> void:
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _is_socket_connected:
				_is_socket_connected = true
				_send_join()
			_handle_incoming()
		WebSocketPeer.STATE_CLOSED:
			if _is_socket_connected:
				_is_socket_connected = false
				disconnected.emit()

func send_message(data: Dictionary) -> void:
	if not _is_socket_connected:
		return
	_socket.send_text(JSON.stringify(data))

func request_lobby() -> void:
	send_message({ "type": "get_lobby" })

func register_character(character: Dictionary) -> void:
	send_message({ "type": "register_character", "character": character })

func create_room(room_name: String = "", max_players: int = 6) -> void:
	var payload := { "type": "create_room", "maxPlayers": max_players }
	if not room_name.is_empty():
		payload["roomName"] = room_name
	send_message(payload)

func join_room(code: String) -> void:
	send_message({ "type": "join_room", "code": code.strip_edges() })

func leave_room() -> void:
	send_message({ "type": "leave_room" })
	current_room.clear()
	lobby_rooms.clear()

func set_p2p_host(address: String) -> void:
	send_message({ "type": "set_p2p_host", "address": address })

func list_rooms() -> void:
	send_message({ "type": "list_rooms" })

func request_scenarios() -> void:
	send_message({ "type": "list_scenarios" })

func start_game(scenario_id: String, party: Array, mode: String, gm_type: String, quest_format: String, party_size: int) -> void:
	send_message({
		"type": "start_game",
		"scenarioId": scenario_id,
		"party": party,
		"mode": mode,
		"gmType": gm_type,
		"questFormat": quest_format,
		"partySizeTarget": party_size,
		"fillWithBots": true,
	})

func send_action(action_text: String) -> void:
	send_message({
		"type": "game_action",
		"gameId": _game_id,
		"action": action_text,
		"playerId": _player_id,
	})

func send_dice_roll(formula: String) -> void:
	send_message({
		"type": "dice_roll",
		"gameId": _game_id if not _game_id.is_empty() else null,
		"formula": formula,
		"playerId": _player_id,
	})

func advance_scene() -> void:
	send_message({ "type": "advance_scene", "gameId": _game_id })

func get_game_id() -> String:
	return _game_id

func get_player_id() -> String:
	return _player_id

func is_host() -> bool:
	if not current_room.is_empty():
		return _player_id == str(current_room.get("hostId", ""))
	return not lobby_host_id.is_empty() and _player_id == lobby_host_id

func is_server_connected() -> bool:
	return _is_socket_connected

func get_my_party_member(state: Dictionary) -> Dictionary:
	for member in state.get("party", []):
		if member.get("clientId", "") == _player_id:
			return member
	return {}

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
			_player_id = data.get("playerId", "")
			connected.emit(_player_id, data.get("playerName", player_name))
			request_lobby()
		"lobby_update":
			if data.has("rooms"):
				lobby_rooms = data.get("rooms", [])
				lobby_players.clear()
				lobby_host_id = ""
				lobby_updated.emit("", lobby_rooms)
			else:
				lobby_host_id = data.get("hostId", "")
				lobby_players = data.get("players", [])
				lobby_updated.emit(lobby_host_id, lobby_players)
		"room_update":
			current_room = data.get("room", {})
			lobby_players = current_room.get("players", [])
			lobby_host_id = str(current_room.get("hostId", ""))
			room_updated.emit(current_room)
			lobby_updated.emit(lobby_host_id, lobby_players)
		"host_assigned":
			lobby_host_id = data.get("hostId", "")
			host_assigned.emit(data.get("hostId", ""), data.get("p2pHost", ""))
		"player_joined":
			player_joined.emit(data.get("playerId", ""), data.get("playerName", ""))
			request_lobby()
		"player_left":
			player_left.emit(data.get("playerId", ""))
			request_lobby()
		"game_started":
			_game_id = data.get("gameId", "")
			var state: Dictionary = data.get("state", {})
			game_started.emit(_game_id, state)
			game_state_received.emit(state)
		"game_state", "state_sync":
			game_state_received.emit(data.get("state", data))
		"scenarios_list":
			scenarios_list_received.emit(data.get("scenarios", []))
		"log_entry":
			log_entry_received.emit(data.get("entry", {}))
		"dice_result":
			dice_result_received.emit(data.get("result", {}), data.get("formatted", ""))
		"gm_narration":
			gm_narration_received.emit(data.get("text", ""))
		"error":
			error_received.emit(data.get("message", "Erreur réseau"))

