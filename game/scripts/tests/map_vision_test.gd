extends SceneTree

## Tests de la ligne de vue, du brouillard dynamique, des portes,
## des opérations de carte synchronisées et des portraits de token.

var VisionScript: GDScript
var DocScript: GDScript

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	VisionScript = load("res://scripts/maps/map_vision.gd")
	DocScript = load("res://scripts/maps/editor/map_edit_document.gd")
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")

	_test_segments()
	_test_line_of_sight()
	_test_field_of_view()
	_test_doors()
	_test_dynamic_fog(md, gd)
	_test_map_ops(md, gd)
	_test_player_filter(md, gd)
	_test_token_portraits(md)

	if _failed:
		quit(1)
		return
	print("map_vision_test:PASS")
	quit(0)

# ===========================================================================

## Mur horizontal de 6 cases centré en (5, 5) : il court de x=2 à x=8.
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
	return {"id": "vision-map", "width": width, "height": height, "walls": walls}

func _test_segments() -> void:
	var wall := _wall(5.0, 5.0, 6.0, 0.0)
	var segment: Dictionary = VisionScript.segment_of(wall)
	_assert("seg_a", (segment["a"] as Vector2).is_equal_approx(Vector2(2.0, 5.0)))
	_assert("seg_b", (segment["b"] as Vector2).is_equal_approx(Vector2(8.0, 5.0)))
	_assert("seg_blocks", bool(segment["blocks"]))

	var vertical: Dictionary = VisionScript.segment_of(_wall(5.0, 5.0, 4.0, 90.0))
	_assert("seg_vertical", absf((vertical["a"] as Vector2).x - 5.0) < 0.001)
	_assert("seg_vertical_span", absf((vertical["b"] as Vector2).y - 7.0) < 0.001)

	_assert("seg_zero_length", (VisionScript.segment_of(_wall(1.0, 1.0, 0.0, 0.0)) as Dictionary).is_empty())

	# Un mur non bloquant ou masqué sort de la liste des occulteurs.
	var mixed := _map([
		_wall(5.0, 5.0, 6.0, 0.0),
		_wall(5.0, 8.0, 6.0, 0.0, {"blocksSight": false}),
		_wall(5.0, 9.0, 6.0, 0.0, {"hidden": true}),
	])
	_assert("seg_filter_blocking", (VisionScript.wall_segments(mixed) as Array).size() == 1)
	_assert("seg_all", (VisionScript.wall_segments(mixed, false) as Array).size() == 3)

func _test_line_of_sight() -> void:
	var map := _map([_wall(5.0, 5.0, 6.0, 0.0)])
	# De part et d'autre du mur : bloqué.
	_assert("los_blocked", not VisionScript.has_line_of_sight(map, Vector2(5, 2), Vector2(5, 8)))
	# Du même côté : dégagé.
	_assert("los_clear_same_side", VisionScript.has_line_of_sight(map, Vector2(3, 2), Vector2(7, 2)))
	# En contournant par l'extrémité du mur (le mur s'arrête à x=8).
	_assert("los_around", VisionScript.has_line_of_sight(map, Vector2(12, 2), Vector2(12, 8)))
	# Sans mur, tout est visible.
	_assert("los_no_walls", VisionScript.has_line_of_sight(_map([]), Vector2(0, 0), Vector2(19, 19)))

func _test_field_of_view() -> void:
	var map := _map([_wall(5.0, 5.0, 6.0, 0.0)])
	var visible: Array = VisionScript.visible_cells(map, Vector2(5, 2), 6.0)
	_assert("fov_self", visible.has("5,2"))
	_assert("fov_near_side", visible.has("5,4"))
	_assert("fov_shadowed", not visible.has("5,7"))
	_assert("fov_not_beyond_radius", not visible.has("5,19"))

	# Sans mur, le champ est un disque plein.
	var open_map := _map([])
	var open_visible: Array = VisionScript.visible_cells(open_map, Vector2(10, 10), 3.0)
	_assert("fov_open_count", open_visible.size() > 20)
	_assert("fov_open_reaches", open_visible.has("13,10"))
	_assert("fov_open_stops", not open_visible.has("14,10"))

	# Deux sources : l'union couvre les deux côtés du mur.
	var both: Array = VisionScript.visible_cells_multi(map, [
		{"pos": Vector2(5, 2), "radius": 5.0},
		{"pos": Vector2(5, 8), "radius": 5.0},
	])
	_assert("fov_union", both.has("5,2") and both.has("5,8"))

	# Rayon nul : aucune source utile.
	_assert("fov_zero_radius", (VisionScript.visible_cells(map, Vector2(5, 2), 0.0) as Array).is_empty())

func _test_doors() -> void:
	var closed := _wall(5.0, 5.0, 6.0, 0.0, {"id": "door-1", "isDoor": true, "open": false})
	var map := _map([closed])
	_assert("door_listed", (VisionScript.doors(map) as Array).size() == 1)
	_assert("door_blocks_when_shut", not VisionScript.has_line_of_sight(map, Vector2(5, 2), Vector2(5, 8)))

	# L'ouverture est un fait de partie, pas une modification de la carte.
	var opened: Dictionary = VisionScript.apply_door_states(map, {"door-1": true})
	_assert("door_clear_when_open", VisionScript.has_line_of_sight(opened, Vector2(5, 2), Vector2(5, 8)))
	_assert("door_map_untouched", not VisionScript.has_line_of_sight(map, Vector2(5, 2), Vector2(5, 8)))

	_assert("door_near", not (VisionScript.door_near(map, Vector2(5.2, 5.1), 1.0) as Dictionary).is_empty())
	_assert("door_far", (VisionScript.door_near(map, Vector2(15, 15), 1.0) as Dictionary).is_empty())

	# Sources de vision : les marqueurs n'éclairent pas.
	var sources: Array = VisionScript.vision_sources_from_tokens([
		{"kind": "member", "x": 1.0, "y": 1.0, "memberId": "hero-1"},
		{"kind": "marker", "x": 2.0, "y": 2.0, "memberId": "hero-2"},
		{"kind": "member", "x": 3.0, "y": 3.0, "memberId": "hero-3", "providesVision": false},
		{"kind": "member", "x": 4.0, "y": 4.0, "memberId": "hero-4", "hidden": true},
		{"kind": "member", "x": 6.0, "y": 6.0},
		{"kind": "member", "x": 7.0, "y": 7.0, "providesVision": true},
	])
	_assert("vision_sources_party_only", sources.size() == 2)

func _test_dynamic_fog(md, gd) -> void:
	var map: Dictionary = md.create_complex_map("Vision LOS", "general", "local", 20, 20)
	var map_id: String = map.get("id", "")
	map["losEnabled"] = true
	map["walls"] = [_wall(5.0, 5.0, 6.0, 0.0)]
	md.update_map(map)

	gd.active_game = {
		"id": "test-vision", "status": "playing", "scenarioId": "demo-couronne-fracturee",
		"mapIds": [map_id], "gmType": "ai",
		"party": [{"id": "hero-1", "name": "Aria", "hp": 12, "isPlayer": true, "clientId": "player-a"}],
		"mapPlayState": {}, "mapNavigation": {"view": "world"}, "mapModeOverrides": {},
	}
	gd.ensure_map_play_state()
	_assert("los_flag", gd.is_los_enabled(map_id))

	var entry: Dictionary = gd.get_map_play_entry(map_id)
	entry["tokens"] = [{"id": "tok-a", "x": 5.0, "y": 2.0, "kind": "member", "memberId": "hero-1"}]
	entry["fogRevealed"] = []

	var visible: Array = gd.recompute_dynamic_fog(map_id)
	_assert("fog_dyn_some", visible.size() > 0)
	_assert("fog_dyn_self", visible.has("5,2"))
	_assert("fog_dyn_shadow", not visible.has("5,8"))
	_assert("fog_dyn_written", gd.get_fog_revealed_cells(map_id).has("5,2"))
	_assert("fog_visible_now", gd.get_visible_now_cells(map_id).has("5,2"))

	# Le brouillard est une mémoire : ce qui a été vu le reste après un
	# déplacement, même hors du champ de vision courant.
	gd.move_complex_token(map_id, "tok-a", 15.0, 15.0)
	_assert("fog_memory", gd.get_fog_revealed_cells(map_id).has("5,2"))
	_assert("fog_now_moved", not gd.get_visible_now_cells(map_id).has("5,2"))
	_assert("fog_now_new", gd.get_visible_now_cells(map_id).has("15,15"))

func _test_map_ops(md, gd) -> void:
	var map: Dictionary = md.create_complex_map("Ops carte", "general", "local", 20, 20)
	var map_id: String = map.get("id", "")
	map["losEnabled"] = true
	map["walls"] = [_wall(5.0, 5.0, 6.0, 0.0, {"id": "door-x", "isDoor": true, "open": false})]
	md.update_map(map)

	gd.active_game = {
		"id": "test-ops", "status": "playing", "scenarioId": "demo-couronne-fracturee",
		"mapIds": [map_id], "gmType": "ai",
		"party": [
			{"id": "hero-1", "name": "Aria", "hp": 12, "isPlayer": true, "clientId": "player-a"},
			{"id": "hero-2", "name": "Brand", "hp": 12, "isPlayer": true, "clientId": "player-b"},
		],
		"mapPlayState": {}, "mapNavigation": {"view": "world"}, "mapModeOverrides": {},
	}
	gd.ensure_map_play_state()
	var entry: Dictionary = gd.get_map_play_entry(map_id)
	entry["tokens"] = [
		{"id": "tok-a", "x": 1.0, "y": 1.0, "kind": "member", "memberId": "hero-1"},
		{"id": "tok-b", "x": 2.0, "y": 1.0, "kind": "member", "memberId": "hero-2"},
	]

	# Déplacement.
	_assert("op_move", gd.apply_map_op(map_id, {
		"type": gd.MAP_OP_MOVE_TOKEN, "tokenId": "tok-a", "x": 7.0, "y": 3.0,
	}))
	_assert("op_move_applied", float(gd.get_map_play_tokens(map_id)[0].get("x", 0)) == 7.0)
	_assert("op_move_unknown", not gd.apply_map_op(map_id, {
		"type": gd.MAP_OP_MOVE_TOKEN, "tokenId": "inconnu", "x": 1.0, "y": 1.0,
	}))

	# Brouillard.
	gd.apply_map_op(map_id, {"type": gd.MAP_OP_FOG_REVEAL, "cells": ["0,0", "1,0"]})
	_assert("op_fog_reveal", gd.get_fog_revealed_cells(map_id).has("0,0"))
	gd.apply_map_op(map_id, {"type": gd.MAP_OP_FOG_HIDE, "cells": ["0,0"]})
	_assert("op_fog_hide", not gd.get_fog_revealed_cells(map_id).has("0,0"))

	# Portes : bascule et recalcul du champ de vision.
	_assert("op_door_shut", not gd.is_door_open(map_id, "door-x"))
	gd.apply_map_op(map_id, {"type": gd.MAP_OP_DOOR, "doorId": "door-x", "open": true})
	_assert("op_door_open", gd.is_door_open(map_id, "door-x"))
	_assert("op_door_los", gd.has_line_of_sight(map_id, Vector2(5, 2), Vector2(5, 8)))
	gd.apply_map_op(map_id, {"type": gd.MAP_OP_DOOR, "doorId": "door-x", "open": false})
	_assert("op_door_los_shut", not gd.has_line_of_sight(map_id, Vector2(5, 2), Vector2(5, 8)))
	_assert("op_door_toggle", gd.toggle_map_door(map_id, "door-x"))
	_assert("op_door_toggled_state", gd.is_door_open(map_id, "door-x"))

	# Sélection et effets.
	gd.apply_map_op(map_id, {"type": gd.MAP_OP_SELECT, "tokenId": "tok-b"})
	_assert("op_select", gd.get_selected_token_id(map_id) == "tok-b")
	var fx: Dictionary = gd.place_map_effect(map_id, "fire", 3.0, 3.0, 1.0)
	gd.apply_map_op(map_id, {"type": gd.MAP_OP_EFFECT_TRIGGER, "effectId": str(fx.get("id", "")), "triggered": true})
	_assert("op_effect", bool(gd.get_map_effects(map_id)[0].get("triggered", false)))

	# Opération inconnue refusée.
	_assert("op_unknown", not gd.apply_map_op(map_id, {"type": "n_importe_quoi"}))

	# Autorité : hors P2P tout est permis (partie solo / MJ IA).
	_assert("auth_solo", gd.can_apply_map_op(map_id, {
		"type": gd.MAP_OP_PLACE, "x": 1.0, "y": 1.0, "tool": {"mode": "marker", "markerType": "npc"},
	}, "player-a"))
	_assert("auth_owner_listed", gd._player_owns_token(map_id, "tok-a", "player-a"))
	_assert("auth_not_owner", not gd._player_owns_token(map_id, "tok-a", "player-b"))
	_assert("auth_unknown_token", not gd._player_owns_token(map_id, "inconnu", "player-a"))
	_assert("auth_player_ops", gd.PLAYER_ALLOWED_OPS.has(gd.MAP_OP_MOVE_TOKEN))
	_assert("auth_place_not_player", not gd.PLAYER_ALLOWED_OPS.has(gd.MAP_OP_PLACE))

func _test_player_filter(md, gd) -> void:
	var map: Dictionary = md.create_complex_map("Filtre joueur", "general", "local", 20, 20)
	var map_id: String = map.get("id", "")
	map["losEnabled"] = true
	map["fogEnabled"] = true
	map["walls"] = [_wall(5.0, 5.0, 6.0, 0.0)]
	md.update_map(map)

	gd.active_game = {
		"id": "test-filtre", "status": "playing", "scenarioId": "demo-couronne-fracturee",
		"mapIds": [map_id], "gmType": "ai",
		"party": [{"id": "hero-1", "name": "Aria", "hp": 12, "isPlayer": true, "clientId": "player-a"}],
		"mapPlayState": {}, "mapNavigation": {"view": "world"}, "mapModeOverrides": {},
	}
	gd.ensure_map_play_state()
	var entry: Dictionary = gd.get_map_play_entry(map_id)
	entry["tokens"] = [
		{"id": "tok-hero", "x": 5.0, "y": 2.0, "kind": "member", "memberId": "hero-1"},
		{"id": "tok-vu", "x": 5.0, "y": 3.0, "kind": "member", "label": "Gobelin visible"},
		{"id": "tok-cache", "x": 5.0, "y": 9.0, "kind": "member", "label": "Gobelin embusqué"},
		{"id": "tok-secret", "x": 5.0, "y": 1.0, "kind": "member", "label": "Piège", "gmOnly": true},
	]
	entry["effects"] = [
		{"id": "fx-1", "x": 1.0, "y": 1.0, "preset": "fire"},
		{"id": "fx-2", "x": 2.0, "y": 2.0, "preset": "magic", "gmOnly": true},
	]
	entry["zones"] = [{"id": "z-1", "x": 1.0, "y": 1.0, "radius": 1.0, "gmOnly": true}]
	gd.recompute_dynamic_fog(map_id)

	var gm_view: Dictionary = gd.filter_map_entry_for_player(map_id, true)
	_assert("filter_gm_all_tokens", (gm_view["tokens"] as Array).size() == 4)
	_assert("filter_gm_all_effects", (gm_view["effects"] as Array).size() == 2)
	_assert("filter_gm_all_zones", (gm_view["zones"] as Array).size() == 1)

	var player_view: Dictionary = gd.filter_map_entry_for_player(map_id, false)
	var ids: Array = []
	for token_variant in player_view["tokens"]:
		ids.append(str((token_variant as Dictionary).get("id", "")))
	_assert("filter_keeps_own", ids.has("tok-hero"))
	_assert("filter_keeps_visible", ids.has("tok-vu"))
	_assert("filter_hides_shadowed", not ids.has("tok-cache"))
	_assert("filter_hides_gm_only", not ids.has("tok-secret"))
	_assert("filter_effects", (player_view["effects"] as Array).size() == 1)
	_assert("filter_zones", (player_view["zones"] as Array).is_empty())
	# La vue filtrée est une copie : le MJ ne perd rien.
	_assert("filter_no_mutation", gd.get_map_play_tokens(map_id).size() == 4)

func _test_token_portraits(md) -> void:
	# Source d'import : un PNG genere pour le test.
	var source := "user://test-portrait-source.png"
	var seed_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	seed_img.fill(Color(0.2, 0.6, 0.9, 1.0))
	seed_img.save_png(source)

	var dest: String = md.import_token_image(source)
	_assert("portrait_import", not dest.is_empty() and FileAccess.file_exists(dest))
	_assert("portrait_listed", (md.list_token_images() as Array).has(dest))

	var texture = md.load_token_portrait(dest)
	_assert("portrait_texture", texture != null)
	if texture != null:
		_assert("portrait_square", texture.get_width() == texture.get_height())
		var img: Image = texture.get_image()
		# Le disque est découpé : les coins sont transparents, le centre non.
		_assert("portrait_corner_clear", img.get_pixel(1, 1).a < 0.01)
		_assert("portrait_center_opaque", img.get_pixel(img.get_width() / 2, img.get_height() / 2).a > 0.5)

	_assert("portrait_missing", md.load_token_portrait("user://inexistant.png") == null)
	_assert("portrait_empty_path", md.load_token_portrait("") == null)
	_assert("portrait_import_missing", md.import_token_image("res://inexistant.png").is_empty())

	DirAccess.remove_absolute(dest)
	DirAccess.remove_absolute(source)

# ===========================================================================

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("map_vision_test:FAIL at ", name)
		_failed = true
