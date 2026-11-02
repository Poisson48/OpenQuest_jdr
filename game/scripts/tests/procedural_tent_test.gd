extends SceneTree

## Test de la tente procédurale du camp.

var TentScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	TentScript = load("res://scripts/maps/construction/procedural_tent_mesh.gd")
	var mesh = TentScript.build(2.2, 2.6, 1.8)
	_assert("tent_mesh", mesh != null and mesh.get_surface_count() > 0)
	var aabb: AABB = mesh.get_aabb()
	_assert("tent_height", absf(aabb.end.y - 1.8) < 0.1)
	_assert("tent_width", aabb.size.x >= 2.0)
	var element: Dictionary = {"w": 3.0, "h": 3.2, "height": 2.0}
	_assert("tent_element", TentScript.build_from_element(element).get_surface_count() > 0)

	if _failed:
		print("procedural_tent_test:FAIL")
		quit(1)
		return
	print("procedural_tent_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
