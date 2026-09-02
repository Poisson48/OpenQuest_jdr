extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var ok := true
	var gd: Node = get_root().get_node("GameData")
	gd.active_game = {
		"id": "test-semantic",
		"status": "playing",
		"scenarioId": "demo-couronne-fracturee",
		"mapIds": ["demo-monde-couronne", "demo-taverne"],
		"party": [{
			"id": "hero-1", "name": "Aria", "isPlayer": true, "isHuman": true,
		}],
		"mapPlayState": {},
		"mapNavigation": { "view": "world", "localMapId": null },
	}
	gd.ensure_map_play_state()
	gd.init_all_world_map_fog()
	gd._ensure_party_tokens_on_world_maps()

	var map_id := "demo-monde-couronne"
	var pos: Vector2i = gd.get_member_token_position(map_id, "hero-1")
	ok = ok and pos.x == 22 and pos.y == 18

	var forest_action := "je vais vers la foret la plus proche"
	ok = ok and gd.try_auto_move_from_action(forest_action)
	var pos2: Vector2i = gd.get_member_token_position(map_id, "hero-1")
	ok = ok and (pos2.x != pos.x or pos2.y != pos.y)

	gd.place_member_token(map_id, 22, 18, "hero-1")
	var tavern_action := "jecoute les indications de torval et vais dans l auberge pres de la capital"
	ok = ok and gd.try_auto_move_from_action(tavern_action)
	var pos3: Vector2i = gd.get_member_token_position(map_id, "hero-1")
	ok = ok and (pos3.x != 22 or pos3.y != 18)

	print("semantic_move_test:", "PASS" if ok else "FAIL", " start=", pos, " forest=", pos2, " tavern=", pos3)
	quit(0 if ok else 1)
