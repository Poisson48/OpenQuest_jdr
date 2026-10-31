extends SceneTree

## Déplacement sémantique : « va vers la forêt / l'auberge » déplace le pion
## d'une case vers le lieu correspondant, sur une carte autonome.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var ok := true
	var md = get_root().get_node("MapData")
	var gd: Node = get_root().get_node("GameData")
	var map: Dictionary = md.create_complex_map("Test déplacement sémantique", "general", "local", 20, 15)
	var map_id := str(map.get("id", ""))
	# Forêt = cases de tuiles dédiées ; auberge = marqueur nommé.
	var tiles: Array = map.get("tiles", [])
	for y in range(4, 8):
		for x in range(15, 19):
			tiles[y * 20 + x] = "forest"
	map["tiles"] = tiles
	map["markers"] = [
		{"id": "mk-taverne", "type": "poi", "label": "Taverne du Corbeau", "x": 3, "y": 12},
		{"id": "mk-foret", "type": "poi", "label": "Forêt", "x": 17, "y": 5},
	]
	map["fogEnabled"] = false
	md.update_map(map)

	gd.active_game = {
		"id": "test-semantic",
		"status": "playing",
		"scenarioId": "demo-valbois",
		"mapIds": [map_id],
		"party": [{
			"id": "hero-1", "name": "Aria", "isPlayer": true, "isHuman": true,
		}],
		"mapPlayState": {},
		"mapNavigation": { "view": "local", "localMapId": map_id },
	}
	gd.ensure_map_play_state()
	gd.place_member_token(map_id, 5, 5, "hero-1")

	var pos: Vector2i = gd.get_member_token_position(map_id, "hero-1")
	ok = ok and pos.x == 5 and pos.y == 5

	var forest_action := "je vais vers la foret la plus proche"
	ok = ok and gd.try_auto_move_from_action(forest_action)
	var pos2: Vector2i = gd.get_member_token_position(map_id, "hero-1")
	ok = ok and (pos2.x != pos.x or pos2.y != pos.y)

	gd.place_member_token(map_id, 5, 5, "hero-1")
	var tavern_action := "j'écoute les indications de Torval et vais dans l'auberge près de la capitale"
	ok = ok and gd.try_auto_move_from_action(tavern_action)
	var pos3: Vector2i = gd.get_member_token_position(map_id, "hero-1")
	ok = ok and (pos3.x != 5 or pos3.y != 5)

	md.delete_map(map_id)
	print("semantic_move_test:", "PASS" if ok else "FAIL", " start=", pos,
		" forest=", pos2, " tavern=", pos3)
	quit(0 if ok else 1)
