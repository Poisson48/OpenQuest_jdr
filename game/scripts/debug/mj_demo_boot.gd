extends Node

func _ready() -> void:
	var party: Array = [
		{
			"id": "hero-demo-1",
			"name": "Aria",
			"race": "Elfe",
			"class": "Rôdeuse",
			"hp": 12,
			"ac": 14,
			"isPlayer": true,
			"isHuman": true,
			"isBot": false,
			"clientId": "joueur-demo"
		},
		{
			"id": "hero-demo-2",
			"name": "Thorin",
			"race": "Nain",
			"class": "Guerrier",
			"hp": 14,
			"ac": 16,
			"isPlayer": true,
			"isHuman": true,
			"isBot": false,
			"clientId": "joueur-2-demo"
		},
		{
			"id": "bot-demo-1",
			"name": "Kael",
			"race": "Humain",
			"class": "Rôdeur",
			"hp": 11,
			"ac": 13,
			"isPlayer": false,
			"isHuman": false,
			"isBot": true
		}
	]

	GameData.reload_builtin_scenarios()
	GameData.create_new_game("demo-kharak", "multi", "human", "long", party)
	GameData.active_game["gmName"] = "MJ Demo"
	GameData.active_game["waitingForGm"] = true
	GameData.active_game["turnIndex"] = 1
	GameData.add_log_entry("Aria", "J'approche la caravane prudemment et observe les nomades.", "player")
	GameData.save_active_game()

	MultiplayerManager.player_role = "gm"
	MultiplayerManager.player_name = "MJ Demo"
	MultiplayerManager.is_gm = true

	print("[MJ DEMO] boot -> session demo-kharak human gm")
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")
