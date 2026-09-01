extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var gd = get_root().get_node("GameData")
	gd.clear_active_game()
	var party := [
		{ "id": "p1", "name": "Aria", "race": "Elfe", "class": "Rôdeuse", "hp": 12, "ac": 14, "isPlayer": true, "isBot": false },
		{ "id": "p2", "name": "Sera", "race": "Demi-elfe", "class": "Clerc", "hp": 11, "ac": 15, "isPlayer": false, "isBot": true },
		{ "id": "p3", "name": "Zara", "race": "Tieffelin", "class": "Occultiste", "hp": 10, "ac": 13, "isPlayer": false, "isBot": true },
		{ "id": "p4", "name": "Lyra", "race": "Elfe", "class": "Mage", "hp": 8, "ac": 12, "isPlayer": false, "isBot": true },
	]
	gd.create_new_game("demo-couronne-fracturee", "solo", "ai", "long", party)
	var long_gm := (
		"Bienvenue dans l'aventure [b]La Couronne Fracturée[/b] !\n\n"
		+ "[b]Personnages clés :[/b]\n"
		+ "• [b]Lysa l'apprentie[/b] — froide. Elle connaît des passages secrets.\n"
		+ "• [b]Bram l'apothicaire[/b] — Aldric n'avait pas d'allié plus loyal.\n"
		+ "• [b]Petronille la tavernière[/b] — son alibi est fragile mais plausible.\n"
		+ "• [b]Zephon le garde[/b] — il a vu quelque chose cette nuit-là.\n"
		+ "• [b]Maître Corbin[/b] — le notaire détient des documents compromettants.\n"
	)
	gd.add_log_entry("MJ (IA)", long_gm, "gm")

	change_scene_to_file("res://scenes/session/session.tscn")
	await _wait_scene("Session")

	for _i in range(60):
		await process_frame

	var session = current_scene
	var game_log: RichTextLabel = session.get_node("%GameLog")
	var map_panel: Control = session.get_node("%MapPanel")

	var log_scroll := game_log.get_v_scroll_bar()
	if log_scroll:
		log_scroll.value = log_scroll.max_value

	await process_frame
	await process_frame

	var viewport_w := DisplayServer.window_get_size().x
	var log_w := int(game_log.size.x)
	var map_w := int(map_panel.size.x)
	var log_h := int(game_log.size.y)
	var log_ok := log_w >= int(viewport_w * 0.45)
	var height_ok := log_h >= 180
	var ratio := float(log_w) / float(viewport_w) if viewport_w > 0 else 0.0

	var img: Image = get_root().get_texture().get_image()
	var shot_path := "user://layout_verify.png"
	if img:
		img.save_png(shot_path)

	print("=== LAYOUT VERIFY ===")
	print("viewport_w=", viewport_w, " log_w=", log_w, " log_h=", log_h, " map_w=", map_w, " ratio=", ratio)
	print("log_width_ok=", log_ok, " log_height_ok=", height_ok)
	print("screenshot=", shot_path)
	quit(0 if log_ok and height_ok else 1)

func _wait_scene(root_name: String, max_frames := 120) -> void:
	for _i in range(max_frames):
		await process_frame
		if current_scene and current_scene.name == root_name:
			return
