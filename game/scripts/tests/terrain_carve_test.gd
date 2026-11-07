extends SceneTree

## Tests des **creusements volumétriques** (Voie B : trous, grottes, tunnels,
## remblais) — cf. `docs/RAPPORT_TERRAIN_DEFORMABLE.md` :
##   • primitives SDF : normalisation, distances signées, smooth-min ;
##   • champ terre/vide : `sample`, sol visible (`top_surface_at`), normales,
##     picking par marche de rayon ;
##   • clusters (`TerrainCarveChunks`) : fusion d'emprises, empreintes ;
##   • document : `add_carve` / `clear_carves`, undo/redo, transactions,
##     sérialisation JSON-sûre ;
##   • sol (`MapGround3D`) : découpe du heightfield, maillage MC du cluster,
##     fences, `set_terrain_carves`, **aucune régression sans creusement** ;
##   • moteur : `terrain_height_at` creusé (fond de trou, toit de grotte),
##     `refresh_terrain` à chaud.
## Règle d'or : sans `terrainCarves`, tout reste bit-identique.

const GroundScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")
const FieldScript := preload("res://scripts/maps/terrain/terrain_carve_field.gd")
const ChunksScript := preload("res://scripts/maps/terrain/terrain_carve_chunks.gd")

const W := 12
const H := 10
const CELL := 1.0

var DocScript: GDScript
var EngineScript: GDScript
var _failed: bool = false
var _nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DocScript = load("res://scripts/maps/editor/map_edit_document.gd")
	EngineScript = load("res://scripts/maps/complex_map_engine_3d.gd")

	_test_normalize()
	_test_field_primitives()
	_test_field_top_surface()
	_test_field_raycast()
	_test_clusters()
	_test_doc_api()
	_test_doc_serialization()
	await _test_ground_meshes()
	await _test_engine_integration()

	for node in _nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await _wait_frames(3)

	if _failed:
		print("terrain_carve_test:FAIL")
		quit(1)
		return
	print("terrain_carve_test:PASS")
	quit(0)

# ===========================================================================
# Données de test
# ===========================================================================

func _flat_heights(value: float = 0.5) -> Array:
	var heights: Array = []
	heights.resize(W * H)
	heights.fill(value)
	return heights

func _sphere(id: String, center: Vector3, radius: float, op: String = "subtract",
		smooth: float = 0.0) -> Dictionary:
	return {
		"id": id, "op": op, "shape": "sphere",
		"center": [center.x, center.y, center.z],
		"radius": radius, "smooth": smooth,
	}

# ===========================================================================
# 1. Normalisation des primitives
# ===========================================================================

func _test_normalize() -> void:
	var e: Dictionary = FieldScript.normalize_carve({
		"op": "union", "shape": "capsule", "a": [0, 0, 0], "b": [2, 0, 0],
		"radius": -3.0, "smooth": 99.0,
	})
	_assert("norm_op_union", e["op"] == "union")
	_assert("norm_shape_capsule", e["shape"] == "capsule")
	_assert("norm_radius_clamped", float(e["radius"]) >= 0.05)
	_assert("norm_smooth_clamped", float(e["smooth"]) <= 2.0)
	_assert("norm_id_autogen", not str(e.get("id", "")).is_empty())
	var bad: Dictionary = FieldScript.normalize_carve({"shape": "unknown", "op": "nope"})
	_assert("norm_bad_shape_sphere", bad["shape"] == "sphere")
	_assert("norm_bad_op_subtract", bad["op"] == "subtract")
	var json_ok := FieldScript.to_json_carve(FieldScript.normalize_carve(
		{"shape": "sphere", "center": [1, 2, 3], "radius": 1.0}))
	_assert("norm_json_center_array", json_ok["center"] is Array and (json_ok["center"] as Array).size() == 3)
	var parsed = JSON.parse_string(JSON.stringify([json_ok]))
	_assert("norm_json_roundtrip", parsed is Array and (parsed as Array).size() == 1)

# ===========================================================================
# 2. Champ : primitives, signes, smooth
# ===========================================================================

func _test_field_primitives() -> void:
	var heights := _flat_heights(0.5)
	var carve := _sphere("s1", Vector3(4.0, 0.0, 4.0), 1.5, "subtract", 0.0)
	var field = FieldScript.new(heights, W, H, [carve])
	_assert("field_empty_in_carve", field.sample(Vector3(4.0, 0.0, 4.0)) < 0.0)
	_assert("field_solid_below", field.sample(Vector3(4.0, -3.0, 4.0)) > 0.0)
	_assert("field_solid_far", field.sample(Vector3(9.0, 0.0, 9.0)) > 0.0)
	_assert("field_surface_at_edge_of_carve",
		field.sample(Vector3(4.0, 0.5, 4.0)) < 0.0)

	# Union (remblai) : matière ajoutée au-dessus du sol.
	var add := _sphere("a1", Vector3(2.0, 1.5, 2.0), 1.0, "union", 0.0)
	var field2 = FieldScript.new(heights, W, H, [add])
	_assert("field_union_solid_inside", field2.sample(Vector3(2.0, 1.5, 2.0)) > 0.0)
	_assert("field_union_top_raised", field2.top_surface_at(2.0, 2.0) > 2.0,
		"top=%.3f" % field2.top_surface_at(2.0, 2.0))

	# Sans creusement : égalité exacte sol visible = interpolation historique.
	var field3 = FieldScript.new(heights, W, H, [])
	_assert("field_nocarve_top_equal",
		is_equal_approx(field3.top_surface_at(5.25, 4.75), field3.cell_bilinear(5.25, 4.75)))
	_assert("field_nocarve_sample_solid", field3.sample(Vector3(5.0, 0.0, 5.0)) > 0.0)
	_assert("field_nocarve_sample_air", field3.sample(Vector3(5.0, 1.0, 5.0)) < 0.0)

# ===========================================================================
# 3. Sol visible : fond de trou / toit de grotte
# ===========================================================================

func _test_field_top_surface() -> void:
	var heights := _flat_heights(0.5)
	# Trou : sphère centrée sous la surface → le sol visible descend au fond.
	var pit := _sphere("pit", Vector3(4.0, -0.6, 4.0), 1.4, "subtract", 0.0)
	var field = FieldScript.new(heights, W, H, [pit])
	var pit_top: float = field.top_surface_at(4.0, 4.0)
	_assert("pit_floor_lower", pit_top < -1.5, "top=%.3f" % pit_top)
	_assert("pit_floor_near_sphere_bottom", absf(pit_top - (-2.0)) < 0.15,
		"top=%.3f" % pit_top)
	_assert("pit_outside_untouched",
		is_equal_approx(field.top_surface_at(9.0, 9.0), 0.5))

	# Grotte : sphère entièrement sous la surface → le toit reste visible.
	var cave := _sphere("cave", Vector3(8.0, -1.5, 8.0), 0.8, "subtract", 0.0)
	var field2 = FieldScript.new(heights, W, H, [cave])
	_assert("cave_roof_kept", is_equal_approx(field2.top_surface_at(8.0, 8.0), 0.5))
	_assert("cave_inside_empty", field2.sample(Vector3(8.0, -1.5, 8.0)) < 0.0)
	_assert("cave_floor_solid", field2.sample(Vector3(8.0, -2.6, 8.0)) > 0.0)
	# Sol visible depuis le dessus = toit ; le sol de grotte est plus bas.
	_assert("cave_floor_below_roof", field2._scan_top_solid(8.0, 8.0, -0.5) < -2.0,
		"floor=%.3f" % field2._scan_top_solid(8.0, 8.0, -0.5))

	# Sculpture « pas que dans le sol » : une morsure dans le FLANC d'une butte
	# (remblai) doit entamer la butte, même si la colonne reste sous son sommet.
	var mound := _sphere("mound", Vector3(3.0, 1.5, 3.0), 1.5, "union", 0.0)
	var bite := _sphere("bite", Vector3(4.2, 1.6, 3.0), 1.0, "subtract", 0.0)
	var field3 = FieldScript.new(heights, W, H, [mound])
	var field4 = FieldScript.new(heights, W, H, [mound, bite])
	var flank_without := field3.top_surface_at(4.2, 3.0)
	var flank_with := field4.top_surface_at(4.2, 3.0)
	_assert("side_bite_carves_flank", flank_with < flank_without - 1.0,
		"sans=%.3f avec=%.3f" % [flank_without, flank_with])
	_assert("side_bite_keeps_top", field4.top_surface_at(3.0, 3.0) > 2.5,
		"h=%.3f" % field4.top_surface_at(3.0, 3.0))

# ===========================================================================
# 4. Picking par marche de rayon
# ===========================================================================

func _test_field_raycast() -> void:
	var heights := _flat_heights(0.5)
	var pit := _sphere("pit", Vector3(4.0, -0.6, 4.0), 1.4, "subtract", 0.0)
	var field = FieldScript.new(heights, W, H, [pit])
	var hit = field.raycast(Vector3(4.0, 5.0, 4.0), Vector3(0.0, -1.0, 0.0))
	_assert("ray_pit_hit", not hit.is_empty())
	if not hit.is_empty():
		var y: float = (hit["position"] as Vector3).y
		_assert("ray_pit_floor", y < -1.5, "y=%.3f" % y)
		_assert("ray_pit_normal_up", (hit["normal"] as Vector3).y > 0.5)
	var hit2 = field.raycast(Vector3(9.0, 5.0, 9.0), Vector3(0.0, -1.0, 0.0))
	_assert("ray_plain_hit", not hit2.is_empty())
	if not hit2.is_empty():
		_assert("ray_plain_height",
			absf((hit2["position"] as Vector3).y - 0.5) < 0.05,
			"y=%.3f" % (hit2["position"] as Vector3).y)
	# Rayon oblique sur le terrain.
	var hit3 = field.raycast(Vector3(0.0, 6.0, 9.0), Vector3(0.5, -1.0, 0.0).normalized())
	_assert("ray_oblique_hit", not hit3.is_empty())
	# Rayon vers le ciel : pas d'intersection.
	var miss = field.raycast(Vector3(4.0, 5.0, 4.0), Vector3(0.0, 1.0, 0.0))
	_assert("ray_sky_miss", miss.is_empty())

# ===========================================================================
# 5. Clusters
# ===========================================================================

func _test_clusters() -> void:
	var far1 := _sphere("f1", Vector3(1.0, 0.0, 1.0), 1.0)
	var far2 := _sphere("f2", Vector3(9.0, 0.0, 8.0), 1.0)
	var clusters: Array = ChunksScript.compute_clusters([far1, far2])
	_assert("cluster_two_far", clusters.size() == 2)
	var near := _sphere("n1", Vector3(3.0, 0.0, 3.0), 1.2)
	var clusters2: Array = ChunksScript.compute_clusters([far1, near])
	_assert("cluster_merged_close", clusters2.size() == 1,
		"n=%d" % clusters2.size())
	if clusters2.size() == 1:
		var ids: Array = clusters2[0]["ids"]
		_assert("cluster_merged_ids", ids.size() == 2)
		var rect: Rect2i = clusters2[0]["rect"]
		_assert("cluster_rect_cells", rect.size.x >= 4 and rect.size.y >= 4,
			"rect=%s" % str(rect))
		_assert("cluster_footprint", ChunksScript.cluster_footprint(clusters2[0]) == rect)
	# L'emprise couvre la primitive + marge (condition de raccord).
	if clusters.size() == 2:
		for cluster in clusters:
			var rect2: Rect2i = cluster["rect"]
			_assert("cluster_margin",
				rect2.size.x >= 3 and rect2.size.y >= 3,
				"rect=%s" % str(rect2))

# ===========================================================================
# 6. Document : API, undo/redo, transactions
# ===========================================================================

func _test_doc_api() -> void:
	var md = get_root().get_node("MapData")
	var base: Dictionary = md.create_complex_map("Test carves doc", "general", "local", W, H)
	var doc = DocScript.new()
	doc.load_map(base)
	_assert("doc_carves_default", doc.terrain_carves().is_empty())

	var id: String = str(doc.add_carve(_sphere("c1", Vector3(3.0, 0.0, 3.0), 1.0)))
	_assert("doc_carve_added", doc.terrain_carves().size() == 1)
	_assert("doc_carve_id", id == str(doc.terrain_carves()[0].get("id")))
	_assert("doc_carve_json_safe", doc.terrain_carves()[0]["center"] is Array)

	# Undo/redo : une étape par appel.
	_assert("doc_carve_undo", doc.undo() and doc.terrain_carves().is_empty())
	_assert("doc_carve_redo", doc.redo() and doc.terrain_carves().size() == 1)

	# Transaction : deux tampons = une seule étape d'undo.
	doc.begin_transaction()
	doc.add_carve(_sphere("c2", Vector3(6.0, 0.0, 3.0), 1.0))
	doc.add_carve(_sphere("c3", Vector3(8.0, 0.0, 3.0), 1.0))
	doc.commit_transaction()
	_assert("doc_carve_batch", doc.terrain_carves().size() == 3)
	_assert("doc_carve_batch_undo", doc.undo() and doc.terrain_carves().size() == 1,
		"n=%d" % doc.terrain_carves().size())
	_assert("doc_carve_batch_redo", doc.redo() and doc.terrain_carves().size() == 3)

	doc.clear_carves()
	_assert("doc_carve_clear", doc.terrain_carves().is_empty())
	_assert("doc_carve_clear_undo", doc.undo() and doc.terrain_carves().size() == 3)
	_assert("doc_carve_clear_redo", doc.redo() and doc.terrain_carves().is_empty())

# ===========================================================================
# 7. Sérialisation
# ===========================================================================

func _test_doc_serialization() -> void:
	var md = get_root().get_node("MapData")
	var base: Dictionary = md.create_complex_map("Test carves ser", "general", "local", W, H)
	var doc = DocScript.new()
	doc.load_map(base)
	doc.add_carve(_sphere("ser1", Vector3(3.0, -0.5, 3.0), 1.2, "subtract", 0.3))
	doc.add_carve(_sphere("ser2", Vector3(6.0, 1.0, 6.0), 0.8, "union", 0.0))
	var out: Dictionary = doc.to_map_data()
	_assert("ser_array", out.get("terrainCarves") is Array)
	_assert("ser_count", (out["terrainCarves"] as Array).size() == 2)
	# JSON-sûr : centres en tableaux, aller-retour JSON sans perte.
	var json_text := JSON.stringify(out["terrainCarves"])
	var parsed = JSON.parse_string(json_text)
	_assert("ser_json_roundtrip", parsed is Array and (parsed as Array).size() == 2)
	var doc2 = DocScript.new()
	doc2.load_map(out)
	_assert("ser_reload_count", doc2.terrain_carves().size() == 2)
	_assert("ser_reload_op", doc2.terrain_carves()[1]["op"] == "union")
	_assert("ser_reload_id", doc2.terrain_carves()[0]["id"] == "ser1")

# ===========================================================================
# 8. Sol 3D : découpe heightfield + clusters MC + fences
# ===========================================================================

func _make_ground(heights: Array, carves: Array):
	var ground = GroundScript.new()
	get_root().add_child(ground)
	_nodes.append(ground)
	ground.configure(null, W, H, CELL, true, null, false, [], [], 0.22,
		heights, "terrain3d", [], 1, carves)
	return ground

func _ground_index_count(ground) -> int:
	var mesh = ground._mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arrays = mesh.surface_get_arrays(0)
	var indices = arrays[Mesh.ARRAY_INDEX]
	return indices.size() if indices != null else 0

func _carve_mesh_instance(ground) -> MeshInstance3D:
	for child in ground.get_children():
		if child is MeshInstance3D and child.name == "CarveCluster":
			return child
	return null

func _test_ground_meshes() -> void:
	var heights := _flat_heights(0.0)
	var ground_plain = _make_ground(heights, [])
	var plain_indices := _ground_index_count(ground_plain)
	_assert("ground_plain_clusters", ground_plain.get_carve_cluster_count() == 0)
	_assert("ground_plain_indices", plain_indices == W * H * 6,
		"n=%d" % plain_indices)
	_assert("ground_plain_not_carve", not ground_plain.is_carve_active())

	var carve := _sphere("g1", Vector3(5.0, -0.5, 4.0), 1.6, "subtract", 0.3)
	var ground = _make_ground(heights, [carve])
	_assert("ground_carve_active", ground.is_carve_active())
	_assert("ground_carve_cluster_count", ground.get_carve_cluster_count() == 1)
	var carved_indices := _ground_index_count(ground)
	_assert("ground_carve_cut", carved_indices < plain_indices,
		"carved=%d plain=%d" % [carved_indices, plain_indices])
	# L'emprise découpée = l'empreinte du cluster (primitive + marge de raccord),
	# mesurée via l'API publique de clusters.
	var clusters: Array = ChunksScript.compute_clusters([carve])
	var cut_cells: int = clusters[0]["rect"].size.x * clusters[0]["rect"].size.y
	_assert("ground_carve_cut_cells", carved_indices == (W * H - cut_cells) * 6,
		"n=%d attendu=%d (cellules=%d)" % [carved_indices, (W * H - cut_cells) * 6, cut_cells])

	var carve_node := _carve_mesh_instance(ground)
	_assert("ground_carve_mesh_exists", carve_node != null)
	if carve_node != null:
		var mesh: ArrayMesh = carve_node.mesh
		_assert("ground_carve_mesh_surface", mesh != null and mesh.get_surface_count() == 1)
		if mesh != null and mesh.get_surface_count() == 1:
			var arrays = mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			_assert("ground_carve_mesh_verts", verts.size() > 24, "n=%d" % verts.size())
			_assert("ground_carve_mesh_colors", colors.size() == verts.size())
			_assert("ground_carve_mesh_uvs", uvs.size() == verts.size())
			_assert("ground_carve_mesh_uv2s", uv2s.size() == verts.size())
			var min_y := INF
			var max_y := -INF
			for v in verts:
				min_y = minf(min_y, v.y)
				max_y = maxf(max_y, v.y)
			_assert("ground_carve_mesh_goes_down", min_y < -0.5, "min_y=%.3f" % min_y)
			_assert("ground_carve_mesh_surface_top", max_y > -0.05, "max_y=%.3f" % max_y)
		_assert("ground_carve_mesh_material",
			carve_node.material_override == ground._mesh_instance.material_override)
		_assert("ground_carve_mesh_no_shadow",
			carve_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	# Retrait des creusements : retour strict à l'état initial.
	ground.set_terrain_carves([])
	_assert("ground_carve_removed", ground.get_carve_cluster_count() == 0)
	_assert("ground_carve_removed_indices", _ground_index_count(ground) == plain_indices)

	# Ajout à chaud sur un sol déjà configuré.
	ground.set_terrain_carves([carve])
	_assert("ground_carve_readded", ground.get_carve_cluster_count() == 1)
	_assert("ground_carve_readded_cut", _ground_index_count(ground) < plain_indices)

# ===========================================================================
# 9. Moteur : sol visible creusé + refresh à chaud
# ===========================================================================

func _test_engine_integration() -> void:
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test carves moteur", "general", "local", W, H)
	map["terrainHeights"] = _flat_heights(0.4)
	map["terrainCarves"] = [_sphere("e1", Vector3(5.0, -0.5, 4.0), 1.4, "subtract", 0.0)]
	var engine: Control = EngineScript.new()
	engine.size = Vector2(800, 600)
	get_root().add_child(engine)
	_nodes.append(engine)
	await _wait_frames(3)
	engine.configure(map, [], [], [], [], [], false, true)
	await _wait_frames(6)

	# Cas sans creusement dans la zone : valeur historique conservée.
	_assert("engine_top_plain", is_equal_approx(engine.terrain_height_at(9.0, 8.0), 0.4),
		"h=%.3f" % engine.terrain_height_at(9.0, 8.0))
	# Fond de trou : le sol visible descend sous le niveau initial.
	var pit_h: float = engine.terrain_height_at(5.0, 4.0)
	_assert("engine_pit_floor", pit_h < -1.4, "h=%.3f" % pit_h)
	# Normale au fond du trou, orientée vers le haut.
	var n: Vector3 = engine.terrain_normal_at(5.0, 4.0)
	_assert("engine_pit_normal", n.y > 0.3, "n=%s" % str(n))
	_assert("engine_carve_cluster", engine._ground.get_carve_cluster_count() == 1)

	# Retrait à chaud via refresh_terrain : retour au comportement historique.
	map["terrainCarves"] = []
	engine.refresh_terrain(map)
	await _wait_frames(2)
	_assert("engine_refresh_plain", is_equal_approx(engine.terrain_height_at(5.0, 4.0), 0.4),
		"h=%.3f" % engine.terrain_height_at(5.0, 4.0))
	_assert("engine_refresh_cluster", engine._ground.get_carve_cluster_count() == 0)

# ===========================================================================
# Utilitaires
# ===========================================================================

func _wait_frames(n: int = 2) -> void:
	for _i in range(n):
		await process_frame

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [name, detail])
