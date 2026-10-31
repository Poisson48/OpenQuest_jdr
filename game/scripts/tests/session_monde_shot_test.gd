extends SceneTree

## Capture de la session « monde 2.5D » (village + groupe en figurines 3D).
## Non headless : nécessite un rendu réel.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var copy_dir := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join("docs/screenshots")
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
		{"id": "hero-aria", "name": "Aria", "class": "Aventurière", "hp": 12, "ac": 14,
			"isPlayer": true, "portrait": "", "image": "", "stats": {}},
		{"id": "hero-bran", "name": "Bran", "class": "Garde", "hp": 15, "ac": 16,
			"isPlayer": true, "portrait": "", "image": "", "stats": {}},
		{"id": "hero-celia", "name": "Célia", "class": "Marchande", "hp": 10, "ac": 12,
			"isPlayer": true, "portrait": "", "image": "", "stats": {}},
	]
	var clean_ids: Array = ids.duplicate()
	var keep_names: Dictionary = {}
	for member_variant in party:
		keep_names[str((member_variant as Dictionary).get("name", ""))] = true
	gd.create_new_game("demo-valbois", "solo", "human", "oneshot", party.duplicate(true), ids.duplicate())
	gd.ensure_map_play_state()
	gd.active_game["currentMapId"] = village_id
	gd.active_game["mapNavigation"] = {
		"view": "local", "worldMapId": null, "localMapId": village_id, "worldCell": null,
	}
	gd.active_game["party"] = (gd.active_game.get("party", []) as Array).filter(
		func(member): return keep_names.has(str((member as Dictionary).get("name", "")))
	)
	gd.active_game["mapIds"] = clean_ids
	gd.save_active_game()
	gd.place_complex_member_token(village_id, 9.0, 7.5, "hero-aria")
	gd.place_complex_member_token(village_id, 8.2, 8.6, "hero-bran")
	gd.place_complex_member_token(village_id, 10.2, 8.2, "hero-celia")
	# PNJ de vie (figurines 3D nommées), comme dans le boot de session.
	var village_entry: Dictionary = gd.get_map_play_entry(village_id)
	(village_entry["tokens"] as Array).append({
		"id": "tok-npc-marchand", "kind": "npc", "label": "Marchand",
		"x": 12.5, "y": 7.2, "hp": 10, "maxHp": 10,
	})
	(village_entry["tokens"] as Array).append({
		"id": "tok-npc-garde", "kind": "npc", "label": "Garde",
		"x": 5.5, "y": 6.0, "hp": 10, "maxHp": 10,
	})
	gd.save_map_play_and_sync()

	var session: Node = (load("res://scenes/session/session.tscn") as PackedScene).instantiate()
	get_root().add_child(session)
	if session is Control:
		(session as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for _i in range(40):
		await process_frame
	# Ferme l'éventuelle carte d'introduction pour capturer la carte elle-même.
	for overlay in session.find_children("*", "SpeakerDialogueOverlay", true, false):
		if overlay.has_method("clear"):
			overlay.clear()
	for _i in range(4):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		printerr("  FAIL capture")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var out := copy_dir.path_join("session_monde_25d.png")
	img.save_png(out)
	print("  capture: ", out, " (", img.get_width(), "x", img.get_height(), ")")
	# Aide de session (touche H).
	var workspaces := session.find_children("*", "MapWorkspacePanel", true, false)
	if not workspaces.is_empty():
		var workspace = workspaces[0]
		if workspace._help_overlay != null:
			workspace._help_overlay.visible = true
			for _i in range(8):
				await process_frame
			var help_img: Image = get_root().get_texture().get_image()
			if help_img != null:
				help_img.convert(Image.FORMAT_RGBA8)
				var help_out := copy_dir.path_join("session_aide.png")
				help_img.save_png(help_out)
				print("  capture: ", help_out)
			workspace._help_overlay.visible = false
		# Outil Pas + curseur de survol sur une case.
		workspace._tool = SessionToolRegistry.make(SessionToolRegistry.MOVE)
		workspace.refresh()
		for _i in range(8):
			await process_frame
		var engine = workspace.stage._complex
		if engine != null:
			engine._update_move_pointer(engine.size * 0.5)
			for _i in range(4):
				await process_frame
			var pas_img: Image = get_root().get_texture().get_image()
			if pas_img != null:
				pas_img.convert(Image.FORMAT_RGBA8)
				var pas_out := copy_dir.path_join("session_pas.png")
				pas_img.save_png(pas_out)
				print("  capture: ", pas_out)
		# Dialogue de PNJ au clic (Marchand).
		var npc_token := ""
		for token_variant in gd.get_map_play_tokens(village_id):
			if str((token_variant as Dictionary).get("label", "")) == "Marchand":
				npc_token = str((token_variant as Dictionary).get("id", ""))
				break
		if not npc_token.is_empty():
			workspace._on_token_selected(npc_token)
			for _i in range(10):
				await process_frame
			var npc_img: Image = get_root().get_texture().get_image()
			if npc_img != null:
				npc_img.convert(Image.FORMAT_RGBA8)
				var npc_out := copy_dir.path_join("session_npc.png")
				npc_img.save_png(npc_out)
				print("  capture: ", npc_out)
	session.queue_free()
	await process_frame
	print("session_monde_shot_test:PASS")
	quit(0)
