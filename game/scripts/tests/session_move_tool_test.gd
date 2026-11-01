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
	var village_entry: Dictionary = gd.get_map_play_entry(village_id)
	(village_entry["tokens"] as Array).append({
		"id": "tok-npc-test", "kind": "npc", "label": "Marchand",
		"x": 12.0, "y": 7.0, "hp": 10, "maxHp": 10,
	})
	gd.save_map_play_and_sync()
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
		var engine = workspace.stage._complex
		_assert("move_hover_layer", engine != null and engine._move_hover_layer != null)
		var before: Vector2i = gd.get_member_token_position(village_id, "move-aria")
		workspace._on_grid_clicked(10.0, 12.0, {"mode": SessionToolRegistry.MOVE})
		await process_frame
		var after: Vector2i = gd.get_member_token_position(village_id, "move-aria")
		_assert("move_tool_moved", after != before)
		_assert("move_tool_target", after.x == 10 and after.y == 12)
		# Animation de marche : le nœud existe et s'anime (arc + poussière).
		var moving_node = engine._token_nodes.get(token_id)
		_assert("move_animation_node", moving_node != null and moving_node.has_method("is_walking"))
		if moving_node != null:
			_assert("move_animation_walking", moving_node.is_walking())
			_assert("move_animation_step_dust", moving_node._dust != null)
			await create_timer(0.9).timeout
			_assert("move_animation_done", not moving_node.is_walking())
		workspace._move_selected_step(Vector2i(1, 0))
		await process_frame
		var stepped: Vector2i = gd.get_member_token_position(village_id, "move-aria")
		_assert("move_arrow_step", stepped.x == 11 and stepped.y == 12)
		# Un bâtiment 3D bloque le déplacement.
		_assert("move_building_blocked", workspace._cell_blocked_by_building(village_id, 7.0, 6.0))
		_assert("move_open_cell", not workspace._cell_blocked_by_building(village_id, 10.0, 12.0))
		# Une case occupée par une autre figurine refuse le déplacement.
		gd.active_game["party"].append({
			"id": "move-bran", "name": "Bran", "class": "Garde", "hp": 15, "isPlayer": true,
			"portrait": "", "image": "", "stats": {},
		})
		gd.place_complex_member_token(village_id, 12.0, 12.0, "move-bran")
		workspace._on_grid_clicked(12.0, 12.0, {"mode": SessionToolRegistry.MOVE})
		await process_frame
		var blocked: Vector2i = gd.get_member_token_position(village_id, "move-aria")
		_assert("move_blocked_occupied", blocked.x == 11 and blocked.y == 12)
		# Clic PNJ : bulle de dialogue.
		_assert("npc_line_marchand", workspace._npc_line("Marchand").contains("marchandises"))
		workspace._on_token_selected("tok-npc-test")
		await process_frame
		_assert("npc_speech_bubble", workspace.stage.speech_bubble_count() >= 1)
		# Passages de zone : fondu (feedback) + pulsation d'arrivée.
		await workspace._fade_to(1.0)
		_assert("transition_fade_dark",
			workspace._fade != null and workspace._fade.visible
			and workspace._fade.color.a > 0.9)
		await workspace._fade_to(0.0)
		_assert("transition_fade_clear",
			workspace._fade == null or not workspace._fade.visible
			or workspace._fade.color.a < 0.01)
		_assert("transition_api", not workspace.is_transitioning())
		workspace._play_arrival_feedback()
		_assert("transition_arrival_pulse", engine.is_arrival_pulse_playing())
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
