extends SceneTree

## Tests du type d'élément « mesh » (objet 3D de la carte 2.5D) :
## schéma de carte, document (aller-retour de sérialisation), catalogue d'outils,
## bibliothèque d'objets 3D et pose depuis l'éditeur réel.
##
## Ne dépend d'aucun asset GLB livré : les chemins sont testés comme données.

const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

const K_MESH := "mesh"
const FAKE_ASSET := "res://assets/objects3d/buildings/maison_test.glb"

var DocScript: GDScript
var AssetLibraryScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DocScript = load("res://scripts/maps/editor/map_edit_document.gd")
	AssetLibraryScript = load("res://scripts/maps/map_asset_library.gd")
	var md = get_root().get_node("MapData")
	var base: Dictionary = md.create_complex_map("Test mesh 3D", "general", "local", 20, 14)

	_test_schema(base)
	_test_tools()
	_test_document(base)
	_test_asset_library()
	await _test_engine_mesh(base)
	await _test_dimensions(base)
	await _test_editor_ui(base)

	if _failed:
		print("map_mesh_test:FAIL")
		quit(1)
		return
	print("map_mesh_test:PASS")
	quit(0)

# ===========================================================================

func _test_schema(base: Dictionary) -> void:
	_assert("schema_version", int(base.get("schemaVersion", 0)) >= 5)
	_assert("schema_meshes_array", base.get("meshes") is Array and (base["meshes"] as Array).is_empty())

func _test_tools() -> void:
	var def := ToolsScript.get_def(ToolsScript.MESH)
	_assert("tool_mesh_exists", not def.is_empty() and str(def.get("id", "")) == ToolsScript.MESH)
	_assert("tool_mesh_label", ToolsScript.label(ToolsScript.MESH) == "Objet 3D")
	_assert("tool_mesh_shortcut", ToolsScript.tool_for_shortcut("O") == ToolsScript.MESH)
	_assert("tool_mesh_pose", ToolsScript.is_pose_tool(ToolsScript.MESH))
	_assert("tool_mesh_icon", not ToolsScript.icon(ToolsScript.MESH).is_empty())

func _test_document(base: Dictionary) -> void:
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	_assert("doc_schema_meshes", doc.map_data.get("meshes") is Array)
	_assert("doc_default_layer_mesh", DocScript.default_layer_for_kind(K_MESH) == 1)

	var id: String = doc.add_element({
		"x": 4.0, "y": 6.0,
		"asset": FAKE_ASSET,
		"elevation": 0.5,
		"display": {"rotation": 90.0, "scale": 2.5},
	}, K_MESH, "Objet 3D")
	_assert("doc_add_mesh", doc.count_of_kind(K_MESH) == 1)
	var elem: Dictionary = doc.get_element(id)
	_assert("doc_mesh_kind", str(elem.get("kind", "")) == K_MESH)
	_assert("doc_mesh_layer_default", int(elem.get("layer", -1)) == 1)
	_assert("doc_mesh_asset", str(elem.get("asset", "")) == FAKE_ASSET)
	_assert("doc_mesh_label", str(elem.get("label", "")).begins_with("Maison"))
	var display: Dictionary = elem.get("display", {})
	_assert("doc_mesh_rotation", is_equal_approx(float(display.get("rotation", 0.0)), 90.0))
	_assert("doc_mesh_scale", is_equal_approx(float(display.get("scale", 0.0)), 2.5))

	# Les mutations de display doivent fusionner, pas écraser rotation/échelle.
	doc.select_only(id)
	doc.modify_selection({"display": {"scale": 3.0}}, "Échelle")
	var after: Dictionary = doc.get_element(id)
	var after_display: Dictionary = after.get("display", {})
	_assert("doc_mesh_scale_modified", is_equal_approx(float(after_display.get("scale", 0.0)), 3.0))
	_assert("doc_mesh_rotation_kept", is_equal_approx(float(after_display.get("rotation", 0.0)), 90.0))

	# Sérialisation → `meshes` dans map_data, puis rechargement.
	var snapshot: Dictionary = doc.to_map_data()
	_assert("ser_meshes_array", snapshot.get("meshes") is Array)
	var meshes: Array = snapshot.get("meshes", [])
	_assert("ser_meshes_count", meshes.size() == 1)
	if not meshes.is_empty():
		var saved: Dictionary = meshes[0]
		_assert("ser_asset", str(saved.get("asset", "")) == FAKE_ASSET)
		_assert("ser_kind", str(saved.get("kind", "")) == K_MESH)
		_assert("ser_elevation", is_equal_approx(float(saved.get("elevation", 0.0)), 0.5))

	var doc2: Variant = DocScript.new()
	doc2.load_map(snapshot)
	_assert("reload_mesh_count", doc2.count_of_kind(K_MESH) == 1)
	var loaded_id: String = str(doc2.elements_of_kind(K_MESH)[0].get("id", ""))
	var loaded: Dictionary = doc2.get_element(loaded_id)
	_assert("reload_asset", str(loaded.get("asset", "")) == FAKE_ASSET)
	var loaded_display: Dictionary = loaded.get("display", {})
	_assert("reload_scale", is_equal_approx(float(loaded_display.get("scale", 0.0)), 3.0))

	# Suppression + undo : le mesh doit revenir.
	doc2.select_only(loaded_id)
	doc2.remove_element(loaded_id)
	_assert("remove_mesh", doc2.count_of_kind(K_MESH) == 0)
	doc2.undo()
	_assert("undo_mesh", doc2.count_of_kind(K_MESH) == 1)

func _test_asset_library() -> void:
	var assets: Array = AssetLibraryScript.list_object3d_assets()
	_assert("lib_list_is_array", assets is Array)
	_assert("lib_thumb_path", AssetLibraryScript.object3d_thumb_path(FAKE_ASSET).ends_with("maison_test_thumb.png"))
	for entry_variant in assets:
		var entry: Dictionary = entry_variant
		var path := str(entry.get("path", ""))
		_assert("lib_entry_is_glb", path.get_extension().to_lower() in ["glb", "gltf"])
		_assert("lib_entry_name", not str(entry.get("name", "")).is_empty())
	var missing: Dictionary = AssetLibraryScript.get_object3d_asset("res://nope.glb")
	_assert("lib_missing_empty", missing.is_empty())

func _test_engine_mesh(base: Dictionary) -> void:
	# E2E avec un vrai GLB livré (nécessite un import : godot --headless --path game --import).
	var real_asset := ""
	for asset_variant in AssetLibraryScript.list_object3d_assets():
		var path := str((asset_variant as Dictionary).get("path", ""))
		if ResourceLoader.exists(path):
			real_asset = path
			break
	if real_asset.is_empty():
		print("  ..   aucun GLB importé : e2e moteur sauté")
		return
	_assert("e2e_asset_found", true)
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	var mesh_id: String = doc.add_element({
		"x": 3.0, "y": 5.0,
		"asset": real_asset,
		"display": {"scale": 1.2},
	}, K_MESH, "Objet 3D")
	var snapshot: Dictionary = doc.to_map_data()
	var EngineScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var engine: Control = EngineScript.new()
	get_root().add_child(engine)
	await process_frame
	engine.configure(snapshot, [], [], [], [], [], false, true, {}, {}, "")
	await process_frame
	await process_frame
	_assert("e2e_engine_built", engine._meshes_layer != null)
	_assert("e2e_mesh_rendered", engine._meshes_layer.get_child_count() == 1)
	if engine._meshes_layer.get_child_count() == 1:
		var mesh_root: Node3D = engine._meshes_layer.get_child(0)
		_assert("e2e_real_asset", not bool(mesh_root.get_meta("fallback", true)))
		var cell: float = float(engine._cell_size)
		_assert("e2e_position_x", is_equal_approx(mesh_root.position.x, 3.0 * cell + cell * 0.5))
		_assert("e2e_position_z", is_equal_approx(mesh_root.position.z, 5.0 * cell + cell * 0.5))
		_assert("e2e_scale", is_equal_approx(mesh_root.scale.x, cell * 1.2))
		_assert("e2e_has_node", engine.has_element_node(mesh_id))
		# Drag live : le moteur doit déplacer le mesh sans reconstruire la scène.
		engine.set_element_position(mesh_id, 7.0, 8.0)
		_assert("e2e_drag_live", is_equal_approx(mesh_root.position.x, 7.0 * cell + cell * 0.5))
	engine.queue_free()
	await process_frame

func _test_dimensions(base: Dictionary) -> void:
	# Dimensions explicites (cases) + rotation, avec le volume de substitution
	# (AABB naturelle 0.9 × 1.0 × 0.9) pour des valeurs vérifiables.
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	doc.add_element({
		"x": 2.0, "y": 2.0,
		"w": 1.8, "h": 0.45,
		"sizeX": 1.8, "sizeY": 2.0, "sizeZ": 0.45,
		"asset": "res://assets/objects3d/absent_test.glb",
		"display": {"rotation": 90.0},
	}, K_MESH, "Dimensions")
	var snapshot: Dictionary = doc.to_map_data()
	var EngineScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var engine: Control = EngineScript.new()
	get_root().add_child(engine)
	await process_frame
	engine.configure(snapshot, [], [], [], [], [], false, true, {}, {}, "")
	await process_frame
	await process_frame
	var layer = engine._meshes_layer
	_assert("dim_layer", layer != null and layer.get_child_count() == 1)
	if layer != null and layer.get_child_count() == 1:
		var root: Node3D = layer.get_child(0)
		var cell: float = float(engine._cell_size)
		_assert("dim_fallback", bool(root.get_meta("fallback", false)))
		_assert("dim_scale_x", is_equal_approx(root.scale.x, cell * 1.8 / 0.9))
		_assert("dim_scale_y", is_equal_approx(root.scale.y, cell * 2.0 / 1.0))
		_assert("dim_scale_z", is_equal_approx(root.scale.z, cell * 0.45 / 0.9))
		_assert("dim_rotation", is_equal_approx(root.rotation_degrees.y, -90.0))
	engine.queue_free()
	await process_frame

func _test_editor_ui(base: Dictionary) -> void:
	var editor: Control = load("res://scenes/map_editor/map_editor.tscn").instantiate()
	get_root().add_child(editor)
	editor.size = Vector2(1280, 800)
	await process_frame
	editor.load_map(base)
	await process_frame
	_assert("ui_loaded", not editor.doc.map_data.is_empty())

	# Pose d'un objet 3D via le chemin réel de l'éditeur.
	editor._mesh_asset = FAKE_ASSET
	editor._mesh_scale = 1.5
	editor._mesh_rotation = 90.0
	editor._create_mesh(Vector2(5.0, 7.0))
	_assert("ui_mesh_added", editor.doc.count_of_kind(K_MESH) == 1)
	var placed: Dictionary = editor.doc.elements_of_kind(K_MESH)[0]
	_assert("ui_mesh_asset", str(placed.get("asset", "")) == FAKE_ASSET)
	var placed_display: Dictionary = placed.get("display", {})
	_assert("ui_mesh_scale", is_equal_approx(float(placed_display.get("scale", 0.0)), 1.5))
	_assert("ui_mesh_rotation", is_equal_approx(float(placed_display.get("rotation", 0.0)), 90.0))
	_assert("ui_mesh_size_fields", float(placed.get("sizeX", 0.0)) > 0.0
		and float(placed.get("sizeY", 0.0)) > 0.0 and float(placed.get("sizeZ", 0.0)) > 0.0)
	_assert("ui_mesh_selected", editor.doc.selection().size() == 1)
	# L'outil doit rester sélectionnable par la palette.
	_assert("ui_mesh_tool", ToolsScript.label(ToolsScript.MESH) == "Objet 3D")

	editor.queue_free()
	await process_frame

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
