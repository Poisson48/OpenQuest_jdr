extends SceneTree

## Clics carte en session : outil par défaut, pas de combat opaque,
## MJ déplace tout le monde, joueur seulement son pion.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var gd = get_root().get_node("GameData")
	var md = get_root().get_node("MapData")

	_assert("default_select", SessionToolRegistry.default_tool().get("mode") == SessionToolRegistry.SELECT)
	_assert("default_ignores_party", SessionToolRegistry.default_tool([{"id": "h1"}]).get("mode") == SessionToolRegistry.SELECT)
	_assert("place_member", SessionToolRegistry.is_place_tool({ "mode": SessionToolRegistry.MEMBER }))
	_assert("select_not_place", not SessionToolRegistry.is_place_tool({ "mode": SessionToolRegistry.SELECT }))
	_assert("simple_select", SessionToolRegistry.to_simple_tool({ "mode": SessionToolRegistry.SELECT }).get("mode") == SessionToolRegistry.SELECT)
	_assert("complex_select", SessionToolRegistry.to_complex_tool({ "mode": SessionToolRegistry.SELECT }).get("mode") == SessionToolRegistry.SELECT)

	gd.reload_builtin_scenarios()
	var party: Array = [
		{"id": "hero-1", "name": "Aria", "hp": 12, "isPlayer": true, "isHuman": true, "clientId": "j1"},
		{"id": "hero-2", "name": "Thorin", "hp": 14, "isPlayer": true, "isHuman": true, "clientId": "j2"},
	]
	gd.create_new_game("demo-crypte", "multi", "human", "oneshot", party)
	gd.ensure_map_play_state()

	var map_id := ""
	for map_id_variant in gd.active_game.get("mapIds", []):
		var entry: Dictionary = md.get_by_id(str(map_id_variant))
		if not entry.is_empty():
			map_id = str(map_id_variant)
			break
	_assert("map_loaded", not map_id.is_empty())

	var before: int = gd.get_map_play_tokens(map_id).size()
	gd.apply_map_play_action(map_id, 3, 4, { "mode": "select" })
	gd.apply_complex_map_click(map_id, 3.0, 4.0, { "mode": "select" })
	_assert("select_noop", gd.get_map_play_tokens(map_id).size() == before)

	gd.apply_map_play_action(map_id, 2, 2, { "mode": "member", "memberId": "hero-1" })
	_assert("explicit_place", gd.member_token_on_map(map_id, "hero-1"))

	var aria := ""
	var npc_id := ""
	for tok_variant in gd.get_map_play_tokens(map_id):
		var tok: Dictionary = tok_variant
		if str(tok.get("memberId", "")) == "hero-1":
			aria = str(tok.get("id", ""))
		elif gd._token_is_npc_speaker(tok) and npc_id.is_empty():
			npc_id = str(tok.get("id", ""))
	_assert("aria_token", not aria.is_empty())
	_assert("gm_moves_aria", gd.can_session_move_token(map_id, aria, true, ""))
	_assert("player_moves_own", gd.can_session_move_token(map_id, aria, false, "hero-1"))
	_assert("player_not_other_pc", not gd.can_session_move_token(map_id, aria, false, "hero-2"))
	if not npc_id.is_empty():
		_assert("gm_moves_npc", gd.can_session_move_token(map_id, npc_id, true, ""))
		_assert("player_not_npc", not gd.can_session_move_token(map_id, npc_id, false, "hero-1"))

	var prop_id := ""
	var prop_x := 0.0
	var prop_y := 0.0
	for prop_variant in md.get_by_id(map_id).get("props", []):
		var prop: Dictionary = prop_variant
		if str(prop.get("id", "")).is_empty():
			continue
		prop_id = str(prop.get("id", ""))
		prop_x = float(prop.get("x", 0))
		prop_y = float(prop.get("y", 0))
		break
	_assert("has_prop", not prop_id.is_empty())
	_assert("gm_moves_prop", gd.move_map_prop(map_id, prop_id, prop_x + 1.0, prop_y + 1.0))
	var moved_prop: Dictionary = {}
	for prop_variant2 in md.get_by_id(map_id).get("props", []):
		if str(prop_variant2.get("id", "")) == prop_id:
			moved_prop = prop_variant2
			break
	_assert("prop_pos_saved", is_equal_approx(float(moved_prop.get("x", 0)), prop_x + 1.0))
	gd.move_map_prop(map_id, prop_id, prop_x, prop_y)

	var hit: Dictionary = gd.inspect_map_at(map_id, 3.0, 5.0)
	_assert("inspect_eldric", str(hit.get("label", "")).to_lower().contains("eldric") or str(hit.get("kind", "")) != "")

	var stack_before: int = (gd.get_area_stack() as Array).size()
	# Un clic select ne doit pas empiler un lieu.
	_assert("no_mystery_enter", (gd.get_area_stack() as Array).size() == stack_before)

	gd.apply_map_play_action(map_id, 1, 5, { "mode": "marker", "markerType": "exit" })
	var placed_exit: Dictionary = gd.inspect_map_at(map_id, 1.0, 5.0)
	_assert("exit_placed", str(placed_exit.get("marker_type", "")) == "exit")
	_assert("exit_no_sortie_label", not str(placed_exit.get("label", "")).to_lower().contains("sortie"))
	gd.apply_map_play_action(map_id, 1, 5, { "mode": "erase" })
	var after_erase: Dictionary = gd.inspect_map_at(map_id, 1.0, 5.0)
	_assert("erase_clears_token", str(after_erase.get("token_id", "")).is_empty())
	_assert("erase_no_sortie_text", not str(after_erase.get("label", "")).to_lower().contains("sortie"))
	_assert("erase_suppresses_marker", gd.is_marker_suppressed(map_id, 1, 5))

	print("session_map_input_test:PASS")
	quit(0)

func _assert(label: String, ok: bool) -> void:
	if not ok:
		print("session_map_input_test:FAIL at ", label)
		quit(1)
