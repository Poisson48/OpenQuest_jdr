extends SceneTree

## Géométrie de la session : docks, carte, bascule immersive.
##
## Le test interroge la coquille par son API (`describe()`, `get_panel()`) et
## jamais par des chemins de nœuds : la mise en page peut être retouchée dans
## l'éditeur Godot sans casser ce fichier.

var _failed := false

func _init() -> void:
	call_deferred("_run")
	call_deferred("_arm_watchdog")

## Une erreur de script interrompt `_run` sans jamais appeler `quit()` : sans
## ce garde-fou, le test resterait suspendu indéfiniment.
func _arm_watchdog() -> void:
	create_timer(90.0).timeout.connect(func():
		print("[SESSION LAYOUT] FAIL — délai dépassé")
		quit(1))

func _run() -> void:
	await process_frame
	_seed_game()

	change_scene_to_file("res://scenes/session/session.tscn")
	await _settle(60)

	var shell: Node = current_scene
	if shell == null or not shell.has_method("describe"):
		print("[SESSION LAYOUT] FAIL — coquille introuvable")
		quit(1)
		return

	var viewport: Vector2 = get_root().get_visible_rect().size
	var gm: Dictionary = shell.describe()
	print("viewport=", viewport)
	print("gm=", gm)

	_assert("role_gm", gm["role"] == "gm")
	_assert("header_visible", gm["header_visible"])
	_assert("docks_visible", gm["left_visible"] and gm["right_visible"])
	_assert("gm_tabs_visible", gm["gm_tabs_visible"])

	var body_width: float = gm["left_width"] + gm["center_width"] + gm["right_width"]
	_assert("columns_fit", body_width <= viewport.x + 2.0)
	_assert("map_dominates", gm["center_width"] >= gm["left_width"] and gm["center_width"] >= gm["right_width"])
	_assert("map_tall", gm["center_height"] >= viewport.y * 0.5)
	_assert("no_vertical_overflow", shell.get_node("%Root").get_combined_minimum_size().y <= viewport.y)

	var log_panel: Control = shell.get_panel("log")
	_assert("log_readable", log_panel.size.x >= 240.0 and log_panel.size.y >= 180.0)
	_assert("action_present", shell.get_panel("action").size.y > 40.0)
	_assert("dice_present", shell.get_panel("dice").size.y > 40.0)

	var map_report: Dictionary = gm["map"]
	print("map=", map_report)
	_assert("map_stage_sized", map_report["stage_size"].x > 200.0 and map_report["stage_size"].y > 120.0)
	_assert("map_chrome_visible", map_report["chrome_visible"])
	# Le navigateur affiche une échelle mesurée : 0 signifierait « toujours 100 % ».
	_assert("scale_is_real", map_report["scale"] > 0.0)

	# Une ligne de journal et un jet de dé ne doivent rien redimensionner.
	var before := [gm["left_width"], gm["center_width"], gm["right_width"], gm["center_height"]]
	shell.model.roll("1d20", false)
	get_root().get_node("GameData").add_log_entry(
		"MJ", "Nouvelle narration ajoutée pendant la partie, assez longue pour remplir le cadre.", "gm"
	)
	await _settle(20)
	var after_state: Dictionary = shell.describe()
	var after := [after_state["left_width"], after_state["center_width"],
		after_state["right_width"], after_state["center_height"]]
	print("before=", before, " after=", after)
	_assert("heights_stable", before == after)

	_shot("session_layout_gm")

	# Vue immersive puis retour : la restauration doit être exactement symétrique.
	var gd = get_root().get_node("GameData")
	gd.active_game["forcePlayerView"] = true
	shell.model.refresh(true)
	await _settle(30)
	var immersive: Dictionary = shell.describe()
	print("immersive=", immersive)
	_assert("immersive_preset", immersive["preset"] == "immersive")
	_assert("immersive_header_hidden", not immersive["header_visible"])
	_assert("immersive_docks_hidden", not immersive["left_visible"] and not immersive["right_visible"])
	_assert("immersive_map_full", immersive["center_height"] >= viewport.y * 0.9)
	_assert("immersive_hud", immersive["hud_visible"])
	_assert("immersive_map_chrome_hidden", not immersive["map"]["chrome_visible"])
	_shot("session_layout_player")

	gd.active_game["forcePlayerView"] = false
	shell.model.refresh(true)
	await _settle(30)
	var restored: Dictionary = shell.describe()
	print("restored=", restored)
	_assert("restore_symmetric",
		restored["preset"] == "gm"
		and restored["header_visible"]
		and restored["left_visible"] == after_state["left_visible"]
		and restored["right_visible"] == after_state["right_visible"]
		and absf(restored["center_width"] - after_state["center_width"]) < 1.0
		and absf(restored["center_height"] - after_state["center_height"]) < 1.0)
	_assert("restore_map_chrome", restored["map"]["chrome_visible"])

	if _failed:
		print("[SESSION LAYOUT] FAIL")
		quit(1)
	else:
		print("[SESSION LAYOUT] PASS")
		quit(0)

func _seed_game() -> void:
	var gd = get_root().get_node("GameData")
	var mm = get_root().get_node("MultiplayerManager")
	var party: Array = [
		{"id": "h1", "name": "Aria", "race": "Elfe", "class": "Rôdeuse", "hp": 12, "ac": 14,
			"isPlayer": true, "isHuman": true, "clientId": "j1"},
		{"id": "h2", "name": "Thorin", "race": "Nain", "class": "Guerrier", "hp": 14, "ac": 16,
			"isPlayer": true, "isHuman": true, "clientId": "j2"},
		{"id": "b1", "name": "Kael", "race": "Humain", "class": "Rôdeur", "hp": 11, "ac": 13, "isBot": true},
	]
	gd.reload_builtin_scenarios()
	gd.create_new_game("demo-kharak", "multi", "human", "long", party)
	gd.active_game["waitingForGm"] = true
	for i in range(40):
		gd.add_log_entry("Aria", "Ligne de journal numéro %d, assez longue pour remplir le cadre." % i, "player")
	mm.player_role = "gm"
	mm.player_name = "MJ"
	mm.is_gm = true

func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame

func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		return
	var path := ProjectSettings.globalize_path("user://%s.png" % shot_name)
	img.save_png(path)
	print("shot=", path)

func _assert(label: String, ok: bool) -> void:
	print(("  OK   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true
