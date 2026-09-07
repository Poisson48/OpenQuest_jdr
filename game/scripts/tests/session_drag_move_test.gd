extends SceneTree

## Vérifie drag MJ décor + PNJ (sans attendre un hang d'import).

var _failed := false
var _prop_sig := ""
var _prop_pos := Vector2.ZERO
var _tok_sig := ""
var _tok_pos := Vector2.ZERO

func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")

func _watchdog() -> void:
	create_timer(25.0).timeout.connect(func():
		print("session_drag_move_test:TIMEOUT")
		quit(1)
	)

func _run() -> void:
	await process_frame
	var gd = get_root().get_node("GameData")
	var md = get_root().get_node("MapData")
	var mm = get_root().get_node("MultiplayerManager")
	gd.reload_builtin_scenarios()
	gd.create_new_game("demo-crypte", "multi", "human", "long", [
		{"id": "hero-1", "name": "Aria", "hp": 12, "isPlayer": true, "isHuman": true, "clientId": "j1"},
	])
	mm.player_role = "gm"
	mm.is_gm = true
	mm.player_name = "MJ"
	gd.ensure_map_play_state()

	var map_id := "demo-crypte-brumeval"
	var map: Dictionary = md.get_by_id(map_id).duplicate(true)
	_assert("map_ok", not map.is_empty())

	var prop_id := ""
	var prop_xy := Vector2.ZERO
	for p in map.get("props", []):
		prop_id = str(p.get("id", ""))
		if prop_id.is_empty():
			continue
		prop_xy = Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
		break
	_assert("prop_found", not prop_id.is_empty())

	var tokens: Array = gd.get_map_play_tokens(map_id).duplicate(true)
	_assert("tokens_found", tokens.size() > 0)
	var npc_id := str(tokens[0].get("id", ""))
	var npc_xy := Vector2(float(tokens[0].get("x", 0)), float(tokens[0].get("y", 0)))

	# Persistance décor (chemin workspace)
	var dest := Vector2(prop_xy.x + 2.0, prop_xy.y + 1.0)
	_assert("move_prop_api", gd.move_map_prop(map_id, prop_id, dest.x, dest.y))
	var after: Dictionary = {}
	for p2 in md.get_by_id(map_id).get("props", []):
		if str(p2.get("id", "")) == prop_id:
			after = p2
			break
	_assert("prop_persisted", is_equal_approx(float(after.get("x", -1)), dest.x) \
		and is_equal_approx(float(after.get("y", -1)), dest.y))
	print("prop_moved ", prop_id, " -> ", dest)

	# Persistance PNJ
	_assert("move_npc_api", gd.can_session_move_token(map_id, npc_id, true, ""))
	gd.submit_map_op(map_id, {
		"type": gd.MAP_OP_MOVE_TOKEN,
		"tokenId": npc_id,
		"x": npc_xy.x + 1.0,
		"y": npc_xy.y + 2.0,
	})
	var npc_after: Dictionary = gd.find_map_token(map_id, npc_id)
	_assert("npc_persisted", is_equal_approx(float(npc_after.get("x", -1)), npc_xy.x + 1.0) \
		and is_equal_approx(float(npc_after.get("y", -1)), npc_xy.y + 2.0))
	print("npc_moved ", npc_id, " -> ", npc_after.get("x"), ",", npc_after.get("y"))

	# Recharger la carte après les moves API (le duplicate initial est périmé).
	map = md.get_by_id(map_id).duplicate(true)

	# Simulation drag InteractiveMap (input synthétique)
	var imap = load("res://scripts/interactive_map.gd").new()
	_assert("imap_created", imap != null)
	var host := Control.new()
	host.size = Vector2(800, 600)
	get_root().add_child(host)
	imap.size = Vector2(800, 600)
	host.add_child(imap)
	imap.configure(map, gd.get_map_play_tokens(map_id), [], [], "oneshot", false)
	imap.set_move_policy(true, "")
	imap.set_session_tool("select")
	imap.prop_moved.connect(func(id, gx, gy):
		_prop_sig = id
		_prop_pos = Vector2(gx, gy)
	)
	imap.token_moved.connect(func(id, gx, gy):
		_tok_sig = id
		_tok_pos = Vector2(gx, gy)
	)
	# Force une grille utilisable sans fit asynchrone.
	imap.zoom = 1.0
	imap.pan_offset = Vector2(40, 40)
	imap.set("_base_cell", 32)
	await process_frame

	var from := Vector2i(int(floor(dest.x)), int(floor(dest.y)))
	# Le décor est centré sur dest : la case floor(dest) doit le toucher.
	var hit_prop: Dictionary = imap.call("_prop_at_cell", from.x, from.y)
	if hit_prop.is_empty():
		hit_prop = imap.call("_prop_at_cell", int(round(dest.x)), int(round(dest.y)))
		from = Vector2i(int(round(dest.x)), int(round(dest.y)))
	_assert("prop_pick", not hit_prop.is_empty())
	var to := Vector2i(from.x + 1, from.y + 1)
	_synth_drag(imap, from, to)
	_assert("drag_prop_signal", _prop_sig == prop_id)
	print("drag_prop_signal ", _prop_sig, " @ ", _prop_pos)

	var nfrom := Vector2i(int(round(float(npc_after.get("x", 0)))), int(round(float(npc_after.get("y", 0)))))
	imap.configure(md.get_by_id(map_id).duplicate(true), gd.get_map_play_tokens(map_id), [], [], "oneshot", false)
	imap.set_move_policy(true, "")
	imap.set_session_tool("select")
	imap.pan_offset = Vector2(40, 40)
	imap.set("_base_cell", 32)
	var nto := Vector2i(nfrom.x + 1, nfrom.y)
	_assert("npc_pick", not imap.call("_token_at", nfrom.x, nfrom.y).is_empty())
	_synth_drag(imap, nfrom, nto)
	_assert("drag_npc_signal", _tok_sig == npc_id)
	print("drag_npc_signal ", _tok_sig, " @ ", _tok_pos)

	# Joueur : pas de drag décor
	_prop_sig = ""
	imap.set_move_policy(false, "hero-1")
	_synth_drag(imap, to, Vector2i(to.x + 1, to.y))
	_assert("player_blocked_prop", _prop_sig.is_empty())

	host.queue_free()
	if _failed:
		print("session_drag_move_test:FAIL")
		quit(1)
		return
	print("session_drag_move_test:PASS")
	quit(0)

func _synth_drag(imap: Control, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var cs := float(imap.call("get_cell_size"))
	var pan: Vector2 = imap.pan_offset
	var from_pos := pan + Vector2((float(from_cell.x) + 0.5) * cs, (float(from_cell.y) + 0.5) * cs)
	var to_pos := pan + Vector2((float(to_cell.x) + 0.5) * cs, (float(to_cell.y) + 0.5) * cs)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from_pos
	imap._gui_input(press)

	var motion := InputEventMouseMotion.new()
	motion.position = from_pos + Vector2(20, 12)
	imap._gui_input(motion)

	var motion2 := InputEventMouseMotion.new()
	motion2.position = to_pos
	imap._gui_input(motion2)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to_pos
	imap._gui_input(release)

func _assert(label: String, ok: bool) -> void:
	print(("  OK   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true
