extends SceneTree

## Tests de la navigation par les bords entre zones (Dofus), zones de tailles
## différentes, avec offsets de bords.

var _failed := false
var _created_maps: Array = []
var NavScript: GDScript
var WorldZonesScript: GDScript

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	NavScript = load("res://scripts/session/world_navigation.gd")
	WorldZonesScript = load("res://scripts/maps/world/world_zones.gd")
	_assert("nav_script", NavScript != null)

	var maps: Array = _make_world([
		{"title": "A", "w": 12, "h": 9, "x": 0, "y": 0},
		{"title": "B", "w": 9, "h": 9, "x": 12, "y": 0},
		{"title": "C", "w": 15, "h": 12, "x": 0, "y": 9},
	])
	_assert("maps_count", maps.size() == 3)

	var a_id := str(maps[0].get("id", ""))
	var b_id := str(maps[1].get("id", ""))
	var c_id := str(maps[2].get("id", ""))

	_assert("can_cross_a", NavScript.can_cross(maps, a_id))

	# Est A → B : entrée par le bord ouest de B.
	var east: Dictionary = NavScript.resolve_edge_transition(maps, a_id, "east", Vector2(11.0, 4.0))
	_assert("east_ok", bool(east.get("ok", false)))
	_assert("east_target", str(east.get("target_map_id", "")) == b_id)
	if bool(east.get("ok", false)):
		var pos: Vector2 = east.get("position", Vector2.ZERO)
		_assert("east_pos_x", pos.x <= 0.001)
		_assert("east_pos_y", absf(pos.y - 4.0) < 1.01)

	# Ouest B → A (retour approximatif).
	var west: Dictionary = NavScript.resolve_edge_transition(maps, b_id, "west", Vector2(0.0, 4.0))
	_assert("west_ok", bool(west.get("ok", false)))
	_assert("west_target", str(west.get("target_map_id", "")) == a_id)
	if bool(west.get("ok", false)):
		var pos: Vector2 = west.get("position", Vector2.ZERO)
		_assert("west_pos_x", pos.x >= 10.9)
		_assert("west_pos_y", absf(pos.y - 4.0) < 1.01)

	# Sud A → C, Nord C → A.
	var south: Dictionary = NavScript.resolve_edge_transition(maps, a_id, "south", Vector2(4.0, 8.0))
	_assert("south_ok", bool(south.get("ok", false)))
	_assert("south_target", str(south.get("target_map_id", "")) == c_id)
	if bool(south.get("ok", false)):
		var pos: Vector2 = south.get("position", Vector2.ZERO)
		_assert("south_pos_y", pos.y <= 0.001)
		_assert("south_pos_x", absf(pos.x - 4.0) < 1.01)

	var north: Dictionary = NavScript.resolve_edge_transition(maps, c_id, "north", Vector2(4.0, 0.0))
	_assert("north_ok", bool(north.get("ok", false)))
	_assert("north_target", str(north.get("target_map_id", "")) == a_id)

	# Bord sans voisin : A.north → refus.
	var none: Dictionary = NavScript.resolve_edge_transition(maps, a_id, "north", Vector2(4.0, 0.0))
	_assert("no_neighbor", not bool(none.get("ok", false)))

	# Zone décalée (offset) : D 6×4 à (15,10) contre C (15×12 en (0,9)).
	var offset_maps: Array = _make_world([
		{"title": "C2", "w": 15, "h": 12, "x": 0, "y": 9},
		{"title": "D", "w": 6, "h": 4, "x": 15, "y": 10},
	])
	_assert("offset_maps", offset_maps.size() == 2)
	var c2_id := str(offset_maps[0].get("id", ""))
	var d_id := str(offset_maps[1].get("id", ""))
	var offset_tr: Dictionary = NavScript.resolve_edge_transition(offset_maps, c2_id, "east", Vector2(14.0, 1.0))
	_assert("offset_ok", bool(offset_tr.get("ok", false)))
	_assert("offset_target", str(offset_tr.get("target_map_id", "")) == d_id)
	if bool(offset_tr.get("ok", false)):
		var pos: Vector2 = offset_tr.get("position", Vector2.ZERO)
		_assert("offset_entry_x", pos.x <= 0.001)
		_assert("offset_entry_y_in_bounds", pos.y >= 0.0 and pos.y <= 3.0)

	# Côté franchi selon la position.
	_assert("side_east", NavScript.edge_side_for_position({"width": 10, "height": 8}, Vector2(10.5, 2.0)) == "east")
	_assert("side_north", NavScript.edge_side_for_position({"width": 10, "height": 8}, Vector2(2.0, -0.5)) == "north")
	_assert("side_inside", NavScript.edge_side_for_position({"width": 10, "height": 8}, Vector2(5.0, 4.0)) == "")

	for map_id in _created_maps:
		get_root().get_node("MapData").delete_map(str(map_id))

	if _failed:
		print("world_navigation_test:FAIL")
		quit(1)
		return
	print("world_navigation_test:PASS")
	quit(0)

## Crée un monde de cartes 2.5D + auto-liens, et renvoie les cartes à jour.
func _make_world(specs: Array) -> Array:
	var md = get_root().get_node("MapData")
	var maps: Array = []
	for spec_variant in specs:
		var spec: Dictionary = spec_variant
		var map: Dictionary = md.create_complex_map(str(spec["title"]), "general", "local",
			int(spec["w"]), int(spec["h"]))
		var map_id := str(map.get("id", ""))
		if map_id.is_empty():
			continue
		map["renderStyle"] = "2.5d"
		map["groundMode"] = "terrain3d"
		map["backgroundImage"] = ""
		map["worldId"] = "test-nav-world"
		map["zoneX"] = int(spec["x"])
		map["zoneY"] = int(spec["y"])
		map["zoneW"] = int(spec["w"])
		map["zoneH"] = int(spec["h"])
		md.update_map(map)
		_created_maps.append(map_id)
		maps.append(md.get_by_id(map_id))
	# Auto-liens sur ce monde, écrits dans les cartes.
	var zones: Array = []
	for map_variant in maps:
		zones.append(WorldZonesScript.zone_from_map(map_variant))
	var links: Dictionary = WorldZonesScript.auto_detect_edges(zones)
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		var stored: Dictionary = md.get_by_id(str(zone.get("id", "")))
		if stored.is_empty():
			continue
		stored["edges"] = links.get(str(zone.get("id", "")), {})
		md.update_map(stored)
	var refreshed: Array = []
	for map_variant in maps:
		refreshed.append(md.get_by_id(str((map_variant as Dictionary).get("id", ""))))
	return refreshed

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
