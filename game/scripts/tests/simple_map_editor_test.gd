extends SceneTree

## Éditeur 2D : document (marqueurs historiques), outils simplifiés, scène.

const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

var DocScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DocScript = load("res://scripts/maps/editor/map_edit_document.gd")
	var md = get_root().get_node("MapData")

	_test_tools()
	_test_simple_markers(md)
	_test_simple_authoring(md)
	await _test_simple_editor_ui(md)

	if _failed:
		quit(1)
		return
	print("simple_map_editor_test:PASS")
	quit(0)

func _test_tools() -> void:
	_assert("simple_has_paint", ToolsScript.is_simple_tool(ToolsScript.PAINT))
	_assert("simple_has_select", ToolsScript.is_simple_tool(ToolsScript.SELECT))
	_assert("simple_has_area", ToolsScript.is_simple_tool(ToolsScript.AREA))
	_assert("simple_no_wall", not ToolsScript.is_simple_tool(ToolsScript.WALL))
	_assert("simple_no_light", not ToolsScript.is_simple_tool(ToolsScript.LIGHT))
	_assert("simple_defs", ToolsScript.simple_defs().size() == ToolsScript.SIMPLE_IDS.size())
	_assert("simple_group_place", ToolsScript.simple_defs_in_group("place").size() >= 3)

func _test_simple_markers(md) -> void:
	var blank: Dictionary = md.create_blank_map("Village 2D", "general", "local")
	blank["markers"] = [
		{"x": 2, "y": 3, "type": "npc", "label": "Garde"},
		{"x": 4, "y": 1, "type": "poi", "label": "Puits"},
	]
	md.update_map(blank)

	var doc: Variant = DocScript.new()
	doc.load_map(blank)
	_assert("ingest_markers", doc.count_of_kind("marker") == 2)
	_assert("hit_marker", not str(doc.hit_element_at(2.4, 3.2)).is_empty())
	_assert("hit_empty", str(doc.hit_element_at(8.0, 8.0)).is_empty())

	var snapshot: Dictionary = doc.to_map_data()
	_assert("ser_markers", (snapshot.get("markers", []) as Array).size() == 2)
	_assert("ser_marker_type", str((snapshot["markers"][0] as Dictionary).get("type", "")) in ["npc", "poi"])

	var reloaded: Variant = DocScript.new()
	reloaded.load_map(snapshot)
	_assert("roundtrip_no_dup", reloaded.count_of_kind("marker") == 2)

func _test_simple_authoring(md) -> void:
	var blank: Dictionary = md.create_blank_map("Atelier 2D", "general", "local")
	var doc: Variant = DocScript.new()
	doc.load_map(blank)

	doc.paint_tiles({"0": "wall"})
	_assert("paint", doc.get_tile_at(0, 0) == "wall")
	doc.undo()
	_assert("paint_undo", doc.get_tile_at(0, 0) != "wall")

	var note_id: String = doc.add_element({"x": 1.0, "y": 1.0, "text": "Piège"}, "note", "Note")
	var area_id: String = doc.add_element({
		"x": 4.0, "y": 4.0, "w": 3.0, "h": 2.0, "label": "Taverne",
	}, "area", "Lieu")
	_assert("note", doc.count_of_kind("note") == 1)
	_assert("area", doc.count_of_kind("area") == 1)
	_assert("hit_note", doc.hit_element_at(1.2, 1.1) == note_id)
	_assert("hit_area", doc.hit_element_at(4.0, 4.0) == area_id)

	var exit_id: String = doc.add_element({
		"x": 2.0, "y": 5.0, "markerType": "exit", "type": "exit", "label": "Sortie",
	}, "marker", "Sortie")
	var door_id: String = doc.add_element({
		"x": 2.0, "y": 5.0, "w": 1.0, "h": 1.2, "asset": "res://data/props/objects/panneau_bois.png",
	}, "prop", "Porte")
	var exit_area: String = doc.add_element({
		"x": 2.0, "y": 5.0, "w": 1.2, "h": 1.2, "label": "Sortie", "category": "exit",
	}, "area", "Sortie")
	var stack: Array = doc.hit_stack_at(2.4, 5.2)
	_assert("erase_stack_hits", stack.has(exit_id) and stack.has(door_id) and stack.has(exit_area))
	doc.remove_elements(stack)
	_assert("erase_stack_clears_marker", doc.count_of_kind("marker") == 0)
	_assert("erase_stack_clears_prop", doc.count_of_kind("prop") == 0)
	var leftover := false
	for area_variant in doc.to_map_data().get("areas", []):
		if str((area_variant as Dictionary).get("label", "")).to_lower().contains("sortie"):
			leftover = true
	_assert("erase_no_sortie_area", not leftover)

	var out: Dictionary = doc.to_map_data()
	_assert("ser_notes", (out.get("notes", []) as Array).size() == 1)
	_assert("ser_areas", (out.get("areas", []) as Array).size() == 1)
	md.update_map(out)
	var child: Dictionary = md.create_child_map_for_area(str(out.get("id", "")), area_id, 16, 12, md.RENDER_MODE_SIMPLE)
	_assert("child_simple", not child.is_empty() and not md.is_complex_map(child))

func _test_simple_editor_ui(md) -> void:
	var blank: Dictionary = md.create_blank_map("UI 2D", "general", "local")
	var editor: Control = load("res://scenes/map_viewer/simple_editor.tscn").instantiate()
	get_root().add_child(editor)
	editor.size = Vector2(1280, 800)
	await process_frame
	editor.load_map(blank)
	await process_frame
	_assert("ui_tools", editor._tool_buttons.has(ToolsScript.PAINT))
	_assert("ui_select", editor._tool_buttons.has(ToolsScript.SELECT))
	_assert("ui_imap", editor._imap != null)
	editor._set_tool(ToolsScript.MARKER)
	editor._place_marker(3, 2)
	_assert("ui_place_marker", editor.doc.count_of_kind("marker") == 1)
	editor.doc.undo()
	_assert("ui_undo", editor.doc.count_of_kind("marker") == 0)
	editor.queue_free()
	await process_frame

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("simple_map_editor_test:FAIL at ", name)
		_failed = true
