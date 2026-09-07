extends SceneTree

## Le MJ contrôle le passage de tour : une action joueur n'avance pas turnIndex.

var _failed := false

func _init() -> void:
	call_deferred("_run")
	call_deferred("_arm_watchdog")

func _arm_watchdog() -> void:
	create_timer(45.0).timeout.connect(func():
		print("[SESSION TURN] FAIL — délai dépassé")
		quit(1))

func _run() -> void:
	await process_frame
	_assert_ai_stub_untouched()
	_seed_human_table()

	change_scene_to_file("res://scenes/session/session.tscn")
	await _settle(40)

	var shell: Node = current_scene
	if shell == null or not shell.has_method("describe"):
		print("[SESSION TURN] FAIL — coquille introuvable")
		quit(1)
		return

	var gd = get_root().get_node("GameData")
	var report: Dictionary = shell.describe()
	print("boot=", report)

	_assert("role_gm", str(report.get("role", "")) == "gm")
	_assert("next_turn_visible", bool(report.get("next_turn_visible", false)))
	_assert("boot_turn_zero", int(gd.active_game.get("turnIndex", -1)) == 0)
	_assert("boot_not_waiting", not bool(gd.active_game.get("waitingForGm", true)))

	var actor_before := str(gd.get_active_member().get("name", ""))
	_assert("actor_aria", actor_before == "Aria")

	gd.apply_player_action("Aria", "J'inspecte le coffre.")
	shell.model.refresh(true)
	await _settle(8)

	report = shell.describe()
	print("after_action=", report)
	_assert("action_sets_wait", bool(gd.active_game.get("waitingForGm", false)))
	_assert("action_keeps_turn", int(gd.active_game.get("turnIndex", -1)) == 0)
	_assert("badge_stays_aria", str(gd.get_active_member().get("name", "")) == "Aria")
	_assert("waiting_headline", str(report.get("turn_headline", "")).contains("Action de Aria"))

	shell.model.narrate("Le coffre est vide.")
	await _settle(8)
	report = shell.describe()
	print("after_narrate=", report)
	_assert("narrate_clears_wait", not bool(gd.active_game.get("waitingForGm", true)))
	_assert("narrate_keeps_turn", int(gd.active_game.get("turnIndex", -1)) == 0)
	_assert("still_aria", str(gd.get_active_member().get("name", "")) == "Aria")

	var console: Node = shell.get_panel("console")
	console.get_node("%BtnNextTurn").pressed.emit()
	await _settle(8)
	report = shell.describe()
	print("after_next=", report)
	_assert("next_clears_wait", not bool(gd.active_game.get("waitingForGm", true)))
	_assert("next_advances", int(gd.active_game.get("turnIndex", -1)) == 1)
	_assert("now_thorin", str(gd.get_active_member().get("name", "")) == "Thorin")
	_assert("next_headline", str(report.get("turn_headline", "")).contains("Thorin"))

	gd.apply_player_action("Thorin", "Je frappe la porte.")
	shell.model.refresh(true)
	await _settle(6)
	var scene_id := _other_scene_id(gd)
	if not scene_id.is_empty():
		shell.model.go_to_scene(scene_id, "Test de scène")
		await _settle(8)
		_assert("scene_keeps_turn", int(gd.active_game.get("turnIndex", -1)) == 1)
		_assert("scene_still_thorin", str(gd.get_active_member().get("name", "")) == "Thorin")

	if _failed:
		print("[SESSION TURN] FAIL")
		quit(1)
	else:
		print("[SESSION TURN] PASS")
		quit(0)

func _assert_ai_stub_untouched() -> void:
	var gd = get_root().get_node("GameData")
	gd.reload_builtin_scenarios()
	gd.create_new_game("demo-kharak", "solo", "ai", "oneshot", [
		{"id": "h1", "name": "Aria", "race": "Elfe", "class": "Rôdeuse", "hp": 12, "ac": 14,
			"isPlayer": true, "isHuman": true},
		{"id": "b1", "name": "Kael", "race": "Humain", "class": "Rôdeur", "hp": 11, "ac": 13,
			"isPlayer": false, "isBot": true},
	])
	gd.apply_player_action("Aria", "Je marche vers la porte.")
	_assert("ai_no_wait", not bool(gd.active_game.get("waitingForGm", true)))
	_assert("ai_turn_untouched", int(gd.active_game.get("turnIndex", -1)) == 0)

func _seed_human_table() -> void:
	var gd = get_root().get_node("GameData")
	var mm = get_root().get_node("MultiplayerManager")
	var party: Array = [
		{"id": "h1", "name": "Aria", "race": "Elfe", "class": "Rôdeuse", "hp": 12, "ac": 14,
			"isPlayer": true, "isHuman": true, "clientId": "j1"},
		{"id": "h2", "name": "Thorin", "race": "Nain", "class": "Guerrier", "hp": 14, "ac": 16,
			"isPlayer": true, "isHuman": true, "clientId": "j2"},
	]
	gd.reload_builtin_scenarios()
	gd.create_new_game("demo-kharak", "multi", "human", "long", party)
	gd.active_game["gmName"] = "MJ Demo"
	gd.active_game["waitingForGm"] = false
	gd.active_game["turnIndex"] = 0
	mm.player_role = "gm"
	mm.player_name = "MJ Demo"
	mm.is_gm = true

func _other_scene_id(gd) -> String:
	var current := str(gd.active_game.get("currentSceneId", ""))
	var scenario: Dictionary = gd.get_scenario_by_id(str(gd.active_game.get("scenarioId", "")))
	for scene_variant in scenario.get("scenes", []):
		if typeof(scene_variant) != TYPE_DICTIONARY:
			continue
		var scene_id := str(scene_variant.get("id", ""))
		if not scene_id.is_empty() and scene_id != current:
			return scene_id
	return ""

func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame

func _assert(label: String, ok: bool) -> void:
	print(("  OK   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true
