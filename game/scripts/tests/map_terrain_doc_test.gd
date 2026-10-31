extends SceneTree

## Tests du relief de terrain côté document/éditeur :
## hauteurs par case (schéma carte), pinceau, undo/redo, sérialisation et pose
## depuis l'éditeur réel. Le rendu moteur est couvert par map_terrain_test.

const K_MESH := "mesh"
var DocScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DocScript = load("res://scripts/maps/editor/map_edit_document.gd")
	var md = get_root().get_node("MapData")
	var base: Dictionary = md.create_complex_map("Test relief", "general", "local", 12, 10)

	_test_data(base)
	_test_undo(base)
	_test_serialization(base)
	await _test_editor(base)

	if _failed:
		print("map_terrain_doc_test:FAIL")
		quit(1)
		return
	print("map_terrain_doc_test:PASS")
	quit(0)

func _test_data(base: Dictionary) -> void:
	_assert("schema_terrain_array", base.get("terrainHeights") is Array and (base["terrainHeights"] as Array).is_empty())
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	_assert("buffer_size", doc.terrain_heights().size() == 12 * 10)
	_assert("flat_0", is_equal_approx(doc.terrain_height(3, 4), 0.0))
	_assert("no_relief", not doc.has_terrain_relief())

	doc.set_terrain_height(3, 4, 1.5)
	_assert("set_height", is_equal_approx(doc.terrain_height(3, 4), 1.5))
	_assert("relief_detected", doc.has_terrain_relief())
	_assert("height_other_cell", is_equal_approx(doc.terrain_height(4, 4), 0.0))

	# Pinceau : rayon 1.5 autour de (6,5), force 0.5.
	doc.paint_terrain_brush(Vector2(6.0, 5.0), 1.5, 0.5, "raise")
	_assert("brush_center_raised", doc.terrain_height(6, 5) > 0.2)
	_assert("brush_edge_lower", doc.terrain_height(6, 5) >= doc.terrain_height(7, 5))
	# Baisser puis aplatir.
	doc.paint_terrain_brush(Vector2(6.0, 5.0), 1.5, 0.5, "lower")
	_assert("brush_lower", doc.terrain_height(6, 5) < 0.2)
	doc.paint_terrain_brush(Vector2(6.0, 5.0), 2.0, 1.0, "flatten")
	_assert("brush_flatten", absf(doc.terrain_height(6, 5) - doc.terrain_height(7, 6)) < 1.2)

func _test_undo(base: Dictionary) -> void:
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	var before: float = float(doc.terrain_height(5, 5))
	doc.set_terrain_height(5, 5, before + 1.0)
	_assert("undo_target_set", absf(doc.terrain_height(5, 5) - (before + 1.0)) < 0.001)
	doc.undo()
	_assert("undo_restores", is_equal_approx(doc.terrain_height(5, 5), before))
	doc.redo()
	_assert("redo_reapplies", absf(doc.terrain_height(5, 5) - (before + 1.0)) < 0.001)

	# Un trait de pinceau = une seule transaction (undo d'un bloc).
	var before_stroke: Array = doc.terrain_heights()
	doc.begin_transaction()
	doc.paint_terrain_brush(Vector2(2.0, 2.0), 1.0, 0.5, "raise")
	doc.paint_terrain_brush(Vector2(3.0, 2.0), 1.0, 0.5, "raise")
	doc.commit_transaction()
	var after_stroke: Array = doc.terrain_heights()
	doc.undo()
	_assert("undo_whole_stroke", doc.terrain_heights() != after_stroke)
	_assert("undo_stroke_reset", doc.terrain_heights() == before_stroke)

func _test_serialization(base: Dictionary) -> void:
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	doc.set_terrain_height(2, 3, 2.0)
	var snapshot: Dictionary = doc.to_map_data()
	_assert("ser_array", snapshot.get("terrainHeights") is Array)
	_assert("ser_size", (snapshot.get("terrainHeights") as Array).size() == 12 * 10)
	_assert("ser_value", is_equal_approx(float((snapshot["terrainHeights"] as Array)[3 * 12 + 2]), 2.0))
	var doc2: Variant = DocScript.new()
	doc2.load_map(snapshot)
	_assert("reload_value", is_equal_approx(doc2.terrain_height(2, 3), 2.0))

func _test_editor(base: Dictionary) -> void:
	var editor: Control = load("res://scenes/map_editor/map_editor.tscn").instantiate()
	get_root().add_child(editor)
	editor.size = Vector2(1280, 800)
	await process_frame
	editor.load_map(base)
	await process_frame

	_assert("editor_loaded", not editor.doc.map_data.is_empty())
	# Outil Relief présent dans la palette + raccourci U.
	var ToolsScript: GDScript = load("res://scripts/maps/editor/map_editor_tools.gd")
	_assert("tool_relief", ToolsScript.label(ToolsScript.TERRAIN_HEIGHT) == "Relief")
	_assert("tool_relief_shortcut", ToolsScript.tool_for_shortcut("U") == ToolsScript.TERRAIN_HEIGHT)

	editor._relief_radius = 1.5
	editor._relief_strength = 0.6
	editor._relief_mode = "raise"
	editor._paint_relief(Vector2(6.0, 5.0))
	_assert("editor_paint_relief", editor.doc.has_terrain_relief())
	_assert("editor_paint_center", editor.doc.terrain_height(6, 5) > 0.2)
	_assert("editor_engine", editor._engine != null)
	if editor._engine.has_method("terrain_height_at"):
		_assert("editor_engine_terrain_api", true)
	else:
		print("  ..   terrain_height_at pas encore exposé par le moteur (task-7)")

	editor.queue_free()
	await process_frame

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
