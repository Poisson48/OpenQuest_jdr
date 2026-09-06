extends Node

## Boot démo Valbois en vue JOUEUR : carte plein écran + HUD overlay.

func _ready() -> void:
	if not GameData.start_valbois_demo_session():
		push_error("[VALBOIS PLAYER] Carte Valbois introuvable.")
		get_tree().quit(1)
		return
	GameData.active_game["forcePlayerView"] = true
	GameData.active_game["gmName"] = "MJ Distant"
	GameData.save_active_game()
	MultiplayerManager.player_role = "player"
	MultiplayerManager.player_name = "Kael"
	MultiplayerManager.is_gm = false
	print("[VALBOIS PLAYER] immersive HUD avec Kael")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/session/session.tscn")
