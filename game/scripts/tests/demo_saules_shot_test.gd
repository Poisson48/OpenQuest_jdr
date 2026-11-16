extends SceneTree

## Captures de la carte de démonstration **Le passage des Saules** importée
## depuis un fichier JSON, avec les volumes 3D de la livraison externe :
##   • vue éditeur (Échap → Importer JSON, puis carte affichée) ;
##   • vue session (bouton « Tester ») avec Aria sur le pont ;
##   • vue rapprochée du pont traversable.
##
## Non headless : nécessite un rendu réel (fenêtre cachée via run_tests.ps1).
## Lancement direct :
##   godot --path game --script res://scripts/tests/demo_saules_shot_test.gd

const DEMO_JSON := "A:/Leo/Downloads/OpenQuest - Le passage des Saules.json"
const OUT_DIR := "user://demo_saules_shots"
const COPY_DIR := "docs/screenshots"

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  [SKIP] capture d'écran impossible en headless.")
		quit(0)
		return
	await process_frame
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var copy_dir := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join(COPY_DIR)
	DirAccess.make_dir_recursive_absolute(copy_dir)

	DisplayServer.window_set_title("Le passage des Saules — éditeur")
	get_root().content_scale_factor = 1.0
	DisplayServer.window_set_size(Vector2i(1920, 1200))
	get_root().size = Vector2i(1920, 1200)

	# 1) Carte complexe vide, puis import JSON par le chemin réel de l'éditeur.
	var map: Dictionary = md.create_complex_map("Le passage des Saules", "general", "local", 26, 18)
	if map.is_empty():
		_fail("empty_map")
		return
	var map_id := str(map.get("id", ""))
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(editor)
	await process_frame
	editor.size = editor.get_viewport_rect().size
	editor.load_map(map)
	editor.set_editable(true)
	await process_frame
	if not FileAccess.file_exists(DEMO_JSON):
		_fail("json_absent")
		return
	editor._on_import_selected(DEMO_JSON)
	for _i in range(30):
		await process_frame
	_assert("imported_title", str(editor.doc.map_data.get("title", "")) == "Le passage des Saules")
	_assert("imported_river", editor.doc.water_bodies().size() >= 1)
	_assert("imported_bridge", editor.doc.count_of_kind("mesh") >= 20)
	_assert("imported_heights", (editor.doc.terrain_heights() as Array).size() == 26 * 18)
	# Comme le bouton « Tester » : la carte doit être enregistrée dans MapData
	# avant la session (sinon la session lirait la carte vide d'origine).
	editor.save_now()
	for _i in range(6):
		await process_frame
	var engine: Control = editor._engine
	engine.request_fit_to_view()
	for _i in range(24):
		await process_frame
	_capture(copy_dir, "demo_saules_editeur.png")

	# 2) Bibliothèque d'objets 3D ouverte (volumes de la livraison externe).
	editor._on_dock_tool_pressed("mesh")
	for _i in range(18):
		await process_frame
	_capture(copy_dir, "demo_saules_bibliotheque.png")

	# 3) Session de jeu (bouton « Tester ») : Aria sur le pont.
	var party := [
		{"id": "hero-aria", "name": "Aria", "class": "Aventurière", "hp": 12, "ac": 14,
			"isPlayer": true, "portrait": "", "image": "", "stats": {}},
	]
	gd.create_new_game("demo-saules", "solo", "human", "oneshot", party.duplicate(true), [map_id])
	gd.ensure_map_play_state()
	gd.active_game["currentMapId"] = map_id
	gd.active_game["mapNavigation"] = {
		"view": "local", "worldMapId": null, "localMapId": map_id, "worldCell": null,
	}
	gd.active_game["mapIds"] = [map_id]
	gd.save_active_game()
	gd.place_complex_member_token(map_id, 16.25, 8.55, "hero-aria")
	var entry: Dictionary = gd.get_map_play_entry(map_id)
	(entry["tokens"] as Array).append({
		"id": "tok-npc-passeur", "kind": "npc", "label": "Passeur",
		"x": 18.6, "y": 6.4, "hp": 10, "maxHp": 10,
	})
	gd.save_map_play_and_sync()
	editor.queue_free()
	for _i in range(6):
		await process_frame
	var session: Node = (load("res://scenes/session/session.tscn") as PackedScene).instantiate()
	get_root().add_child(session)
	if session is Control:
		(session as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for _i in range(50):
		await process_frame
	for overlay in session.find_children("*", "SpeakerDialogueOverlay", true, false):
		if overlay.has_method("clear"):
			overlay.clear()
	for _i in range(8):
		await process_frame
	_capture(copy_dir, "demo_saules_session.png")

	# 4) Vue rapprochée du pont (caméra cadrée sur la travée).
	var engines := session.find_children("*", "ComplexMapEngine3D", true, false)
	if engines.is_empty():
		var layered := session.find_children("*", "Control", true, false)
		for candidate in layered:
			if candidate.has_method("focus_grid_rect"):
				engines = [candidate]
				break
	if engines.is_empty():
		_fail("session_engine_absent")
	else:
		var view = engines[0]
		view.focus_grid_rect(Rect2(13.6, 7.2, 5.4, 2.8), 1.15)
		for _i in range(24):
			await process_frame
		_capture(copy_dir, "demo_saules_pont.png")

	# Nettoyage : la carte de démo ne doit pas rester dans le monde local.
	md.delete_map(map_id)
	for _i in range(3):
		await process_frame
	if _failed:
		printerr("demo_saules_shot_test:FAIL")
		quit(1)
		return
	print("demo_saules_shot_test:PASS")
	quit(0)

func _capture(copy_dir: String, name: String) -> void:
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		_fail("capture_" + name)
		return
	img.convert(Image.FORMAT_RGBA8)
	var out := copy_dir.path_join(name)
	img.save_png(out)
	print("  capture: ", out, " (", img.get_width(), "x", img.get_height(), ")")

func _fail(name: String) -> void:
	_failed = true
	printerr("  [FAIL] ", name)

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		printerr("  [FAIL] ", name, " ", detail)
	else:
		print("  ✓ ", name)
