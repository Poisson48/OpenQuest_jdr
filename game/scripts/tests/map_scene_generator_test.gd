extends SceneTree

## Tests du générateur de scène : déterminisme, bornes, non-chevauchement.

var GenScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	GenScript = load("res://scripts/maps/construction/procedural_scene_generator.gd")
	var village: Dictionary = GenScript.generate("village", 30, 20, 42, 1.0)
	var houses: Array = village["houses"]
	_assert("village_houses", houses.size() >= 2, "count=%d" % houses.size())
	_assert("village_paths", (village["paths"] as Array).size() > 0)
	_assert("village_fences", (village["fences"] as Array).size() > 0)
	_assert("village_props", (village["props"] as Array).size() > 0)
	var within := true
	for rect_variant in houses:
		var rect: Rect2 = rect_variant
		if rect.position.x < 0.0 or rect.position.y < 0.0 \
				or rect.end.x > 30.0 or rect.end.y > 20.0:
			within = false
	_assert("village_bounds", within)
	var overlap := false
	for i in range(houses.size()):
		for j in range(i + 1, houses.size()):
			if (houses[i] as Rect2).intersects(houses[j]):
				overlap = true
	_assert("village_no_overlap", not overlap)

	var village2: Dictionary = GenScript.generate("village", 30, 20, 42, 1.0)
	_assert("village_deterministic", houses.size() == (village2["houses"] as Array).size()
		and (village["props"] as Array).size() == (village2["props"] as Array).size())
	var other: Dictionary = GenScript.generate("village", 30, 20, 43, 1.0)
	_assert("village_seed_changes", str(village["houses"]) != str(other["houses"]))

	var forest: Dictionary = GenScript.generate("foret", 30, 20, 7, 1.0)
	_assert("forest_props", (forest["props"] as Array).size() > 5)
	_assert("forest_clearing_path", (forest["paths"] as Array).size() > 0)
	var camp: Dictionary = GenScript.generate("camp", 30, 20, 7, 1.0)
	_assert("camp_props", (camp["props"] as Array).size() > 0)
	_assert("invalid_small", (GenScript.generate("village", 4, 4, 1).get("houses", []) as Array).is_empty())

	if _failed:
		print("map_scene_generator_test:FAIL")
		quit(1)
		return
	print("map_scene_generator_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
