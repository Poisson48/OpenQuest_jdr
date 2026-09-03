extends SceneTree

## Tests headless de l'éditeur de scénario non linéaire (graphe + persistance).

const REPORT_PATH := "user://scenario_editor_test_report.json"
const QuestNavigation = preload("res://scripts/quest_navigation.gd")

var _steps: Array = []
var _failed := false
var _gd: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_gd = get_root().get_node("GameData")
	await process_frame

	await _step("load_blank_editor", func():
		_gd.editor_scenario_id = ""
		change_scene_to_file("res://scenes/scenario_editor.tscn")
		await _wait_scene("ScenarioEditor")
		var editor := current_scene
		await _wait_graph_ready(editor)
		var nodes := _graph_nodes(editor)
		return {
			"has_graph": editor.has_node("%GraphEdit"),
			"has_health": editor.has_node("%LblGraphHealth"),
			"has_auto_layout": editor.has_node("%BtnAutoLayout"),
			"has_fit": editor.has_node("%BtnFitView"),
			"has_validate": editor.has_node("%BtnValidate"),
			"has_scene_badge": editor.has_node("%LblSceneBadge"),
			"node_count": nodes.size(),
			"ok": editor.has_node("%GraphEdit")
				and editor.has_node("%BtnAutoLayout")
				and nodes.size() >= 1,
		}
	)

	await _step("add_scenes_and_branches", func():
		var editor := current_scene
		editor.get_node("%BtnAddScene").pressed.emit()
		await process_frame
		await process_frame
		editor.get_node("%BtnAddScene").pressed.emit()
		await process_frame
		await _wait_graph_ready(editor)
		var nodes := _graph_nodes(editor)
		var scenario: Dictionary = editor.get("_scenario")
		var scene_count: int = scenario.get("scenes", []).size()
		# Sélectionne la 2e scène et ajoute une branche
		if scene_count >= 2:
			var second_id := str(scenario["scenes"][1].get("id", ""))
			editor.set("_selected_scene_id", second_id)
			editor.call("_refresh_scene_panel")
			editor.get_node("%BtnAddTransition").pressed.emit()
			await process_frame
			await _wait_graph_ready(editor)
		scenario = editor.get("_scenario")
		var analysis := QuestNavigation.analyze_graph(scenario)
		return {
			"scene_count": scene_count,
			"graph_nodes": nodes.size(),
			"branches": analysis.get("branchCount"),
			"ok": scene_count >= 3 and int(analysis.get("branchCount", 0)) >= 1,
		}
	)

	await _step("edit_scene_fields", func():
		var editor := current_scene
		var scenario: Dictionary = editor.get("_scenario")
		var sid := str(scenario["scenes"][0].get("id", ""))
		editor.set("_selected_scene_id", sid)
		editor.call("_refresh_scene_panel")
		await process_frame
		editor.get_node("%SceneTitle").text = "Prologue testé"
		editor.get_node("%SceneTags").text = "debut, test"
		editor.get_node("%SceneContent").text = "Le vent hurle sur les remparts."
		editor.call("_commit_scene_editor")
		scenario = editor.get("_scenario")
		var scene: Dictionary = scenario["scenes"][0]
		var tags: Array = scene.get("tags", [])
		return {
			"title": scene.get("title"),
			"tags": tags,
			"content_len": str(scene.get("content", "")).length(),
			"badge_visible": editor.get_node("%LblSceneBadge").visible,
			"ok": scene.get("title") == "Prologue testé"
				and tags.has("debut")
				and tags.has("test")
				and str(scene.get("content", "")).contains("remparts"),
		}
	)

	await _step("auto_layout_and_validate", func():
		var editor := current_scene
		editor.get_node("%BtnAutoLayout").pressed.emit()
		await process_frame
		await _wait_graph_ready(editor)
		editor.get_node("%BtnValidate").pressed.emit()
		await process_frame
		var scenario: Dictionary = editor.get("_scenario")
		var has_pos := true
		for scene in scenario.get("scenes", []):
			var gp = scene.get("graphPos", {})
			if typeof(gp) != TYPE_DICTIONARY or not gp.has("x"):
				has_pos = false
		var health: String = editor.get_node("%LblGraphHealth").text
		var status: String = editor.get_node("%LblStatus").text
		return {
			"has_pos": has_pos,
			"health": health,
			"status": status,
			"ok": has_pos and not health.is_empty(),
		}
	)

	await _step("save_and_reload_branched", func():
		var editor := current_scene
		editor.get_node("%MetaTitle").text = "Scénario test éditeur NL"
		editor.call("_on_meta_changed")
		# Force un graphe branché propre
		var branched := {
			"id": "test-editor-nl",
			"title": "Scénario test éditeur NL",
			"synopsis": "Test headless",
			"setting": "Labo",
			"questFormat": "oneshot",
			"roster": "general",
			"startSceneId": "s1",
			"scenes": [
				{
					"id": "s1",
					"title": "Entrée",
					"content": "A",
					"tags": ["debut"],
					"transitions": [
						{ "to": "s2", "label": "Porte", "default": true },
						{ "to": "s3", "label": "Fenetre", "gmOnly": true },
					],
					"graphPos": { "x": 40, "y": 40 },
				},
				{
					"id": "s2",
					"title": "Couloir",
					"content": "B",
					"tags": [],
					"transitions": [{ "to": "s3", "label": "Suite", "default": true }],
					"graphPos": { "x": 300, "y": 40 },
				},
				{
					"id": "s3",
					"title": "Finale",
					"content": "C",
					"tags": ["fin"],
					"transitions": [],
					"graphPos": { "x": 560, "y": 40 },
				},
			],
			"npcs": [{ "id": "npc-1", "name": "Gardien", "role": "Gardien", "description": "Mute" }],
		}
		editor.set("_scenario", branched)
		editor.call("_refresh_all")
		await _wait_graph_ready(editor)
		editor.get_node("%BtnSave").pressed.emit()
		await process_frame
		var stored: Dictionary = _gd.get_scenario_by_id("test-editor-nl")
		if stored.is_empty():
			return { "error": "Scénario non persisté" }

		_gd.editor_scenario_id = "test-editor-nl"
		change_scene_to_file("res://scenes/scenario_editor.tscn")
		await _wait_scene("ScenarioEditor")
		editor = current_scene
		await _wait_graph_ready(editor)
		var reloaded: Dictionary = editor.get("_scenario")
		var analysis := QuestNavigation.analyze_graph(reloaded)
		var nodes := _graph_nodes(editor)
		_gd.delete_scenario("test-editor-nl")
		return {
			"title": reloaded.get("title"),
			"scenes": reloaded.get("scenes", []).size(),
			"branches": analysis.get("branchCount"),
			"carrefours": analysis.get("multiBranchScenes"),
			"npcs": reloaded.get("npcs", []).size(),
			"graph_nodes": nodes.size(),
			"ok": str(reloaded.get("title")) == "Scénario test éditeur NL"
				and int(analysis.get("branchCount", 0)) == 3
				and int(analysis.get("multiBranchScenes", 0)) == 1
				and nodes.size() == 3,
		}
	)

	await _step("load_demo_crypte_graph", func():
		_gd.editor_scenario_id = "demo-crypte"
		change_scene_to_file("res://scenes/scenario_editor.tscn")
		await _wait_scene("ScenarioEditor")
		var editor := current_scene
		await _wait_graph_ready(editor)
		var scenario: Dictionary = editor.get("_scenario")
		var analysis := QuestNavigation.analyze_graph(scenario)
		var nodes := _graph_nodes(editor)
		editor.get_node("%BtnAutoLayout").pressed.emit()
		await process_frame
		await _wait_graph_ready(editor)
		editor.get_node("%BtnFitView").pressed.emit()
		await process_frame
		return {
			"id": scenario.get("id"),
			"scenes": analysis.get("sceneCount"),
			"branches": analysis.get("branchCount"),
			"nodes": nodes.size(),
			"health": editor.get_node("%LblGraphHealth").text,
			"ok": str(scenario.get("id")) == "demo-crypte"
				and nodes.size() == int(analysis.get("sceneCount", 0))
				and int(analysis.get("multiBranchScenes", 0)) >= 1,
		}
	)

	await _step("delete_scene_cleans_links", func():
		_gd.editor_scenario_id = ""
		change_scene_to_file("res://scenes/scenario_editor.tscn")
		await _wait_scene("ScenarioEditor")
		var editor := current_scene
		var fixture := {
			"id": "tmp-delete",
			"title": "Delete test",
			"questFormat": "oneshot",
			"roster": "general",
			"startSceneId": "a",
			"scenes": [
				{ "id": "a", "title": "A", "content": "", "transitions": [
					{ "to": "b", "label": "To B", "default": true },
					{ "to": "c", "label": "To C" },
				], "graphPos": { "x": 0, "y": 0 } },
				{ "id": "b", "title": "B", "content": "", "transitions": [], "graphPos": { "x": 200, "y": 0 } },
				{ "id": "c", "title": "C", "content": "", "transitions": [], "graphPos": { "x": 200, "y": 120 } },
			],
			"npcs": [],
		}
		editor.set("_scenario", fixture)
		editor.set("_selected_scene_id", "b")
		editor.call("_refresh_all")
		await _wait_graph_ready(editor)
		editor.call("_on_confirm_delete_scene")
		await process_frame
		await _wait_graph_ready(editor)
		var scenario: Dictionary = editor.get("_scenario")
		var ids: Array = []
		for s in scenario.get("scenes", []):
			ids.append(s.get("id"))
		var from_a := QuestNavigation.get_available_transitions(scenario, "a")
		var still_points_b := false
		for t in from_a:
			if str(t.get("to")) == "b":
				still_points_b = true
		return {
			"ids": ids,
			"from_a": from_a.size(),
			"still_points_b": still_points_b,
			"ok": not ids.has("b") and ids.has("a") and ids.has("c") and not still_points_b,
		}
	)

	await _step("set_start_and_connection_api", func():
		var editor := current_scene
		var scenario: Dictionary = editor.get("_scenario")
		if scenario.get("scenes", []).size() < 2:
			editor.get_node("%BtnAddScene").pressed.emit()
			await process_frame
			scenario = editor.get("_scenario")
		var target_id := str(scenario["scenes"][1].get("id", ""))
		editor.set("_selected_scene_id", target_id)
		editor.call("_refresh_scene_panel")
		editor.get_node("%BtnSetStart").pressed.emit()
		await process_frame
		await _wait_graph_ready(editor)
		scenario = editor.get("_scenario")
		var start_id := str(scenario.get("startSceneId", ""))
		# Simule une connexion graphe
		var from_name: StringName = StringName(str(editor.call("_graph_node_name_for_id", start_id)))
		var other_id := ""
		for s in scenario.get("scenes", []):
			var sid := str(s.get("id", ""))
			if sid != start_id:
				other_id = sid
				break
		var to_name: StringName = StringName(str(editor.call("_graph_node_name_for_id", other_id)))
		var before: int = int(QuestNavigation.analyze_graph(scenario).get("branchCount", 0))
		if not from_name.is_empty() and not to_name.is_empty():
			editor.call("_on_graph_connection_request", from_name, 0, to_name, 0)
			await process_frame
			await _wait_graph_ready(editor)
		scenario = editor.get("_scenario")
		var after: int = int(QuestNavigation.analyze_graph(scenario).get("branchCount", 0))
		return {
			"start": start_id,
			"target": target_id,
			"before": before,
			"after": after,
			"ok": start_id == target_id and int(after) >= int(before),
		}
	)

	await _step("validation_rejects_empty_title", func():
		var editor := current_scene
		editor.get_node("%MetaTitle").text = ""
		editor.call("_on_meta_changed")
		var err: String = str(editor.call("_validate_scenario", editor.get("_scenario")))
		editor.get_node("%MetaTitle").text = "Titre restauré"
		editor.call("_on_meta_changed")
		return {
			"message": err,
			"ok": err.to_lower().contains("titre"),
		}
	)

	_write_report()
	quit(0 if not _failed else 1)

func _graph_nodes(editor: Node) -> Array:
	var result: Array = []
	var graph: GraphEdit = editor.get_node("%GraphEdit")
	for child in graph.get_children():
		if child is GraphNode and is_instance_valid(child) and not child.is_queued_for_deletion():
			result.append(child)
	return result

func _wait_graph_ready(editor: Node, max_frames := 30) -> void:
	for _i in range(max_frames):
		await process_frame
		if not bool(editor.get("_rebuilding_graph")):
			# laisse un frame pour queue_free
			await process_frame
			return

func _step(name: String, action: Callable) -> void:
	print("[SCENARIO_EDITOR] ", name, "...")
	var result: Variant = await action.call()
	var ok := _result_ok(result)
	_steps.append({ "step": name, "ok": ok, "result": result })
	if not ok:
		_failed = true
		print("[SCENARIO_EDITOR] FAIL ", name, " -> ", result)
	else:
		print("[SCENARIO_EDITOR] OK   ", name, " -> ", result)

func _result_ok(result: Variant) -> bool:
	if result is Dictionary:
		if result.has("error"):
			return false
		if result.has("ok"):
			return bool(result.get("ok"))
	return true

func _wait_scene(root_name: String, max_frames := 120) -> void:
	for _i in range(max_frames):
		await process_frame
		if current_scene and current_scene.name == root_name:
			await process_frame
			return
	push_warning("Timeout scène: " + root_name)

func _write_report() -> void:
	var report := { "passed": not _failed, "steps": _steps }
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
	print("\n=== RAPPORT TEST ÉDITEUR SCÉNARIO ===")
	print(JSON.stringify(report, "\t"))
