extends SceneTree

## Tests de la peinture de **matières du sol** (herbe / terre / pierre) de la
## carte 2.5D, mode `terrain3d` :
##   • texture de splat `width × height` (R = herbe, G = terre, B = pierre) ;
##   • `ShaderMaterial` `terrain_splat.gdshader` avec les 3 textures tuilées,
##     le splat en UV2 et les vertex colors d'ombrage (terrain éclairé) ;
##   • repli exact sur le matériau actuel quand les matières ou les textures
##     sont absentes ;
##   • mise à jour fluide des matières (splat seul, sans reconstruire le mesh) ;
##   • mode `illustrated` inchangé (quad plat, aucune matière) ;
##   • relief + matières ensemble, et intégration moteur (`configure`,
##     `refresh_terrain`, `set_terrain_materials`).
##
## Autonome : le moteur est chargé par `load()` (il référence l'autoload MapData).

const GroundScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")
const SplatShader := preload("res://shaders/terrain_splat.gdshader")

const W := 8
const H := 8
const CELL := 1.0
const RAMP_STEP := 0.25

var EngineScript: GDScript

var _failed: bool = false
var _nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	EngineScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	if EngineScript == null:
		print("map_terrain_materials_test:FAIL at engine_load")
		_failed = true
		quit(1)
		return

	await _test_ground_splat()
	await _test_ground_fallback()
	await _test_material_update()
	await _test_illustrated()
	await _test_engine_integration()

	for node in _nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await _wait_frames(3)

	if _failed:
		quit(1)
		return
	print("map_terrain_materials_test:PASS")
	quit(0)

# ===========================================================================
# Données de test
# ===========================================================================

## Matières de base : case (0,0) herbe, (1,0) terre, (2,0) pierre, le reste herbe.
func _make_materials() -> Array:
	var materials: Array = []
	materials.resize(W * H)
	materials.fill(0)
	materials[0 * W + 0] = 0
	materials[0 * W + 1] = 1
	materials[0 * W + 2] = 2
	return materials

## Toutes les cases de la même matière.
func _flat_materials(material: int) -> Array:
	var materials: Array = []
	materials.resize(W * H)
	materials.fill(material)
	return materials

func _make_heights(with_relief: bool) -> Array:
	var heights: Array = []
	heights.resize(W * H)
	for y in range(H):
		for x in range(W):
			heights[y * W + x] = float(x) * RAMP_STEP if with_relief else 0.0
	return heights

func _make_map(materials: Array, with_relief: bool, ground_mode: String = "terrain3d") -> Dictionary:
	var map := {
		"id": "terrain-materials-test",
		"name": "Terrain materials test",
		"width": W,
		"height": H,
		"grid": {"size": 70},
		"renderStyle": "2.5d",
		"fogEnabled": false,
		"layers": [],
		"groundMode": ground_mode,
		"terrainHeights": _make_heights(with_relief),
		"terrainMaterials": materials,
	}
	return map

func _make_solid_texture(color: Color) -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func _make_ground() -> Node3D:
	var ground = GroundScript.new()
	get_root().add_child(ground)
	_nodes.append(ground)
	return ground

func _configure_ground(
	ground,
	materials: Array,
	with_relief: bool = true,
	ground_mode: String = "terrain3d",
	night_mode: bool = false
) -> void:
	ground.configure(
		null, W, H, CELL, true, null, night_mode, [], [], 0.22,
		_make_heights(with_relief), ground_mode, materials
	)

func _ground_arrays(ground) -> Array:
	var mesh: ArrayMesh = ground._mesh_instance.mesh
	if mesh == null or not (mesh is ArrayMesh) or (mesh as ArrayMesh).get_surface_count() == 0:
		return []
	return (mesh as ArrayMesh).surface_get_arrays(0)

func _ground_vertex_count(ground) -> int:
	var arrays := _ground_arrays(ground)
	if arrays.is_empty():
		return -1
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts.size()

func _ground_max_y(ground) -> float:
	var arrays := _ground_arrays(ground)
	if arrays.is_empty():
		return -INF
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var max_y := -INF
	for v in verts:
		max_y = maxf(max_y, v.y)
	return max_y

func _splat_pixel(ground, x: int, y: int) -> Color:
	var img: Image = ground.get_splat_image()
	if img == null:
		return Color(-1, -1, -1, -1)
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return Color(-1, -1, -1, -1)
	return img.get_pixel(x, y)

# ===========================================================================
# Splat : texture + shader + UV2 + ombrage neutre
# ===========================================================================

func _test_ground_splat() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_ground(ground, _make_materials())

	_assert("ground_terrain3d", ground.is_terrain3d())
	_assert("ground_splat_active", ground.is_splat_active())

	# --- Texture de splat : une case = un texel, canaux herbe/terre/pierre.
	var splat: ImageTexture = ground.get_splat_texture()
	_assert("splat_texture", splat != null)
	if splat != null:
		_assert("splat_size", splat.get_width() == W and splat.get_height() == H,
			"size=%dx%d" % [splat.get_width(), splat.get_height()])
		var img: Image = ground.get_splat_image()
		_assert("splat_image", img != null)
		if img != null:
			_assert("splat_image_size", img.get_width() == W and img.get_height() == H)
			_assert("splat_pixel_grass", img.get_pixel(0, 0).is_equal_approx(Color(1, 0, 0, 1)),
				"pixel=%s" % [str(img.get_pixel(0, 0))])
			_assert("splat_pixel_dirt", img.get_pixel(1, 0).is_equal_approx(Color(0, 1, 0, 1)),
				"pixel=%s" % [str(img.get_pixel(1, 0))])
			_assert("splat_pixel_stone", img.get_pixel(2, 0).is_equal_approx(Color(0, 0, 1, 1)),
				"pixel=%s" % [str(img.get_pixel(2, 0))])
			_assert("splat_pixel_grass_default", img.get_pixel(7, 7).is_equal_approx(Color(1, 0, 0, 1)))

	# --- Matériau : ShaderMaterial de splat avec les 3 textures + le splat.
	var mat = ground._mesh_instance.material_override
	_assert("splat_material_shader", mat is ShaderMaterial)
	if mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = mat
		_assert("splat_shader", shader_mat.shader == SplatShader)
		_assert("splat_grass_tex", shader_mat.get_shader_parameter("grass_tex") is Texture2D)
		_assert("splat_dirt_tex", shader_mat.get_shader_parameter("dirt_tex") is Texture2D)
		_assert("splat_stone_tex", shader_mat.get_shader_parameter("stone_tex") is Texture2D)
		_assert("splat_tex_param", shader_mat.get_shader_parameter("splat_tex") is Texture2D)
		var tint = shader_mat.get_shader_parameter("albedo_tint")
		_assert("splat_day_tint", tint is Color and (tint as Color).is_equal_approx(Color.WHITE))

	# --- Maillage : UV2 0..1 sur la carte, couleurs neutres (ombrage seul).
	var arrays := _ground_arrays(ground)
	_assert("splat_mesh_surface", not arrays.is_empty())
	if not arrays.is_empty():
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		_assert("splat_mesh_vertex_count", verts.size() == (W + 1) * (H + 1),
			"count=%d" % [verts.size()])
		_assert("splat_uv2_count", uv2s.size() == verts.size())
		if uv2s.size() == verts.size():
			_assert("splat_uv2_origin", uv2s[0].is_equal_approx(Vector2(0, 0)))
			_assert("splat_uv2_corner", uv2s[uv2s.size() - 1].is_equal_approx(Vector2(1, 1)),
				"uv2=%s" % [str(uv2s[uv2s.size() - 1])])
		_assert("splat_colors_count", colors.size() == verts.size())
		var neutral := true
		for c in colors:
			if absf(c.r - c.g) > 0.001 or absf(c.g - c.b) > 0.001:
				neutral = false
				break
		_assert("splat_vertex_colors_neutral", neutral)
		# Relief + matières ensemble.
		_assert("splat_relief_kept", _ground_max_y(ground) > 0.5)
	_assert("splat_no_shadow",
		ground._mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

# ===========================================================================
# Repli : sans matières → matériau actuel (texture de détail + palette)
# ===========================================================================

func _test_ground_fallback() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_ground(ground, [])

	_assert("fallback_terrain3d", ground.is_terrain3d())
	_assert("fallback_not_splat", not ground.is_splat_active())
	_assert("fallback_no_splat_texture", ground.get_splat_texture() == null)
	_assert("fallback_no_splat_image", ground.get_splat_image() == null)
	var mat = ground._mesh_instance.material_override
	_assert("fallback_standard_material", mat is StandardMaterial3D)
	if mat is StandardMaterial3D:
		var standard: StandardMaterial3D = mat
		_assert("fallback_lit", standard.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED)
		_assert("fallback_vertex_colors", standard.vertex_color_use_as_albedo)
	# Palette de repli : couleurs non neutres (herbe/terre/roche).
	var arrays := _ground_arrays(ground)
	if not arrays.is_empty():
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var non_neutral := 0
		for c in colors:
			if absf(c.r - c.g) > 0.01 or absf(c.g - c.b) > 0.01:
				non_neutral += 1
		_assert("fallback_palette_colors", non_neutral > 0)

# ===========================================================================
# Mise à jour fluide des matières (splat seul, mesh conservé)
# ===========================================================================

func _test_material_update() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_ground(ground, _make_materials())
	var mesh_before = ground._mesh_instance.mesh
	_assert("update_initial_stone", _splat_pixel(ground, 2, 0).is_equal_approx(Color(0, 0, 1, 1)))

	# Case (2,0) passe de pierre à herbe : seul le splat change.
	var next := _make_materials()
	next[0 * W + 2] = 0
	ground.set_terrain_materials(next)
	_assert("update_pixel_grass", _splat_pixel(ground, 2, 0).is_equal_approx(Color(1, 0, 0, 1)),
		"pixel=%s" % [str(_splat_pixel(ground, 2, 0))])
	_assert("update_mesh_not_rebuilt", ground._mesh_instance.mesh == mesh_before)
	_assert("update_material_kept", ground._mesh_instance.material_override is ShaderMaterial)
	_assert("update_materials_value", is_equal_approx(int(ground.get_terrain_materials()[2]), 0))

	# Toutes les matières → terre : tout le splat devient vert.
	ground.set_terrain_materials(_flat_materials(1))
	_assert("update_all_dirt", _splat_pixel(ground, 0, 0).is_equal_approx(Color(0, 1, 0, 1)))
	_assert("update_all_dirt_bottom", _splat_pixel(ground, W - 1, H - 1).is_equal_approx(Color(0, 1, 0, 1)))

	# Tableau invalide (mauvaise taille) → repli matériau actuel + palette.
	ground.set_terrain_materials([1, 2, 0])
	_assert("update_invalid_fallback", not ground.is_splat_active())
	_assert("update_invalid_texture_cleared", ground.get_splat_texture() == null)
	_assert("update_invalid_image_cleared", ground.get_splat_image() == null)
	_assert("update_invalid_standard_material",
		ground._mesh_instance.material_override is StandardMaterial3D)

	# Nuit + matières : le splat reste actif, la teinte d'albédo est sombre.
	_configure_ground(ground, _make_materials(), true, "terrain3d", true)
	_assert("night_splat_active", ground.is_splat_active())
	var night_mat = ground._mesh_instance.material_override
	if night_mat is ShaderMaterial:
		var tint = (night_mat as ShaderMaterial).get_shader_parameter("albedo_tint")
		_assert("night_splat_tint", tint is Color
			and not (tint as Color).is_equal_approx(Color.WHITE)
			and (tint as Color).get_luminance() < 0.6)
	else:
		_assert("night_splat_material", false)

# ===========================================================================
# Mode illustrated : aucun splat, quad plat
# ===========================================================================

func _test_illustrated() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	ground.configure(
		_make_solid_texture(Color(0.5, 0.5, 0.5, 1.0)), W, H, CELL, true, null, false,
		[], [], 0.22, _make_heights(true), "illustrated", _make_materials()
	)
	_assert("illustrated_not_terrain3d", not ground.is_terrain3d())
	_assert("illustrated_not_splat", not ground.is_splat_active())
	_assert("illustrated_no_splat_texture", ground.get_splat_texture() == null)
	_assert("illustrated_no_splat_image", ground.get_splat_image() == null)
	_assert("illustrated_flat_quad", _ground_vertex_count(ground) == 12,
		"count=%d" % _ground_vertex_count(ground))
	_assert("illustrated_no_deformation", is_zero_approx(_ground_max_y(ground)))
	var mat = ground._mesh_instance.material_override
	_assert("illustrated_material", mat is StandardMaterial3D)

# ===========================================================================
# Intégration moteur
# ===========================================================================

func _test_engine_integration() -> void:
	var map := _make_map(_make_materials(), true)
	map["meshes"] = []
	var engine: Control = EngineScript.new()
	engine.size = Vector2(1000, 700)
	get_root().add_child(engine)
	_nodes.append(engine)
	await _wait_frames(3)
	engine.configure(map, [], [], [], [], [], false, true)
	await _wait_frames(8)

	var cell: float = float(engine.get_cell_size())
	_assert("engine_cell_size", is_equal_approx(cell, 0.7))
	_assert("engine_terrain3d", engine.is_terrain3d_ground())
	_assert("engine_splat_active", engine.is_terrain_splat_active())
	_assert("engine_gound_splat", engine._ground != null and engine._ground.is_splat_active())
	_assert("engine_materials_count", engine.get_terrain_materials().size() == W * H)
	_assert("engine_splat_size",
		engine._ground.get_splat_texture() != null
		and engine._ground.get_splat_texture().get_width() == W
		and engine._ground.get_splat_texture().get_height() == H)
	_assert("engine_splat_pixel_stone",
		_splat_pixel(engine._ground, 2, 0).is_equal_approx(Color(0, 0, 1, 1)))

	# Peinture (pinceau) : le document met à jour terrainMaterials, puis on
	# appelle refresh_terrain(map_data) → le splat suit sans recharger la carte.
	var painted := _make_materials()
	painted[0 * W + 2] = 0
	map["terrainMaterials"] = painted
	engine.refresh_terrain(map)
	await _wait_frames(2)
	_assert("engine_refresh_materials",
		_splat_pixel(engine._ground, 2, 0).is_equal_approx(Color(1, 0, 0, 1)),
		"pixel=%s" % [str(_splat_pixel(engine._ground, 2, 0))])
	_assert("engine_refresh_relief_kept", engine.terrain_has_relief())

	# API directe (outils/tests) : set_terrain_materials.
	engine.set_terrain_materials(_flat_materials(2))
	await _wait_frames(1)
	_assert("engine_set_materials",
		_splat_pixel(engine._ground, 0, 0).is_equal_approx(Color(0, 0, 1, 1)))
	_assert("engine_get_materials", engine.get_terrain_materials().size() == W * H)
	_assert("engine_set_materials_kept_splat", engine.is_terrain_splat_active())

	# Carte sans terrainMaterials : repli matériau actuel.
	var no_materials := _make_map([], true)
	no_materials["id"] = "terrain-materials-test-nomats"
	engine.configure(no_materials, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_no_materials_fallback", not engine.is_terrain_splat_active())
	_assert("engine_no_materials_standard",
		engine._ground.is_terrain3d()
		and engine._ground._mesh_instance.material_override is StandardMaterial3D)

	# Carte illustrated avec matières : inchangée, aucun splat.
	var illustrated := _make_map(_make_materials(), true, "illustrated")
	illustrated["id"] = "terrain-materials-test-illustrated"
	engine.configure(illustrated, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_illustrated_no_splat", not engine.is_terrain_splat_active())
	_assert("engine_illustrated_flat", _ground_vertex_count(engine._ground) == 12)

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
	print("map_terrain_materials_test:FAIL at ", name, suffix)
	_failed = true
