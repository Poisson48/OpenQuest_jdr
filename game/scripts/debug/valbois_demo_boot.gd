extends Node

## Boot démo Valbois : vue joueur immersive (carte + HUD) avec Kael.

func _ready() -> void:
	if not GameData.start_valbois_demo_session():
		push_error("[VALBOIS DEMO] Carte Valbois introuvable.")
		get_tree().quit(1)
		return
	print("[VALBOIS DEMO] boot -> session avec Kael")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/session/session.tscn")
