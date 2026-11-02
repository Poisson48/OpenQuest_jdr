extends SceneTree

## Test du décor contextuel : un clic près d'un mur sème des éléments le long
## de ses abords, en une seule transaction.

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test décor contextuel", "general", "local", 18, 14)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(960, 540)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	await process_frame
	editor.doc.add_element({
		"x": 7.0, "y": 6.0, "w": 4.0, "h": 0.8,
		"sizeX": 4.0, "sizeY": 1.3, "sizeZ": 0.8,
		"asset": "res://assets/objects3d/buildings/mur.glb",
		"elevation": 0.0, "followTerrain": true,
		"label": "Mur test", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, "mesh", "Mur test")
	editor._context_decor_radius = 3.0
	editor._context_decor_density = 0.8
	editor._context_decor_seed = 5
	editor._construction._decorate_context(Vector2(7.0, 6.0))
	var decor: Array = []
	for elem_variant in editor.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("label", "")) == "Décor contextuel":
			decor.append(elem)
	_assert("context_decor_created", decor.size() > 0, "count=%d" % decor.size())
	_assert("context_decor_has_variation", decor.size() >= 2)
	var first_x := float(decor[0].get("x", 0.0))
	_assert("context_decor_off_wall", absf(first_x - 7.0) > 0.1 or decor.size() > 1)

	# Décor de berge : une case d'eau entourée de terre.
	editor.doc.map_data["waterLevel"] = 0.0
	editor.doc.set_terrain_height(4, 11, -1.0)
	editor.doc.set_terrain_height(5, 11, 0.0)
	editor._context_decor_seed = 9
	editor._construction._decorate_context(Vector2(5.0, 11.0))
	var bank_decor: Array = []
	for elem_variant in editor.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("asset", "")).contains("roseaux") or str(elem.get("asset", "")).contains("nenuphars"):
			bank_decor.append(elem)
	_assert("context_decor_bank", bank_decor.size() > 0, "count=%d" % bank_decor.size())

	# Décor de chemin : bordure de terre entourée d'herbe.
	editor.doc.set_terrain_material(10, 10, 1)
	editor.doc.set_terrain_material(10, 11, 1)
	editor.doc.set_terrain_material(9, 10, 1)
	editor._context_decor_seed = 11
	editor._construction._decorate_context(Vector2(10.0, 10.0))
	var path_decor: Array = []
	for elem_variant in editor.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("label", "")) == "Décor contextuel" and (
			str(elem.get("asset", "")).contains("buisson")
			or str(elem.get("asset", "")).contains("rocher")
			or str(elem.get("asset", "")).contains("haie")
		):
			path_decor.append(elem)
	_assert("context_decor_path", path_decor.size() > 0, "count=%d" % path_decor.size())

	if _failed:
		print("map_context_decor_test:FAIL")
		quit(1)
		return
	print("map_context_decor_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
