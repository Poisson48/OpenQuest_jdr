extends SceneTree

## Tests de la clôture procédurale : mesh non vide, hauteur, longueur.

var FenceScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	FenceScript = load("res://scripts/maps/construction/procedural_fence_mesh.gd")
	var mesh = FenceScript.build([Vector2(0, 0), Vector2(3, 1), Vector2(5, 3)], 0.9, 1.0)
	_assert("fence_mesh", mesh != null and mesh.get_surface_count() > 0)
	var aabb: AABB = mesh.get_aabb()
	_assert("fence_height", aabb.size.y >= 0.8)
	_assert("fence_span", aabb.size.x >= 4.5)
	_assert("fence_empty", FenceScript.build([], 0.9, 1.0).get_surface_count() == 0)
	var element: Dictionary = {
		"points": [[0.0, 0.0], [2.0, 0.5], [4.0, 2.0]],
		"height": 1.1, "spacing": 0.8,
	}
	_assert("fence_element", FenceScript.build_from_element(element).get_surface_count() > 0)

	if _failed:
		print("procedural_fence_test:FAIL")
		quit(1)
		return
	print("procedural_fence_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
