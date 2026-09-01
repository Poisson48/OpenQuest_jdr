extends Node2D

@onready var network: NetworkClient = $NetworkClient
@onready var status_label: Label = $UI/StatusLabel
@onready var players_node: Node2D = $Players

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PLAYER_COLORS := [Color.CORNFLOWER_BLUE, Color.SALMON, Color.MEDIUM_SEA_GREEN, Color.GOLD]

var _player_nodes: Dictionary = {}

func _ready() -> void:
	network.connected.connect(_on_connected)
	network.disconnected.connect(_on_disconnected)
	network.state_synced.connect(_on_state_synced)
	network.error_received.connect(_on_error)

func _process(_delta: float) -> void:
	if not network.is_connected():
		return

	var move_x := Input.get_axis("ui_left", "ui_right")
	var move_y := Input.get_axis("ui_up", "ui_down")

	if move_x != 0.0 or move_y != 0.0:
		network.send_input(move_x, move_y)

func _on_connected(player_id: String, player_name: String) -> void:
	status_label.text = "Connecté en tant que %s" % player_name

func _on_disconnected() -> void:
	status_label.text = "Déconnecté du serveur"

func _on_error(message: String) -> void:
	status_label.text = "Erreur : %s" % message

func _on_state_synced(players: Array) -> void:
	var seen: Dictionary = {}

	for i in players.size():
		var data: Dictionary = players[i]
		var id: String = data.get("id", "")
		if id.is_empty():
			continue
		seen[id] = true

		if not _player_nodes.has(id):
			var node: Node2D = PLAYER_SCENE.instantiate()
			node.name = id
			var color: Color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
			node.set("player_color", color)
			node.set("player_name", data.get("name", "???"))
			players_node.add_child(node)
			_player_nodes[id] = node

		var player_node: Node2D = _player_nodes[id]
		player_node.position = Vector2(data.get("x", 0.0), data.get("y", 0.0))

	for id in _player_nodes.keys():
		if not seen.has(id):
			_player_nodes[id].queue_free()
			_player_nodes.erase(id)
