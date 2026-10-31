extends SceneTree

## Test d'intégration session : franchissement de bord entre deux zones
## (monde façon Dofus, tailles différentes), transfert du token et bascule de
## carte active.

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
	var NavScript: GDScript = load("res://scripts/session/world_navigation.gd")
	var WorldZonesScript: GDScript = load("res://scripts/maps/world/world_zones.gd")

	var maps: Array = []
	for spec in [
		{"title": "Bord A", "w": 12, "h": 9, "x": 0, "y": 0},
		{"title": "Bord B", "w": 9, "h": 9, "x": 12, "y": 0},
	]:
		var map: Dictionary = md.create_complex_map(str(spec["title"]), "general", "local",
			int(spec["w"]), int(spec["h"]))
		var map_id := str(map.get("id", ""))
		map["renderStyle"] = "2.5d"
		map["groundMode"] = "terrain3d"
		map["backgroundImage"] = ""
		map["worldId"] = "test-edge-world"
		map["zoneX"] = int(spec["x"])
		map["zoneY"] = int(spec["y"])
		map["zoneW"] = int(spec["w"])
		map["zoneH"] = int(spec["h"])
		md.update_map(map)
		_created_maps.append(map_id)
		maps.append(md.get_by_id(map_id))
	var a_id := str(maps[0].get("id", ""))
	var b_id := str(maps[1].get("id", ""))

	# Liens de bords.
	var zones: Array = []
	for map_variant in maps:
		zones.append(WorldZonesScript.zone_from_map(map_variant))
	var links: Dictionary = WorldZonesScript.auto_detect_edges(zones)
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		var stored: Dictionary = md.get_by_id(str(zone.get("id", "")))
		stored["edges"] = links.get(str(zone.get("id", "")), {})
		md.update_map(stored)
	maps[0] = md.get_by_id(a_id)
	maps[1] = md.get_by_id(b_id)

	# Session simulée : la carte A est active, un héros y est posé au bord est.
	gd.active_game = {
		"id": "test-edge-session", "status": "playing", "scenarioId": "demo-couronne-fracturee",
		"mapIds": [a_id, b_id], "currentMapId": a_id, "gmType": "ai",
		"party": [{"id": "hero-1", "name": "Aria", "portrait": ""}],
		"mapPlayState": {}, "mapModeOverrides": {},
		"mapNavigation": {"view": "local", "localMapId": a_id},
	}
	gd.ensure_map_play_state()
	gd.place_complex_member_token(a_id, 11.0, 4.0, "hero-1")
	var tokens_a: Array = gd.get_map_play_tokens(a_id)
	_assert("token_placed", tokens_a.size() == 1)
	var token_id := str((tokens_a[0] as Dictionary).get("id", ""))
	_assert("token_id", not token_id.is_empty())

	# Résolution + bascule de carte.
	var result: Dictionary = NavScript.resolve_edge_transition(maps, a_id, "east", Vector2(11.0, 4.0))
	_assert("resolve_ok", bool(result.get("ok", false)))
	_assert("resolve_target", str(result.get("target_map_id", "")) == b_id)
	var target_pos: Vector2 = result.get("position", Vector2.ZERO)
	_assert("transition_applied", gd.transition_map_edge(b_id, token_id, target_pos))
	_assert("active_map_changed", gd.get_active_play_map_id() == b_id)
	_assert("token_left_old_map", gd.get_map_play_tokens(a_id).is_empty())
	var tokens_b: Array = gd.get_map_play_tokens(b_id)
	_assert("token_arrived", tokens_b.size() == 1)
	if tokens_b.size() == 1:
		var moved: Dictionary = tokens_b[0]
		_assert("token_same_id", str(moved.get("id", "")) == token_id)
		_assert("token_entry_x", float(moved.get("x", 99.0)) <= 0.001)
		_assert("token_entry_in_bounds", float(moved.get("y", -1.0)) >= 0.0
			and float(moved.get("y", -1.0)) <= 8.0)

	# Bord sans voisin : refus.
	_assert("no_neighbor_refused", not bool(NavScript.resolve_edge_transition(
		maps, a_id, "north", Vector2(4.0, 0.0)).get("ok", false)))

	# Nettoyage.
	for map_id in _created_maps:
		md.delete_map(str(map_id))
	gd.active_game = _saved_game

	if _failed:
		print("world_edge_session_test:FAIL")
		quit(1)
		return
	print("world_edge_session_test:PASS")
	quit(0)

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
