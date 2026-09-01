extends Node

signal connected(player_id: String, player_name: String)
signal disconnected
signal game_state_received(state: Dictionary)
signal game_started(game_id: String, state: Dictionary)
signal scenarios_list_received(scenarios: Array)
signal log_entry_received(entry: Dictionary)
signal dice_result_received(result: Dictionary)
signal gm_narration_received(text: String)
signal error_received(message: String)

@export var server_url: String = "ws://127.0.0.1:8080"
@export var player_name: String = "Joueur"
@export var auto_connect: bool = true

var _socket: WebSocketPeer = WebSocketPeer.new()
var _player_id: String = ""
var _game_id: String = ""
var _is_socket_connected: bool = false

func _ready() -> void:
	if auto_connect:
		connect_to_server()

func connect_to_server(url: String = "", custom_name: String = "") -> void:
	if not url.is_empty():
		server_url = url
	if not custom_name.is_empty():
		player_name = custom_name
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

func request_scenarios() -> void:
	send_message({ "type": "list_scenarios" })

func start_game(scenario_id: String, party: Array, mode: String, gm_type: String, quest_format: String, party_size: int, map_ids: Array = []) -> void:
	send_message({
		"type": "start_game",
		"scenarioId": scenario_id,
		"party": party,
		"mode": mode,
		"gmType": gm_type,
		"questFormat": quest_format,
		"partySizeTarget": party_size,
		"fillWithBots": true,
		"mapIds": map_ids,
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

func is_server_connected() -> bool:
	return _is_socket_connected

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
			dice_result_received.emit(data.get("result", {}))
		"gm_narration":
			gm_narration_received.emit(data.get("text", ""))
		"error":
			error_received.emit(data.get("message", "Erreur réseau"))
