extends SceneTree

## Tests headless de la mini-carte du graphe (refonte 04).
##
## Instancie un GraphEdit + deux GraphNode + la minimap, puis vérifie sa taille,
## sa position auto en haut-droite, les couleurs sémantiques, la conversion
## local <-> graphe et le recentrage du GraphEdit au clic.

const REPORT_PATH := "user://editor_minimap_test_report.json"
const MinimapScript := preload("res://scripts/scenario_editor/panels/editor_minimap.gd")

const GRAPH_POS := Vector2(20, 30)
const GRAPH_SIZE := Vector2(900, 600)
const PANEL_SIZE := Vector2(220, 140)
const EDGE_MARGIN := 12.0

var _steps: Array = []
var _failed := false
var _graph: GraphEdit = null
var _minimap = null
var _node_a: GraphNode = null
var _node_b: GraphNode = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_graph = GraphEdit.new()
	_graph.name = "TestGraph"
	_graph.position = GRAPH_POS
	_graph.size = GRAPH_SIZE
	get_root().add_child(_graph)
	await process_frame

	_node_a = _make_node("a", "Entrée", Vector2(100, 50), Vector2(220, 120))
	_node_a.set_meta("is_start", true)
	_node_a.set_meta("is_terminal", false)
	_node_a.selected = true
	_graph.add_child(_node_a)

	_node_b = _make_node("b", "Finale", Vector2(500, 300), Vector2(180, 100))
	_node_b.set_meta("is_start", false)
	_node_b.set_meta("is_terminal", true)
	_graph.add_child(_node_b)
	await process_frame

	_minimap = MinimapScript.new()
	_minimap.call("setup", _graph, Callable(self, "_scenario_provider"))
	await process_frame
	await process_frame

	await _step("taille_et_position", func():
		var expected_pos := GRAPH_POS + Vector2(
			GRAPH_SIZE.x - PANEL_SIZE.x - EDGE_MARGIN,
			GRAPH_SIZE.y - PANEL_SIZE.y - EDGE_MARGIN)
		var state: Dictionary = _minimap.call("get_debug_state")
		return {
			"top_level": bool(_minimap.top_level),
			"size": _minimap.size,
			"position": _minimap.global_position,
			"expected_position": expected_pos,
			"node_count": int(state.get("node_count", 0)),
			"visible": bool(_minimap.visible),
			"ok": bool(_minimap.top_level)
				and _minimap.size.distance_to(PANEL_SIZE) < 0.5
				and _minimap.global_position.distance_to(expected_pos) < 0.5
				and int(state.get("node_count", 0)) == 2
				and bool(_minimap.visible),
		}
	)

	await _step("couleurs_semantiques", func():
		var selected_color: Color = _minimap.call("_node_color", _node_a)
		_node_a.selected = false
		await process_frame
		var start_color: Color = _minimap.call("_node_color", _node_a)
		_node_a.selected = true
		await process_frame
		var terminal_color: Color = _minimap.call("_node_color", _node_b)
		return {
			"selected": selected_color.to_html(false),
			"start": start_color.to_html(false),
			"terminal": terminal_color.to_html(false),
			"ok": selected_color.is_equal_approx(ThemeColors.GOLD_LIGHT)
				and start_color.is_equal_approx(ThemeColors.GOLD)
				and terminal_color.is_equal_approx(ThemeColors.SUCCESS),
		}
	)

	await _step("conversion_local_graphe", func():
		var points: Array = [
			Vector2(100, 50),
			Vector2(590, 350),
			Vector2(140, 90),
		]
		var max_error := 0.0
		for point in points:
			var local: Vector2 = _minimap.call("local_point_for_graph", point)
			var back: Vector2 = _minimap.call("pick", local)
			max_error = maxf(max_error, (back - point).length())
		return {
			"max_error": max_error,
			"ok": max_error < 0.05,
		}
	)

	await _step("navigation_clic", func():
		_graph.scroll_offset = Vector2.ZERO
		await process_frame
		var target := Vector2(590, 350)
		var local: Vector2 = _minimap.call("local_point_for_graph", target)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		event.position = local
		_minimap.call("_gui_input", event)
		await process_frame
		var expected := target * _graph.zoom - _graph.size * 0.5
		return {
			"local": local,
			"scroll": _graph.scroll_offset,
			"expected": expected,
			"ok": _graph.scroll_offset.distance_to(expected) < 0.5,
		}
	)

	await _step("center_at_et_force_redraw", func():
		_graph.scroll_offset = Vector2.ZERO
		_minimap.call("center_at", Vector2(100, 50))
		var expected_direct := Vector2(100, 50) * _graph.zoom - _graph.size * 0.5
		var direct_ok := _graph.scroll_offset.distance_to(expected_direct) < 0.5
		_minimap.call("force_redraw")
		await process_frame
		var state: Dictionary = _minimap.call("get_debug_state")
		return {
			"scroll": _graph.scroll_offset,
			"has_content": bool(state.get("has_content", false)),
			"bounds": state.get("bounds", Rect2()),
			"ok": direct_ok and bool(state.get("has_content", false)),
		}
	)

	await _step("desactivation", func():
		_minimap.call("set_enabled", false)
		await process_frame
		var hidden := not bool(_minimap.visible) and not bool(_minimap.call("is_enabled"))
		_minimap.call("set_enabled", true)
		await process_frame
		return {
			"hidden": hidden,
			"visible": bool(_minimap.visible),
			"ok": hidden and bool(_minimap.visible) and bool(_minimap.call("is_enabled")),
		}
	)

	if _minimap != null and is_instance_valid(_minimap):
		_minimap.free()
	if _graph != null and is_instance_valid(_graph):
		_graph.free()
	await process_frame
	_write_report()
	quit(0 if not _failed else 1)


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

func _make_node(scene_id: String, title: String, graph_pos: Vector2,
		node_size: Vector2) -> GraphNode:
	var node := GraphNode.new()
	node.name = scene_id
	node.title = title
	node.position_offset = graph_pos
	node.custom_minimum_size = node_size
	node.size = node_size
	node.set_meta("scene_id", scene_id)
	return node


func _scenario_provider() -> Dictionary:
	return {
		"id": "test-minimap",
		"title": "Mini-carte test",
		"startSceneId": "a",
		"scenes": [
			{
				"id": "a", "title": "Entrée", "transitions": [
					{ "to": "b", "label": "Aller à la fin" },
				],
			},
			{ "id": "b", "title": "Finale", "transitions": [] },
		],
	}


func _step(step_name: String, action: Callable) -> void:
	print("[EDITOR_MINIMAP] ", step_name, "...")
	var result: Variant = await action.call()
	var ok := _result_ok(result)
	_steps.append({ "step": step_name, "ok": ok, "result": result })
	if not ok:
		_failed = true
		print("[EDITOR_MINIMAP] FAIL ", step_name, " -> ", result)
	else:
		print("[EDITOR_MINIMAP] OK   ", step_name, " -> ", result)


func _result_ok(result: Variant) -> bool:
	if result is Dictionary:
		if result.has("error"):
			return false
		if result.has("ok"):
			return bool(result.get("ok"))
	return true


func _write_report() -> void:
	var report := { "passed": not _failed, "steps": _steps }
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
	print("\n=== RAPPORT TEST MINI-CARTE ===")
	print(JSON.stringify(report, "\t"))
