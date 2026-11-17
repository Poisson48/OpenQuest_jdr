extends SceneTree

## Tests du brouillard par polygone de visibilité (étape 2).
##
## Couvre : le module géométrique pur (`visibility_polygon.gd`), l'intégration
## `MapVision.visible_cells_polygonal` / `is_point_visible`, l'ouverture de
## porte et le recalcul du brouillard côté `GameData`.
##
##   godot --headless --path game -s res://scripts/tests/visibility_polygon_test.gd

var Poly: GDScript
var Vision: GDScript

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	Poly = load("res://scripts/core/los/visibility_polygon.gd")
	Vision = load("res://scripts/maps/map_vision.gd")
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")

	_test_fallback_circle()
	_test_closed_room()
	_test_radius_clip()
	_test_cells_and_points()
	_test_doors()
	_test_corridor()
	_test_gamedata_integration(md, gd)

	if _failed:
		quit(1)
		return
	print("visibility_polygon_test:PASS")
	quit(0)

# ===========================================================================
# Outillage
# ===========================================================================

func _wall(x: float, y: float, length: float, rotation: float, extra: Dictionary = {}) -> Dictionary:
	var wall := {
		"id": "wall-%d" % randi(),
		"kind": "wall", "x": x, "y": y, "w": length, "h": 0.25,
		"height": 1.4, "blocksSight": true,
		"display": {"rotation": rotation},
	}
	wall.merge(extra, true)
	return wall

func _map(walls: Array, width: int = 20, height: int = 20) -> Dictionary:
	return {"id": "poly-map", "width": width, "height": height, "walls": walls}

func _room_walls() -> Array:
	# Pièce 6×6 : murs de (2,2) à (8,8).
	return [
		_wall(5.0, 2.0, 6.0, 0.0),
		_wall(5.0, 8.0, 6.0, 0.0),
		_wall(2.0, 5.0, 6.0, 90.0),
		_wall(8.0, 5.0, 6.0, 90.0),
	]

func _segments(walls: Array) -> Array:
	return Vision.wall_segments(_map(walls))

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("visibility_polygon_test:FAIL at ", name)
		_failed = true

# ===========================================================================
# Module pur
# ===========================================================================

func _test_fallback_circle() -> void:
	var polygon: PackedVector2Array = Poly.compute(Vector2.ZERO, [], 3.0)
	_assert("circle_points", polygon.size() >= 40)
	var radius_ok := true
	for point in polygon:
		if absf((point as Vector2).length() - 3.0) > 0.002:
			radius_ok = false
	_assert("circle_radius", radius_ok)
	_assert("circle_contains_near", Poly.contains(polygon, Vector2(1.0, 1.0)))
	_assert("circle_excludes_far", not Poly.contains(polygon, Vector2(3.5, 0.0)))

func _test_closed_room() -> void:
	var segments := _segments(_room_walls())
	var polygon: PackedVector2Array = Poly.compute(Vector2(5, 5), segments, 20.0)
	_assert("room_points", polygon.size() >= 8)
	_assert("room_contains_self", Poly.contains(polygon, Vector2(5, 5)))
	_assert("room_contains_near", Poly.contains(polygon, Vector2(7.5, 7.5)))
	_assert("room_excludes_left", not Poly.contains(polygon, Vector2(1.0, 5.0)))
	_assert("room_excludes_right", not Poly.contains(polygon, Vector2(9.0, 5.0)))

	var box: Rect2 = Poly.bounding_box(polygon)
	_assert("room_box_min", box.position.x >= 1.9 and box.position.y >= 1.9)
	_assert("room_box_max", box.end.x <= 8.1 and box.end.y <= 8.1)

func _test_radius_clip() -> void:
	var polygon: PackedVector2Array = Poly.compute(Vector2(10, 10), [], 2.0)
	_assert("radius_contains", Poly.contains(polygon, Vector2(11.5, 10.0)))
	_assert("radius_excludes", not Poly.contains(polygon, Vector2(12.5, 10.0)))
	var far_ok := true
	for point in polygon:
		if (point as Vector2).distance_to(Vector2(10, 10)) > 2.002:
			far_ok = false
	_assert("radius_bounded", far_ok)

# ===========================================================================
# Intégration MapVision
# ===========================================================================

func _test_cells_and_points() -> void:
	var map := _map([_wall(5.0, 5.0, 6.0, 0.0)])
	var sources: Array = [{"pos": Vector2(5, 2), "radius": 8.0}]
	var polygons: Array = Vision.visibility_polygons(map, sources)
	_assert("polygon_count", polygons.size() == 1)
	var polygon: PackedVector2Array = polygons[0]
	_assert("polygon_shape", polygon.size() > 20)
	_assert("polygon_self", Poly.contains(polygon, Vector2(5, 2)))
	_assert("polygon_before_wall", Poly.contains(polygon, Vector2(5, 4)))
	_assert("polygon_shadow", not Poly.contains(polygon, Vector2(5, 8)))
	_assert("polygon_beyond_radius", not Poly.contains(polygon, Vector2(5, 11)))

	_assert("point_visible", Vision.is_point_visible(map, sources, Vector2(5, 4)))
	_assert("point_hidden", not Vision.is_point_visible(map, sources, Vector2(5, 8)))
	_assert("point_out_of_radius", not Vision.is_point_visible(map, sources, Vector2(5, 11)))

	# Deux sources : l'union couvre les deux côtés du mur.
	var both: Array = Vision.visibility_polygons(map, [
		{"pos": Vector2(5, 2), "radius": 5.0},
		{"pos": Vector2(5, 8), "radius": 5.0},
	])
	_assert("polygon_union_count", both.size() == 2)
	_assert("polygon_union_covers", Poly.contains_any(both, Vector2(5, 2)) and Poly.contains_any(both, Vector2(5, 8)))

	# Rayon nul : aucune source utile.
	_assert("polygon_zero_radius", Vision.visibility_polygons(map, [{"pos": Vector2(5, 2), "radius": 0.0}]).is_empty())

func _test_doors() -> void:
	var closed := _map([_wall(5.0, 5.0, 6.0, 0.0, {"id": "door-1", "isDoor": true, "open": false})])
	var opened: Dictionary = Vision.apply_door_states(closed, {"door-1": true})
	var poly_closed: PackedVector2Array = Poly.compute(Vector2(5, 2), Vision.wall_segments(closed), 8.0)
	var poly_open: PackedVector2Array = Poly.compute(Vector2(5, 2), Vision.wall_segments(opened), 8.0)
	_assert("door_closed_blocks_polygon", not Poly.contains(poly_closed, Vector2(5, 8)))
	_assert("door_open_reveals_polygon", Poly.contains(poly_open, Vector2(5, 8)))

func _test_corridor() -> void:
	# Deux murs avec une ouverture entre x=5 et x=7.
	var map := _map([
		_wall(4.0, 5.0, 2.0, 0.0),
		_wall(8.0, 5.0, 2.0, 0.0),
	])
	var sources: Array = [{"pos": Vector2(6, 2), "radius": 9.0}]
	_assert("corridor_through_gap", Vision.is_point_visible(map, sources, Vector2(6, 8)))
	_assert("corridor_left_blocked", not Vision.is_point_visible(map, sources, Vector2(3.5, 8)))
	_assert("corridor_right_blocked", not Vision.is_point_visible(map, sources, Vector2(8.5, 8)))

# ===========================================================================
# Intégration GameData (brouillard dynamique)
# ===========================================================================

func _test_gamedata_integration(md, gd) -> void:
	var map: Dictionary = md.create_complex_map("Polygone LOS", "general", "local", 20, 20)
	var map_id: String = map.get("id", "")
	map["losEnabled"] = true
	map["walls"] = [_wall(5.0, 5.0, 6.0, 0.0, {"id": "door-1", "isDoor": true, "open": false})]
	md.update_map(map)

	gd.active_game = {
		"id": "test-polygon", "status": "playing", "scenarioId": "demo-couronne-fracturee",
		"mapIds": [map_id], "gmType": "ai",
		"party": [{"id": "hero-1", "name": "Aria", "hp": 12, "isPlayer": true, "clientId": "player-a"}],
		"mapPlayState": {}, "mapNavigation": {"view": "world"}, "mapModeOverrides": {},
	}
	gd.ensure_map_play_state()
	var entry: Dictionary = gd.get_map_play_entry(map_id)
	entry["tokens"] = [{"id": "tok-a", "x": 5.0, "y": 2.0, "kind": "member", "memberId": "hero-1"}]
	entry["fogRevealed"] = []

	var visible: Array = gd.recompute_dynamic_fog(map_id)
	_assert("gd_visible_self", visible.has("5,2"))
	_assert("gd_visible_near", visible.has("5,4"))
	_assert("gd_hidden_behind_door", not visible.has("5,8"))
	_assert("gd_fog_memory", gd.get_fog_revealed_cells(map_id).has("5,2"))

	var polygons: Array = gd.get_map_visibility_polygons(map_id)
	_assert("gd_polygon_count", polygons.size() == 1)
	_assert("gd_polygon_shape", polygons.size() == 1 and (polygons[0] as PackedVector2Array).size() >= 8)

	# La porte ouverte laisse passer la vision (et le brouillard se met à jour).
	gd.apply_map_op(map_id, {"type": gd.MAP_OP_DOOR, "doorId": "door-1", "open": true})
	gd.recompute_dynamic_fog(map_id)
	_assert("gd_door_opened", gd.is_door_open(map_id, "door-1"))
	_assert("gd_visible_through_door", gd.get_visible_now_cells(map_id).has("5,8"))
	_assert("gd_fog_revealed_door", gd.get_fog_revealed_cells(map_id).has("5,8"))

	# Le brouillard reste une mémoire après fermeture.
	gd.apply_map_op(map_id, {"type": gd.MAP_OP_DOOR, "doorId": "door-1", "open": false})
	gd.recompute_dynamic_fog(map_id)
	_assert("gd_memory_after_close", gd.get_fog_revealed_cells(map_id).has("5,8"))
	_assert("gd_now_closed", not gd.get_visible_now_cells(map_id).has("5,8"))
