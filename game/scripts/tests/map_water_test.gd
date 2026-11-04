extends SceneTree

## Tests des plans d'eau (lacs, étangs, douves) de la carte 2.5D :
##   • `MapWater3D` : aucun rendu par défaut (waterLevel = -1), plan créé à la
##     bonne hauteur quand des cases sont immergées, retiré si niveau < 0 ou si
##     aucune case n'est sous l'eau, texture de profondeur, shader translucide
##     animé, teinte de nuit, marge d'emprise ;
##   • mise à jour du niveau et des hauteurs (immersion recalculée) ;
##   • `MapGround3D` expose la hauteur par case (`get_cell_height`,
##     `count_cells_below`) ;
##   • intégration moteur : `configure`, `refresh_terrain`, API
##     `set_water_level`/`get_water_level`/`is_water_active`, retrait en mode
##     `illustrated`, carte sans eau.
##
## Autonome : le moteur est chargé par `load()` (il référence l'autoload MapData).

const WaterScript := preload("res://scripts/maps/map_layers/map_water_3d.gd")
const WaterShader := preload("res://shaders/water_surface.gdshader")

const W := 8
const H := 8
const CELL := 1.0
## Fond du bassin de test : 3×3 cases à -0.8 case sous un plateau à 0.6 case.
const PLATEAU_HEIGHT := 0.6
const BASIN_HEIGHT := -0.8

var EngineScript: GDScript

var _failed: bool = false
var _nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	EngineScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	if EngineScript == null:
		print("map_water_test:FAIL at engine_load")
		_failed = true
		quit(1)
		return

	await _test_water_layer_basics()
	await _test_water_layer_updates()
	await _test_water_layer_night()
	await _test_water_decor()
	await _test_ground_exposes_heights()
	await _test_engine_integration()

	for node in _nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await _wait_frames(3)

	if _failed:
		quit(1)
		return
	print("map_water_test:PASS")
	quit(0)

# ===========================================================================
# Données de test
# ===========================================================================

## Hauteurs : plateau à 0.6, bassin 3×3 à -0.8 au centre. Sans bassin : plateau.
func _make_heights(with_basin: bool = true) -> Array:
	var heights: Array = []
	heights.resize(W * H)
	heights.fill(PLATEAU_HEIGHT)
	if with_basin:
		for cy in range(3, 6):
			for cx in range(3, 6):
				heights[cy * W + cx] = BASIN_HEIGHT
	return heights

func _make_map(water_level: Variant, with_basin: bool = true, ground_mode: String = "terrain3d") -> Dictionary:
	var map := {
		"id": "water-test",
		"name": "Water test",
		"width": W,
		"height": H,
		"grid": {"size": 70},
		"renderStyle": "2.5d",
		"fogEnabled": false,
		"layers": [],
		"groundMode": ground_mode,
		"terrainHeights": _make_heights(with_basin),
	}
	if water_level != null:
		map["waterLevel"] = water_level
	return map

func _make_water() -> Node3D:
	var water = WaterScript.new()
	get_root().add_child(water)
	_nodes.append(water)
	return water

func _mesh_aabb_size(water) -> Vector3:
	var mesh = water._mesh_instance.mesh
	if mesh == null:
		return Vector3.ZERO
	return (mesh as Mesh).get_aabb().size

# ===========================================================================
# Calque d'eau : activation, position, profondeur, matériau
# ===========================================================================

func _test_water_layer_basics() -> void:
	var water = _make_water()
	await _wait_frames(2)
	_assert("default_no_water", not water.is_active())
	_assert("default_level", is_equal_approx(water.get_water_level(), -1.0))

	# --- Niveau >= 0 avec bassin : plan actif, à la bonne hauteur.
	water.configure(W, H, CELL, 0.0, _make_heights(true), false)
	_assert("water_active", water.is_active())
	_assert("water_level", is_equal_approx(water.get_water_level(), 0.0))
	_assert("water_surface_y", is_equal_approx(water.get_surface_y(), 0.0))
	_assert("water_mesh", water._mesh_instance.mesh != null)
	_assert("water_visible", water.visible and water._mesh_instance.visible)
	_assert("water_submerged_count", water.get_submerged_cell_count() == 9,
		"count=%d" % water.get_submerged_cell_count())
	_assert("water_cell_submerged", water.is_cell_submerged(4, 4))
	_assert("water_cell_dry", not water.is_cell_submerged(0, 0))
	_assert("water_out_of_bounds_dry", not water.is_cell_submerged(-1, 4))
	_assert("water_max_depth", is_equal_approx(water.get_max_depth(), 0.8),
		"max_depth=%f" % water.get_max_depth())

	# Marge minime (0.05 case par côté) : emprise = (w + 0.1) × (h + 0.1) cases.
	var margin_cells := 0.1
	_assert("water_extent", water.get_water_extent().is_equal_approx(
		Vector2(W + margin_cells, H + margin_cells)),
		"extent=%s" % [str(water.get_water_extent())])
	_assert("water_mesh_extent",
		absf(_mesh_aabb_size(water).x - (W + margin_cells)) < 0.001
		and absf(_mesh_aabb_size(water).z - (H + margin_cells)) < 0.001,
		"aabb=%s" % [str(_mesh_aabb_size(water))])
	_assert("water_depth_texture", water.get_depth_texture() != null)
	if water.get_depth_texture() != null:
		_assert("water_depth_size",
			water.get_depth_texture().get_width() == W and water.get_depth_texture().get_height() == H)
	var depth: Image = water.get_depth_image()
	_assert("water_depth_image", depth != null)
	if depth != null:
		_assert("water_depth_shore", is_zero_approx(depth.get_pixel(0, 0).r))
		_assert("water_depth_deep", is_equal_approx(depth.get_pixel(4, 4).r, 1.0))
		_assert("water_depth_land", is_zero_approx(depth.get_pixel(7, 7).r))

	# --- Matériau : shader translucide animé, textures/paramètres branchés.
	var mat = water._mesh_instance.material_override
	_assert("water_material_shader", mat is ShaderMaterial)
	if mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = mat
		_assert("water_shader", shader_mat.shader == WaterShader)
		_assert("water_depth_param", shader_mat.get_shader_parameter("depth_map") is Texture2D)
		_assert("water_shallow_param", shader_mat.get_shader_parameter("shallow_color") is Color)
		_assert("water_deep_param", shader_mat.get_shader_parameter("deep_color") is Color)
		_assert("water_foam_param", shader_mat.get_shader_parameter("foam_color") is Color)
		var alpha = shader_mat.get_shader_parameter("base_alpha")
		_assert("water_alpha", alpha is float and float(alpha) >= 0.7 and float(alpha) <= 0.9,
			"alpha=%s" % [str(alpha)])
		var wave_speed = shader_mat.get_shader_parameter("wave_speed")
		_assert("water_wave_speed", wave_speed is float and float(wave_speed) > 0.0)
		_assert("water_day_tint",
			(shader_mat.get_shader_parameter("night_tint") as Color).is_equal_approx(Color.WHITE))
	_assert("water_no_shadow",
		water._mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	# --- Niveau < 0 : plus aucun plan d'eau.
	water.set_water_level(-1.0)
	_assert("water_removed_negative", not water.is_active())
	_assert("water_removed_mesh", water._mesh_instance.mesh == null)
	_assert("water_removed_hidden", not water._mesh_instance.visible)
	_assert("water_removed_count", water.get_submerged_cell_count() == 0)

	# --- Niveau >= 0 mais aucune case immergée : aucun nœud rendu.
	water.configure(W, H, CELL, 0.6, _make_heights(false), false)
	_assert("water_no_submerged", not water.is_active(),
		"count=%d" % water.get_submerged_cell_count())
	_assert("water_no_submerged_mesh", water._mesh_instance.mesh == null)

	# --- Niveau positif au-dessus du plateau : toute la carte est immergée.
	water.configure(W, H, CELL, 1.2, _make_heights(true), false)
	_assert("water_all_submerged", water.get_submerged_cell_count() == W * H,
		"count=%d" % water.get_submerged_cell_count())
	_assert("water_all_surface_y", is_equal_approx(water.get_surface_y(), 1.2))
	var high_depth: Image = water.get_depth_image()
	if high_depth != null:
		_assert("water_all_depth_center", is_equal_approx(high_depth.get_pixel(4, 4).r, 1.0))
		_assert("water_all_depth_shore_positive", high_depth.get_pixel(0, 0).r > 0.0)

# ===========================================================================
# Mise à jour du niveau et des hauteurs (immersion recalculée)
# ===========================================================================

func _test_water_layer_updates() -> void:
	var water = _make_water()
	await _wait_frames(2)
	water.configure(W, H, CELL, 0.0, _make_heights(true), false)
	_assert("update_initial_active", water.is_active())
	var depth_before: Image = water.get_depth_image()

	# Relief aplati : plus aucune case sous le niveau → plan retiré.
	water.set_terrain_heights(_make_heights(false))
	_assert("update_flat_inactive", not water.is_active())
	# Relief recreusé : le plan revient.
	water.set_terrain_heights(_make_heights(true))
	_assert("update_basin_active", water.is_active())
	_assert("update_depth_refreshed", water.get_depth_image() != null
		and water.get_depth_image() != depth_before)

	# Changement de niveau seul : position en Y et immersion suivent.
	water.set_water_level(1.2)
	_assert("update_level_active", water.is_active())
	_assert("update_level_y", is_equal_approx(water.get_surface_y(), 1.2))
	_assert("update_level_count", water.get_submerged_cell_count() == W * H)
	water.set_water_level(0.0)
	_assert("update_level_back", water.get_submerged_cell_count() == 9)

	# Niveau < 0 puis retour : retire / recrée proprement.
	water.set_water_level(-5.0)
	_assert("update_negative", not water.is_active())
	water.set_water_level(0.0)
	_assert("update_restored", water.is_active() and water._mesh_instance.mesh != null)

# ===========================================================================
# Nuit : teinte sombre sur l'eau
# ===========================================================================

func _test_water_layer_night() -> void:
	var water = _make_water()
	await _wait_frames(2)
	water.configure(W, H, CELL, 0.0, _make_heights(true), true)
	_assert("night_water_active", water.is_active())
	var mat = water._mesh_instance.material_override
	_assert("night_water_shader", mat is ShaderMaterial)
	if mat is ShaderMaterial:
		var tint = (mat as ShaderMaterial).get_shader_parameter("night_tint")
		_assert("night_water_tint", tint is Color
			and not (tint as Color).is_equal_approx(Color.WHITE)
			and (tint as Color).get_luminance() < 0.6)
	water.set_night_mode(false)
	if water._mesh_instance.material_override is ShaderMaterial:
		var day_tint = (water._mesh_instance.material_override as ShaderMaterial).get_shader_parameter("night_tint")
		_assert("night_water_day_tint", (day_tint as Color).is_equal_approx(Color.WHITE))

# ===========================================================================
# Décor de surface : lentilles d'eau + nénuphars
# ===========================================================================

func _make_shallow_heights() -> Array:
	var heights: Array = []
	heights.resize(W * H)
	heights.fill(0.2)
	for cy in range(3, 6):
		for cx in range(3, 6):
			heights[cy * W + cx] = 0.0
	return heights

func _test_water_decor() -> void:
	var water = _make_water()
	await _wait_frames(2)
	# Bassin 3×3 à profondeur 0.1 : assez peu profond pour des nénuphars.
	water.configure(W, H, CELL, 0.1, _make_shallow_heights(), false, 7)
	_assert("decor_active", water.is_active())
	_assert("decor_duckweed", water.get_duckweed_count() > 0,
		"duckweed=%d" % water.get_duckweed_count())
	_assert("decor_lily", water.get_lily_count() > 0,
		"lily=%d" % water.get_lily_count())
	_assert("decor_duckweed_bounded", water.get_duckweed_count() <= 2400)
	_assert("decor_lily_bounded", water.get_lily_count() <= 360)
	# Sans eau : le décor disparaît.
	water.set_water_level(-1.0)
	_assert("decor_cleared", water.get_duckweed_count() == 0 and water.get_lily_count() == 0)

# ===========================================================================
# Le sol expose ses hauteurs par case
# ===========================================================================

func _test_ground_exposes_heights() -> void:
	var ground = load("res://scripts/maps/map_layers/map_ground_3d.gd").new()
	get_root().add_child(ground)
	_nodes.append(ground)
	await _wait_frames(2)
	ground.configure(
		null, W, H, CELL, true, null, false, [], [], 0.22,
		_make_heights(true), "terrain3d", []
	)
	_assert("ground_cell_height_plateau", is_equal_approx(ground.get_cell_height(0, 0), PLATEAU_HEIGHT))
	_assert("ground_cell_height_basin", is_equal_approx(ground.get_cell_height(4, 4), BASIN_HEIGHT))
	_assert("ground_cell_height_out", is_zero_approx(ground.get_cell_height(-1, 4)))
	_assert("ground_terrain_size", ground.get_terrain_size() == Vector2i(W, H))
	_assert("ground_heights_copy", ground.get_terrain_heights().size() == W * H)
	_assert("ground_count_below", ground.count_cells_below(0.0) == 9,
		"count=%d" % ground.count_cells_below(0.0))
	_assert("ground_count_below_high", ground.count_cells_below(1.2) == W * H)

# ===========================================================================
# Intégration moteur
# ===========================================================================

func _test_engine_integration() -> void:
	var map := _make_map(0.0)
	var engine: Control = EngineScript.new()
	engine.size = Vector2(1000, 700)
	get_root().add_child(engine)
	_nodes.append(engine)
	await _wait_frames(3)
	engine.configure(map, [], [], [], [], [], false, true)
	await _wait_frames(8)

	var cell: float = float(engine.get_cell_size())
	_assert("engine_cell_size", is_equal_approx(cell, 0.7))
	_assert("engine_water_layer", engine._water_layer != null)
	_assert("engine_water_active", engine.is_water_active())
	_assert("engine_water_level", is_equal_approx(engine.get_water_level(), 0.0))
	_assert("engine_water_submerged",
		engine._water_layer.get_submerged_cell_count() == 9,
		"count=%d" % engine._water_layer.get_submerged_cell_count())
	_assert("engine_water_surface_y", is_equal_approx(engine._water_layer.get_surface_y(), 0.0))
	_assert("engine_ground_cell_height",
		is_equal_approx(engine._ground.get_cell_height(4, 4), BASIN_HEIGHT))

	# API set_water_level : hauteur monde = niveau * cell_size.
	engine.set_water_level(1.2)
	_assert("engine_set_level", is_equal_approx(engine.get_water_level(), 1.2))
	_assert("engine_set_level_active", engine.is_water_active())
	_assert("engine_set_level_y",
		is_equal_approx(engine._water_layer.get_surface_y(), 1.2 * cell),
		"y=%f" % engine._water_layer.get_surface_y())
	_assert("engine_set_level_all_submerged",
		engine._water_layer.get_submerged_cell_count() == W * H)

	# API set_water_level < 0 : retire le plan d'eau.
	engine.set_water_level(-1.0)
	_assert("engine_set_level_off", not engine.is_water_active())
	_assert("engine_set_level_mesh", engine._water_layer._mesh_instance.mesh == null)

	# refresh_terrain : niveau et hauteurs relus depuis map_data.
	map["waterLevel"] = 0.0
	engine.refresh_terrain(map)
	await _wait_frames(2)
	_assert("engine_refresh_active", engine.is_water_active())
	_assert("engine_refresh_level", is_equal_approx(engine.get_water_level(), 0.0))

	var flat_map := _make_map(0.0, false)
	flat_map["id"] = "water-test-flat"
	engine.refresh_terrain(flat_map)
	await _wait_frames(2)
	_assert("engine_refresh_no_submerged", not engine.is_water_active())

	var deep_map := _make_map(1.0, true)
	deep_map["id"] = "water-test-deep"
	engine.refresh_terrain(deep_map)
	await _wait_frames(2)
	_assert("engine_refresh_deep_active", engine.is_water_active())
	_assert("engine_refresh_deep_level", is_equal_approx(engine.get_water_level(), 1.0))
	_assert("engine_refresh_deep_y",
		is_equal_approx(engine._water_layer.get_surface_y(), 1.0 * cell))

	# Carte sans waterLevel : pas d'eau par défaut.
	var dry_map := _make_map(null)
	dry_map["id"] = "water-test-dry"
	engine.configure(dry_map, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_default_dry", not engine.is_water_active())
	_assert("engine_default_level", engine.get_water_level() < 0.0)

	# Mode illustrated : le calque eau est retiré même si waterLevel >= 0.
	var illustrated := _make_map(0.0, true, "illustrated")
	illustrated["id"] = "water-test-illustrated"
	engine.configure(illustrated, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_illustrated_no_water", not engine.is_water_active())
	_assert("engine_illustrated_water_cleared",
		engine._water_layer._mesh_instance.mesh == null and not engine._water_layer.visible)
	_assert("engine_illustrated_level_kept", is_equal_approx(engine.get_water_level(), 0.0))

	# Nuit : teinte sombre sur le calque d'eau.
	var night_map := _make_map(0.0)
	night_map["id"] = "water-test-night"
	night_map["lighting"] = {"nightMode": true}
	engine.configure(night_map, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_night_water_active", engine.is_water_active())
	if engine._water_layer._mesh_instance.material_override is ShaderMaterial:
		var tint = (engine._water_layer._mesh_instance.material_override as ShaderMaterial).get_shader_parameter("night_tint")
		_assert("engine_night_water_tint", tint is Color
			and not (tint as Color).is_equal_approx(Color.WHITE))

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
	print("map_water_test:FAIL at ", name, suffix)
	_failed = true
