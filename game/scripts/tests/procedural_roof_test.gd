extends SceneTree

## Tests du toit procédural : mesh, hauteur de faîtage, débord, orientation.

var RoofScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	RoofScript = load("res://scripts/maps/construction/procedural_roof_mesh.gd")
	var mesh = RoofScript.build(4.0, 3.0, 1.4, 0.4)
	_assert("roof_mesh", mesh != null and mesh.get_surface_count() > 0)
	var aabb: AABB = mesh.get_aabb()
	_assert("roof_height", absf(aabb.end.y - 1.4) < 0.05)
	_assert("roof_overhang_x", aabb.size.x >= 4.7)
	_assert("roof_overhang_z", aabb.size.z >= 3.7)
	_assert("roof_width", aabb.size.x <= 5.2)

	var mesh_z = RoofScript.build(3.0, 5.0, 1.2, 0.3)
	_assert("roof_ridge_along_z", mesh_z.get_aabb().size.z > mesh_z.get_aabb().size.x)
	var element: Dictionary = {
		"w": 5.0, "h": 2.5, "roofHeight": 1.0, "overhang": 0.2,
	}
	var element_mesh = RoofScript.build_from_element(element)
	_assert("roof_element", element_mesh.get_surface_count() > 0)
	var hip = RoofScript.build(5.0, 3.0, 1.2, 0.3, "hip")
	_assert("roof_hip", hip.get_surface_count() > 0)
	_assert("roof_hip_height", absf(hip.get_aabb().end.y - 1.2) < 0.1)

	if _failed:
		print("procedural_roof_test:FAIL")
		quit(1)
		return
	print("procedural_roof_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
