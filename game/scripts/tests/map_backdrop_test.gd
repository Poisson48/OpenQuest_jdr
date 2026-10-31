extends SceneTree

## Tests du **fond de plateau** (backdrop) de la carte 2.5D :
##   • aucun fond en mode illustré ;
##   • fond actif en mode terrain3d (grand plan QuadMesh centré sous la jupe de
##     falaise, taille > carte, matériau ShaderMaterial procédural unshaded,
##     render_priority très bas, pas d'ombre) ;
##   • teinte de nuit ;
##   • reconstruction après changement de taille / de mode ;
##   • intégration moteur : calque `Backdrop` créé avant `Ground`,
##     `is_backdrop_active()`, `get_backdrop_material()`, `configure`,
##     `refresh_terrain`, bascule de mode.
##
## Autonome : le moteur est chargé par `load()` (il référence l'autoload MapData).

const BackdropScript := preload("res://scripts/maps/map_layers/map_backdrop_3d.gd")

const W := 8
const H := 8
const CELL := 1.0
## Cf. MapBackdrop3D / MapGround3D.
const CLIFF_DEPTH := 2.5
const Y_GAP := 0.5
const SIZE_FACTOR := 4.0

var EngineScript: GDScript

var _failed: bool = false
var _nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	EngineScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	if EngineScript == null:
		print("map_backdrop_test:FAIL at engine_load")
		_failed = true
		quit(1)
		return

	await _test_layer_basics()
	await _test_layer_night()
	await _test_layer_updates()
	await _test_engine_integration()

	for node in _nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await _wait_frames(3)

	if _failed:
		quit(1)
		return
	print("map_backdrop_test:PASS")
	quit(0)

# ===========================================================================
# Données de test
# ===========================================================================

func _make_map(
	width: int = W,
	height: int = H,
	ground_mode: String = "terrain3d",
	night: bool = false
) -> Dictionary:
	var map := {
		"id": "backdrop-test",
		"name": "Backdrop test",
		"width": width,
		"height": height,
		"grid": {"size": 70},
		"renderStyle": "2.5d",
		"fogEnabled": false,
		"layers": [],
		"groundMode": ground_mode,
		"terrainHeights": [],
	}
	if night:
		map["lighting"] = {"nightMode": true}
	return map

func _make_layer() -> Node3D:
	var layer = BackdropScript.new()
	get_root().add_child(layer)
	_nodes.append(layer)
	return layer

# ===========================================================================
# Calque : actif en terrain3d, position/taille/matériau
# ===========================================================================

func _test_layer_basics() -> void:
	var layer = _make_layer()
	await _wait_frames(2)
	_assert("default_inactive", not layer.is_active())
	_assert("default_material", layer.get_material() == null)
	_assert("default_mesh", layer.get_mesh_instance().mesh == null)
	_assert("default_hidden", not layer.get_mesh_instance().visible)

	layer.configure(W, H, CELL, false)
	_assert("active", layer.is_active())
	_assert("visible", layer.get_mesh_instance().visible and layer.visible)
	var mesh = layer.get_mesh_instance().mesh
	_assert("quad_mesh", mesh is QuadMesh)
	var expected_size := maxf(float(W), float(H)) * CELL * SIZE_FACTOR
	if mesh is QuadMesh:
		_assert("quad_size", (mesh as QuadMesh).size.is_equal_approx(
			Vector2(expected_size, expected_size)),
			"size=%s" % [str((mesh as QuadMesh).size)])
	_assert("backdrop_size_api", is_equal_approx(layer.get_backdrop_size(), expected_size))
	_assert("backdrop_size_larger_than_map", layer.get_backdrop_size() > float(W) * CELL)
	_assert("backdrop_y", is_equal_approx(layer.get_backdrop_y(), -(CLIFF_DEPTH + Y_GAP) * CELL))
	_assert("backdrop_under_cliff", layer.get_backdrop_y() < -CLIFF_DEPTH * CELL,
		"y=%f" % layer.get_backdrop_y())
	var pos: Vector3 = layer.get_mesh_instance().position
	_assert("backdrop_centered",
		is_equal_approx(pos.x, float(W) * CELL * 0.5)
		and is_equal_approx(pos.z, float(H) * CELL * 0.5),
		"pos=%s" % [str(pos)])
	_assert("backdrop_y_position", is_equal_approx(pos.y, layer.get_backdrop_y()))
	_assert("backdrop_flat",
		is_equal_approx(layer.get_mesh_instance().rotation_degrees.x, -90.0))
	_assert("backdrop_no_shadow",
		layer.get_mesh_instance().cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	# Matériau : shader procédural unshaded, sans texture, priorité très basse.
	var mat = layer.get_material()
	_assert("material_shader", mat is ShaderMaterial)
	if mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = mat
		_assert("material_has_shader", shader_mat.shader != null)
		if shader_mat.shader != null:
			var code := shader_mat.shader.code
			_assert("shader_unshaded", code.contains("unshaded"))
			_assert("shader_spatial", code.contains("shader_type spatial"))
			_assert("shader_no_texture", not code.contains("sampler2D") and not code.contains("texture("))
		_assert("shader_center_color",
			shader_mat.get_shader_parameter("center_color") is Color)
		_assert("shader_mid_color",
			shader_mat.get_shader_parameter("mid_color") is Color)
		_assert("shader_edge_color",
			shader_mat.get_shader_parameter("edge_color") is Color)
		_assert("material_priority_low", shader_mat.render_priority <= -50,
			"priority=%d" % shader_mat.render_priority)
		_assert("material_day_tint",
			(shader_mat.get_shader_parameter("night_tint") as Color).is_equal_approx(Color.WHITE))

	# Reconfigure identique : pas de reconstruction (même matériau, même mesh).
	var material_before = layer.get_material()
	var mesh_before = layer.get_mesh_instance().mesh
	layer.configure(W, H, CELL, false)
	_assert("noop_keeps_material", layer.get_material() == material_before)
	_assert("noop_keeps_mesh", layer.get_mesh_instance().mesh == mesh_before)

# ===========================================================================
# Nuit : teinte froide sombre
# ===========================================================================

func _test_layer_night() -> void:
	var layer = _make_layer()
	await _wait_frames(2)
	layer.configure(W, H, CELL, true)
	_assert("night_active", layer.is_active())
	var mat = layer.get_material()
	_assert("night_material", mat is ShaderMaterial)
	if mat is ShaderMaterial:
		var tint = (mat as ShaderMaterial).get_shader_parameter("night_tint")
		_assert("night_tint", tint is Color
			and not (tint as Color).is_equal_approx(Color.WHITE)
			and (tint as Color).get_luminance() < 0.6,
			"tint=%s" % [str(tint)])
	# set_night_mode à chaud.
	layer.set_night_mode(false)
	if layer.get_material() is ShaderMaterial:
		var day_tint = (layer.get_material() as ShaderMaterial).get_shader_parameter("night_tint")
		_assert("night_to_day", (day_tint as Color).is_equal_approx(Color.WHITE))

# ===========================================================================
# Changement de taille / clear / invalide
# ===========================================================================

func _test_layer_updates() -> void:
	var layer = _make_layer()
	await _wait_frames(2)
	layer.configure(W, H, CELL, false)
	var quad_before = layer.get_mesh_instance().mesh

	# Taille différente + autre cell_size : plan et position recalculés.
	layer.configure(12, 5, 0.7, false)
	var expected_size := maxf(12.0, 5.0) * 0.7 * SIZE_FACTOR
	_assert("resize_size", is_equal_approx(layer.get_backdrop_size(), expected_size),
		"size=%f" % layer.get_backdrop_size())
	_assert("resize_y", is_equal_approx(layer.get_backdrop_y(), -(CLIFF_DEPTH + Y_GAP) * 0.7))
	_assert("resize_mesh_replaced", layer.get_mesh_instance().mesh != quad_before)
	var pos: Vector3 = layer.get_mesh_instance().position
	_assert("resize_center",
		is_equal_approx(pos.x, 12.0 * 0.7 * 0.5)
		and is_equal_approx(pos.z, 5.0 * 0.7 * 0.5),
		"pos=%s" % [str(pos)])
	var mesh = layer.get_mesh_instance().mesh
	if mesh is QuadMesh:
		_assert("resize_quad", (mesh as QuadMesh).size.is_equal_approx(
			Vector2(expected_size, expected_size)))

	# clear() : plus de fond.
	layer.clear()
	_assert("clear_inactive", not layer.is_active())
	_assert("clear_mesh", layer.get_mesh_instance().mesh == null)
	_assert("clear_hidden", not layer.get_mesh_instance().visible)

	# Reconfigurer après clear refonctionne.
	layer.configure(W, H, CELL, false)
	_assert("restore_after_clear", layer.is_active())

	# Dimensions invalides : désactivé proprement.
	layer.configure(0, 0, CELL, false)
	_assert("invalid_inactive", not layer.is_active())
	_assert("invalid_mesh", layer.get_mesh_instance().mesh == null)

# ===========================================================================
# Intégration moteur
# ===========================================================================

func _test_engine_integration() -> void:
	var map := _make_map()
	var engine: Control = EngineScript.new()
	engine.size = Vector2(1000, 700)
	get_root().add_child(engine)
	_nodes.append(engine)
	await _wait_frames(3)
	engine.configure(map, [], [], [], [], [], false, true)
	await _wait_frames(8)

	_assert("engine_layer", engine._backdrop_layer != null)
	_assert("engine_active", engine.is_backdrop_active())
	var mat = engine.get_backdrop_material()
	_assert("engine_material", mat is ShaderMaterial)
	_assert("engine_layer_before_ground",
		engine._backdrop_layer.get_index() < engine._ground.get_index())
	_assert("engine_layer_name", str(engine._backdrop_layer.name) == "Backdrop")

	var cell: float = float(engine.get_cell_size())
	_assert("engine_cell_size", is_equal_approx(cell, 0.7))
	_assert("engine_backdrop_y",
		is_equal_approx(engine._backdrop_layer.get_backdrop_y(), -(CLIFF_DEPTH + Y_GAP) * cell))
	_assert("engine_backdrop_under_cliff",
		engine._backdrop_layer.get_backdrop_y() < -CLIFF_DEPTH * cell)
	_assert("engine_backdrop_size",
		engine._backdrop_layer.get_backdrop_size() > maxf(W, H) * cell)

	# refresh_terrain après changement de dimensions : plan reconstruit.
	map["width"] = 12
	map["height"] = 10
	engine.refresh_terrain(map)
	await _wait_frames(2)
	_assert("engine_refresh_active", engine.is_backdrop_active())
	_assert("engine_refresh_size",
		is_equal_approx(engine._backdrop_layer.get_backdrop_size(),
			maxf(12.0, 10.0) * cell * SIZE_FACTOR),
		"size=%f" % engine._backdrop_layer.get_backdrop_size())
	_assert("engine_refresh_center",
		is_equal_approx(engine._backdrop_layer.get_mesh_instance().position.x, 12.0 * cell * 0.5))
	_assert("engine_refresh_material",
		engine.get_backdrop_material() is ShaderMaterial)

	# Mode illustré : le fond est retiré.
	var illustrated := _make_map(W, H, "illustrated")
	illustrated["id"] = "backdrop-test-illustrated"
	engine.configure(illustrated, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_illustrated_inactive", not engine.is_backdrop_active())
	_assert("engine_illustrated_material_null", engine.get_backdrop_material() == null)
	_assert("engine_illustrated_mesh",
		engine._backdrop_layer.get_mesh_instance().mesh == null)

	# Bascule à chaud terrain3d ↔ illustré.
	var terrain_map := _make_map()
	terrain_map["id"] = "backdrop-test-terrain"
	engine.configure(terrain_map, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_back_terrain_active", engine.is_backdrop_active())
	engine.set_ground_mode("illustrated")
	await _wait_frames(2)
	_assert("engine_set_mode_illustrated", not engine.is_backdrop_active())
	engine.set_ground_mode("terrain3d")
	await _wait_frames(2)
	_assert("engine_set_mode_terrain", engine.is_backdrop_active())

	# Nuit : fond actif et teinté.
	var night_map := _make_map(W, H, "terrain3d", true)
	night_map["id"] = "backdrop-test-night"
	engine.configure(night_map, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_night_active", engine.is_backdrop_active())
	var night_mat = engine.get_backdrop_material()
	_assert("engine_night_material", night_mat is ShaderMaterial)
	if night_mat is ShaderMaterial:
		var tint = night_mat.get_shader_parameter("night_tint")
		_assert("engine_night_tint", tint is Color
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
	print("map_backdrop_test:FAIL at ", name, suffix)
	_failed = true
