extends SceneTree

## Les scènes générées contiennent des rochers empilés du kit, posés par assises
## et appliqués comme vrais éléments mesh dans le document.

const ROW_STEP := 0.48
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test rochers générés", "general", "local", 30, 20)
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["lighting"] = {"enabled": false, "preset": "tiny_glade", "sources": []}
	md.update_map(map)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1280, 720)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(md.get_by_id(str(map.get("id", ""))))
	await process_frame

	editor._scene_style = "village"
	editor._scene_seed = 4242
	editor._scene_density = 1.0
	editor._construction._generate_scene(Vector2(15.0, 10.0))
	await process_frame

	var kit_assets := {}
	for elem_variant in editor.doc.elements_of_kind("mesh"):
		var elem: Dictionary = elem_variant
		if str(elem.get("label", "")) != "Rocher généré":
			continue
		kit_assets[str(elem.get("asset", ""))] = true
	_assert("scene_rocks_count", kit_assets.size() >= 2, "assets=%d" % kit_assets.size())
	for asset_variant in kit_assets.keys():
		var asset := str(asset_variant)
		# Les rochers viennent des assets du projet (rocher / gros_rocher / falaise).
		_assert("rocks_from_project", asset.contains("rocher") or asset.contains("falaise"), asset)
		_assert("rock_asset_exists", ResourceLoader.exists(asset), asset)

	# Une seconde génération avec la même graine doit produire le même plan.
	var plan_a: Dictionary = ProceduralSceneGenerator.generate("foret", 30, 20, 77, 1.0)
	var plan_b: Dictionary = ProceduralSceneGenerator.generate("foret", 30, 20, 77, 1.0)
	var rocks_a: Array = plan_a.get("rocks", [])
	var rocks_b: Array = plan_b.get("rocks", [])
	_assert("forest_has_rocks", rocks_a.size() > 0, "count=%d" % rocks_a.size())
	_assert("forest_deterministic", rocks_a.size() == rocks_b.size())
	# En forêt, l'affleurement fait trois assises.
	var max_elevation := 0.0
	var min_elevation := INF
	for rock_variant in rocks_a:
		var rock: Dictionary = rock_variant
		max_elevation = maxf(max_elevation, float(rock.get("elevation", 0.0)))
		min_elevation = minf(min_elevation, float(rock.get("elevation", 0.0)))
	_assert("forest_has_stacked_rows", max_elevation > ROW_STEP, "max=%.2f" % max_elevation)
	_assert("forest_has_bottom_row", is_equal_approx(min_elevation, 0.0), "min=%.3f" % min_elevation)

	if _failed:
		print("scene_rocks_test:FAIL")
		quit(1)
		return
	print("scene_rocks_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	_failed = true
	print("  FAIL %s %s" % [name, detail])
