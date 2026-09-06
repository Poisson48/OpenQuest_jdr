extends SceneTree

## Vue joueur immersive sur une carte illustrée : carte plein cadre + HUD.
## À lancer SANS --headless pour obtenir la capture.

const OUT_DIR := "user://valbois_screenshots"
const DOCS_DIR := "res://../docs/screenshots"
const PORTRAIT_RES := "res://assets/portraits/voleur_kael.png"

var _failed := false

func _init() -> void:
	call_deferred("_run")
	call_deferred("_arm_watchdog")

func _arm_watchdog() -> void:
	create_timer(90.0).timeout.connect(func():
		print("[VALBOIS PLAYER HUD] FAIL — délai dépassé")
		quit(1))

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")
	var mm = get_root().get_node("MultiplayerManager")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var village := _find_valbois(md)
	_assert("village_found", not village.is_empty())
	if _failed:
		quit(1)
		return
	_seed_game(gd, mm, village)

	DisplayServer.window_set_title("Valbois player HUD")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_root().size = Vector2i(1280, 720)

	change_scene_to_file("res://scenes/session/session.tscn")
	for _i in range(90):
		await process_frame

	var shell: Node = current_scene
	_assert("shell_ready", shell != null and shell.has_method("describe"))
	if not shell.has_method("describe"):
		quit(1)
		return

	var report: Dictionary = shell.describe()
	print("report=", report)
	var hud: Control = shell.get_player_hud()

	_assert("immersive", shell.is_immersive())
	_assert("role_is_player", report["role"] != "gm")
	_assert("hud_visible", hud != null and hud.visible)
	_assert("header_hidden", not report["header_visible"])
	_assert("docks_hidden", not report["left_visible"] and not report["right_visible"])

	var map_report: Dictionary = report["map"]
	_assert("map_complex", map_report["mode"] == "complex")
	_assert("map_filtered_for_player", not map_report["is_gm"])
	_assert("map_full_bleed", map_report["stage_size"].y >= 500.0)
	_assert("map_chrome_hidden", not map_report["chrome_visible"])
	_assert("scale_is_real", map_report["scale"] > 0.0)

	await _shot("05_valbois_player_hud")

	if _failed:
		print("[VALBOIS PLAYER HUD] FAIL")
		quit(1)
	else:
		print("[VALBOIS PLAYER HUD] PASS")
		quit(0)

func _seed_game(gd, mm, village: Dictionary) -> void:
	var village_id := str(village.get("id", ""))
	var portrait := PORTRAIT_RES if ResourceLoader.exists(PORTRAIT_RES) else ""
	var party: Array = [{
		"id": "hero-kael-voleur", "name": "Kael", "race": "Humain", "class": "Voleur",
		"hp": 11, "ac": 14, "isPlayer": true, "isHuman": true,
		"portrait": portrait, "image": portrait,
		"stats": {"str": 10, "dex": 16, "con": 12, "int": 11, "wis": 13, "cha": 9},
	}]

	gd.reload_builtin_scenarios()
	gd.create_new_game("demo-couronne-fracturee", "solo", "human", "long", party, [village_id])
	gd.active_game["waitingForGm"] = false
	gd.active_game["forcePlayerView"] = true
	gd.active_game["mapModeOverrides"] = {village_id: "complex"}
	gd.active_game["mapNavigation"] = {
		"view": "local", "localMapId": village_id, "worldMapId": null,
		"worldCell": null, "areaStack": [],
	}
	gd.ensure_map_play_state()
	var w: int = int(village.get("width", 20))
	var h: int = int(village.get("height", 16))
	gd.place_member_token(village_id, int(w * 0.5), int(h * 0.58), "hero-kael-voleur")
	gd.add_log_entry("Kael", "Test HUD immersif.", "player")
	gd.save_active_game()

	mm.player_role = "player"
	mm.player_name = "Kael"
	mm.is_gm = false

func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img == null:
		return
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot_name])
	img.save_png(path)
	var docs := ProjectSettings.globalize_path(DOCS_DIR)
	if DirAccess.dir_exists_absolute(docs):
		img.save_png("%s/%s.png" % [docs, shot_name])
	print("[SHOT] ", path, " ", img.get_width(), "x", img.get_height())

func _find_valbois(md) -> Dictionary:
	var best: Dictionary = {}
	for m_variant in md.maps:
		var m: Dictionary = m_variant
		if not str(m.get("title", "")).begins_with("Valbois — Village"):
			continue
		if str(m.get("backgroundImage", "")).is_empty():
			continue
		best = m
	return best

func _assert(label: String, ok: bool) -> void:
	print(("  OK   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true
