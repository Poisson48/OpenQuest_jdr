extends SceneTree

## Test du toit libre sur emprise irrégulière.

var RoofScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	RoofScript = load("res://scripts/maps/construction/procedural_poly_roof.gd")
	var l_shape: Array = [
		Vector2(0, 0), Vector2(6, 0), Vector2(6, 2),
		Vector2(3, 2), Vector2(3, 5), Vector2(0, 5),
	]
	var mesh = RoofScript.build(l_shape, 1.3)
	_assert("poly_roof_mesh", mesh != null and mesh.get_surface_count() > 0)
	var aabb: AABB = mesh.get_aabb()
	_assert("poly_roof_height", absf(aabb.end.y - 1.3) < 0.1)
	_assert("poly_roof_span", aabb.size.x >= 5.9 and aabb.size.z >= 4.9)
	_assert("poly_roof_empty", RoofScript.build([Vector2.ZERO, Vector2.ONE], 1.0).get_surface_count() == 0)
	if _failed:
		print("procedural_poly_roof_test:FAIL")
		quit(1)
		return
	print("procedural_poly_roof_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
