extends Node

## Boot partie démo enquête : « Scénario Démo » (colonel Moutarde) en session MJ.

func _ready() -> void:
	if not GameData.start_scenario_demo_session():
		push_error("[SCENARIO DEMO] Impossible de démarrer la partie démo enquête.")
		get_tree().quit(1)
		return
	print("[SCENARIO DEMO] boot -> session MJ « Scénario Démo »")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/session/session.tscn")
