extends SceneTree

## Test du rocher Marching Cubes.

var RockScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	RockScript = load("res://scripts/maps/construction/procedural_rock_mesh.gd")
	var mesh = RockScript.build(42, 12)
	_assert("rock_mesh", mesh != null and mesh.get_surface_count() > 0)
	var aabb: AABB = mesh.get_aabb()
	_assert("rock_sits_on_ground", aabb.position.y >= -0.01, "min_y=%.3f" % aabb.position.y)
	_assert("rock_size", aabb.size.x > 0.8 and aabb.size.y > 0.4, "size=%s" % aabb.size)
	if _failed:
		print("procedural_rock_test:FAIL")
		quit(1)
		return
	print("procedural_rock_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
