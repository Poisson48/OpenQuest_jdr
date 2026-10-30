extends SceneTree

## Tests du calque des objets 3D génériques (`kind = "mesh"`) de la carte 2.5D :
## chargement/fallback, position sur la grille, rotation, échelle, déplacement,
## et branchement dans le moteur 3D.
##
## Autonome : la classe du calque est chargée par chemin, sans autoload. Seul le
## smoke d'intégration instancie le moteur (qui dépend de l'autoload MapData).

const Meshes3DScript := preload("res://scripts/maps/map_layers/map_meshes_3d.gd")

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_test_empty_layer()
	_test_fallback_placement()
	_test_contact_shadow()
	_test_atmosphere_tint()
	_test_rotation_scale_elevation()
	_test_hidden_and_invalid()
	_test_move_and_registry()
	_test_reconfigure()
	await _test_engine_integration()
	if _failed:
		quit(1)
		return
	print("map_meshes_3d_test:PASS")
	quit(0)

# ===========================================================================

func _make_layer() -> Node3D:
	var layer: Node3D = Meshes3DScript.new()
	get_root().add_child(layer)
	return layer

func _wait_frames(n: int = 4) -> void:
	for _i in range(n):
		await process_frame

func _test_empty_layer() -> void:
	var layer := _make_layer()
	layer.configure([], 1.0)
	_assert("empty_no_children", layer.get_child_count() == 0)
	_assert("empty_registry", layer._nodes.is_empty())
	_assert("empty_has_mesh_false", not layer.has_mesh("inconnu"))
	# map_data vide + cell_size fourni : ne doit pas planter.
	layer.configure([], 0.7, {})
	_assert("empty_with_map_data", layer.get_child_count() == 0)
	# cell_size invalide : garde-fou (> 0), pas de division zéro.
	layer.configure([], 0.0, {"width": 20, "height": 20})
	_assert("cell_size_guarded", layer._cell_size > 0.0)
	layer.queue_free()

func _test_fallback_placement() -> void:
	var layer := _make_layer()
	layer.configure([
		{
			"id": "m1", "kind": "mesh",
			"asset": "res://assets/objects3d/objects/nexiste_pas.glb",
			"x": 2.0, "y": 3.0, "elevation": 1.0,
			"display": {"rotation": 0.0, "scale": 1.0},
		},
	], 0.7)
	var cell := 0.7
	_assert("fallback_child_count", layer.get_child_count() == 1)
	_assert("fallback_has_mesh", layer.has_mesh("m1"))
	_assert("fallback_flag", layer.is_fallback("m1"))
	var root: Node3D = layer._nodes.get("m1")
	_assert("fallback_root_node", root != null)
	if root != null:
		_assert("fallback_pos_x", is_equal_approx(root.position.x, 2.0 * cell + cell * 0.5))
		_assert("fallback_pos_elevation", is_equal_approx(root.position.y, 1.0 * cell))
		_assert("fallback_pos_z", is_equal_approx(root.position.z, 3.0 * cell + cell * 0.5))
		_assert("fallback_uniform_scale", is_equal_approx(root.scale.x, cell)
			and is_equal_approx(root.scale.y, cell) and is_equal_approx(root.scale.z, cell))
		# Deux enfants : le volume (fallback) + l'ombre de contact peinte.
		_assert("fallback_root_children", root.get_child_count() == 2)
		var visual := _find_child_with_meta(root, "fallback") as MeshInstance3D
		_assert("fallback_mesh_instance", visual != null)
		if visual != null:
			_assert("fallback_meta", bool(visual.get_meta("fallback", false)))
			_assert("fallback_box_mesh", visual.mesh is BoxMesh)
			if visual.mesh is BoxMesh:
				var box := visual.mesh as BoxMesh
				_assert("fallback_box_grounded", is_equal_approx(visual.position.y, box.size.y * 0.5))
				_assert("fallback_box_footprint", box.size.x <= 1.0 and box.size.z <= 1.0)
			_assert("fallback_no_shadow",
				visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var mat := visual.material_override as StandardMaterial3D
			_assert("fallback_material", mat != null)
			if mat != null:
				_assert("fallback_unshaded",
					mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	# Asset vide : fallback aussi (pas d'erreur de chargement).
	var empty_layer := _make_layer()
	empty_layer.configure([{"id": "m-vide", "asset": ""}], 1.0)
	_assert("fallback_empty_asset", empty_layer.has_mesh("m-vide") and empty_layer.is_fallback("m-vide"))
	empty_layer.queue_free()
	layer.queue_free()

func _test_contact_shadow() -> void:
	var layer := _make_layer()
	layer.configure([
		{
			"id": "m-shadow", "kind": "mesh", "asset": "",
			"x": 2.0, "y": 2.0, "elevation": 1.0,
			"display": {"scale": 1.5},
		},
	], 0.7)
	var root: Node3D = layer._nodes.get("m-shadow")
	_assert("shadow_root", root != null)
	if root == null:
		layer.queue_free()
		return
	var shadow := _find_child_with_meta(root, "contact_shadow") as MeshInstance3D
	_assert("shadow_exists", shadow != null)
	if shadow == null:
		layer.queue_free()
		return
	_assert("shadow_quad", shadow.mesh is QuadMesh)
	_assert("shadow_flat", is_equal_approx(shadow.rotation_degrees.x, -90.0))
	# Offset monde constant (~0.02) au-dessus du sol, même élevé et mis à l'échelle.
	var world_y := root.position.y + shadow.position.y * root.scale.y
	_assert("shadow_above_ground",
		is_equal_approx(world_y, 1.0 * 0.7 + Meshes3DScript.CONTACT_SHADOW_HEIGHT))
	# Dimensionnée sur l'empreinte XZ du volume (fallback : boîte 0.9 case).
	if shadow.mesh is QuadMesh:
		var quad := shadow.mesh as QuadMesh
		_assert("shadow_footprint",
			is_equal_approx(quad.size.x, Meshes3DScript.FALLBACK_BOX_SIZE.x)
			and is_equal_approx(quad.size.y, Meshes3DScript.FALLBACK_BOX_SIZE.z))
		_assert("shadow_centered",
			is_zero_approx(shadow.position.x) and is_zero_approx(shadow.position.z))
	var mat := shadow.material_override as StandardMaterial3D
	_assert("shadow_material", mat != null)
	if mat != null:
		_assert("shadow_alpha", mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA)
		_assert("shadow_unshaded",
			mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
		_assert("shadow_texture", mat.albedo_texture != null)
		_assert("shadow_priority_low", mat.render_priority < 0)
		if mat.albedo_texture is GradientTexture2D:
			var gradient := (mat.albedo_texture as GradientTexture2D).gradient
			_assert("shadow_opacity_soft",
				gradient != null and gradient.get_color(0).a >= 0.15 and gradient.get_color(0).a <= 0.35)
	_assert("shadow_no_cast",
		shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	layer.queue_free()

func _test_atmosphere_tint() -> void:
	# Sans map_data : couleur neutre du fallback intacte.
	var neutral := _make_layer()
	neutral.configure([{"id": "n", "asset": ""}], 1.0)
	var neutral_root: Node3D = neutral._nodes.get("n")
	var neutral_visual := _find_child_with_meta(neutral_root, "fallback") as MeshInstance3D
	_assert("atmo_neutral_visual", neutral_visual != null)
	var neutral_color := Color.WHITE
	if neutral_visual != null:
		neutral_color = (neutral_visual.material_override as StandardMaterial3D).albedo_color
	neutral.queue_free()
	# Avec ambiance sombre : le fallback est légèrement fondu dedans.
	var tinted := _make_layer()
	tinted.configure([{"id": "t", "asset": ""}], 1.0,
		{"renderStyle": "diorama", "atmosphere": {"tint": "#101018"}})
	var tinted_root: Node3D = tinted._nodes.get("t")
	var tinted_visual := _find_child_with_meta(tinted_root, "fallback") as MeshInstance3D
	_assert("atmo_tinted_visual", tinted_visual != null)
	if tinted_visual != null:
		var tinted_color := (tinted_visual.material_override as StandardMaterial3D).albedo_color
		_assert("atmo_neutral_base", is_equal_approx(neutral_color.r, Meshes3DScript.FALLBACK_COLOR.r))
		_assert("atmo_tinted", tinted_color.r < neutral_color.r and tinted_color.g < neutral_color.g)
	tinted.queue_free()

func _test_rotation_scale_elevation() -> void:
	var layer := _make_layer()
	layer.configure([
		{
			"id": "m-rot", "kind": "mesh", "asset": "res://assets/objects3d/objects/absent.glb",
			"x": 0.0, "y": 0.0, "elevation": 2.0,
			"display": {"rotation": 45.0, "scale": 1.5},
		},
	], 0.7)
	var root: Node3D = layer._nodes.get("m-rot")
	_assert("rot_node", root != null)
	if root != null:
		# Convention des décors : lacet inversé pour compenser le repère carte.
		_assert("rot_inverted", is_equal_approx(root.rotation_degrees.y, -45.0))
		_assert("scale_combined", is_equal_approx(root.scale.x, 0.7 * 1.5))
		_assert("scale_uniform", is_equal_approx(root.scale.x, root.scale.y)
			and is_equal_approx(root.scale.y, root.scale.z))
		_assert("elevation_in_cells", is_equal_approx(root.position.y, 2.0 * 0.7))
	layer.queue_free()

func _test_hidden_and_invalid() -> void:
	var layer := _make_layer()
	layer.configure([
		{"id": "visible", "kind": "mesh", "asset": "", "x": 1.0, "y": 1.0},
		{"id": "cache", "kind": "mesh", "asset": "", "x": 2.0, "y": 2.0, "hidden": true},
		"pas un dictionnaire",
		42,
	], 1.0)
	_assert("hidden_visible_only", layer.get_child_count() == 1)
	_assert("hidden_kept_visible", layer.has_mesh("visible"))
	_assert("hidden_skipped", not layer.has_mesh("cache"))
	_assert("hidden_registry", layer._nodes.size() == 1)
	layer.queue_free()

func _test_move_and_registry() -> void:
	var layer := _make_layer()
	layer.configure([
		{"id": "m-move", "kind": "mesh", "asset": "", "x": 1.0, "y": 2.0},
		{"id": "m-fixe", "kind": "mesh", "asset": "", "x": 4.0, "y": 5.0},
	], 0.7)
	var root: Node3D = layer._nodes.get("m-move")
	_assert("move_root", root != null)
	layer.set_mesh_position("m-move", 5.0, 6.0)
	if root != null:
		_assert("move_x", is_equal_approx(root.position.x, 5.0 * 0.7 + 0.35))
		_assert("move_z", is_equal_approx(root.position.z, 6.0 * 0.7 + 0.35))
		# Le déplacement live ne touche pas l'élévation ni l'échelle.
		_assert("move_keeps_elevation", is_equal_approx(root.position.y, 0.0))
		_assert("move_keeps_scale", is_equal_approx(root.scale.x, 0.7))
	# Id inconnu : ne doit pas planter et ne rien déplacer.
	layer.set_mesh_position("inconnu", 9.0, 9.0)
	var fixed: Node3D = layer._nodes.get("m-fixe")
	_assert("move_unknown_noop", fixed != null and is_equal_approx(fixed.position.x, 4.0 * 0.7 + 0.35))
	layer.queue_free()

func _test_reconfigure() -> void:
	var layer := _make_layer()
	layer.configure([{"id": "m-a", "asset": ""}], 1.0)
	_assert("reconf_initial", layer.has_mesh("m-a"))
	layer.configure([{"id": "m-b", "asset": ""}], 1.0)
	_assert("reconf_cleared", not layer.has_mesh("m-a"))
	_assert("reconf_replaced", layer.has_mesh("m-b") and layer.get_child_count() == 1)
	layer.configure([], 1.0)
	_assert("reconf_empty", layer.get_child_count() == 0 and layer._nodes.is_empty())
	layer.queue_free()

## Smoke d'intégration : le moteur crée le calque « Meshes » après « Props » et
## le réalimente depuis map_data["meshes"].
func _test_engine_integration() -> void:
	var Engine3DScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd") as GDScript
	if Engine3DScript == null:
		print("  (smoke moteur ignoré : script moteur indisponible)")
		return
	var engine: Control = Engine3DScript.new()
	engine.size = Vector2(1000, 700)
	get_root().add_child(engine)
	await _wait_frames(2)
	var map := {
		"id": "mesh-layer-test",
		"name": "Meshes test",
		"width": 20,
		"height": 14,
		"grid": {"size": 70},
		"renderStyle": "vtt",
		"fogEnabled": false,
		"layers": [],
		"meshes": [
			{
				"id": "smoke-mesh", "kind": "mesh",
				"asset": "res://assets/objects3d/objects/nexiste_pas.glb",
				"x": 3.0, "y": 4.0, "elevation": 1.0,
				"display": {"rotation": 30.0, "scale": 2.0},
			},
		],
	}
	engine.configure(map, [], [], [], [], [], false, true)
	await _wait_frames(8)
	_assert("engine_meshes_layer", engine._meshes_layer != null)
	if engine._meshes_layer == null:
		engine.queue_free()
		return
	_assert("engine_cell_size", is_equal_approx(engine._cell_size, 0.7))
	_assert("engine_mesh_present", engine._meshes_layer.has_mesh("smoke-mesh"))
	_assert("engine_mesh_fallback", engine._meshes_layer.is_fallback("smoke-mesh"))
	var root: Node3D = engine._meshes_layer._nodes.get("smoke-mesh")
	_assert("engine_mesh_node", root != null)
	if root != null:
		_assert("engine_mesh_position",
			is_equal_approx(root.position.x, 3.0 * 0.7 + 0.35)
			and is_equal_approx(root.position.z, 4.0 * 0.7 + 0.35)
			and is_equal_approx(root.position.y, 0.7))
		_assert("engine_mesh_rotation", is_equal_approx(root.rotation_degrees.y, -30.0))
		_assert("engine_mesh_contact_shadow",
			_find_child_with_meta(root, "contact_shadow") != null)
	# Le calque est un enfant du monde, juste après « Props ».
	if engine._meshes_layer != null and engine._meshes_layer.get_parent() != null:
		var world: Node = engine._meshes_layer.get_parent()
		var idx: int = engine._meshes_layer.get_index()
		var prev: Node = world.get_child(idx - 1) if idx > 0 else null
		_assert("engine_mesh_after_props",
			prev != null and str(prev.name) == "Props" and str(engine._meshes_layer.name) == "Meshes")
	# Reconfiguration : map_data["meshes"] = [] vide le calque.
	map["meshes"] = []
	engine.configure(map, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_mesh_cleared",
		engine._meshes_layer != null and not engine._meshes_layer.has_mesh("smoke-mesh"))
	_assert("engine_mesh_layer_empty",
		engine._meshes_layer != null and engine._meshes_layer.get_child_count() == 0)
	engine.queue_free()
	await _wait_frames(2)

# ===========================================================================

## Premier descendant (ou enfant direct) portant le meta demandé.
func _find_child_with_meta(node: Node, meta_name: String) -> Node:
	if node == null:
		return null
	for child in node.get_children():
		if child.has_meta(meta_name):
			return child
		var nested := _find_child_with_meta(child, meta_name)
		if nested != null:
			return nested
	return null

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("map_meshes_3d_test:FAIL at ", name)
		_failed = true
