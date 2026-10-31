extends SceneTree

## Tests du sol et du relief de la carte 2.5D (M6) :
##   • modes de sol : `terrain3d` (vrai heightfield 3D éclairé, vertex colors
##     herbe/terre/roche, relief visible même à plat, nuit teintée) et
##     `illustrated` (quad + texture + shader nuit actuels, AUCUNE déformation) ;
##   • API moteur `terrain_has_relief` / `terrain_height_at` / `terrain_normal_at`
##     (convention grille centrée case, interpolation bilinéaire) ;
##   • `refresh_terrain` (pinceau de relief) : sol + meshes reposés sans rebuild ;
##   • `MapMeshes3D` : bâtiments **droits** par défaut (hauteur moyenne de
##     l'empreinte), objets `tiltToTerrain: true` inclinés sur la hauteur max ;
##     ombre de contact à la base ; option `followTerrain` ;
##   • `MapProps3D` / `MapToken3D` : pied posé à la hauteur du terrain ;
##   • projection : `grid_to_screen` tient compte de la hauteur du terrain et
##     `screen_to_grid_pos` retombe sur la bonne case sur une pente.
##
## Autonome : les scripts qui référencent l'autoload MapData sont chargés par
## `load()` à l'exécution (même contrainte que map_editor_test).

const GroundScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")
const MeshesScript := preload("res://scripts/maps/map_layers/map_meshes_3d.gd")
const PropsScript := preload("res://scripts/maps/map_layers/map_props_3d.gd")

const W := 8
const H := 8
const CELL := 1.0
## Pente de la rampe de test : +0.25 case par case en x (14° > seuil 8°).
const RAMP_STEP := 0.25
const PROP_ASSET := "res://assets/objects3d/buildings/maison_thumb.png"

var EngineScript: GDScript
var TokenScript: GDScript

var _failed: bool = false
var _nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	EngineScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	TokenScript = load("res://scripts/maps/map_layers/map_token_3d.gd")
	if EngineScript == null or TokenScript == null:
		print("map_terrain_test:FAIL at scripts_load")
		_failed = true
		quit(1)
		return

	await _test_engine_terrain_api()
	await _test_ground_layer()
	_test_meshes_layer()
	_test_props_layer()
	_test_token_layer()

	for node in _nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await _wait_frames(3)

	if _failed:
		quit(1)
		return
	print("map_terrain_test:PASS")
	quit(0)

# ===========================================================================
# Données de test
# ===========================================================================

## Hauteurs en rampe sur x : h(x,y) = x * RAMP_STEP (0 = plat).
func _make_heights(with_relief: bool) -> Array:
	var heights: Array = []
	heights.resize(W * H)
	for y in range(H):
		for x in range(W):
			heights[y * W + x] = float(x) * RAMP_STEP if with_relief else 0.0
	return heights

func _make_map(with_relief: bool, ground_mode: String = "") -> Dictionary:
	var map := {
		"id": "terrain-test",
		"name": "Terrain test",
		"width": W,
		"height": H,
		"grid": {"size": 70},
		"renderStyle": "2.5d",
		"fogEnabled": false,
		"layers": [],
		"terrainHeights": _make_heights(with_relief),
	}
	if not ground_mode.is_empty():
		map["groundMode"] = ground_mode
	return map

func _make_solid_texture(color: Color) -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func _ground_vertex_count(ground) -> int:
	var mesh: ArrayMesh = ground._mesh_instance.mesh
	if mesh == null or not (mesh is ArrayMesh) or (mesh as ArrayMesh).get_surface_count() == 0:
		return -1
	var arrays: Array = (mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts.size()

func _ground_max_y(ground) -> float:
	var mesh: ArrayMesh = ground._mesh_instance.mesh
	if mesh == null or not (mesh is ArrayMesh) or (mesh as ArrayMesh).get_surface_count() == 0:
		return -INF
	var arrays: Array = (mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var max_y := -INF
	for v in verts:
		max_y = maxf(max_y, v.y)
	return max_y

# ===========================================================================
# Moteur : mode de sol, API relief, refresh_terrain, projection
# ===========================================================================

func _test_engine_terrain_api() -> void:
	# Carte 2.5D sans `groundMode` ni fond illustré : nouveau défaut = terrain3d.
	var map := _make_map(true)
	map["meshes"] = [
		{
			"id": "engine-mesh", "kind": "mesh", "asset": "",
			"x": 4.0, "y": 4.0, "elevation": 0.5,
			"w": 1.0, "h": 1.0,
		},
	]
	var engine: Control = EngineScript.new()
	engine.size = Vector2(1000, 700)
	get_root().add_child(engine)
	_nodes.append(engine)
	await _wait_frames(3)
	engine.configure(map, [
		{"id": "engine-token", "kind": "npc", "x": 4.0, "y": 4.0},
	], [], [], [], [], false, true)
	await _wait_frames(8)

	var cell: float = float(engine.get_cell_size())
	_assert("engine_cell_size", is_equal_approx(cell, 0.7))
	# --- Mode de sol : terrain3d par défaut sur une carte 2.5D sans fond.
	_assert("engine_ground_mode_default", engine.get_ground_mode() == "terrain3d",
		"mode=%s" % engine.get_ground_mode())
	_assert("engine_is_terrain3d", engine.is_terrain3d_ground())
	_assert("engine_ground_terrain3d", engine._ground != null and engine._ground.is_terrain3d())
	_assert("engine_ground_relief_active",
		engine._ground != null and engine._ground.is_relief_active())
	_assert("engine_ground_vertex_count",
		_ground_vertex_count(engine._ground) == (W + 1) * (H + 1))
	_assert("engine_ground_has_relief",
		engine._ground != null and engine._ground.has_terrain_relief())

	# --- Hauteurs / normales (convention grille centrée case).
	_assert("engine_terrain_has_relief", engine.terrain_has_relief())
	_assert("height_flat_cell", is_equal_approx(engine.terrain_height_at(0.0, 0.0), 0.0))
	_assert("height_cell_4", is_equal_approx(engine.terrain_height_at(4.0, 4.0), 1.0))
	_assert("height_cell_7", is_equal_approx(engine.terrain_height_at(7.0, 2.0), 1.75))
	_assert("height_interp_mid", is_equal_approx(engine.terrain_height_at(4.5, 4.0), 1.125))
	_assert("height_interp_quarter", is_equal_approx(engine.terrain_height_at(2.25, 0.0), 0.5625))
	_assert("height_ridge_constant_y",
		is_equal_approx(engine.terrain_height_at(3.0, 0.0), engine.terrain_height_at(3.0, 7.0)))
	_assert("height_out_left", is_equal_approx(engine.terrain_height_at(-1.0, 0.0), 0.0))
	_assert("height_out_right", is_equal_approx(engine.terrain_height_at(8.0, 0.0), 0.0))
	_assert("height_edge_clamped", is_equal_approx(engine.terrain_height_at(7.5, 0.0), 1.75))

	var expected_normal := Vector3(-RAMP_STEP, 1.0, 0.0).normalized()
	var normal: Vector3 = engine.terrain_normal_at(4.0, 4.0)
	_assert("normal_slope", normal.dot(expected_normal) > 0.999,
		"normal=%s attendu=%s" % [str(normal), str(expected_normal)])
	_assert("normal_up_y", normal.y > 0.9)

	# --- Mesh du moteur : bâtiment droit → base sur la hauteur MOYENNE.
	# Empreinte 1 case : centre 1.0, coins à 3.5/4.5 → 0.875 / 1.125 → moyenne 1.0.
	if engine._meshes_layer != null:
		var mesh_root: Node3D = engine._meshes_layer._nodes.get("engine-mesh")
		_assert("engine_mesh_upright_mean", mesh_root != null
			and is_equal_approx(mesh_root.position.y, (1.0 + 0.5) * cell),
			"y=%s" % [str(mesh_root.position.y) if mesh_root != null else "null"])
		if mesh_root != null:
			_assert("engine_mesh_upright_vertical",
				mesh_root.basis.y.normalized().dot(Vector3.UP) > 0.999)
	else:
		_assert("engine_meshes_layer", false)

	# --- Refresh terrain3d : sol reconstruit, mode conservé, mesh reposé.
	var flat_map := _make_map(false)
	flat_map["meshes"] = map["meshes"]
	engine.refresh_terrain(flat_map)
	await _wait_frames(4)
	_assert("refresh_flat_mode_kept", engine.get_ground_mode() == "terrain3d")
	_assert("refresh_flat_is_terrain3d", engine._ground.is_terrain3d())
	_assert("refresh_flat_mask_real", engine._ground.is_relief_active())
	_assert("refresh_flat_has_relief", not engine.terrain_has_relief())
	_assert("refresh_flat_height_zero", is_equal_approx(engine.terrain_height_at(4.0, 4.0), 0.0))
	_assert("refresh_flat_ground_max_y", is_zero_approx(_ground_max_y(engine._ground)))
	_assert("refresh_flat_vertex_count",
		_ground_vertex_count(engine._ground) == (W + 1) * (H + 1))
	if engine._meshes_layer != null:
		var flat_mesh: Node3D = engine._meshes_layer._nodes.get("engine-mesh")
		_assert("refresh_flat_mesh_ground", flat_mesh != null
			and is_equal_approx(flat_mesh.position.y, 0.5 * cell),
			"y=%s" % [str(flat_mesh.position.y) if flat_mesh != null else "null"])
	else:
		_assert("refresh_flat_meshes_layer", false)

	engine.refresh_terrain(map)
	await _wait_frames(4)
	_assert("refresh_relief_mode_kept", engine.get_ground_mode() == "terrain3d")
	_assert("refresh_relief_has_relief", engine.terrain_has_relief())
	_assert("refresh_relief_ground_max_y", _ground_max_y(engine._ground) > 0.5)
	if engine._meshes_layer != null:
		var back_mesh: Node3D = engine._meshes_layer._nodes.get("engine-mesh")
		_assert("refresh_relief_mesh_base", back_mesh != null
			and is_equal_approx(back_mesh.position.y, (1.0 + 0.5) * cell),
			"y=%s" % [str(back_mesh.position.y) if back_mesh != null else "null"])
	else:
		_assert("refresh_relief_meshes_layer", false)

	# --- Projection : grid_to_screen ajoute la hauteur du terrain.
	var gx := 4.0
	var gy := 4.0
	var terrain_h: float = engine.terrain_height_at(gx, gy) * cell
	var surface_world := Vector3(
		gx * cell + cell * 0.5,
		terrain_h,
		gy * cell + cell * 0.5
	)
	var expected: Vector2 = engine._viewport_to_control(engine._camera.unproject_position(surface_world))
	var actual: Vector2 = engine.grid_to_screen(gx, gy)
	_assert("grid_to_screen_surface", actual.distance_to(expected) < 1.5,
		"actual=%s attendu=%s" % [str(actual), str(expected)])
	var flat_world := Vector3(surface_world.x, 0.0, surface_world.z)
	var without_height: Vector2 = engine._viewport_to_control(engine._camera.unproject_position(flat_world))
	_assert("grid_to_screen_height_shift",
		actual.distance_to(without_height) > 2.0,
		"delta=%s" % [str(actual.distance_to(without_height))])

	var back: Vector2 = engine.screen_to_grid_pos(engine.grid_to_screen(gx, gy))
	_assert("screen_to_grid_roundtrip", back.distance_to(Vector2(gx, gy)) < 0.6,
		"back=%s" % [str(back)])

	# --- Token moteur posé à la hauteur du terrain.
	if engine._tokens_layer != null:
		var tok = engine._token_nodes.get("engine-token")
		_assert("engine_token_on_terrain", tok != null
			and is_equal_approx(tok.position.y, engine.terrain_height_at(4.0, 4.0) * cell),
			"y=%s" % [str(tok.position.y) if tok != null else "null"])
	else:
		_assert("engine_tokens_layer", false)

	# --- Bascule de mode à chaud : illustrated = quad plat, aucune déformation.
	engine.set_ground_mode("illustrated")
	await _wait_frames(2)
	_assert("toggle_illustrated_mode", engine.get_ground_mode() == "illustrated")
	_assert("toggle_illustrated_flag", not engine.is_terrain3d_ground())
	_assert("toggle_illustrated_ground", engine._ground.get_ground_mode() == "illustrated")
	_assert("toggle_illustrated_vertex_count", _ground_vertex_count(engine._ground) == 12,
		"count=%d" % _ground_vertex_count(engine._ground))
	_assert("toggle_illustrated_flat", is_zero_approx(_ground_max_y(engine._ground)))
	# Les hauteurs restent des données logiques (pose des objets / picking).
	_assert("toggle_illustrated_data_kept", engine.terrain_has_relief())

	engine.set_ground_mode("terrain3d")
	await _wait_frames(2)
	_assert("toggle_terrain3d_mode", engine.get_ground_mode() == "terrain3d")
	_assert("toggle_terrain3d_vertex_count",
		_ground_vertex_count(engine._ground) == (W + 1) * (H + 1))

	# --- `groundMode: "illustrated"` explicite dans map_data (configure).
	var illustrated_map := _make_map(true, "illustrated")
	illustrated_map["id"] = "terrain-test-illustrated"
	engine.configure(illustrated_map, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("configure_illustrated_mode", engine.get_ground_mode() == "illustrated")
	_assert("configure_illustrated_vertex_count",
		_ground_vertex_count(engine._ground) == 12,
		"count=%d" % _ground_vertex_count(engine._ground))
	_assert("configure_illustrated_flat", is_zero_approx(_ground_max_y(engine._ground)))

# ===========================================================================
# Sol : terrain3d (heightfield éclairé) vs illustrated (quad plat)
# ===========================================================================

func _test_ground_layer() -> void:
	var ground = GroundScript.new()
	get_root().add_child(ground)
	_nodes.append(ground)
	await _wait_frames(2)

	# --- terrain3d avec relief : grille (w+1)*(h+1), couleurs, matériau éclairé.
	ground.configure(
		null, W, H, CELL, true, null, false, [], [], 0.22,
		_make_heights(true), "terrain3d"
	)
	_assert("ground_terrain3d_mode", ground.get_ground_mode() == "terrain3d")
	_assert("ground_terrain3d_is_terrain3d", ground.is_terrain3d())
	_assert("ground_terrain3d_relief_active", ground.is_relief_active())
	_assert("ground_terrain3d_has_relief", ground.has_terrain_relief())
	var mesh: ArrayMesh = ground._mesh_instance.mesh
	_assert("ground_terrain3d_mesh", mesh is ArrayMesh)
	if mesh is ArrayMesh:
		_assert("ground_terrain3d_surfaces", mesh.get_surface_count() == 1)
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		_assert("ground_terrain3d_vertex_count", verts.size() == (W + 1) * (H + 1),
			"count=%d" % [verts.size()])
		_assert("ground_terrain3d_normals", normals.size() == verts.size())
		_assert("ground_terrain3d_colors", colors.size() == verts.size())
		var max_y := -INF
		var min_y := INF
		var different_colors := 0
		var first_color: Color = colors[0] if colors.size() > 0 else Color.WHITE
		for i in range(verts.size()):
			max_y = maxf(max_y, verts[i].y)
			min_y = minf(min_y, verts[i].y)
			if colors.size() > i and not colors[i].is_equal_approx(first_color):
				different_colors += 1
		_assert("ground_terrain3d_max_y", is_equal_approx(max_y, 7.0 * RAMP_STEP),
			"max_y=%f" % max_y)
		_assert("ground_terrain3d_min_y", is_zero_approx(min_y))
		_assert("ground_terrain3d_color_variation", different_colors > 8,
			"different=%d" % [different_colors])
		# Palette : herbe/terre/roche → couleurs opaques, pas du gris plat.
		var greenish := 0
		for c in colors:
			if c.g > c.r and c.g > c.b:
				greenish += 1
		_assert("ground_terrain3d_grass", greenish > 0)
		var slope_normals := 0
		for n in normals:
			if n.y < 0.99:
				slope_normals += 1
		_assert("ground_terrain3d_normals_slope", slope_normals > 0)
	var mat := ground._mesh_instance.material_override as StandardMaterial3D
	_assert("ground_terrain3d_material", mat != null)
	if mat != null:
		_assert("ground_terrain3d_lit",
			mat.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL)
		_assert("ground_terrain3d_roughness", is_equal_approx(mat.roughness, 1.0))
		_assert("ground_terrain3d_no_texture", mat.albedo_texture == null)
		_assert("ground_terrain3d_vertex_colors", mat.vertex_color_use_as_albedo)
		_assert("ground_terrain3d_day_white", mat.albedo_color.is_equal_approx(Color.WHITE))
	_assert("ground_terrain3d_no_shadow",
		ground._mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_assert("ground_terrain3d_extent",
		ground.get_map_extent().is_equal_approx(Vector2(W * CELL, H * CELL)))

	# --- terrain3d même à plat : vrai maillage 3D (pas un quad).
	ground.configure(null, W, H, CELL, true, null, false, [], [], 0.22, [], "terrain3d")
	_assert("ground_terrain3d_flat_mode", ground.is_terrain3d())
	_assert("ground_terrain3d_flat_relief_active", ground.is_relief_active())
	_assert("ground_terrain3d_flat_has_relief", not ground.has_terrain_relief())
	_assert("ground_terrain3d_flat_vertex_count",
		_ground_vertex_count(ground) == (W + 1) * (H + 1),
		"count=%d" % _ground_vertex_count(ground))
	_assert("ground_terrain3d_flat_y_zero", is_zero_approx(_ground_max_y(ground)))

	# --- illustrated avec relief : quad plat, AUCUNE déformation.
	ground.configure(
		null, W, H, CELL, true, null, false, [], [], 0.22,
		_make_heights(true), "illustrated"
	)
	_assert("ground_illustrated_mode", ground.get_ground_mode() == "illustrated")
	_assert("ground_illustrated_not_relief", not ground.is_relief_active())
	_assert("ground_illustrated_vertex_count", _ground_vertex_count(ground) == 12,
		"count=%d" % _ground_vertex_count(ground))
	_assert("ground_illustrated_no_deformation", is_zero_approx(_ground_max_y(ground)))
	_assert("ground_illustrated_keeps_data", ground.has_terrain_relief())
	var illustrated_mat := ground._mesh_instance.material_override as StandardMaterial3D
	_assert("ground_illustrated_material", illustrated_mat != null
		and not illustrated_mat.vertex_color_use_as_albedo)

	# --- Mode par défaut d'un appel historique (sans ground_mode) : illustrated.
	ground.configure(null, W, H, CELL, true, null, false, [], [], 0.22, _make_heights(true))
	_assert("ground_default_mode_illustrated", ground.get_ground_mode() == "illustrated")

	# --- Bascule à chaud sur le calque.
	ground.set_ground_mode("terrain3d")
	_assert("ground_set_mode_terrain3d", ground.is_terrain3d()
		and _ground_vertex_count(ground) == (W + 1) * (H + 1))
	ground.set_ground_mode("illustrated")
	_assert("ground_set_mode_illustrated", not ground.is_terrain3d()
		and _ground_vertex_count(ground) == 12)

	# --- Nuit terrain3d : relief conservé, petite teinte sombre (pas ignoré).
	ground.configure(
		null, W, H, CELL, true, null, true, [], [], 0.22,
		_make_heights(true), "terrain3d"
	)
	_assert("ground_terrain3d_night_mode", ground.is_night_mode_enabled())
	_assert("ground_terrain3d_night_keeps_relief", ground.is_relief_active()
		and _ground_vertex_count(ground) == (W + 1) * (H + 1))
	_assert("ground_terrain3d_night_max_y", _ground_max_y(ground) > 0.5)
	var night_mat := ground._mesh_instance.material_override as StandardMaterial3D
	_assert("ground_terrain3d_night_tint", night_mat != null
		and not night_mat.albedo_color.is_equal_approx(Color.WHITE)
		and night_mat.albedo_color.get_luminance() < 0.6)
	_assert("ground_terrain3d_night_no_shader", not ground.is_night_active())

	# --- Nuit illustrated : shader jour/nuit actuel, quad plat.
	ground.configure(
		_make_solid_texture(Color(0.5, 0.5, 0.5, 1.0)), W, H, CELL, true,
		_make_solid_texture(Color(0.05, 0.05, 0.1, 1.0)), true, [], [], 0.22,
		_make_heights(true), "illustrated"
	)
	_assert("ground_illustrated_night_shader", ground.is_night_active())
	_assert("ground_illustrated_night_flat", not ground.is_relief_active()
		and _ground_vertex_count(ground) == 12)
	_assert("ground_illustrated_night_material",
		ground._mesh_instance.material_override is ShaderMaterial)

# ===========================================================================
# Meshes : bâtiment droit (moyenne) vs objet incliné (max)
# ===========================================================================

func _test_meshes_layer() -> void:
	var layer = MeshesScript.new()
	get_root().add_child(layer)
	_nodes.append(layer)
	var map := _make_map(true)
	layer.configure([
		{
			"id": "m-upright", "kind": "mesh", "asset": "",
			"x": 4.0, "y": 4.0, "elevation": 0.5,
			"w": 2.0, "h": 2.0,
			"display": {"rotation": 30.0, "scale": 1.0},
		},
		{
			"id": "m-tilt", "kind": "mesh", "asset": "",
			"x": 4.0, "y": 4.0, "elevation": 0.5,
			"w": 2.0, "h": 2.0, "tiltToTerrain": true,
			"display": {"rotation": 0.0, "scale": 1.0},
		},
		{
			"id": "m-fixed", "kind": "mesh", "asset": "",
			"x": 4.0, "y": 4.0, "elevation": 1.0,
			"followTerrain": false,
		},
	], CELL, map)

	# Bâtiment droit : empreinte 2×2 → échantillons 1.0 / 0.75 / 1.25 / 0.75 / 1.25
	# → moyenne 1.0 ; reste vertical malgré la pente (14°).
	var upright: Node3D = layer._nodes.get("m-upright")
	_assert("mesh_upright_node", upright != null)
	if upright != null:
		_assert("mesh_upright_mean_base", is_equal_approx(upright.position.y, 1.0 + 0.5),
			"y=%f" % upright.position.y)
		_assert("mesh_upright_vertical",
			upright.basis.y.normalized().dot(Vector3.UP) > 0.999,
			"up=%s" % [str(upright.basis.y.normalized())])
		_assert("mesh_upright_yaw_kept", is_equal_approx(upright.rotation_degrees.y, -30.0))
		var shadow = layer._find_child_with_meta(upright, "contact_shadow")
		_assert("mesh_upright_shadow", shadow is Node3D)
		if shadow is Node3D:
			var shadow_world: Vector3 = upright.transform * (shadow as Node3D).position
			_assert("mesh_upright_shadow_height",
				is_equal_approx(shadow_world.y, upright.position.y + 0.02),
				"shadow_y=%f" % shadow_world.y)

	# Objet incliné (rocher/arbre) : base sur la hauteur MAX (1.25), +Y = normale.
	var tilt: Node3D = layer._nodes.get("m-tilt")
	_assert("mesh_tilt_node", tilt != null)
	if tilt != null:
		_assert("mesh_tilt_max_base", is_equal_approx(tilt.position.y, 1.25 + 0.5),
			"y=%f" % tilt.position.y)
		var expected_normal := Vector3(-RAMP_STEP, 1.0, 0.0).normalized()
		_assert("mesh_tilt_inclined",
			tilt.basis.y.normalized().dot(expected_normal) > 0.99,
			"up=%s" % [str(tilt.basis.y.normalized())])
		var shadow = layer._find_child_with_meta(tilt, "contact_shadow")
		_assert("mesh_tilt_shadow", shadow is Node3D)
		if shadow is Node3D:
			var shadow_world: Vector3 = tilt.transform * (shadow as Node3D).position
			_assert("mesh_tilt_shadow_height",
				is_equal_approx(shadow_world.y, tilt.position.y + 0.02),
				"shadow_y=%f" % shadow_world.y)
			var shadow_up: Vector3 = (shadow as Node3D).global_transform.basis.z.normalized()
			_assert("mesh_tilt_shadow_horizontal", shadow_up.dot(Vector3.UP) > 0.99)

	# followTerrain = false → comportement historique (pied au plan y=0 + élévation).
	var fixed: Node3D = layer._nodes.get("m-fixed")
	_assert("mesh_fixed_node", fixed != null)
	if fixed != null:
		_assert("mesh_fixed_flat_y", is_equal_approx(fixed.position.y, 1.0))
		_assert("mesh_fixed_upright", fixed.basis.y.normalized().dot(Vector3.UP) > 0.999)

	# Drag live sur relief : le bâtiment droit se repose sur la moyenne locale.
	# x=6 → centre 1.5, coins 1.25 / 1.75 → moyenne 1.5 (+ élévation 0.5).
	layer.set_mesh_position("m-upright", 6.0, 4.0)
	if upright != null:
		_assert("mesh_drag_mean_height", is_equal_approx(upright.position.y, 1.5 + 0.5),
			"y=%f" % upright.position.y)
		_assert("mesh_drag_stays_vertical",
			upright.basis.y.normalized().dot(Vector3.UP) > 0.999)

	# Sans relief : pied au plan y=0, aucune inclinaison.
	var flat_layer = MeshesScript.new()
	get_root().add_child(flat_layer)
	_nodes.append(flat_layer)
	flat_layer.configure([
		{
			"id": "m-flat", "kind": "mesh", "asset": "",
			"x": 4.0, "y": 4.0, "elevation": 0.5, "w": 2.0, "h": 2.0,
			"tiltToTerrain": true,
		},
	], CELL, _make_map(false))
	var flat_root: Node3D = flat_layer._nodes.get("m-flat")
	_assert("mesh_flat_node", flat_root != null)
	if flat_root != null:
		_assert("mesh_flat_y", is_equal_approx(flat_root.position.y, 0.5))
		_assert("mesh_flat_upright", flat_root.basis.y.normalized().dot(Vector3.UP) > 0.999)

# ===========================================================================
# Décors 2D : pied à la hauteur du terrain, découpe verticale
# ===========================================================================

func _test_props_layer() -> void:
	var layer = PropsScript.new()
	get_root().add_child(layer)
	_nodes.append(layer)
	layer.configure([
		{
			"id": "p-butt", "x": 4.0, "y": 4.0, "w": 2.0, "h": 2.0,
			"asset": PROP_ASSET, "standing": true,
		},
	], CELL, _make_map(true))
	_assert("prop_built", layer.has_prop("p-butt"))
	var root: Node3D = layer._nodes.get("p-butt")
	_assert("prop_root", root != null)
	if root != null:
		_assert("prop_terrain_y", is_equal_approx(root.position.y, 1.0),
			"y=%f" % root.position.y)
		_assert("prop_upright", root.basis.y.normalized().dot(Vector3.UP) > 0.999)
		layer.set_prop_position("p-butt", 6.0, 4.0)
		_assert("prop_drag_terrain_y", is_equal_approx(root.position.y, 1.5),
			"y=%f" % root.position.y)

	layer.configure([
		{
			"id": "p-flat", "x": 4.0, "y": 4.0, "asset": PROP_ASSET, "standing": true,
		},
	], CELL, _make_map(false))
	var flat_root: Node3D = layer._nodes.get("p-flat")
	_assert("prop_flat_node", flat_root != null)
	if flat_root != null:
		_assert("prop_flat_y", is_zero_approx(flat_root.position.y))

# ===========================================================================
# Tokens : pied à la hauteur du terrain
# ===========================================================================

func _test_token_layer() -> void:
	var token = TokenScript.new()
	token.setup(
		{"id": "t-terrain", "kind": "npc", "x": 4.0, "y": 4.0},
		CELL, [], false, false, _make_heights(true), Vector2i(W, H)
	)
	get_root().add_child(token)
	_nodes.append(token)
	_assert("token_terrain_y", is_equal_approx(token.position.y, 1.0),
		"y=%f" % token.position.y)
	_assert("token_upright", token.basis.y.normalized().dot(Vector3.UP) > 0.999)

	token.set_terrain_heights(_make_heights(false), Vector2i(W, H))
	_assert("token_flat_y", is_zero_approx(token.position.y))
	token.set_terrain_heights(_make_heights(true), Vector2i(W, H))
	_assert("token_relief_restored_y", is_equal_approx(token.position.y, 1.0))

	var left = TokenScript.new()
	left.setup(
		{"id": "t-left", "kind": "npc", "x": 0.0, "y": 0.0},
		CELL, [], false, false, _make_heights(true), Vector2i(W, H)
	)
	get_root().add_child(left)
	_nodes.append(left)
	_assert("token_left_flat_y", is_zero_approx(left.position.y))

# ===========================================================================
# Utilitaires
# ===========================================================================

func _wait_frames(n: int = 2) -> void:
	for _i in range(n):
		await process_frame

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		return
	var suffix := "" if detail.is_empty() else " (%s)" % detail
	print("map_terrain_test:FAIL at ", name, suffix)
	_failed = true
