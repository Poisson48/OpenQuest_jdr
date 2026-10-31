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
	var awning_path := "res://assets/objects3d/buildings/auvent_etal.glb"
	_assert("meta_roof", str(AssetLibraryScript.get_object3d_meta(roof_path).get("anchor", "")) == "roof")
	_assert("meta_wall", str(AssetLibraryScript.get_object3d_meta(door_path).get("anchor", "")) == "wall")

	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	get_root().add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	editor.load_map(village)
	await process_frame
	# Navigation rapide entre zones du monde (émet l'ouverture d'une autre zone).
	var cycle_targets: Array = []
	editor.open_map_requested.connect(func(id): cycle_targets.append(id))
	editor._cycle_world_map(1)
	_assert("world_cycle_emits", not cycle_targets.is_empty()
		and str(cycle_targets[0]) != str(village.get("id", "")))
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

	# Auvent contre un mur latéral puis contre le mur avant.
	editor.doc.add_element({
		"x": 20.0, "y": 20.0, "w": 2.0, "h": 2.0,
		"sizeX": 1.95, "sizeY": 1.88, "sizeZ": 1.81,
		"asset": "res://assets/objects3d/buildings/maison.glb",
		"elevation": 0.0, "followTerrain": true,
		"label": "Maison auvent", "layer": 1,
		"display": {"rotation": 0.0},
	}, "mesh", "Objet 3D")
	var awnings_before := _meshes_with_asset(editor, awning_path).size()
	editor._mesh_snap_modules = true
	editor._mesh_asset = awning_path
	editor._create_mesh(Vector2(21.2, 20.0))
	await process_frame
	var side_awnings := _meshes_with_asset(editor, awning_path)
	_assert("awning_side_created", side_awnings.size() == awnings_before + 1)
	if side_awnings.size() == awnings_before + 1:
		var side_awning: Dictionary = side_awnings[side_awnings.size() - 1]
		var side_display: Dictionary = side_awning.get("display", {})
		_assert("awning_side_rotation", is_equal_approx(float(side_display.get("rotation", 0.0)), -90.0))
		_assert("awning_side_against_wall", float(side_awning.get("x", 0.0)) > 20.9
			and absf(float(side_awning.get("y", 0.0)) - 20.0) < 0.1)
	editor._create_mesh(Vector2(20.0, 21.2))
	await process_frame
	var front_awnings := _meshes_with_asset(editor, awning_path)
	_assert("awning_front_created", front_awnings.size() == awnings_before + 2)
	if front_awnings.size() == awnings_before + 2:
		var front_awning: Dictionary = front_awnings[front_awnings.size() - 1]
		var front_display: Dictionary = front_awning.get("display", {})
		_assert("awning_front_rotation", is_equal_approx(float(front_display.get("rotation", 0.0)), 0.0))
		_assert("awning_front_against_wall", float(front_awning.get("y", 0.0)) > 20.9
			and absf(float(front_awning.get("x", 0.0)) - 20.0) < 0.1)

	# Redimensionnement à la poignée : proportions conservées, pas de hauteur écrasée.
	var resize_id: String = editor.doc.add_element({
		"x": 30.0, "y": 30.0, "w": 1.0, "h": 1.0,
		"asset": "res://assets/objects3d/buildings/maison.glb",
		"elevation": 0.0, "followTerrain": true,
		"label": "Maison resize", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, "mesh", "Objet 3D")
	var resize_elem: Dictionary = editor.doc.get_element(resize_id)
	var dims_before: Vector3 = editor._mesh_actual_dimensions(resize_elem)
	_assert("resize_natural_dims", dims_before.x > 0.5 and dims_before.y > 0.5 and dims_before.z > 0.5)
	editor._handle_state = {
		"id": resize_id, "x": 30.0, "y": 30.0,
		"w": dims_before.x, "h": dims_before.z,
		"mesh_dims": dims_before, "start_grid": Vector2(30.0 + dims_before.x, 30.0),
	}
	editor._apply_handle_resize(Vector2(30.0 + dims_before.x * 2.0, 30.0))
	var dims_after: Vector3 = editor._mesh_actual_dimensions(editor.doc.get_element(resize_id))
	_assert("resize_keeps_height", dims_after.y > dims_before.y * 1.5 and dims_after.y < dims_before.y * 2.5)
	_assert("resize_keeps_proportions", absf(dims_after.x / dims_before.x - dims_after.z / dims_before.z) < 0.05)
	editor._handle_state.clear()

	# Construction d'un mur 3D modulaire le long d'un tracé.
	var wall_asset := "res://assets/objects3d/buildings/mur.glb"
	var walls_before := _meshes_with_asset(editor, wall_asset).size()
	editor._create_mesh_wall_chain(Vector2(2.0, 2.0), Vector2(8.0, 2.0))
	await process_frame
	var walls_after := _meshes_with_asset(editor, wall_asset)
	_assert("mesh_wall_chain_count", walls_after.size() > walls_before)
	if walls_after.size() > walls_before:
		var first_wall: Dictionary = walls_after[walls_before]
		var first_display: Dictionary = first_wall.get("display", {})
		_assert("mesh_wall_chain_rotation", absf(float(first_display.get("rotation", 0.0))) < 1.0)
		_assert("mesh_wall_chain_follows", bool(first_wall.get("followTerrain", false)))
	# Tracé vertical : rotation à 90°.
	# Hauteur de mur personnalisée.
	editor._wall_height = 2.2
	editor._create_mesh_wall_chain(Vector2(12.0, 12.0), Vector2(16.0, 12.0))
	await process_frame
	var tall_walls := _meshes_with_asset(editor, wall_asset)
	var tall_wall: Dictionary = tall_walls[tall_walls.size() - 1]
	_assert("mesh_wall_height", is_equal_approx(float(tall_wall.get("sizeY", 0.0)), 2.2))
	editor._wall_height = 1.3

	# Porte 3D : ouverture dans un mur (deux montants + porte).
	editor._create_mesh_wall_chain(Vector2(12.0, 10.0), Vector2(17.0, 10.0))
	await process_frame
	var door_path_ui := "res://assets/objects3d/buildings/porte_auvent.glb"
	var ui_wall_count := _meshes_with_asset(editor, wall_asset).size()
	var ui_door_count := _meshes_with_asset(editor, door_path_ui).size()
	var target_wall: Dictionary = _meshes_with_asset(editor, wall_asset)[ui_wall_count - 1]
	editor._insert_door(Vector2(float(target_wall.get("x", 0.0)), float(target_wall.get("y", 0.0))))
	await process_frame
	_assert("mesh_door_opening", _meshes_with_asset(editor, wall_asset).size() == ui_wall_count + 1)
	_assert("mesh_door_created", _meshes_with_asset(editor, door_path_ui).size() == ui_door_count + 1)

	# Fenêtre 3D sur une façade.
	var window_path_ui := "res://assets/objects3d/buildings/fenetre_volets.glb"
	var window_count := _meshes_with_asset(editor, window_path_ui).size()
	var window_wall: Dictionary = _meshes_with_asset(editor, wall_asset)[0]
	editor._insert_window(Vector2(float(window_wall.get("x", 0.0)), float(window_wall.get("y", 0.0))))
	await process_frame
	_assert("mesh_window_created", _meshes_with_asset(editor, window_path_ui).size() == window_count + 1)

	# Mobilier : ensemble de salle commune posé autour d'un point.
	var mesh_count_before_furnish: int = editor.doc.elements_of_kind("mesh").size()
	editor._furnish_preset = "salle"
	editor._insert_furniture(Vector2(6.0, 15.0))
	await process_frame
	_assert("mesh_furniture_created",
		editor.doc.elements_of_kind("mesh").size() >= mesh_count_before_furnish + 2)
	_assert("mesh_furniture_selected", editor.doc.selection_size() >= 2)

	# Clôture modulaire le long d'un tracé.
	var fence_asset := "res://assets/objects3d/props/barriere.glb"
	var fences_before := _meshes_with_asset(editor, fence_asset).size()
	editor._create_mesh_fence(Vector2(2.0, 15.0), Vector2(8.0, 15.0))
	await process_frame
	var fences_after := _meshes_with_asset(editor, fence_asset)
	_assert("mesh_fence_created", fences_after.size() > fences_before)
	if fences_after.size() > fences_before:
		var fence_display: Dictionary = fences_after[fences_before].get("display", {})
		_assert("mesh_fence_rotation", absf(float(fence_display.get("rotation", 0.0))) < 1.0)
	var walls_before_v := _meshes_with_asset(editor, wall_asset).size()
	editor._create_mesh_wall_chain(Vector2(2.0, 4.0), Vector2(2.0, 8.0))
	await process_frame
	var walls_v := _meshes_with_asset(editor, wall_asset)
	_assert("mesh_wall_chain_vertical", walls_v.size() > walls_before_v)
	if walls_v.size() > walls_before_v:
		var vert_display: Dictionary = walls_v[walls_before_v].get("display", {})
		_assert("mesh_wall_chain_vertical_rotation",
			absf(float(vert_display.get("rotation", 0.0)) - 90.0) < 1.0)

	# Même chose via l'état de l'outil (press → drag → release).
	editor._set_tool("mesh_wall")
	var ui_walls_before := _meshes_with_asset(editor, wall_asset).size()
	var mods := {"shift": false, "ctrl": false, "alt": false}
	editor._on_pointer_pressed(Vector2(2.0, 10.0), Vector2(200, 200), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_moved(Vector2(8.0, 10.0), Vector2(400, 200), mods)
	editor._on_pointer_released(Vector2(8.0, 10.0), Vector2(400, 200), MOUSE_BUTTON_LEFT, mods)
	await process_frame
	_assert("mesh_wall_tool_drag", _meshes_with_asset(editor, wall_asset).size() > ui_walls_before)

	# Pièce 3D : quatre murs qui se recouvrent aux angles.
	var room_walls_before := _meshes_with_asset(editor, wall_asset).size()
	editor._create_mesh_room(Vector2(2.0, 14.0), Vector2(8.0, 18.0))
	await process_frame
	_assert("mesh_room_walls", _meshes_with_asset(editor, wall_asset).size() > room_walls_before + 4)
	_assert("mesh_room_selected", editor.doc.selection_size() >= 8)

	# Toit 3D : grille de tuiles au-dessus de la pièce.
	var roof_asset := "res://assets/objects3d/buildings/toit_2pentes.glb"
	var roofs_before := _meshes_with_asset(editor, roof_asset).size()
	editor._create_mesh_roof(Vector2(2.0, 14.0), Vector2(8.0, 18.0))
	await process_frame
	var roofs_after := _meshes_with_asset(editor, roof_asset)
	_assert("mesh_roof_tiles", roofs_after.size() == roofs_before + 6)
	if roofs_after.size() > roofs_before:
		var roof_tile: Dictionary = roofs_after[roofs_before]
		_assert("mesh_roof_elevation", is_equal_approx(float(roof_tile.get("elevation", 0.0)), 1.1))

	# Dallage : matière pierre (2) et sol nivelé dans le rectangle.
	editor._create_floor(Vector2(3.0, 15.0), Vector2(7.0, 17.0))
	var floor_map: Dictionary = editor.doc.map_data
	var floor_w := int(floor_map.get("width", 1))
	var floor_mats: Array = floor_map.get("terrainMaterials", [])
	_assert("mesh_floor_material", floor_mats.size() > 16 * 15 + 3
		and int(floor_mats[15 * floor_w + 3]) == 2)
	var floor_heights: Array = floor_map.get("terrainHeights", [])
	_assert("mesh_floor_flattened", floor_heights.size() > 16 * 15 + 3
		and is_equal_approx(float(floor_heights[15 * floor_w + 3]), 0.0))

	# Matière de dallage au choix (terre).
	editor._floor_material = 1
	editor._create_floor(Vector2(10.0, 15.0), Vector2(12.0, 17.0))
	var earth_mats: Array = editor.doc.map_data.get("terrainMaterials", [])
	_assert("mesh_floor_material_choice", earth_mats.size() > 15 * 16 + 10
		and int(earth_mats[15 * floor_w + 10]) == 1)
	editor._floor_material = 2

	# Style de toit au choix (chaume).
	var thatch_asset := "res://assets/objects3d/buildings/toit_chaume.glb"
	editor._roof_asset = thatch_asset
	var thatch_before := _meshes_with_asset(editor, thatch_asset).size()
	editor._create_mesh_roof(Vector2(10.0, 3.0), Vector2(14.0, 6.0))
	_assert("mesh_roof_style_choice", _meshes_with_asset(editor, thatch_asset).size() > thatch_before)
	editor._roof_asset = "res://assets/objects3d/buildings/toit_2pentes.glb"

	# Maison rapide : tout en une passe.
	var house_walls_before := _meshes_with_asset(editor, wall_asset).size()
	var house_roofs_before := _meshes_with_asset(editor, "res://assets/objects3d/buildings/toit_2pentes.glb").size()
	var house_doors_before := _meshes_with_asset(editor, "res://assets/objects3d/buildings/porte_auvent.glb").size()
	editor._create_mesh_house(Vector2(12.0, 2.0), Vector2(18.0, 6.0))
	await process_frame
	_assert("house_walls", _meshes_with_asset(editor, wall_asset).size() > house_walls_before)
	_assert("house_roof",
		_meshes_with_asset(editor, "res://assets/objects3d/buildings/toit_2pentes.glb").size() > house_roofs_before)
	_assert("house_door",
		_meshes_with_asset(editor, "res://assets/objects3d/buildings/porte_auvent.glb").size() > house_doors_before)
	var house_mats: Array = editor.doc.map_data.get("terrainMaterials", [])
	_assert("house_floor", house_mats.size() > 4 * int(editor.doc.map_data.get("width", 1)) + 15
		and int(house_mats[4 * int(editor.doc.map_data.get("width", 1)) + 15]) == 2)

	# Échelle uniforme depuis l'inspecteur : les trois axes suivent.
	var meshes: Array = editor.doc.elements_of_kind("mesh")
	if not meshes.is_empty():
		var first_mesh: Dictionary = meshes[0]
		var first_asset := str(first_mesh.get("asset", ""))
		var natural: Vector3 = editor._inspector._mesh_natural_dimensions(first_asset)
		editor.doc.select_only(str(first_mesh.get("id", "")))
		editor._inspector._apply_mesh_scale(2.0, natural)
		var scaled_elem: Dictionary = editor.doc.get_element(str(first_mesh.get("id", "")))
		var scaled_dims: Vector3 = editor._mesh_actual_dimensions(scaled_elem)
		_assert("inspector_scale_uniform", natural.y > 0.1
			and absf(scaled_dims.y - natural.y * 2.0) < 0.05
			and absf(scaled_dims.x - natural.x * 2.0) < 0.05)

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
