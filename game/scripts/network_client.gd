extends Node
class_name NetworkClient

signal connected(player_id: String, player_name: String)
signal disconnected
signal state_synced(players: Array)
signal error_received(message: String)

@export var server_url: String = "ws://127.0.0.1:8080"
@export var player_name: String = "Joueur"

var _socket: WebSocketPeer = WebSocketPeer.new()
var _player_id: String = ""
var _is_connected: bool = false

func _ready() -> void:
	connect_to_server()

func connect_to_server() -> void:
	var url := "%s?name=%s" % [server_url, player_name.uri_encode()]
	var err := _socket.connect_to_url(url)
	if err != OK:
		push_error("Impossible de se connecter : %s" % err)
		error_received.emit("Connexion impossible")

func _process(_delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _is_connected:
				_is_connected = true
			_handle_incoming()
		WebSocketPeer.STATE_CLOSED:
			if _is_connected:
				_is_connected = false
				disconnected.emit()

func send_input(move_x: float, move_y: float) -> void:
	if not _is_connected:
		return
	var msg := {"type": "player_input", "input": {"moveX": move_x, "moveY": move_y}}
	_socket.send_text(JSON.stringify(msg))

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
			connected.emit(_player_id, data.get("playerName", ""))
		"state_sync":
			state_synced.emit(data.get("players", []))
		"error":
			error_received.emit(data.get("message", "Erreur inconnue"))

func get_player_id() -> String:
	return _player_id

func is_connected() -> bool:
	return _is_connected
