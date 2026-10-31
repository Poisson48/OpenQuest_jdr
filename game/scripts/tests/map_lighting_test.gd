extends SceneTree

## Éclairage des zones de démo : foyer/lanternes de la taverne, torches/brasier
## du donjon, et création effective des OmniLight3D par le moteur.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = boot.build_demo(md)
	var tavern: Dictionary = {}
	var dungeon: Dictionary = {}
	for map_variant in demo.get("world_maps", []):
		if not map_variant is Dictionary:
			continue
		var title := str((map_variant as Dictionary).get("title", ""))
		if title.contains("Taverne"):
			tavern = map_variant
		elif title.contains("Donjon"):
			dungeon = map_variant
	_assert("tavern_found", not tavern.is_empty())
	_assert("dungeon_found", not dungeon.is_empty())
	if _failed:
		_finish()
		return
	var tavern_lighting: Dictionary = md.get_lighting_config(tavern)
	var dungeon_lighting: Dictionary = md.get_lighting_config(dungeon)
	_assert("tavern_lighting_enabled", bool(tavern_lighting.get("enabled", false)))
	_assert("tavern_sources", (tavern_lighting.get("sources", []) as Array).size() == 2)
	_assert("dungeon_lighting_enabled", bool(dungeon_lighting.get("enabled", false)))
	_assert("dungeon_sources", (dungeon_lighting.get("sources", []) as Array).size() == 3)
	var dungeon_sources: Array = dungeon_lighting.get("sources", [])
	_assert("dungeon_brazier", str((dungeon_sources[2] as Dictionary).get("id", "")) == "donjon-brasier")

	var engine = (load("res://scripts/maps/complex_map_engine_3d.gd") as GDScript).new()
	engine.size = Vector2(960, 540)
	get_root().add_child(engine)
	await process_frame
	engine.configure(dungeon, [], [], [], [], [], false, true, {"mode": "select"})
	for _i in range(8):
		await process_frame
	_assert("dungeon_lights_built", engine._lights_layer != null
		and engine._lights_layer.get_child_count() >= 3)
	_assert("dungeon_sun", engine._sun != null and engine._sun.visible)
	engine.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	if _failed:
		print("map_lighting_test:FAIL")
		quit(1)
		return
	print("map_lighting_test:PASS")
	quit(0)

var _failed := false

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
