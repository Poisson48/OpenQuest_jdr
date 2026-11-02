extends SceneTree

## Test Marching Cubes : sphère implicite + champ de hauteur.

var MC: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	MC = load("res://scripts/maps/construction/marching_cubes.gd")
	var sphere = MC.polygonize(Callable(self, "_sphere"), Vector3(-1.3, -1.3, -1.3),
		Vector3(1.3, 1.3, 1.3), Vector3i(18, 18, 18), 0.0)
	_assert("mc_sphere_mesh", sphere != null and sphere.get_surface_count() > 0)
	var aabb: AABB = sphere.get_aabb()
	_assert("mc_sphere_bounds", aabb.size.x > 1.8 and aabb.size.y > 1.8, "aabb=%s" % aabb)

	var terrain = MC.polygonize(Callable(self, "_height"), Vector3(0, -2, 0),
		Vector3(8, 2, 8), Vector3i(24, 12, 24), 0.0)
	_assert("mc_height_field", terrain != null and terrain.get_surface_count() > 0)
	var taabb: AABB = terrain.get_aabb()
	_assert("mc_height_flat", absf(taabb.end.y) < 0.25, "end_y=%.2f" % taabb.end.y)

	if _failed:
		print("marching_cubes_test:FAIL")
		quit(1)
		return
	print("marching_cubes_test:PASS")
	quit(0)

func _sphere(p: Vector3) -> float:
	return 1.0 - p.length()

func _height(p: Vector3) -> float:
	# Surface y=0 : intérieur = sous le sol.
	return -p.y

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
