extends SceneTree

## Test de densité de la végétation procédurale (`MapVegetation3D`) :
##   • densité 0 : la couche n'est pas active et `get_vegetation_count() == 0` ;
##   • densité 1 : couche active, instances de touffes et de végétation > 0 ;
##   • densité 2 : `get_vegetation_count()` strictement supérieur à la densité 1.
##
## Scénario : carte 12×12, `cell_size` 1.0, tout en matériau herbe (id 0),
## hauteurs à 0, `water_level` -1 (pas d'eau), `night_mode` false.
##
## Autonome : `MapVegetation3D` ne référence pas l'autoload MapData, donc le
## `preload` est sûr (comme `MapWater3D` dans `map_water_test.gd`).

const VegetationScript := preload("res://scripts/maps/map_layers/map_vegetation_3d.gd")

const W := 12
const H := 12
const CELL := 1.0

var _failed: bool = false
var _nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame

	await _test_density_scaling()

	for node in _nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await _wait_frames(3)

	if _failed:
		print("map_vegetation_density_test:FAIL")
		quit(1)
		return
	print("map_vegetation_density_test:PASS")
	quit(0)

# ===========================================================================
# Données de test
# ===========================================================================

## Hauteurs : carte entièrement plate à 0.
func _make_heights() -> Array:
	var heights: Array = []
	heights.resize(W * H)
	heights.fill(0.0)
	return heights

## Matériaux : toute la carte en herbe (id 0).
func _make_materials() -> Array:
	var materials: Array = []
	materials.resize(W * H)
	materials.fill(0)
	return materials

func _make_vegetation() -> Node3D:
	var veg = VegetationScript.new()
	get_root().add_child(veg)
	_nodes.append(veg)
	return veg

# ===========================================================================
# Densité : 0 (désactivé) → 1 (actif) → 2 (plus dense)
# ===========================================================================

func _test_density_scaling() -> void:
	var veg = _make_vegetation()
	await _wait_frames(2)
	var heights := _make_heights()
	var materials := _make_materials()

	# --- Densité 0 : aucune végétation, couche inactive.
	veg.configure(W, H, CELL, heights, materials, -1.0, false, true, 0.0)
	_assert("density_zero_inactive", not veg.is_active())
	_assert("density_zero_count", veg.get_vegetation_count() == 0,
		"count=%d" % veg.get_vegetation_count())

	# --- Densité 1 : couche active, touffes et végétation présentes.
	veg.configure(W, H, CELL, heights, materials, -1.0, false, true, 1.0)
	_assert("density_one_active", veg.is_active())
	var count_density_one: int = veg.get_vegetation_count()
	_assert("density_one_count", count_density_one > 0,
		"count=%d" % count_density_one)
	_assert("density_one_tufts", veg.get_tuft_count() > 0,
		"tufts=%d" % veg.get_tuft_count())

	# --- Densité 2 : strictement plus d'instances qu'en densité 1.
	veg.configure(W, H, CELL, heights, materials, -1.0, false, true, 2.0)
	_assert("density_two_active", veg.is_active())
	var count_density_two: int = veg.get_vegetation_count()
	_assert("density_two_more_than_one", count_density_two > count_density_one,
		"density1=%d density2=%d" % [count_density_one, count_density_two])

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
	print("map_vegetation_density_test:FAIL at ", name, suffix)
	_failed = true
