extends SceneTree

## Vérifie l'aimantation des modules de toit/façade aux bâtiments proches
## (métadonnées du manifeste Blender : anchor roof/wall).

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = boot.build_demo(md)
	var village: Dictionary = demo.get("map", {})
	if village.is_empty():
		printerr("  FAIL village")
		quit(1)
		return
	var AssetLibraryScript: GDScript = load("res://scripts/maps/map_asset_library.gd")
	var roof_path := "res://assets/objects3d/buildings/toit_2pentes.glb"
	var door_path := "res://assets/objects3d/buildings/porte_auvent.glb"
	_assert("meta_roof", str(AssetLibraryScript.get_object3d_meta(roof_path).get("anchor", "")) == "roof")
	_assert("meta_wall", str(AssetLibraryScript.get_object3d_meta(door_path).get("anchor", "")) == "wall")

	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	get_root().add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	editor.load_map(village)
	await process_frame
	editor._set_tool("mesh")
	editor._mesh_snap_modules = true

	# Toit aimanté sur la maison proche : posé sur le toit (élévation > 0).
	editor._mesh_asset = roof_path
	editor._create_mesh(Vector2(7.0, 6.0))
	await process_frame
	var roofs := _meshes_with_asset(editor, roof_path)
	_assert("roof_created", roofs.size() == 1)
	if roofs.size() == 1:
		_assert("roof_elevated", float(roofs[0].get("elevation", 0.0)) > 0.5)
		_assert("roof_centered", absf(float(roofs[0].get("x", 0.0)) - 7.0) < 1.5)

	# Façade aimantée côté sud de la maison (la démo contient déjà une porte).
	var base_doors := _meshes_with_asset(editor, door_path).size()
	editor._mesh_asset = door_path
	editor._create_mesh(Vector2(7.0, 6.0))
	await process_frame
	var doors := _meshes_with_asset(editor, door_path)
	_assert("door_created", doors.size() == base_doors + 1)
	if doors.size() == base_doors + 1:
		var door: Dictionary = doors[doors.size() - 1]
		_assert("door_on_ground", is_equal_approx(float(door.get("elevation", 0.0)), 0.0))
		_assert("door_in_front", float(door.get("y", 0.0)) > 6.0)

	# Sans aimantation : le module reste à l'endroit cliqué, à plat.
	editor._mesh_snap_modules = false
	editor._mesh_asset = roof_path
	editor._create_mesh(Vector2(3.0, 12.0))
	await process_frame
	var flat_roofs := _meshes_with_asset(editor, roof_path)
	_assert("flat_roof_created", flat_roofs.size() == 2)
	if flat_roofs.size() == 2:
		_assert("flat_roof_ground", is_equal_approx(float(flat_roofs[1].get("elevation", 0.0)), 0.0))

	# Un module aimanté hérite de la rotation du bâtiment.
	editor.doc.add_element({
		"x": 14.0, "y": 14.0, "w": 2.0, "h": 1.8,
		"sizeX": 1.95, "sizeY": 1.88, "sizeZ": 1.81,
		"asset": "res://assets/objects3d/buildings/maison.glb",
		"elevation": 0.0, "followTerrain": true,
		"label": "Maison test", "layer": 1,
		"display": {"rotation": 90.0},
	}, "mesh", "Objet 3D")
	editor._mesh_snap_modules = true
	editor._mesh_asset = roof_path
	editor._create_mesh(Vector2(14.0, 14.0))
	await process_frame
	var rotated_roofs := _meshes_with_asset(editor, roof_path)
	_assert("rotated_roof_created", rotated_roofs.size() == 3)
	if rotated_roofs.size() == 3:
		var display: Dictionary = rotated_roofs[2].get("display", {})
		_assert("rotated_roof_inherits", is_equal_approx(float(display.get("rotation", 0.0)), 90.0))
		_assert("rotated_roof_at_building", absf(float(rotated_roofs[2].get("x", 0.0)) - 14.0) < 1.0)

	# Façade : posée sur l'avant du bâtiment, qui suit la rotation (90° = ouest).
	editor._mesh_asset = door_path
	editor._create_mesh(Vector2(14.0, 14.0))
	await process_frame
	var rotated_doors := _meshes_with_asset(editor, door_path)
	_assert("rotated_door_created", rotated_doors.size() == base_doors + 2)
	if rotated_doors.size() == base_doors + 2:
		var door_display: Dictionary = rotated_doors[rotated_doors.size() - 1].get("display", {})
		_assert("rotated_door_rotation", is_equal_approx(float(door_display.get("rotation", 0.0)), 90.0))
		_assert("rotated_door_front", float(rotated_doors[rotated_doors.size() - 1].get("x", 14.0)) < 13.9)

	editor.queue_free()
	await process_frame
	if _failed:
		print("map_editor_snap_test:FAIL")
		quit(1)
		return
	print("map_editor_snap_test:PASS")
	quit(0)

func _meshes_with_asset(editor: Control, asset_path: String) -> Array:
	var out: Array = []
	for elem_variant in editor.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("kind", "")) == "mesh" and str(elem.get("asset", "")) == asset_path:
			out.append(elem)
	return out

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
