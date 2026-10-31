extends SceneTree

## Outil « Déplacer » en session : un clic déplace le personnage sélectionné.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = boot.build_demo(md)
	var village: Dictionary = demo.get("map", {})
	var village_id := str(village.get("id", ""))
	var ids: Array = []
	for map_variant in demo.get("world_maps", []):
		ids.append(str((map_variant as Dictionary).get("id", "")))
	var party := [
		{"id": "move-aria", "name": "Aria", "class": "Aventurière", "hp": 12, "ac": 14,
			"isPlayer": true, "portrait": "", "image": "", "stats": {}},
	]
	gd.create_new_game("demo-valbois", "solo", "human", "oneshot", party.duplicate(true), ids.duplicate())
	gd.ensure_map_play_state()
	gd.active_game["currentMapId"] = village_id
	gd.active_game["mapNavigation"] = {"view": "local", "localMapId": village_id}
	gd.active_game["mapIds"] = ids.duplicate()
	gd.active_game["party"] = party.duplicate(true)
	gd.place_complex_member_token(village_id, 9.0, 7.0, "move-aria")
	# Un token pour un autre membre, non sélectionné.
	gd.place_complex_member_token(village_id, 8.0, 8.0, "move-aria")
	var tokens: Array = gd.get_map_play_tokens(village_id)
	var token_id := ""
	for token_variant in tokens:
		if str((token_variant as Dictionary).get("memberId", "")) == "move-aria":
			token_id = str((token_variant as Dictionary).get("id", ""))
			break
	_assert("token_found", not token_id.is_empty())
	gd.set_selected_token_id(village_id, token_id)
	var session: Node = (load("res://scenes/session/session.tscn") as PackedScene).instantiate()
	get_root().add_child(session)
	if session is Control:
		(session as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for _i in range(30):
		await process_frame
	var workspaces := session.find_children("*", "MapWorkspacePanel", true, false)
	_assert("workspace_found", not workspaces.is_empty())
	if not workspaces.is_empty():
		var workspace = workspaces[0]
		var before: Vector2i = gd.get_member_token_position(village_id, "move-aria")
		workspace._on_grid_clicked(4.0, 4.0, {"mode": SessionToolRegistry.MOVE})
		await process_frame
		var after: Vector2i = gd.get_member_token_position(village_id, "move-aria")
		_assert("move_tool_moved", after != before)
		_assert("move_tool_target", after.x == 4 and after.y == 4)
		workspace._move_selected_step(Vector2i(1, 0))
		await process_frame
		var stepped: Vector2i = gd.get_member_token_position(village_id, "move-aria")
		_assert("move_arrow_step", stepped.x == 5 and stepped.y == 4)
	session.queue_free()
	await process_frame
	if _failed:
		print("session_move_tool_test:FAIL")
		quit(1)
		return
	print("session_move_tool_test:PASS")
	quit(0)

var _failed := false

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
