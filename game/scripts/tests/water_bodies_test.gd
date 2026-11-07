extends SceneTree

## Bassins d'eau : lacs/marais qui remplissent les **creux** (pas la hauteur),
## rivières tracées avec cascade sur les dénivelés, undo/sérialisation.

const WaterScript := preload("res://scripts/maps/map_layers/map_water_3d.gd")

var DocScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DocScript = load("res://scripts/maps/editor/map_edit_document.gd")
	await _test_lake_fills_basin()
	await _test_river_with_falls()
	_test_doc_water_bodies()
	_test_legacy_plan_unchanged()
	if _failed:
		print("water_bodies_test:FAIL")
		quit(1)
		return
	print("water_bodies_test:PASS")
	quit(0)

## Terrain 20×14 à 1.0 avec une **cuvette** (cells 8..12 × 6..9) plus profonde
## au centre — comme un vrai bassin creusé.
func _heights_with_basin() -> Array:
	var heights: Array = []
	heights.resize(20 * 14)
	heights.fill(1.0)
	for y in range(6, 10):
		for x in range(8, 13):
			var d := absf(float(x) - 10.0) * 0.12 + absf(float(y) - 7.5) * 0.12
			heights[y * 20 + x] = 0.2 + d
	return heights

func _test_lake_fills_basin() -> void:
	var water = WaterScript.new()
	get_root().add_child(water)
	var lake := {
		"id": "lac_test", "kind": "lake", "level": 0.6,
		"area": [[7, 5], [13, 5], [13, 10], [7, 10]],
	}
	water.configure(20, 14, 1.0, -1.0, _heights_with_basin(), false, 1, 1.0, [], {}, [lake])
	await process_frame
	_assert("lake_active", water.is_active())
	_assert("lake_body_count", water.get_body_count() == 1, "n=%d" % water.get_body_count())
	_assert("lake_submerged", water.get_submerged_cell_count() > 10,
		"n=%d" % water.get_submerged_cell_count())
	# Le masque : eau dans le creux, à sec sur la hauteur (le lac remplit le
	# creux, il ne déborde pas sur le terrain au-dessus de son niveau).
	var img: Image = water.get_depth_image()
	_assert("lake_mask_in_basin", img != null and img.get_pixel(10, 7).g > 0.9)
	_assert("lake_mask_on_high", img != null and img.get_pixel(2, 2).g < 0.1)
	_assert("lake_depth_deeper", img.get_pixel(10, 7).r > img.get_pixel(8, 6).r)
	water.queue_free()
	await process_frame

func _test_river_with_falls() -> void:
	# Relief à une VRAIE falaise (plateau 4.0 → plaine 0.0, une seule case) :
	# la rivière drape le terrain et le ressaut devient une cascade.
	var heights: Array = []
	heights.resize(20 * 14)
	for y in range(14):
		for x in range(20):
			heights[y * 20 + x] = 4.0 if y < 3 else 0.0
	var river := {
		"id": "riv_test", "kind": "river", "width": 1.2, "flow_speed": 0.4,
		"path": [[8, 4.0, 1], [8, 4.0, 2], [8, 0.0, 4], [8, 0.0, 6]],
	}
	var water = WaterScript.new()
	get_root().add_child(water)
	water.configure(20, 14, 1.0, -1.0, heights, false, 1, 1.0, [], {}, [river])
	await process_frame
	_assert("river_active", water.is_active())
	_assert("river_body_count", water.get_body_count() == 1, "n=%d" % water.get_body_count())
	# Le maillage porte une surface dédiée aux cascades (plans verticaux) avec
	# le shader de chute ; la surface 0 reste l'eau courante.
	var node: MeshInstance3D = water._body_nodes[0]
	var mesh: ArrayMesh = node.mesh
	_assert("river_two_surfaces", mesh.get_surface_count() == 2,
		"surfaces=%d" % mesh.get_surface_count())
	var arrays := mesh.surface_get_arrays(1)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var has_fall := false
	for n in normals:
		if absf(n.y) < 0.5:
			has_fall = true
			break
	_assert("river_has_fall", has_fall)
	_assert("river_fall_material", mesh.surface_get_material(1) is ShaderMaterial)
	# Sens d'écoulement posé sur le matériau de SURFACE 0 (les matériaux de
	# rivière vivent sur les surfaces, pas en `material_override`).
	var mat: ShaderMaterial = mesh.surface_get_material(0)
	var flow = mat.get_shader_parameter("flow_dir")
	_assert("river_flow_dir", flow is Vector2 and absf((flow as Vector2).y - 1.0) < 0.01,
		"flow=%s" % str(flow))
	_assert("river_flow_speed", absf(float(mat.get_shader_parameter("flow_speed")) - 0.4) < 0.01)
	# Le ruban drape le relief : il descend la pente en continu (ses sommets
	# interpolent le talus, ni collés au plateau ni à la plaine), sans jamais
	# sortir de la plage de hauteur du terrain.
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var draped := true
	var mid_slope := false
	for v in verts:
		if v.y < 0.04 or v.y > 4.3:
			draped = false
		if v.z > 2.0 and v.z < 3.0 and v.y > 0.3 and v.y < 2.1:
			mid_slope = true
	_assert("river_drapes_terrain", draped and mid_slope)
	water.queue_free()
	await process_frame

func _test_doc_water_bodies() -> void:
	var md = get_root().get_node("MapData")
	var base: Dictionary = md.create_complex_map("Test eau", "general", "local", 20, 14)
	var doc = DocScript.new()
	doc.load_map(base)
	var id: String = doc.add_water_body({
		"kind": "lake", "level": 0.5,
		"area": [[2, 2], [8, 2], [8, 8], [2, 8]],
	})
	_assert("doc_body_added", doc.water_bodies().size() == 1)
	_assert("doc_body_id", not id.is_empty())
	doc.update_water_body(id, {"level": 0.9})
	_assert("doc_body_updated", is_equal_approx(float(doc.water_bodies()[0].get("level")), 0.9))
	_assert("doc_body_undo", doc.undo() and is_equal_approx(float(doc.water_bodies()[0].get("level")), 0.5))
	_assert("doc_body_undo2", doc.undo() and doc.water_bodies().is_empty())
	_assert("doc_body_redo", doc.redo() and doc.water_bodies().size() == 1)
	# Sérialisation aller-retour.
	var out: Dictionary = doc.to_map_data()
	_assert("doc_body_json", JSON.parse_string(JSON.stringify(out.get("waterBodies", []))) is Array)
	var doc2 = DocScript.new()
	doc2.load_map(out)
	_assert("doc_body_reload", doc2.water_bodies().size() == 1)
	doc2.remove_water_body(str(doc2.water_bodies()[0].get("id")))
	_assert("doc_body_removed", doc2.water_bodies().is_empty())
	_assert("doc_body_remove_undo", doc2.undo() and doc2.water_bodies().size() == 1)

## Sans bassin, le plan historique (waterLevel) est strictement inchangé.
func _test_legacy_plan_unchanged() -> void:
	var heights := _heights_with_basin()
	var water = WaterScript.new()
	get_root().add_child(water)
	water.configure(20, 14, 1.0, 0.6, heights, false, 1, 1.0, [], {}, [])
	await process_frame
	_assert("legacy_active", water.is_active())
	_assert("legacy_no_bodies", water.get_body_count() == 0)
	_assert("legacy_submerged", water.get_submerged_cell_count() > 10,
		"n=%d" % water.get_submerged_cell_count())
	water.queue_free()
	await process_frame

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [name, detail])
