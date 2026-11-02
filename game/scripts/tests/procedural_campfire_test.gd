extends SceneTree

## Test du feu de camp procédural.

var FireScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	FireScript = load("res://scripts/maps/construction/procedural_campfire_mesh.gd")
	var mesh = FireScript.build()
	_assert("campfire_mesh", mesh != null and mesh.get_surface_count() > 0)
	var aabb: AABB = mesh.get_aabb()
	_assert("campfire_height", aabb.size.y > 0.5)
	_assert("campfire_width", aabb.size.x > 0.3)
	if _failed:
		print("procedural_campfire_test:FAIL")
		quit(1)
		return
	print("procedural_campfire_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
