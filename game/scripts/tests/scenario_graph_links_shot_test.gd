extends SceneTree

## Captures de validation des LIENS du graphe de scénarios (fenêtre cachée).
##
## Objectif mesurable : les branches doivent être visibles AU-DESSUS des cartes,
## séparées au départ de chaque scène, et re-router quand on déplace les scènes.
## Captures : `scenario_graph_links_*.png` dans `docs/screenshots`.
##
## PASS = `scenario_graph_links_shot_test:PASS`.

const SHOT_DIR := "docs/screenshots"
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
	_gd.editor_scenario_id = ""
	change_scene_to_file("res://scenes/scenario_editor.tscn")
	await _wait_scene("ScenarioEditor")
	_editor = current_scene
	await _wait_graph_ready(_editor)
	var overlay: Control = _overlay()
	_assert("overlay_present", overlay != null)
	if overlay == null:
		print("scenario_graph_links_shot_test:FAIL")
		quit(1)
		return

	# 1) Scénario réel chargé (Valbois, 9 scènes / 27 branches).
	_gd.editor_scenario_id = "demo-valbois"
	_editor.call("_load_scenario")
	_editor.call("_refresh_all")
	await _wait_nodes(9)
	_editor.call("_on_fit_view_pressed")
	await _settle(14)
	var valbois_edges: Array = overlay.call("get_debug_edges")
	_assert("valbois_edges", valbois_edges.size() >= 20)
	# A/B : rendu natif de GraphEdit (liens SOUS les cartes) vs overlay.
	overlay.set_process(false)
	overlay.visible = false
	for child in _graph().get_children():
		if child is GraphNode:
			(child as GraphNode).set_slot(0, true, 0, ThemeColors.GOLD_LIGHT, true, 0, ThemeColors.GOLD_LIGHT)
	await _settle(8)
	await _capture("scenario_graph_links_avant")
	for child in _graph().get_children():
		if child is GraphNode:
			(child as GraphNode).set_slot(0, true, 0, Color(0, 0, 0, 0), true, 0, Color(0, 0, 0, 0))
	overlay.set_process(true)
	overlay.visible = true
	await _settle(8)
	await _capture("scenario_graph_links_valbois")

	# 2) Graphe dense : peignes de séparation, cartes superposées, détours.
	var fixture := _dense_fixture()
	_editor.set("_scenario", QuestNavigation.normalize_scenario(fixture))
	_editor.set("_selected_scene_id", "hub")
	_editor.call("_refresh_all")
	await _wait_nodes(9)
	_editor.call("_on_fit_view_pressed")
	await _settle(14)
	var dense_edges: Array = overlay.call("get_debug_edges")
	_assert("dense_edges", dense_edges.size() == 8)
	var fan_ok := _fan_separated(dense_edges, "hub")
	if not fan_ok:
		print("    DEBUG fan=", _fan_debug(dense_edges, "hub"))
	_assert("dense_fan_separated", fan_ok)
	await _capture("scenario_graph_links_dense")

	# 3bis) Gros plan : détours calculés autour d'une carte posée sur un lien.
	_graph().zoom = 0.9
	_editor.call("_focus_graph_on_scene", "obstacle")
	await _settle(12)
	dense_edges = overlay.call("get_debug_edges")
	var avoid_ok := _edge_avoids_card(dense_edges, "long-left", "far-right", "obstacle")
	if not avoid_ok:
		print("    DEBUG avoid: ", _avoid_debug(dense_edges, "long-left", "far-right", "obstacle"))
	_assert("dense_obstacle_avoided", avoid_ok)
	await _capture("scenario_graph_links_zoom")

	# 4) Déplacement d'une scène : les liens la suivent et re-routent.
	var moved := false
	for child in _graph().get_children():
		if child is GraphNode and str(child.get_meta("scene_id", "")) == "obstacle":
			child.position_offset = Vector2(430.0, 520.0)
			_editor.call("_persist_graph_node_layout", child)
			_editor.call("_on_graph_end_node_move")
			moved = true
			break
	_assert("moved_node", moved)
	await _settle(12)
	await _capture("scenario_graph_links_moved")

	print("scenario_graph_links_shot_test:" + ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)


func _dense_fixture() -> Dictionary:
	# Graphe volontairement piégeux : un carrefour à 5 sorties, des cartes qui
	# se chevauchent, une carte posée AU MILIEU d'un lien, et des retours.
	var scenes: Array = [
		{ "id": "hub", "title": "Carrefour", "tags": ["carrefour"],
			"graphPos": { "x": 300, "y": 260 }, "graphSize": { "w": 240, "h": 150 },
			"transitions": [
				{ "to": "n1", "label": "Monter au nord", "default": true },
				{ "to": "n2", "label": "Descendre au sud" },
				{ "to": "n3", "label": "Suivre la rivière" },
				{ "to": "n4", "label": "Passer la porte" },
				{ "to": "n5", "label": "Prendre le raccourci", "gmOnly": true },
			] },
		{ "id": "n1", "title": "Nord", "graphPos": { "x": 640, "y": 40 }, "transitions": [] },
		{ "id": "n2", "title": "Sud", "graphPos": { "x": 640, "y": 150 }, "transitions": [
			{ "to": "hub", "label": "Revenir", "gmOnly": true } ] },
		{ "id": "n3", "title": "Rivière", "graphPos": { "x": 650, "y": 262 }, "transitions": [] },
		{ "id": "n4", "title": "Porte", "graphPos": { "x": 660, "y": 374 }, "transitions": [] },
		{ "id": "n5", "title": "Raccourci", "graphPos": { "x": 660, "y": 480 }, "transitions": [] },
		{ "id": "long-left", "title": "Lointain ouest", "graphPos": { "x": 40, "y": 250 },
			"transitions": [
				{ "to": "far-right", "label": "Traverser la carte" },
				{ "to": "hub", "label": "Rejoindre le carrefour", "default": true },
			] },
		{ "id": "obstacle", "title": "Carte posée sur le lien", "graphPos": { "x": 380, "y": 236 },
			"graphSize": { "w": 200, "h": 110 }, "transitions": [] },
		{ "id": "far-right", "title": "Lointain est", "graphPos": { "x": 980, "y": 250 },
			"transitions": [] },
	]
	return {
		"id": "shot-dense",
		"title": "Graphe dense (capture)",
		"roster": "general",
		"startSceneId": "hub",
		"scenes": scenes,
		"npcs": [],
	}


## Les branches sortant d'une scène ne doivent pas partager le même point de
## départ après le peigne : on vérifie les décalages de sortie calculés.
func _fan_separated(edges: Array, from_id: String) -> bool:
	var offsets: Array = []
	for edge in edges:
		var e: Dictionary = edge
		if str(e.get("from_id", "")) != from_id:
			continue
		offsets.append(snappedf(float(e.get("fan_out", 0.0)), 0.5))
	offsets.sort()
	for i in range(1, offsets.size()):
		if absf(float(offsets[i]) - float(offsets[i - 1])) < 6.0:
			return false
	return offsets.size() >= 4


## Le lien long ne doit pas traverser la carte `obstacle` posée au milieu.
func _edge_avoids_card(edges: Array, from_id: String, to_id: String, card_id: String) -> bool:
	var card_rect := Rect2()
	for child in _graph().get_children():
		if child is GraphNode and str(child.get_meta("scene_id", "")) == card_id:
			var gt: Transform2D = child.get_global_transform()
			var p0: Vector2 = gt * Vector2.ZERO
			var p1: Vector2 = gt * (child as GraphNode).size
			card_rect = Rect2(p0, p1 - p0).abs()
			break
	if card_rect.size.x < 1.0:
		return false
	for edge in edges:
		var e: Dictionary = edge
		if str(e.get("from_id", "")) != from_id or str(e.get("to_id", "")) != to_id:
			continue
		var overlay_origin: Vector2 = _overlay().get_global_position()
		var pts: PackedVector2Array = e.get("points", PackedVector2Array())
		for i in range(pts.size()):
			if i % 2 == 1:
				continue
			if card_rect.has_point(pts[i] + overlay_origin):
				return false
		return true
	return false


func _fan_debug(edges: Array, from_id: String) -> Array:
	var out: Array = []
	for edge in edges:
		var e: Dictionary = edge
		if str(e.get("from_id", "")) != from_id:
			continue
		out.append({ "to": e.get("to_id", ""), "fan_out": e.get("fan_out", 0.0) })
	return out


func _avoid_debug(edges: Array, from_id: String, to_id: String, card_id: String) -> Dictionary:
	var card_rect := Rect2()
	for child in _graph().get_children():
		if child is GraphNode and str(child.get_meta("scene_id", "")) == card_id:
			var gt: Transform2D = child.get_global_transform()
			var p0: Vector2 = gt * Vector2.ZERO
			var p1: Vector2 = gt * (child as GraphNode).size
			card_rect = Rect2(p0, p1 - p0).abs()
			break
	var origin: Vector2 = _overlay().get_global_position()
	for edge in edges:
		var e: Dictionary = edge
		if str(e.get("from_id", "")) != from_id or str(e.get("to_id", "")) != to_id:
			continue
		var pts: PackedVector2Array = e.get("points", PackedVector2Array())
		var hits: Array = []
		for i in range(pts.size()):
			if card_rect.has_point(pts[i] + origin):
				hits.append(i)
		return { "origin": origin, "card": card_rect, "points": pts, "hits": hits }
	return { "error": "edge not found", "edges": edges.size(), "origin": origin, "card": card_rect }


func _overlay() -> Control:
	if _editor == null:
		return null
	for child in _editor.get_children():
		if child.name == "GraphLinkOverlay" and child is Control:
			return child as Control
	return null


func _graph() -> GraphEdit:
	return _editor.get_node("%GraphEdit") as GraphEdit


func _capture(shot_name: String) -> void:
	var root_win := get_root()
	print("    viewport=", root_win.get_visible_rect(), " win=", DisplayServer.window_get_size(),
		" content_scale=", root_win.content_scale_size,
		" editor_size=", _editor.size if _editor != null else Vector2.ZERO)
	var img: Image = get_root().get_texture().get_image()
	var copy_dir := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(copy_dir)
	var out := copy_dir.path_join("%s.png" % shot_name)
	img.save_png(out)
	print("  capture ", shot_name)


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


## Attend que le graphe contienne réellement ses scènes (rebuild différé inclus).
func _wait_nodes(min_count: int, max_frames := 90) -> void:
	for _i in range(max_frames):
		await process_frame
		var nodes := 0
		for child in _graph().get_children():
			if child is GraphNode and is_instance_valid(child) and not child.is_queued_for_deletion():
				nodes += 1
		if nodes >= min_count and not bool(_editor.get("_rebuilding_graph")):
			await _settle(3)
			return


func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  [OK]   ", label)
	else:
		_failed = true
		print("  [FAIL] ", label)
