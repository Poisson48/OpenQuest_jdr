extends SceneTree

## Test de l'empilement automatique : une lanterne posée sur une table doit
## prendre l'élévation du dessus de la table, sans réglage manuel.

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test empilement", "general", "local", 16, 12)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(960, 540)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	await process_frame
	editor._auto_stack = true
	editor._mesh_snap_modules = false
	editor._mesh_scale = 1.0
	editor._mesh_asset = "res://assets/objects3d/props/table_tabourets.glb"
	editor._create_mesh(Vector2(6.0, 6.0))
	editor._mesh_asset = "res://assets/objects3d/props/lanterne.glb"
	editor._create_mesh(Vector2(6.0, 6.0))
	var lantern: Dictionary = {}
	for elem_variant in editor.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("asset", "")).contains("lanterne"):
			lantern = elem
			break
	_assert("stack_lantern_created", not lantern.is_empty())
	_assert("stack_lantern_elevated", float(lantern.get("elevation", 0.0)) > 0.2,
		"elevation=%s" % str(lantern.get("elevation", 0.0)))
	# Sans empilement, elle reste au sol.
	editor._auto_stack = false
	editor._create_mesh(Vector2(10.0, 6.0))
	var ground_lantern: Dictionary = {}
	for elem_variant in editor.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("asset", "")).contains("lanterne") and absf(float(elem.get("x", 0.0)) - 10.0) < 0.5:
			ground_lantern = elem
			break
	_assert("stack_disabled_ground", not ground_lantern.is_empty()
		and absf(float(ground_lantern.get("elevation", 0.0))) < 0.05)

	if _failed:
		print("map_stacking_test:FAIL")
		quit(1)
		return
	print("map_stacking_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
