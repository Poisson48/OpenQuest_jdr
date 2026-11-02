extends SceneTree

## Test : une porte peut ouvrir un mur procédural (le mur est scindé).

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test porte procédurale", "general", "local", 18, 12)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(960, 540)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	await process_frame
	editor.doc.add_element({
		"x": 8.0, "y": 6.0, "w": 8.0, "h": 0.7,
		"asset": "procedural://wall",
		"points": [[-4.0, 0.0], [0.0, 0.0], [4.0, 0.0]],
		"height": 2.2, "thickness": 0.7, "bevel": 0.12,
		"elevation": 0.0, "followTerrain": true,
		"label": "Mur procédural", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, "mesh", "Mur procédural")
	editor._insert_door(Vector2(8.0, 6.0))
	await process_frame
	var walls := 0
	var doors := 0
	for elem_variant in editor.doc.elements_of_kind("mesh"):
		var elem: Dictionary = elem_variant
		var asset := str(elem.get("asset", ""))
		if asset == "procedural://wall":
			walls += 1
		elif asset.contains("porte"):
			doors += 1
	_assert("proc_door_created", doors > 0, "doors=%d" % doors)
	_assert("proc_wall_split", walls >= 2, "walls=%d" % walls)

	if _failed:
		print("procedural_wall_door_test:FAIL")
		quit(1)
		return
	print("procedural_wall_door_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
