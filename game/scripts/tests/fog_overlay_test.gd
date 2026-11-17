extends SceneTree

## Tests du voile de brouillard « vision courante » (étape 2b).
##
## Vérifie la classification des cases (mémoire révélée vs champ de vision),
## la projection des quads de case, et l'inactivité en vue MJ / brouillard off.
##
##   godot --headless --path game -s res://scripts/tests/fog_overlay_test.gd

const FogOverlayScript := preload("res://scripts/session/panels/fog_overlay.gd")

var _failed := false
var _overlay: Control

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_overlay = FogOverlayScript.new()
	get_root().add_child(_overlay)
	await process_frame

	_test_dim_classification()
	_test_projection()
	_test_gm_and_disabled()
	_test_polygons()
	await _test_stage_wiring()

	_overlay.queue_free()
	if _failed:
		quit(1)
		return
	print("fog_overlay_test:PASS")
	quit(0)

func _test_stage_wiring() -> void:
	var scene = load("res://scenes/session/panels/map_stage.tscn")
	_assert("stage_scene", scene != null)
	if scene == null:
		return
	var stage = scene.instantiate()
	get_root().add_child(stage)
	await process_frame
	_assert("stage_overlay_created", stage.has_method("fog_overlay") and stage.fog_overlay() != null)
	_assert("stage_overlay_hidden_by_default", not stage.fog_overlay().visible)
	stage.queue_free()
	await process_frame

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("fog_overlay_test:FAIL at ", name)
		_failed = true

func _identity_scale(scale: float) -> Callable:
	return func(gx: float, gy: float) -> Vector2:
		return Vector2(gx * scale, gy * scale)

func _test_dim_classification() -> void:
	_overlay.projector = _identity_scale(10.0)
	_overlay.configure(null, {
		"map_id": "map-test",
		"is_gm": false,
		"fog_enabled": true,
		"fog_revealed": ["0,0", "1,0", "2,0", "1,1", "8,8"],
		"visible_now": ["1,0", "1,1"],
		"vision_polygons": [],
	})
	_assert("active_player", _overlay.is_active())
	var dim: Array = _overlay.dim_cells()
	_assert("dim_count", dim.size() == 3)
	_assert("dim_keeps_memory", dim.has("0,0") and dim.has("2,0") and dim.has("8,8"))
	_assert("dim_excludes_visible", not dim.has("1,0") and not dim.has("1,1"))
	_assert("dim_map_id", _overlay.map_id == "map-test")

	# Rien de révélé : rien à assombrir.
	_overlay.apply_state([], ["0,0"], [])
	_assert("dim_empty", _overlay.dim_cells().is_empty())

	# Tout visible : rien à assombrir.
	_overlay.apply_state(["0,0", "1,0"], ["0,0", "1,0"], [])
	_assert("dim_all_visible", _overlay.dim_cells().is_empty())

func _test_projection() -> void:
	_overlay.projector = _identity_scale(10.0)
	_overlay.apply_state([], [], [])
	var quad: PackedVector2Array = _overlay.cell_quad("1,2")
	_assert("quad_size", quad.size() == 4)
	if quad.size() == 4:
		_assert("quad_origin", quad[0].is_equal_approx(Vector2(10.0, 20.0)))
		_assert("quad_x", quad[1].is_equal_approx(Vector2(20.0, 20.0)))
		_assert("quad_xy", quad[2].is_equal_approx(Vector2(20.0, 30.0)))
		_assert("quad_y", quad[3].is_equal_approx(Vector2(10.0, 30.0)))
	_assert("quad_invalid_key", _overlay.cell_quad("bad").is_empty())

func _test_gm_and_disabled() -> void:
	_overlay.projector = _identity_scale(10.0)
	_overlay.configure(null, {
		"map_id": "map-test", "is_gm": true, "fog_enabled": true,
		"fog_revealed": ["0,0"], "visible_now": [], "vision_polygons": [],
	})
	_assert("gm_inactive", not _overlay.is_active())
	_assert("gm_no_dim", _overlay.dim_cells().is_empty())

	_overlay.configure(null, {
		"map_id": "map-test", "is_gm": false, "fog_enabled": false,
		"fog_revealed": ["0,0"], "visible_now": [], "vision_polygons": [],
	})
	_assert("fog_off_inactive", not _overlay.is_active())

func _test_polygons() -> void:
	_overlay.projector = _identity_scale(10.0)
	var square := PackedVector2Array([
		Vector2(1, 1), Vector2(3, 1), Vector2(3, 3), Vector2(1, 3),
	])
	_overlay.configure(null, {
		"map_id": "map-test", "is_gm": false, "fog_enabled": true,
		"fog_revealed": [], "visible_now": [], "vision_polygons": [square],
	})
	_assert("polygon_received", _overlay.polygon_count() == 1)
	# Un polygone d'un seul point est ignoré au rendu (pas de crash).
	_overlay.apply_state([], [], [PackedVector2Array([Vector2.ZERO])])
	_assert("polygon_degenerate_ok", _overlay.polygon_count() == 1)
