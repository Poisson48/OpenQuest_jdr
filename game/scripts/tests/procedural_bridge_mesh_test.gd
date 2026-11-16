extends SceneTree

## Tests du pont procédural : construction de base et cas dégénérés.

const BridgeScript = preload("res://scripts/maps/construction/procedural_bridge_mesh.gd")

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_basic_build()
	_test_zero_length()
	await _test_crossing_in_editor()

	if _failed:
		quit(1)
		return
	print("procedural_bridge_mesh_test:PASS")
	quit(0)

# ===========================================================================

## Pont de 10 unités, montant de y=1 à y=2 : le mesh doit être non vide,
## avec au moins une surface et des sommets.
func _test_basic_build() -> void:
	var mesh: ArrayMesh = BridgeScript.build({
		"start": Vector3(0, 1, 0),
		"end": Vector3(10, 2, 0),
		"width": 2.0,
		"seed": 7,
		"ground_y": 0.0,
	})
	_assert("bridge_mesh_non_null", mesh != null)
	if mesh == null:
		return
	_assert("bridge_surface_count", mesh.get_surface_count() >= 1)
	if mesh.get_surface_count() < 1:
		return
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_assert("bridge_vertex_count", vertices.size() > 0)

## start == end : longueur nulle -> ArrayMesh vide, sans crash.
func _test_zero_length() -> void:
	var mesh: ArrayMesh = BridgeScript.build({
		"start": Vector3(3, 1, 3),
		"end": Vector3(3, 1, 3),
		"width": 2.0,
		"seed": 7,
		"ground_y": 0.0,
	})
	_assert("bridge_zero_length_non_null", mesh != null)
	if mesh == null:
		return
	_assert("bridge_zero_length_empty", mesh.get_surface_count() == 0)

func _test_crossing_in_editor() -> void:
	var md = root.get_node("MapData")
	var map: Dictionary = md.create_complex_map("Traversée", "general", "local", 14, 9)
	var heights: Array = []
	for y in range(9):
		for x in range(14):
			heights.append(0.4 if x < 5 else (0.8 if x > 8 else -1.0))
	map["terrainHeights"] = heights
	var editor = load("res://scenes/map_editor/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.load_map(map)
	editor.set_editable(true)
	await process_frame
	editor._create_bridge(Vector2(2, 4), Vector2(11, 4))
	var id: String = editor.doc.selection()[0]
	var engine = editor._engine
	var layer = engine._meshes_layer
	var cs: float = engine.get_cell_size()
	var center := Vector2(7.0, 4.5) * cs
	var deck: float = layer.bridge_height_at(center.x, center.y)
	_assert("crossing_deck_interpolates_between_banks", absf(deck - 0.645 * cs) < 0.001)
	_assert("crossing_outside_uses_terrain", layer.bridge_height_at(center.x, center.y + cs * 2.0) == -INF)
	var hit: Vector3 = layer.raycast_bridges(Vector3(center.x - cs, 4.0, center.y),
		Vector3(cs, deck - 4.0, 0.0).normalized())
	_assert("crossing_ray_hits_deck", hit.is_equal_approx(Vector3(center.x, deck, center.y)))

	var token = engine._create_token_node({"id": "pont-test", "kind": "npc", "x": 6.5, "y": 4.0}, 14, 9)
	engine._tokens_layer.add_child(token)
	_assert("crossing_figurine_sits_on_deck", is_equal_approx(token.position.y, deck))
	token.move_to_grid(6.5, 6.0, false)
	_assert("crossing_figurine_returns_to_ground", absf(token.position.y + cs) < 0.001)

	editor._handle_state = {"id": id, "kind": "bridge_end"}
	editor._edit_ops._apply_bridge_endpoint_drag(Vector2(10, 4))
	var ends: PackedVector3Array = layer.bridge_endpoints(id)
	_assert("crossing_handle_updates_mesh_live", absf(ends[1].x / cs - 10.5) < 0.001)
	editor.doc.commit_live_edit([id], "Pont")
	_assert("crossing_handle_undo", editor.doc.undo()
		and absf(layer.bridge_endpoints(id)[1].x / cs - 11.5) < 0.001)
	editor.doc.move_elements_by([id], 0.0, 1.0)
	var moved: Dictionary = editor.doc.get_element(id)
	_assert("crossing_translation_moves_both_endpoints", moved["start"]["y"] == 5.0 and moved["end"]["y"] == 5.0)
	var placed := {
		"id": "pont-catalogue", "asset": BridgeScript.CATALOG_ASSET, "x": 6.5, "y": 2.0,
		"sizeX": 9.0, "sizeZ": 1.6, "display": {"scale": 2.0},
	}
	editor.doc.add_element(placed, "mesh", "Pont catalogue")
	var fixed: PackedVector3Array = layer.bridge_endpoints("pont-catalogue")
	_assert("crossing_catalog_asset_provides_a_deck", fixed.size() == 2)
	if fixed.size() == 2:
		_assert("crossing_explicit_dimensions_override_scale", absf((fixed[1].x - fixed[0].x) / cs - 9.0) < 0.001)
	editor.queue_free()
	await process_frame

func _assert(test_name: String, ok: bool) -> void:
	if ok:
		return
	_failed = true
	print("FAIL " + test_name)
