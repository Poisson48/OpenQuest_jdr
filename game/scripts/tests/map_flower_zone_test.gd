extends SceneTree

## Tests de la zone fleurie procédurale : mesh non vide, bornes du polygone,
## déterminisme de la graine et types de fleurs.

var FlowerScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	FlowerScript = load("res://scripts/maps/construction/procedural_flower_zone.gd")
	var square: Array = [
		Vector2(-2.0, -2.0), Vector2(2.0, -2.0),
		Vector2(2.0, 2.0), Vector2(-2.0, 2.0),
	]
	var mesh = FlowerScript.build(square, "coquelicot", 3.0, 0.22, 42)
	_assert("flower_mesh", mesh != null and mesh.get_surface_count() > 0)
	var aabb: AABB = mesh.get_aabb()
	_assert("flower_bounds_x", aabb.position.x >= -2.3 and aabb.end.x <= 2.3)
	_assert("flower_bounds_z", aabb.position.z >= -2.3 and aabb.end.z <= 2.3)
	_assert("flower_height", aabb.size.y > 0.0 and aabb.size.y < 1.0)

	var mesh_again = FlowerScript.build(square, "coquelicot", 3.0, 0.22, 42)
	_assert("flower_deterministic", mesh.get_surface_count() == mesh_again.get_surface_count())
	_assert("flower_different_seed", mesh.get_aabb().size != FlowerScript.build(square, "coquelicot", 3.0, 0.22, 43).get_aabb().size)

	var marguerite: Array = FlowerScript.FLOWER_TYPES
	_assert("flower_type_count", marguerite.size() >= 5)
	_assert("flower_label", FlowerScript.type_label("lavande") == "Lavande")
	_assert("flower_empty_zone", FlowerScript.build([], "mix", 3.0, 0.2, 1).get_surface_count() == 0)

	# Élément de carte : points locaux + type/densité/graine.
	var element: Dictionary = {
		"points": [[-2.0, -2.0], [2.0, -2.0], [2.0, 2.0], [-2.0, 2.0]],
		"flowerType": "marguerite", "density": 2.0, "size": 0.2, "seed": 7,
	}
	var element_mesh = FlowerScript.build_from_element(element)
	_assert("flower_element_mesh", element_mesh != null and element_mesh.get_surface_count() > 0)

	if _failed:
		print("map_flower_zone_test:FAIL")
		quit(1)
		return
	print("map_flower_zone_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
