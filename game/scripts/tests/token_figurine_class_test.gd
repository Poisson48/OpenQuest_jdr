extends SceneTree

## Vérifie le choix des figurines 3D par classe (kit v6) en carte 2.5D.

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test figurines classes", "general", "local", 10, 8)
	var map_id := str(map.get("id", ""))
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	md.update_map(map)
	map = md.get_by_id(map_id)

	var party := [
		{"id": "h-arch", "name": "Lyra", "class": "Archère"},
		{"id": "h-mage", "name": "Orin", "class": "Mage"},
		{"id": "h-gob", "name": "Grik", "class": "Gobelin"},
		{"id": "h-none", "name": "Mystère", "class": ""},
	]
	var tokens := [
		{"id": "t1", "kind": "member", "memberId": "h-arch", "label": "Lyra", "x": 2.0, "y": 2.0},
		{"id": "t2", "kind": "member", "memberId": "h-mage", "label": "Orin", "x": 3.0, "y": 2.0},
		{"id": "t3", "kind": "member", "memberId": "h-gob", "label": "Grik", "x": 4.0, "y": 2.0},
		{"id": "t4", "kind": "member", "memberId": "h-none", "label": "Mystère", "x": 5.0, "y": 2.0},
		{"id": "t5", "kind": "marker", "label": "Sortie", "x": 6.0, "y": 4.0},
	]
	var EngineScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var engine: Control = EngineScript.new()
	get_root().add_child(engine)
	engine.size = Vector2(800, 600)
	await process_frame
	engine.configure(map, tokens, party, [], [], [], false, true)
	for _i in range(4):
		await process_frame

	var by_label: Dictionary = {}
	for node in engine._token_nodes.values():
		var label := str(node.token_data.get("label", ""))
		by_label[label] = str(node.get("figurine_asset"))
	_assert("archere", str(by_label.get("Lyra", "")).ends_with("pnj_archere.glb"))
	_assert("mage", str(by_label.get("Orin", "")).ends_with("pnj_mage.glb"))
	_assert("gobelin", str(by_label.get("Grik", "")).ends_with("pnj_gobelin.glb"))
	_assert("fallback_figurine", not str(by_label.get("Mystère", "")).is_empty())
	_assert("marker_no_figurine", str(by_label.get("Sortie", "")).is_empty())

	engine.queue_free()
	await process_frame
	md.delete_map(map_id)

	if _failed:
		print("token_figurine_class_test:FAIL")
		quit(1)
		return
	print("token_figurine_class_test:PASS")
	quit(0)

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
