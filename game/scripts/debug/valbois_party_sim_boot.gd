extends Node

## Boot debug : table Valbois 3J+MJ+15 PNJ, puis simulation accélérée visible.

const SimulatorScript = preload("res://scripts/debug/valbois_session_simulator.gd")

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	md.load_maps()

	if not GameData.start_valbois_party_session():
		push_error("[VALBOIS PARTY SIM] Impossible de démarrer la table.")
		get_tree().quit(1)
		return

	# Le simulateur vit sur la racine : le boot est détruit au change_scene.
	var sim: Node = SimulatorScript.new()
	sim.name = "ValboisSessionSimulator"
	sim.step_delay = 0.9
	sim.quit_on_finish = false
	sim.keep_window_open = true
	get_tree().root.add_child(sim)

	print("[VALBOIS PARTY SIM] boot -> session MJ + simulateur UI")
	get_tree().change_scene_to_file.call_deferred("res://scenes/session/session.tscn")
	sim.call_deferred("start_when_session_ready")
