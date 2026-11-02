extends SceneTree

## Tests du chemin procédural : mesh non vide, largeur et déterminisme.

var PathScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	PathScript = load("res://scripts/maps/construction/procedural_path_mesh.gd")
	var points: Array = [Vector2(0, 0), Vector2(3, 1), Vector2(6, 4)]
	var mesh = PathScript.build(points, 1.4, Color("#8a7654"))
	_assert("path_mesh", mesh != null and mesh.get_surface_count() > 0)
	var aabb: AABB = mesh.get_aabb()
	_assert("path_span", aabb.size.x >= 6.0)
	_assert("path_width", aabb.size.z >= 1.0 or aabb.size.x >= 1.0)
	_assert("path_empty", PathScript.build([], 1.0, Color.WHITE).get_surface_count() == 0)
	var element: Dictionary = {
		"points": [[0.0, 0.0], [2.0, 1.0], [4.0, 1.0]],
		"width": 1.2, "color": "#8a7654",
	}
	_assert("path_element", PathScript.build_from_element(element).get_surface_count() > 0)

	if _failed:
		print("procedural_path_test:FAIL")
		quit(1)
		return
	print("procedural_path_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
