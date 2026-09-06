extends SceneTree

## Vérifie que Diffuser / Faire parler ajoutent une ligne visible dans Histoire.

var _failed := false

func _init() -> void:
	call_deferred("_run")
	call_deferred("_arm_watchdog")

func _arm_watchdog() -> void:
	create_timer(45.0).timeout.connect(func():
		print("[STORY LOG] FAIL — délai dépassé")
		quit(1))

func _run() -> void:
	await process_frame
	_seed_demo()

	change_scene_to_file("res://scenes/session/session.tscn")
	await _settle(40)

	var shell: Node = current_scene
	if shell == null or not shell.has_method("describe"):
		print("[STORY LOG] FAIL — coquille introuvable")
		quit(1)
		return

	var gd = get_root().get_node("GameData")
	var mm = get_root().get_node("MultiplayerManager")
	var report: Dictionary = shell.describe()
	var role = shell.model.role
	var log_panel: Control = shell.get_panel("log")
	var log_text: RichTextLabel = log_panel.get_node("%LogText")
	var before_count: int = gd.active_game.get("log", []).size()
	var before_ui := log_text.get_parsed_text()

	print("role=", report.get("role", ""), " can_narrate=", role.can_narrate,
		" kind=", role.kind, " is_mj=", role.is_mj,
		" p2p=", mm.is_p2p_active(), " forcePlayer=", gd.active_game.get("forcePlayerView", false),
		" log_count=", before_count)
	print("ui_before_len=", before_ui.length(), " latest=", log_panel.latest_line())

	_assert("role_gm", str(report.get("role", "")) == "gm")
	_assert("can_narrate", role.can_narrate)
	_assert("not_p2p", not mm.is_p2p_active())

	var console: Node = shell.get_panel("console")
	console.get_node("%NarrationInput").text = "La brume s'écarte et révèle la caravane."
	console.get_node("%BtnNarrate").pressed.emit()
	await _settle(8)

	var after_narrate: Array = gd.active_game.get("log", [])
	var ui_after_narrate: String = log_panel.visible_text()
	print("after_narrate count=", after_narrate.size(), " ui_len=", ui_after_narrate.length(),
		" latest=", log_panel.latest_line())
	if not after_narrate.is_empty():
		print("last_entry=", after_narrate[after_narrate.size() - 1])

	_assert("narrate_grows_log", after_narrate.size() == before_count + 1)
	_assert("narrate_visible_ui", ui_after_narrate.contains("La brume s'écarte"))
	_assert("narrate_latest", log_panel.latest_line().contains("La brume s'écarte"))

	# Chemin démo : placeholder « Choisir un PNJ » encore sélectionné.
	var picker: OptionButton = console.get_node("%NpcPicker")
	picker.select(0)
	console.get_node("%NpcInput").text = "Halte ! Qui va là ?"
	console.get_node("%BtnNpc").pressed.emit()
	await _settle(8)

	var after_npc: Array = gd.active_game.get("log", [])
	var ui_after_npc: String = log_panel.visible_text()
	print("after_npc count=", after_npc.size(), " ui_len=", ui_after_npc.length(),
		" latest=", log_panel.latest_line())
	if not after_npc.is_empty():
		print("last_entry=", after_npc[after_npc.size() - 1])

	_assert("npc_grows_log", after_npc.size() == before_count + 2)
	_assert("npc_visible_ui", ui_after_npc.contains("Halte"))
	_assert("npc_latest", log_panel.latest_line().contains("Halte"))

	if _failed:
		print("[STORY LOG] FAIL")
		quit(1)
	else:
		print("[STORY LOG] PASS")
		quit(0)

func _seed_demo() -> void:
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
	gd.active_game["waitingForGm"] = true
	gd.add_log_entry("Aria", "J'approche la caravane.", "player")
	mm.player_role = "gm"
	mm.player_name = "MJ Demo"
	mm.is_gm = true

func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame

func _assert(label: String, ok: bool) -> void:
	print(("  OK   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true
