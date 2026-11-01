extends SceneTree

## Tests du « Tiny Glade » organique : tracé freehand lissé (Catmull-Rom) en
## modules orientés tangente, et dispersion automatique de végétation.
##
## Couvre les helpers purs (`OrganicPath`, `OrganicScatter`) et l'intégration
## éditeur (transaction unique, undo, options, eau, dédoublonnage).

const OrganicPathScript := preload("res://scripts/maps/construction/organic_path.gd")
const OrganicScatterScript := preload("res://scripts/maps/construction/organic_scatter.gd")
const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_test_path_math()
	_test_scatter_math()
	await _test_editor_organic()
	await _test_editor_scatter()
	if _failed:
		quit(1)
		return
	print("map_organic_creation_test:PASS")
	quit(0)

# ===========================================================================
# Helpers purs
# ===========================================================================

func _test_path_math() -> void:
	# Lissage d'une droite : la courbe reste sur l'axe, extrémités conservées.
	var straight := [Vector2(0, 0), Vector2(4, 0), Vector2(8, 0)]
	var smoothed := OrganicPathScript.smooth_points(straight, 4)
	_assert("smooth_straight_count", smoothed.size() == 9)
	var max_offset := 0.0
	for point_variant in smoothed:
		max_offset = maxf(max_offset, absf((point_variant as Vector2).y))
	_assert("smooth_straight_flat", max_offset < 0.01)
	_assert("smooth_endpoints_kept",
		(smoothed[0] as Vector2).distance_to(Vector2(0, 0)) < 0.001
		and (smoothed[smoothed.size() - 1] as Vector2).distance_to(Vector2(8, 0)) < 0.001)
	_assert("path_total_length", is_equal_approx(OrganicPathScript.total_length(straight), 8.0))

	# Ré-échantillonnage : pas constant, début/fin exacts.
	var resampled := OrganicPathScript.resample(smoothed, 2.0)
	_assert("resample_count", resampled.size() == 5)
	var uniform := true
	for i in range(1, resampled.size()):
		var step := (resampled[i] as Vector2).distance_to(resampled[i - 1] as Vector2)
		if absf(step - 2.0) > 0.01:
			uniform = false
	_assert("resample_uniform", uniform)
	_assert("resample_endpoints",
		(resampled[0] as Vector2).distance_to(Vector2(0, 0)) < 0.001
		and (resampled[resampled.size() - 1] as Vector2).distance_to(Vector2(8, 0)) < 0.001)

	# Tracé courbe : les modules suivent la tangente et se chevauchent (pas de trou).
	var curve := [Vector2(0, 0), Vector2(2, 3), Vector2(6, 3), Vector2(8, 0)]
	var chain := OrganicPathScript.build_chain(curve, {
		"smoothing": 4, "spacing": 1.2, "nominal_length": 2.363,
		"nominal_depth": 0.697,
	})
	_assert("chain_curve_modules", chain.size() > 4)
	var tangent_ok := true
	var heights_ok := true
	for module_variant in chain:
		var module: Dictionary = module_variant
		var ends := OrganicPathScript.module_endpoints(module)
		var chord_dir: Vector2 = ((ends[1] as Vector2) - (ends[0] as Vector2)).normalized()
		var rad := deg_to_rad(float(module.get("rotation", 0.0)))
		var axis := Vector2(cos(rad), sin(rad))
		if axis.dot(chord_dir) < 0.999:
			tangent_ok = false
		if float(module.get("length", 0.0)) <= float(module.get("chord", 0.0)):
			heights_ok = false
	_assert("chain_tangent", tangent_ok)
	_assert("chain_overlap", heights_ok)
	var no_hole := true
	for i in range(chain.size() - 1):
		var prev_ends := OrganicPathScript.module_endpoints(chain[i])
		var next_ends := OrganicPathScript.module_endpoints(chain[i + 1])
		var gap: Vector2 = (next_ends[0] as Vector2) - (prev_ends[1] as Vector2)
		var rad := deg_to_rad(float((chain[i] as Dictionary).get("rotation", 0.0)))
		var axis := Vector2(cos(rad), sin(rad))
		# Les modules se chevauchent : la jointure n'est jamais un trou.
		if gap.dot(axis) > 0.01:
			no_hole = false
	_assert("chain_no_hole", no_hole)
	# Extrémités du tracé : la chaîne reste collée au départ et à l'arrivée.
	var first_ends := OrganicPathScript.module_endpoints(chain[0])
	var last_ends := OrganicPathScript.module_endpoints(chain[chain.size() - 1])
	_assert("chain_starts_on_curve", (first_ends[0] as Vector2).distance_to(Vector2(0, 0)) < 0.6)
	_assert("chain_ends_on_curve", (last_ends[1] as Vector2).distance_to(Vector2(8, 0)) < 0.6)

	# Geste trop court / points insuffisants : chaîne vide, pas de crash.
	_assert("chain_single_point_empty",
		OrganicPathScript.build_chain([Vector2(1, 1)], {}).is_empty())

func _test_scatter_math() -> void:
	for mode_id in OrganicScatterScript.MODE_ORDER:
		_assert("scatter_mode_" + mode_id,
			not OrganicScatterScript.mode_label(mode_id).is_empty())
	_assert("scatter_mode_assets_buisson",
		OrganicScatterScript.mode_asset_paths("buisson").size() == 1
		and str(OrganicScatterScript.mode_asset_paths("buisson")[0]).ends_with("buisson.glb"))
	_assert("scatter_mode_assets_mix", OrganicScatterScript.mode_asset_paths("mix").size() >= 5)
	_assert("scatter_mode_assets_rocher",
		OrganicScatterScript.mode_asset_paths("rocher").size() >= 1)

	var positions := OrganicScatterScript.scatter_along_path(
		[Vector2(0, 0), Vector2(10, 0)], 1.0, 1.5, 7)
	_assert("scatter_positions_count", positions.size() >= 9)
	var deterministic := true
	var again := OrganicScatterScript.scatter_along_path(
		[Vector2(0, 0), Vector2(10, 0)], 1.0, 1.5, 7)
	if positions.size() != again.size():
		deterministic = false
	else:
		for i in range(positions.size()):
			if (positions[i]["position"] as Vector2).distance_to(again[i]["position"] as Vector2) > 0.0001:
				deterministic = false
	_assert("scatter_positions_deterministic", deterministic)
	var other_seed := OrganicScatterScript.scatter_along_path(
		[Vector2(0, 0), Vector2(10, 0)], 1.0, 1.5, 8)
	var differs := false
	for i in range(mini(positions.size(), other_seed.size())):
		if (positions[i]["position"] as Vector2).distance_to(other_seed[i]["position"] as Vector2) > 0.01:
			differs = true
	_assert("scatter_positions_seeded", differs)
	# Dispersion autour du tracé, pas dessus uniquement.
	var max_offset := 0.0
	for entry_variant in positions:
		var entry: Dictionary = entry_variant
		max_offset = maxf(max_offset, absf((entry["position"] as Vector2).y))
	_assert("scatter_spread", max_offset > 0.3 and max_offset < 2.5)

	var assets := OrganicScatterScript.mode_asset_paths("mix")
	var items := OrganicScatterScript.make_items(positions, assets, 11, 1.2, 0.15)
	_assert("scatter_items_count", items.size() == positions.size())
	var rotations := {}
	var scales := {}
	for item_variant in items:
		var item: Dictionary = item_variant
		rotations[int(round(float(item["rotation"])))] = true
		scales[snappedf(float(item["scale"]), 0.01)] = true
	_assert("scatter_items_varied", rotations.size() > 3 and scales.size() > 1)
	var deduped := OrganicScatterScript.dedupe_by_cell([
		{"cell": Vector2i(2, 3), "x": 2.0, "y": 3.0},
		{"cell": Vector2i(2, 3), "x": 2.0, "y": 3.0},
		{"cell": Vector2i(4, 5), "x": 4.0, "y": 5.0},
	])
	_assert("scatter_dedupe", deduped.size() == 2)
	var zone_positions := OrganicScatterScript.scatter_in_cells(
		[Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)], 1.0, 1.0, 5)
	_assert("scatter_zone_positions", zone_positions.size() == 3)
	_assert("scatter_zone_empty_chance",
		OrganicScatterScript.scatter_in_cells([Vector2i(1, 1)], 0.0, 1.0, 5).is_empty())

# ===========================================================================
# Intégration éditeur
# ===========================================================================

func _make_editor(map: Dictionary) -> Control:
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	get_root().add_child(editor)
	editor.size = Vector2(1280, 800)
	editor.load_map(map)
	return editor

func _make_map(md, title: String) -> Dictionary:
	var map: Dictionary = md.create_complex_map(title, "general", "local", 40, 30)
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["fogEnabled"] = false
	md.update_map(map)
	return md.get_by_id(str(map.get("id", "")))

func _test_editor_organic() -> void:
	var md = get_root().get_node("MapData")
	var editor := _make_editor(_make_map(md, "Tracé organique test"))
	await process_frame
	_assert("organic_tool_catalog", ToolsScript.label(ToolsScript.ORGANIC) == "Tracé organique")
	_assert("organic_tool_present", not ToolsScript.icon(ToolsScript.ORGANIC).is_empty())
	_assert("scatter_tool_catalog", ToolsScript.label(ToolsScript.SCATTER) == "Végétation")

	editor._set_tool("organic")
	editor._organic_asset = "res://assets/objects3d/buildings/mur.glb"
	editor._wall_height = 1.8
	editor._organic_smoothing = 4
	var curve := [Vector2(4, 4), Vector2(7, 6), Vector2(11, 6), Vector2(14, 4)]
	var ids: Array = editor._build_organic_chain(curve)
	await process_frame
	_assert("organic_chain_created", ids.size() >= 4)
	_assert("organic_chain_selected", editor.doc.selection_size() == ids.size())
	var modules: Array = []
	for id_variant in ids:
		modules.append(editor.doc.get_element(str(id_variant)))
	var tangent_ok := true
	var height_ok := true
	var overlap_ok := true
	for i in range(modules.size()):
		var module: Dictionary = modules[i]
		var display: Dictionary = module.get("display", {}) if module.get("display") is Dictionary else {}
		var rad := deg_to_rad(float(display.get("rotation", 0.0)))
		var axis := Vector2(cos(rad), sin(rad))
		var ends := _mesh_endpoints(module)
		var chord_dir: Vector2 = ((ends[1] as Vector2) - (ends[0] as Vector2)).normalized()
		if axis.dot(chord_dir) < 0.999:
			tangent_ok = false
		if not is_equal_approx(float(module.get("sizeY", 0.0)), 1.8):
			height_ok = false
		if not bool(module.get("followTerrain", false)):
			overlap_ok = false
		if i + 1 < modules.size():
			var next_ends := _mesh_endpoints(modules[i + 1])
			if ((next_ends[0] as Vector2) - (ends[1] as Vector2)).dot(axis) > 0.01:
				overlap_ok = false
	_assert("organic_modules_tangent", tangent_ok)
	_assert("organic_modules_height", height_ok)
	_assert("organic_no_hole_follow_terrain", overlap_ok)

	# Undo unique : tout le tracé part en une seule action.
	var meshes_after: int = editor.doc.elements_of_kind("mesh").size()
	editor.doc.undo()
	_assert("organic_undo_single",
		editor.doc.elements_of_kind("mesh").size() == meshes_after - ids.size())
	editor.doc.redo()
	_assert("organic_redo", editor.doc.elements_of_kind("mesh").size() == meshes_after)

	# Geste souris réel : press → moves → release.
	editor._set_tool("organic")
	var mods := {"shift": false, "ctrl": false, "alt": false}
	var ui_before: int = editor.doc.elements_of_kind("mesh").size()
	editor._on_pointer_pressed(Vector2(20, 20), Vector2(300, 300), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_moved(Vector2(23, 22), Vector2(330, 320), mods)
	editor._on_pointer_moved(Vector2(27, 22), Vector2(370, 320), mods)
	editor._on_pointer_moved(Vector2(30, 20), Vector2(400, 300), mods)
	_assert("organic_preview_path", editor._overlay.polygon_points.size() >= 3)
	editor._on_pointer_released(Vector2(30, 20), Vector2(400, 300), MOUSE_BUTTON_LEFT, mods)
	await process_frame
	_assert("organic_ui_created", editor.doc.elements_of_kind("mesh").size() > ui_before)
	var status := str(editor._status_lbl.text) if editor._status_lbl != null else ""
	_assert("organic_ui_status", status.find("Tracé organique") >= 0)
	_assert("organic_preview_cleared", editor._overlay.polygon_points.is_empty())

	# Style clôture : modules plus courts, asset dédié.
	editor._set_tool("organic")
	editor._organic_asset = "res://assets/objects3d/props/palissade.glb"
	editor._wall_height = 1.2
	var fence_ids: Array = editor._build_organic_chain(
		[Vector2(6, 24), Vector2(10, 22), Vector2(14, 24)])
	await process_frame
	_assert("organic_fence_created", fence_ids.size() >= 3)
	var fence_ok := true
	for id_variant in fence_ids:
		var elem: Dictionary = editor.doc.get_element(str(id_variant))
		if not str(elem.get("asset", "")).ends_with("palissade.glb"):
			fence_ok = false
	_assert("organic_fence_asset", fence_ok)
	editor._organic_asset = "res://assets/objects3d/buildings/mur.glb"

	# Geste trop court : rien n'est créé.
	var before_short: int = editor.doc.elements_of_kind("mesh").size()
	editor._on_pointer_pressed(Vector2(35, 27), Vector2(500, 400), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_released(Vector2(35, 27), Vector2(500, 400), MOUSE_BUTTON_LEFT, mods)
	await process_frame
	_assert("organic_short_gesture", editor.doc.elements_of_kind("mesh").size() == before_short)
	editor.queue_free()
	await process_frame

func _test_editor_scatter() -> void:
	var md = get_root().get_node("MapData")
	var editor := _make_editor(_make_map(md, "Végétation test"))
	await process_frame
	editor._set_tool("scatter")
	editor._scatter_mode = "mix"
	editor._scatter_density = 1.5
	editor._scatter_size = 1.2
	editor._scatter_radius = 1.2
	editor._scatter_seed = 4242
	editor._scatter_zone_mode = false
	var before: int = editor.doc.elements_of_kind("mesh").size()
	var ids: Array = editor._scatter_stroke_points([Vector2(5, 20), Vector2(15, 20)])
	await process_frame
	_assert("scatter_created", ids.size() > 3)
	_assert("scatter_meshes", editor.doc.elements_of_kind("mesh").size() == before + ids.size())
	var cells: Dictionary = {}
	var duplicate := false
	var rotations: Dictionary = {}
	var scales: Dictionary = {}
	var follow_terrain := true
	var in_bounds := true
	for id_variant in ids:
		var elem: Dictionary = editor.doc.get_element(str(id_variant))
		var cx := int(round(float(elem.get("x", 0.0))))
		var cy := int(round(float(elem.get("y", 0.0))))
		var key := "%d,%d" % [cx, cy]
		if cells.has(key):
			duplicate = true
		cells[key] = true
		if cx < 0 or cy < 0 or cx >= 40 or cy >= 30:
			in_bounds = false
		follow_terrain = follow_terrain and bool(elem.get("followTerrain", false))
		var display: Dictionary = elem.get("display", {}) if elem.get("display") is Dictionary else {}
		rotations[int(round(float(display.get("rotation", 0.0))))] = true
		scales[snappedf(float(display.get("scale", 1.0)), 0.01)] = true
	_assert("scatter_unique_cells", not duplicate)
	_assert("scatter_in_bounds", in_bounds)
	_assert("scatter_follow_terrain", follow_terrain)
	_assert("scatter_variety", rotations.size() > 3 and scales.size() > 1)
	var status := str(editor._status_lbl.text) if editor._status_lbl != null else ""
	_assert("scatter_status", status.find("Décor auto") >= 0)

	# Undo unique du trait complet.
	var after: int = editor.doc.elements_of_kind("mesh").size()
	editor.doc.undo()
	_assert("scatter_undo_single",
		editor.doc.elements_of_kind("mesh").size() == after - ids.size())
	editor.doc.redo()

	# Déterminisme : même graine + même tracé => mêmes cases.
	var cells_after_redo := _scatter_cells(editor, ids)
	editor.doc.undo()
	var ids_again: Array = editor._scatter_stroke_points([Vector2(5, 20), Vector2(15, 20)])
	_assert("scatter_deterministic", _scatter_cells(editor, ids_again) == cells_after_redo)
	editor.doc.undo()

	# Eau : les cases immergées (hauteur < waterLevel) sont évitées.
	var width := int(editor.doc.map_data.get("width", 1))
	var heights: Array = editor.doc.map_data.get("terrainHeights", [])
	for y in range(17, 24):
		for x in range(3, 18):
			heights[y * width + x] = -1.0
	editor.doc.set_meta_values({"waterLevel": 0.0}, "Eau test")
	editor._scatter_seed = 99
	var water_ids: Array = editor._scatter_stroke_points([Vector2(5, 20), Vector2(15, 20)])
	var in_water := false
	for id_variant in water_ids:
		var elem: Dictionary = editor.doc.get_element(str(id_variant))
		var cx := int(round(float(elem.get("x", 0.0))))
		var cy := int(round(float(elem.get("y", 0.0))))
		if float(heights[cy * width + cx]) < -0.001:
			in_water = true
	_assert("scatter_avoids_water", not in_water)
	editor.doc.undo()

	# Mode « remplir la zone ».
	editor._scatter_zone_mode = true
	editor._scatter_seed = 7
	var zone_ids: Array = editor._scatter_stroke_points([Vector2(25, 12)])
	_assert("scatter_zone_created", zone_ids.size() > 0)
	editor._scatter_zone_mode = false
	editor.doc.undo()

	# Geste souris réel (press → move → release) et feedback.
	editor._set_tool("scatter")
	editor._scatter_seed = 123
	var ui_before: int = editor.doc.elements_of_kind("mesh").size()
	var mods := {"shift": false, "ctrl": false, "alt": false}
	editor._on_pointer_pressed(Vector2(25, 20), Vector2(400, 300), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_moved(Vector2(31, 20), Vector2(470, 300), mods)
	editor._on_pointer_released(Vector2(31, 20), Vector2(470, 300), MOUSE_BUTTON_LEFT, mods)
	await process_frame
	_assert("scatter_ui_created", editor.doc.elements_of_kind("mesh").size() > ui_before)
	_assert("scatter_ui_not_active", not editor._scatter_active)
	editor.queue_free()
	await process_frame

## Extrémités monde d'un élément mesh (utilise sizeX + display.rotation).
func _mesh_endpoints(elem: Dictionary) -> Array:
	var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
	var display: Dictionary = elem.get("display", {}) if elem.get("display") is Dictionary else {}
	var rad := deg_to_rad(float(display.get("rotation", 0.0)))
	var axis := Vector2(cos(rad), sin(rad))
	var half := float(elem.get("sizeX", 0.0)) * 0.5
	return [center - axis * half, center + axis * half]

func _scatter_cells(editor: Control, ids: Array) -> Dictionary:
	var cells: Dictionary = {}
	for id_variant in ids:
		var elem: Dictionary = editor.doc.get_element(str(id_variant))
		cells["%d,%d" % [int(round(float(elem.get("x", 0.0)))),
			int(round(float(elem.get("y", 0.0))))]] = true
	return cells

# ===========================================================================

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
