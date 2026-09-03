extends SceneTree

## Tests unitaires du moteur de navigation non linéaire (sans GUI).

const REPORT_PATH := "user://quest_navigation_test_report.json"
const QuestNavigation = preload("res://scripts/quest_navigation.gd")

var _steps: Array = []
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame

	await _step("normalize_linear_legacy", func():
		var raw := {
			"title": "Linéaire legacy",
			"scenes": [
				{ "title": "Intro", "content": "A" },
				{ "title": "Milieu", "content": "B" },
				{ "title": "Fin", "content": "C" },
			],
		}
		var n := QuestNavigation.normalize_scenario(raw)
		var scenes: Array = n.get("scenes", [])
		var t0: Array = scenes[0].get("transitions", [])
		var t2: Array = scenes[2].get("transitions", [])
		return {
			"start": n.get("startSceneId"),
			"ids": [scenes[0].get("id"), scenes[1].get("id"), scenes[2].get("id")],
			"first_to": t0[0].get("to") if not t0.is_empty() else "",
			"first_default": t0[0].get("default", false) if not t0.is_empty() else false,
			"terminal_empty": t2.is_empty(),
			"ok": str(n.get("startSceneId", "")) != "" and t0.size() == 1 and t2.is_empty(),
		}
	)

	await _step("sanitize_broken_and_unique_ids", func():
		var raw := {
			"title": "Cassé",
			"startSceneId": "a",
			"scenes": [
				{ "id": "a", "title": "A", "transitions": [
					{ "to": "ghost", "label": "Mort" },
					{ "to": "b", "label": "OK" },
				]},
				{ "id": "a", "title": "Doublon", "transitions": [] },
				{ "id": "b", "title": "B", "transitions": [] },
			],
		}
		var n := QuestNavigation.normalize_scenario(raw)
		var ids: Array = []
		for s in n.get("scenes", []):
			ids.append(s.get("id"))
		var unique: bool = ids.size() == 3 and ids[0] != ids[1]
		var from_a := QuestNavigation.get_available_transitions(n, str(ids[0]))
		var only_b: bool = from_a.size() == 1 and str(from_a[0].get("to")) == "b"
		var has_default: bool = bool(from_a[0].get("default", false)) if not from_a.is_empty() else false
		return {
			"ids": ids,
			"unique": unique,
			"only_b": only_b,
			"has_default": has_default,
			"ok": unique and only_b and has_default,
		}
	)

	await _step("branching_default_and_terminal", func():
		var scn := _branched_fixture()
		var from_hub := QuestNavigation.get_available_transitions(scn, "hub")
		var default_t := QuestNavigation.get_default_transition(from_hub)
		return {
			"branch_count": from_hub.size(),
			"default_to": default_t.get("to"),
			"left_terminal": QuestNavigation.is_terminal_scene(scn, "left"),
			"right_terminal": QuestNavigation.is_terminal_scene(scn, "right"),
			"hub_not_terminal": not QuestNavigation.is_terminal_scene(scn, "hub"),
			"ok": from_hub.size() == 2 and str(default_t.get("to")) == "left"
				and QuestNavigation.is_terminal_scene(scn, "left"),
		}
	)

	await _step("analyze_reachability", func():
		# Orpheline + terminale explicite (transitions: []) — ne doit pas être reliée par legacy.
		var scn := {
			"title": "Reach",
			"startSceneId": "start",
			"scenes": [
				{ "id": "start", "title": "S", "transitions": [{ "to": "mid", "label": "Go", "default": true }] },
				{ "id": "mid", "title": "M", "transitions": [{ "to": "end", "label": "Fin", "default": true }] },
				{ "id": "end", "title": "E", "transitions": [] },
				{ "id": "orphan", "title": "Orpheline", "transitions": [{ "to": "end", "label": "Raccourci MJ", "gmOnly": true }] },
			],
		}
		var analysis := QuestNavigation.analyze_graph(scn)
		var unreachable: Array = analysis.get("unreachable", [])
		var orphans: Array = analysis.get("orphans", [])
		return {
			"reachable": analysis.get("reachableCount"),
			"unreachable": unreachable,
			"orphans": orphans,
			"terminals": analysis.get("terminals"),
			"ok": int(analysis.get("reachableCount", 0)) == 3
				and unreachable.has("orphan")
				and orphans.has("orphan")
				and (analysis.get("terminals", []) as Array).has("end"),
		}
	)

	await _step("analyze_demo_crypte", func():
		var gd = get_root().get_node("GameData")
		var crypte: Dictionary = gd.get_scenario_by_id("demo-crypte")
		if crypte.is_empty():
			return { "error": "demo-crypte introuvable" }
		var analysis := QuestNavigation.analyze_graph(crypte)
		return {
			"scenes": analysis.get("sceneCount"),
			"branches": analysis.get("branchCount"),
			"carrefours": analysis.get("multiBranchScenes"),
			"unreachable": analysis.get("unreachable"),
			"ok_flag": analysis.get("ok"),
			"ok": int(analysis.get("sceneCount", 0)) >= 5
				and int(analysis.get("multiBranchScenes", 0)) >= 1
				and (analysis.get("unreachable", []) as Array).is_empty(),
		}
	)

	await _step("auto_layout_positions", func():
		var scn := _branched_fixture()
		var laid := QuestNavigation.apply_auto_layout(scn)
		var positions: Dictionary = {}
		for scene in laid.get("scenes", []):
			var gp = scene.get("graphPos", {})
			if typeof(gp) != TYPE_DICTIONARY:
				return { "error": "graphPos manquant", "id": scene.get("id") }
			positions[str(scene.get("id"))] = Vector2(float(gp["x"]), float(gp["y"]))
		var hub: Vector2 = positions.get("hub", Vector2.ZERO)
		var left: Vector2 = positions.get("left", Vector2.ZERO)
		var right: Vector2 = positions.get("right", Vector2.ZERO)
		var start: Vector2 = positions.get("start", Vector2.ZERO)
		return {
			"positions": {
				"start": [start.x, start.y],
				"hub": [hub.x, hub.y],
				"left": [left.x, left.y],
				"right": [right.x, right.y],
			},
			"hub_right_of_start": hub.x > start.x,
			"branches_same_layer": is_equal_approx(left.x, right.x),
			"ok": hub.x > start.x and is_equal_approx(left.x, right.x) and left.y != right.y,
		}
	)

	await _step("ensure_graph_positions_preserves", func():
		var scn := {
			"title": "Pos",
			"startSceneId": "a",
			"scenes": [
				{ "id": "a", "title": "A", "graphPos": { "x": 10, "y": 20 }, "transitions": [{ "to": "b", "default": true }] },
				{ "id": "b", "title": "B", "graphPos": { "x": 99, "y": 88 }, "transitions": [] },
			],
		}
		var kept := QuestNavigation.ensure_graph_positions(scn)
		var a_pos = kept["scenes"][0]["graphPos"]
		var missing_one := {
			"title": "Pos2",
			"startSceneId": "a",
			"scenes": [
				{ "id": "a", "title": "A", "graphPos": { "x": 10, "y": 20 }, "transitions": [{ "to": "b", "default": true }] },
				{ "id": "b", "title": "B", "transitions": [] },
			],
		}
		var filled := QuestNavigation.ensure_graph_positions(missing_one)
		var b_pos = filled["scenes"][1].get("graphPos", {})
		return {
			"kept_x": a_pos.get("x"),
			"filled_b": b_pos,
			"ok": float(a_pos.get("x", -1)) == 10.0 and b_pos.has("x"),
		}
	)

	await _step("validate_and_health_label", func():
		var bad := { "title": "", "scenes": [] }
		var errs := QuestNavigation.validate_scenario_graph(bad)
		var good := _branched_fixture()
		good["title"] = "Branche OK"
		var ok_errs := QuestNavigation.validate_scenario_graph(good)
		var health := QuestNavigation.format_graph_health(QuestNavigation.analyze_graph(good))
		return {
			"bad_errors": errs,
			"good_errors": ok_errs,
			"health": health,
			"ok": not errs.is_empty() and ok_errs.is_empty() and health.begins_with("✓"),
		}
	)

	await _step("runtime_go_to_scene_branches", func():
		var gd = get_root().get_node("GameData")
		var fixture := _branched_fixture()
		fixture["id"] = "test-branch-runtime"
		fixture["title"] = "Test branches runtime"
		fixture["questFormat"] = "oneshot"
		fixture["roster"] = "general"
		gd.save_scenario(fixture)
		gd.clear_all_saved_games()
		var party := [{ "id": "p1", "name": "Test", "hp": 10, "isPlayer": true, "isBot": false }]
		gd.create_new_game("test-branch-runtime", "solo", "human", "oneshot", party)
		var start_id := QuestNavigation.resolve_current_scene_id(gd.active_game, fixture)
		var advanced: bool = bool(gd.advance_scene())
		var after_default := str(gd.active_game.get("currentSceneId", ""))
		var jumped: bool = bool(gd.go_to_scene("right", "Choix MJ"))
		var after_jump := str(gd.active_game.get("currentSceneId", ""))
		var summary: Dictionary = gd.get_scene_navigation_summary()
		gd.delete_scenario("test-branch-runtime")
		return {
			"start": start_id,
			"advanced": advanced,
			"after_default": after_default,
			"jumped": jumped,
			"after_jump": after_jump,
			"summary_terminal": summary.get("isTerminal"),
			"ok": start_id == "start" and advanced and after_default == "hub"
				and jumped and after_jump == "right" and summary.get("isTerminal", false) == true,
		}
	)

	await _step("picker_and_progress_labels", func():
		var scn := _branched_fixture()
		var game := {
			"currentSceneId": "hub",
			"visitedSceneIds": ["start", "hub"],
		}
		var picker := QuestNavigation.format_picker_label(QuestNavigation.get_scene_by_id(scn, "hub"), true, true)
		var progress := QuestNavigation.format_progress_label(scn, game)
		return {
			"picker": picker,
			"progress": progress,
			"ok": picker.begins_with("▶") and progress.contains("branches"),
		}
	)

	_write_report()
	quit(0 if not _failed else 1)

func _branched_fixture() -> Dictionary:
	return {
		"title": "Fixture branches",
		"startSceneId": "start",
		"scenes": [
			{
				"id": "start",
				"title": "Départ",
				"tags": ["debut"],
				"content": "Intro",
				"transitions": [{ "to": "hub", "label": "Entrer", "default": true }],
			},
			{
				"id": "hub",
				"title": "Carrefour",
				"tags": ["carrefour"],
				"content": "Choisissez",
				"transitions": [
					{ "to": "left", "label": "Gauche", "default": true },
					{ "to": "right", "label": "Droite", "gmOnly": true },
				],
			},
			{ "id": "left", "title": "Gauche", "content": "Fin A", "transitions": [] },
			{ "id": "right", "title": "Droite", "content": "Fin B", "transitions": [] },
		],
	}

func _step(name: String, action: Callable) -> void:
	print("[QUEST_NAV] ", name, "...")
	var result: Variant = await action.call()
	var ok := _result_ok(result)
	_steps.append({ "step": name, "ok": ok, "result": result })
	if not ok:
		_failed = true
		print("[QUEST_NAV] FAIL ", name, " -> ", result)
	else:
		print("[QUEST_NAV] OK   ", name, " -> ", result)

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
	print("\n=== RAPPORT QUEST NAVIGATION ===")
	print(JSON.stringify(report, "\t"))
