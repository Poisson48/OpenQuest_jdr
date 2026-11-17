extends SceneTree

## Tests headless de l'overlay des LIENS du graphe de scénarios.
##
## Couvre ce que `scenario_editor_test` ne couvre pas : les branches sont
## dessinées au-dessus des cartes, séparées au port, re-routées au déplacement,
## et les libellés/sémantiques (défaut, MJ seul) sont corrects.

const REPORT_PATH := "user://scenario_graph_links_test_report.json"
const QuestNavigation = preload("res://scripts/quest_navigation.gd")

var _steps: Array = []
var _failed := false
var _gd: Node
var _editor: Node = null
var _overlay: Control = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_gd = get_root().get_node("GameData")
	await process_frame

	await _step("editor_charges_valbois", func():
		_gd.editor_scenario_id = "demo-valbois"
		change_scene_to_file("res://scenes/scenario_editor.tscn")
		await _wait_scene("ScenarioEditor")
		_editor = current_scene
		await _wait_nodes(9)
		_overlay = _find_overlay()
		return {
			"overlay": _overlay != null,
			"top_level": _overlay.top_level if _overlay != null else false,
			"mouse_ignore": _overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE if _overlay != null else false,
			"ok": _overlay != null and _overlay.top_level
				and _overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		}
	)

	await _step("liens_natifs_masques", func():
		var all_hidden := true
		var count := 0
		for child in _graph().get_children():
			if child is GraphNode and is_instance_valid(child) and not child.is_queued_for_deletion():
				count += 1
				var lc: Color = (child as GraphNode).get_slot_color_left(0)
				var rc: Color = (child as GraphNode).get_slot_color_right(0)
				if lc.a > 0.001 or rc.a > 0.001:
					all_hidden = false
		return { "nodes": count, "all_hidden": all_hidden, "ok": count == 9 and all_hidden }
	)

	await _step("une_arete_par_transition", func():
		var scenario: Dictionary = _editor.get("_scenario")
		var transitions := 0
		for scene in scenario.get("scenes", []):
			transitions += scene.get("transitions", []).size()
		var edges: Array = _overlay.call("get_debug_edges")
		return {
			"transitions": transitions,
			"edges": edges.size(),
			"ok": edges.size() == transitions and transitions >= 20,
		}
	)

	await _step("peigne_de_separation", func():
		var scenario: Dictionary = _editor.get("_scenario")
		var reference_id := ""
		var outgoing := 0
		for scene in scenario.get("scenes", []):
			var n: int = scene.get("transitions", []).size()
			if n >= 3:
				reference_id = str(scene.get("id", ""))
				outgoing = n
				break
		var offsets: Array = []
		for edge in _overlay.call("get_debug_edges"):
			var e: Dictionary = edge
			if str(e.get("from_id", "")) == reference_id:
				offsets.append(snappedf(float(e.get("fan_out", 0.0)), 0.5))
		offsets.sort()
		var separated := offsets.size() == outgoing
		for i in range(1, offsets.size()):
			if absf(float(offsets[i]) - float(offsets[i - 1])) < 6.0:
				separated = false
		return {
			"scene": reference_id, "branches": outgoing, "offsets": offsets,
			"ok": separated and outgoing >= 3,
		}
	)

	await _step("semantique_defaut_et_mj", func():
		var default_ok := false
		var gm_only_ok := false
		var label_default := ""
		var label_gm := ""
		for edge in _overlay.call("get_debug_edges"):
			var e: Dictionary = edge
			if str(e.get("from_id", "")) == "retour-a-valbois" and str(e.get("to_id", "")) == "place-du-marche":
				default_ok = bool(e.get("default", false)) and not bool(e.get("gm_only", false))
				label_default = str(_overlay.call("_label_text", e))
			if bool(e.get("gm_only", false)) and label_gm.is_empty():
				gm_only_ok = true
				label_gm = str(_overlay.call("_label_text", e))
		return {
			"default": default_ok, "label_default": label_default,
			"gm_only": gm_only_ok, "label_gm": label_gm,
			"ok": default_ok and gm_only_ok
				and label_default.begins_with("★ ")
				and label_gm.begins_with("MJ · "),
		}
	)

	await _step("survol_d_un_lien", func():
		var target: Dictionary = {}
		for edge in _overlay.call("get_debug_edges"):
			if str((edge as Dictionary).get("from_id", "")) == "place-du-marche":
				target = edge
				break
		if target.is_empty():
			return { "error": "aucun lien depuis place-du-marche" }
		var mid: Vector2 = target.get("mid", Vector2.ZERO)
		var global_mid: Vector2 = _overlay.get_global_transform() * mid
		_overlay.call("set_hover_global", global_mid)
		await process_frame
		await process_frame
		var hovered: Dictionary = _overlay.call("get_hovered_edge")
		var hover_ok := not hovered.is_empty() \
			and str(hovered.get("from_id", "")) == "place-du-marche" \
			and str(hovered.get("to_id", "")) == str(target.get("to_id", ""))
		# Survoler une carte ne doit pas surcharger un lien qui passe dessous.
		var node_center := Vector2.ZERO
		for child in _graph().get_children():
			if child is GraphNode and str(child.get_meta("scene_id", "")) == "place-du-marche":
				node_center = (child as GraphNode).get_global_rect().get_center()
				break
		_overlay.call("set_hover_global", node_center)
		await process_frame
		await process_frame
		var hovered_over_node: Dictionary = _overlay.call("get_hovered_edge")
		return {
			"scene_hovered": not hovered.is_empty(),
			"hovered_to": hovered.get("to_id", ""),
			"over_node_empty": hovered_over_node.is_empty(),
			"ok": hover_ok and hovered_over_node.is_empty(),
		}
	)

	await _step("deplacement_reroute", func():
		var node: GraphNode = null
		for child in _graph().get_children():
			if child is GraphNode and str(child.get_meta("scene_id", "")) == "piste-bijou":
				node = child
				break
		if node == null:
			return { "error": "piste-bijou absente" }
		var before := _edge_points("place-du-marche", "piste-bijou")
		node.position_offset = node.position_offset + Vector2(0.0, 120.0)
		_editor.call("_persist_graph_node_layout", node)
		_overlay.call("force_rebuild")
		await process_frame
		var after := _edge_points("place-du-marche", "piste-bijou")
		var moved := _endpoint_changed(before, after)
		return { "before_n": before.size(), "after_n": after.size(), "moved": moved, "ok": moved }
	)

	await _step("detour_autour_d_une_carte", func():
		var fixture := _dense_fixture()
		_editor.set("_scenario", QuestNavigation.normalize_scenario(fixture))
		_editor.set("_selected_scene_id", "hub")
		_editor.call("_refresh_all")
		await _wait_nodes(9)
		_graph().zoom = 0.8
		_overlay.call("force_rebuild")
		await process_frame
		var edges: Array = _overlay.call("get_debug_edges")
		var card_rect := _node_global_rect("obstacle")
		var origin: Vector2 = _overlay.get_global_position()
		var found := false
		var clear := false
		for edge in edges:
			var e: Dictionary = edge
			if str(e.get("from_id", "")) != "long-left" or str(e.get("to_id", "")) != "far-right":
				continue
			found = true
			clear = true
			var pts: PackedVector2Array = e.get("points", PackedVector2Array())
			for pt in pts:
				if card_rect.grow(2.0).has_point((pt as Vector2) + origin):
					clear = false
					break
		return { "edge_found": found, "clear": clear, "ok": found and clear }
	)

	_write_report()
	quit(0 if not _failed else 1)


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

func _dense_fixture() -> Dictionary:
	return {
		"id": "test-links-dense",
		"title": "Graphe dense (test)",
		"roster": "general",
		"startSceneId": "hub",
		"scenes": [
			{ "id": "hub", "title": "Carrefour", "graphPos": { "x": 300, "y": 260 },
				"graphSize": { "w": 240, "h": 150 }, "transitions": [
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
			{ "id": "far-right", "title": "Lointain est", "graphPos": { "x": 980, "y": 250 }, "transitions": [] },
		],
		"npcs": [],
	}


func _edge_points(from_id: String, to_id: String) -> PackedVector2Array:
	for edge in _overlay.call("get_debug_edges"):
		var e: Dictionary = edge
		if str(e.get("from_id", "")) == from_id and str(e.get("to_id", "")) == to_id:
			return e.get("points", PackedVector2Array())
	return PackedVector2Array()


func _endpoint_changed(before: PackedVector2Array, after: PackedVector2Array) -> bool:
	if before.is_empty() or after.is_empty():
		return false
	return before[before.size() - 1].distance_to(after[after.size() - 1]) > 4.0


func _node_global_rect(scene_id: String) -> Rect2:
	for child in _graph().get_children():
		if child is GraphNode and str(child.get_meta("scene_id", "")) == scene_id:
			var gt: Transform2D = (child as Control).get_global_transform()
			var p0: Vector2 = gt * Vector2.ZERO
			var p1: Vector2 = gt * (child as Control).size
			return Rect2(p0, p1 - p0).abs()
	return Rect2()


func _find_overlay() -> Control:
	if _editor == null:
		return null
	for child in _editor.get_children():
		if child is Control and child.name == "GraphLinkOverlay":
			return child as Control
	return null


func _graph() -> GraphEdit:
	return _editor.get_node("%GraphEdit") as GraphEdit


func _wait_nodes(min_count: int, max_frames := 120) -> void:
	for _i in range(max_frames):
		await process_frame
		var nodes := 0
		for child in _graph().get_children():
			if child is GraphNode and is_instance_valid(child) and not child.is_queued_for_deletion():
				nodes += 1
		if nodes >= min_count and not bool(_editor.get("_rebuilding_graph")):
			for _j in range(3):
				await process_frame
			return


func _wait_scene(root_name: String, max_frames := 180) -> void:
	for _i in range(max_frames):
		await process_frame
		if current_scene and current_scene.name == root_name:
			await process_frame
			return
	push_warning("Timeout scène: " + root_name)


func _step(name: String, action: Callable) -> void:
	print("[SCENARIO_LINKS] ", name, "...")
	var result: Variant = await action.call()
	var ok := _result_ok(result)
	_steps.append({ "step": name, "ok": ok, "result": result })
	if not ok:
		_failed = true
		print("[SCENARIO_LINKS] FAIL ", name, " -> ", result)
	else:
		print("[SCENARIO_LINKS] OK   ", name, " -> ", result)


func _result_ok(result: Variant) -> bool:
	if result is Dictionary:
		if result.has("error"):
			return false
		if result.has("ok"):
			return bool(result.get("ok"))
	return true


func _write_report() -> void:
	var report := { "passed": not _failed, "steps": _steps }
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
	print("\n=== RAPPORT TEST LIENS DU GRAPHE ===")
	print(JSON.stringify(report, "\t"))
