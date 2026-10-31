extends SceneTree

## Tests de la carte du monde de session : bascule de zone active (voyage rapide),
## découverte persistante et overlay (zones, zone courante).

var _failed := false
var _created_maps: Array = []
var _saved_game: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")
	_saved_game = gd.active_game.duplicate(true)

	var maps: Array = []
	for spec in [
		{"title": "Monde A", "w": 12, "h": 9, "x": 0, "y": 0},
		{"title": "Monde B", "w": 9, "h": 9, "x": 12, "y": 0},
		{"title": "Monde C", "w": 15, "h": 12, "x": 0, "y": 9},
	]:
		var map: Dictionary = md.create_complex_map(str(spec["title"]), "general", "local",
			int(spec["w"]), int(spec["h"]))
		var map_id := str(map.get("id", ""))
		map["renderStyle"] = "2.5d"
		map["groundMode"] = "terrain3d"
		map["backgroundImage"] = ""
		map["worldId"] = "test-worldmap"
		map["zoneX"] = int(spec["x"])
		map["zoneY"] = int(spec["y"])
		map["zoneW"] = int(spec["w"])
		map["zoneH"] = int(spec["h"])
		md.update_map(map)
		_created_maps.append(map_id)
		maps.append(md.get_by_id(map_id))
	var a_id := str(maps[0].get("id", ""))
	var b_id := str(maps[1].get("id", ""))
	var c_id := str(maps[2].get("id", ""))

	gd.active_game = {
		"id": "test-worldmap", "status": "playing", "scenarioId": "demo-couronne-fracturee",
		"mapIds": [a_id, b_id, c_id], "currentMapId": a_id, "gmType": "ai",
		"party": [{"id": "hero-1", "name": "Aria", "portrait": ""}],
		"mapPlayState": {}, "mapModeOverrides": {},
		"mapNavigation": {"view": "local", "localMapId": a_id},
	}
	gd.ensure_map_play_state()

	# Découverte : la carte courante est découverte, les autres non.
	gd.mark_world_zone_discovered(a_id)
	var discovered: Array = gd.get_discovered_world_zones()
	_assert("discovered_current", discovered.has(a_id))
	_assert("not_discovered_b", not discovered.has(b_id))

	# Voyage rapide vers B.
	_assert("travel_b", gd.enter_world_zone(b_id))
	_assert("active_b", gd.get_active_play_map_id() == b_id)
	_assert("b_discovered", gd.get_discovered_world_zones().has(b_id))

	# Voyage vers C.
	_assert("travel_c", gd.enter_world_zone(c_id))
	_assert("active_c", gd.get_active_play_map_id() == c_id)

	# Overlay : 3 zones du monde, zone courante = C, découvertes = A/B/C.
	var OverlayScript: GDScript = load("res://scripts/session/world_map_overlay.gd")
	var overlay: Control = OverlayScript.new()
	get_root().add_child(overlay)
	overlay.size = Vector2(960, 640)
	await process_frame
	overlay.refresh()
	_assert("overlay_ready", overlay.zones.size() == 3)
	_assert("overlay_current", str(overlay.current_id) == c_id)
	_assert("overlay_discovered_3", overlay.discovered.size() >= 3)
	overlay.fit_view()
	_assert("overlay_fit", overlay.zoom > 0.0)
	overlay.queue_free()
	await process_frame

	for map_id in _created_maps:
		md.delete_map(str(map_id))
	gd.active_game = _saved_game

	if _failed:
		print("world_map_test:FAIL")
		quit(1)
		return
	print("world_map_test:PASS")
	quit(0)

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
