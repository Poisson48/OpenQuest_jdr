extends Node2D

@export var player_color: Color = Color.CORNFLOWER_BLUE:
	set(value):
		player_color = value
		if is_node_ready():
			$Body.color = value

@export var player_name: String = "Joueur":
	set(value):
		player_name = value
		if is_node_ready():
			$NameLabel.text = value

func _ready() -> void:
	$Body.color = player_color
	$NameLabel.text = player_name
