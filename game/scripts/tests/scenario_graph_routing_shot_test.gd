extends SceneTree

## Captures de validation du ROUTAGE des liens (fenêtre cachée).
##
## Produit deux images lisibles par un humain :
##  - `artifacts/routing_after.png` : demo-valbois au zoom 1.0 (câbles routés
##    autour des cartes, coins arrondis, pas d'empilement) ;
##  - `artifacts/routing_actes.png` : petit graphe avec tags « acte-1/acte-2 »
##    montrant les cadres d'actes dessinés SOUS les cartes.
##
## PASS = `scenario_graph_routing_shot_test:PASS`.

const SHOT_DIR := "artifacts"
const QuestNavigation = preload("res://scripts/quest_navigation.gd")

var _failed := false
var _editor: Node = null
var _gd: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  [SKIP] capture d'écran impossible en headless.")
		quit(0)
		return
	await process_frame
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	_gd = get_root().get_node("GameData")
	_gd.editor_scenario_id = "demo-valbois"
	change_scene_to_file("res://scenes/scenario_editor.tscn")
	await _wait_scene("ScenarioEditor")
	_editor = current_scene
	await _wait_graph_ready(_editor)
	await _wait_nodes(9)
	var overlay: Control = _overlay()
	_assert("overlay_present", overlay != null)
	if overlay == null:
		print("scenario_graph_routing_shot_test:FAIL")
		quit(1)
		return

	# 1) Vue lisible du scénario réel : les câbles doivent contourner les cartes.
	_editor.call("_focus_graph_on_scene", "place-du-marche")
	_graph().zoom = 1.0
	await _settle(10)
	overlay.call("force_rebuild")
	await _settle(3)
	var edges: Array = overlay.call("get_debug_edges")
	_assert("valbois_edges", edges.size() >= 20)
	var stats: Dictionary = overlay.call("get_routing_stats")
	_assert("valbois_routed", int(stats.get("routed", 0)) >= 20)
	_assert("valbois_no_card_hits", int(stats.get("hits", 0)) == 0)
	await _capture("routing_after")

	# 2) Cadres d'actes : fixture dédiée avec tags « acte-1 / acte-2 ».
	_editor.set("_scenario", QuestNavigation.normalize_scenario(_act_fixture()))
	_editor.set("_selected_scene_id", "a1-intro")
	_editor.call("_refresh_all")
	await _wait_nodes(4)
	_editor.call("_on_fit_view_pressed")
	await _settle(10)
	overlay.call("force_rebuild")
	await _settle(3)
	var frames: Array = overlay.call("get_debug_act_frames")
	_assert("act_frames_calcules", frames.size() == 2)
	var layer := _graph().get_node_or_null("GraphLinkActFrames")
	_assert("act_layer_sous_les_cartes", layer != null)
	await _capture("routing_actes")

	print("scenario_graph_routing_shot_test:" + ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)


func _act_fixture() -> Dictionary:
	return {
		"id": "test-routing-actes-shot",
		"title": "Graphe actes (capture)",
		"roster": "general",
		"startSceneId": "a1-intro",
		"scenes": [
			{ "id": "a1-intro", "title": "Intro", "tags": ["acte-1", "debut"],
				"graphPos": { "x": 60, "y": 80 }, "transitions": [
					{ "to": "a1-puits", "label": "Descendre", "default": true } ] },
			{ "id": "a1-puits", "title": "Puits", "tags": ["acte-1"],
				"graphPos": { "x": 440, "y": 80 }, "transitions": [
					{ "to": "a2-chapelle", "label": "Sortir" } ] },
			{ "id": "a2-chapelle", "title": "Chapelle", "tags": ["acte-2"],
				"graphPos": { "x": 440, "y": 400 }, "transitions": [
					{ "to": "a2-fin", "label": "Terminer", "default": true } ] },
			{ "id": "a2-fin", "title": "Fin", "tags": ["acte-2", "fin"],
				"graphPos": { "x": 800, "y": 400 }, "transitions": [] },
		],
		"npcs": [],
	}


func _overlay() -> Control:
	if _editor == null:
		return null
	for child in _editor.get_children():
		if child is Control and child.name == "GraphLinkOverlay":
			return child as Control
	return null


func _graph() -> GraphEdit:
	return _editor.get_node("%GraphEdit") as GraphEdit


func _capture(shot_name: String) -> void:
	var root_win := get_root()
	print("    viewport=", root_win.get_visible_rect(), " win=", DisplayServer.window_get_size())
	var img: Image = root_win.get_texture().get_image()
	var copy_dir := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(copy_dir)
	var out := copy_dir.path_join("%s.png" % shot_name)
	img.save_png(out)
	_assert("capture_" + shot_name + "_taille", FileAccess.file_exists(out)
		and FileAccess.get_file_as_bytes(out).size() > 20000)
	print("  capture ", out)


func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame


func _wait_scene(root_name: String, max_frames := 150) -> void:
	for _i in range(max_frames):
		await process_frame
		if current_scene and current_scene.name == root_name:
			await process_frame
			return
	push_warning("Timeout scène: " + root_name)


func _wait_graph_ready(editor: Node, max_frames := 40) -> void:
	for _i in range(max_frames):
		await process_frame
		if not bool(editor.get("_rebuilding_graph")):
			await process_frame
			return


func _wait_nodes(min_count: int, max_frames := 120) -> void:
	for _i in range(max_frames):
		await process_frame
		var nodes := 0
		for child in _graph().get_children():
			if child is GraphNode and is_instance_valid(child) and not child.is_queued_for_deletion():
				nodes += 1
		if nodes >= min_count and not bool(_editor.get("_rebuilding_graph")):
			await _settle(4)
			return


func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  [OK]   ", label)
	else:
		_failed = true
		print("  [FAIL] ", label)
