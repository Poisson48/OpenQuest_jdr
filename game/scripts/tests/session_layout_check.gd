extends SceneTree

## Vérifie la géométrie de la session MJ (bande haute, colonnes, carte).

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var gd = get_root().get_node("GameData")
	var mm = get_root().get_node("MultiplayerManager")
	var party: Array = [
		{"id": "h1", "name": "Aria", "race": "Elfe", "class": "Rôdeuse", "hp": 12, "ac": 14, "isPlayer": true, "isHuman": true, "clientId": "j1"},
		{"id": "h2", "name": "Thorin", "race": "Nain", "class": "Guerrier", "hp": 14, "ac": 16, "isPlayer": true, "isHuman": true, "clientId": "j2"},
		{"id": "b1", "name": "Kael", "race": "Humain", "class": "Rôdeur", "hp": 11, "ac": 13, "isBot": true},
	]
	gd.reload_builtin_scenarios()
	gd.create_new_game("demo-kharak", "multi", "human", "long", party)
	gd.active_game["waitingForGm"] = true
	for i in range(40):
		gd.add_log_entry("Aria", "Ligne de journal numéro %d, assez longue pour remplir le cadre Histoire et forcer le scroll interne." % i, "player")
	mm.player_role = "gm"
	mm.player_name = "MJ"
	mm.is_gm = true

	change_scene_to_file("res://scenes/session/session.tscn")
	for _i in range(60):
		await process_frame

	var s: Node = current_scene
	var root_size: Vector2 = get_root().get_visible_rect().size
	var main: Control = s.get_node("%MainLayout")
	var band: Control = s.get_node("%TopBand")
	var side: Control = s.get_node("%Sidebar")
	var area: Control = s.get_node("%MainGameArea")
	var party_panel: Control = s.get_node("%PartyPanel")
	var gm: Control = s.get_node("%GmPanel")
	var log_p: Control = s.get_node("%LogPanel")
	var dice: Control = s.get_node("%DiceSection")
	var action: Control = s.get_node("%ActionSection")
	var map: Control = s.get_node("%MapPanel")
	var game_log: RichTextLabel = s.get_node("%GameLog")

	print("viewport=", root_size)
	print("main=", main.position, main.size)
	print("band=", band.position, band.size)
	print("  sidebar=", side.position, side.size, " main_area=", area.position, area.size)
	print("  party=", party_panel.size, " gm=", gm.size)
	print("  log=", log_p.size, " dice=", dice.size, " action=", action.size)
	print("map=", map.position, map.size, " min=", map.get_combined_minimum_size())
	# MainLayout est ancré avec 12px de marge haut/bas : si son minimum dépasse la
	# hauteur disponible, la page déborde du viewport.
	var available := root_size.y - 24.0
	print("  main_min=", main.get_combined_minimum_size().y, " available=", available)
	_assert("no_vertical_overflow", main.get_combined_minimum_size().y <= available)

	var gm_clip: Control = s.get_node("%GmPanel/GmBody/GmClip")
	var gm_vbox: Control = s.get_node("%GmPanel/GmBody/GmClip/GmVBox")
	print("  gm_clip=", gm_clip.position, gm_clip.size, " gm_vbox=", gm_vbox.position, gm_vbox.size,
		" grow=", gm_vbox.grow_vertical, " min=", gm_vbox.get_combined_minimum_size())
	_assert("gm_content_from_top", gm_vbox.position.y >= -0.5)
	# Suite/Clore sont en pied de panneau (hors clip) pour rester visibles sans scroll.
	var end_row: Control = s.get_node("%BtnGmCompleteScenario").get_parent()
	var gm_body: Control = s.get_node("%GmPanel/GmBody")
	_assert("gm_essentials_visible",
		end_row.get_parent() == gm_body
		and end_row.position.y + end_row.size.y <= gm_body.size.y + 1.0
		and end_row.size.y > 8.0)

	_assert("columns_same_height", absf(side.size.y - area.size.y) < 1.0)
	_assert("gm_fills_column", gm.size.y > 80.0 and absf(side.size.y - (party_panel.size.y + gm.size.y + 8.0)) < 1.5)
	_assert("map_full_width", absf(map.size.x - main.size.x) < 1.0)
	_assert("map_below_band", map.position.y >= band.position.y + band.size.y)
	# Le moteur de carte simple doit remplir le cadre (pas une pastille en bas à gauche).
	var simple_eng: Control = null
	for child in map.get_children():
		if child is VBoxContainer:
			for sub in child.get_children():
				if sub is Panel or sub.get_class() == "Panel":
					for eng in sub.get_children():
						if eng.visible and eng is Control and eng.size.y > 10:
							simple_eng = eng
							break
	if simple_eng == null:
		# Fallback : chercher InteractiveMap / SimpleMapRenderer parmi les descendants.
		simple_eng = _find_visible_map_engine(map)
	print("  map_engine=", simple_eng.size if simple_eng else Vector2.ZERO)
	_assert("map_engine_fills_frame", simple_eng != null and simple_eng.size.x > 200.0 and simple_eng.size.y > 120.0)
	_assert("fits_viewport", main.position.y + main.size.y <= root_size.y + 1.0)
	_assert("action_visible_for_gm", action.visible)
	_assert("gm_no_scroll", gm.get_node_or_null("GmScroll") == null)
	_assert("log_no_fit_content", not game_log.fit_content)

	# Stabilité : écrire, lancer un dé, rafraîchir ne doit pas bouger les hauteurs.
	var before := [band.size.y, map.size.y, log_p.size.y, gm.size.y]
	s.get_node("%GmInput").text = "Une narration assez longue pour tester la stabilité du panneau MJ.\nAvec un retour ligne."
	s.get_node("%DiceResultLabel").text = "🎲 2d6+3 : 4 + 6 + 3 = 13 (résultat très verbeux)"
	s.call("_roll_dice_formula", "1d20")
	gd.add_log_entry("MJ", "Nouvelle narration ajoutée au journal pendant la partie.", "gm")
	for _i in range(20):
		await process_frame
	var after := [band.size.y, map.size.y, log_p.size.y, gm.size.y]
	print("before=", before, " after=", after)
	_assert("heights_stable", before == after)

	_shot("session_layout_gm")

	# Vue joueur immersive.
	gd.active_game["forcePlayerView"] = true
	s.call("_apply_role_ui")
	for _i in range(20):
		await process_frame
	print("immersive map=", map.size, " band_visible=", band.visible)
	_assert("immersive_band_hidden", not band.visible)
	_assert("immersive_map_tall", map.size.y > root_size.y * 0.8)
	_shot("session_layout_player")

	if _failed:
		print("[SESSION LAYOUT] FAIL")
		quit(1)
	else:
		print("[SESSION LAYOUT] PASS")
		quit(0)

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		return
	var path := ProjectSettings.globalize_path("user://%s.png" % name)
	img.save_png(path)
	print("shot=", path)

func _find_visible_map_engine(node: Node) -> Control:
	for child in node.get_children():
		if child is Control and child.visible:
			var scr = child.get_script()
			if scr != null:
				var path := str(scr.resource_path)
				if path.find("interactive_map") >= 0 or path.find("simple_map") >= 0 or path.find("complex_map_engine") >= 0:
					return child as Control
			var found := _find_visible_map_engine(child)
			if found:
				return found
	return null

func _assert(label: String, ok: bool) -> void:
	print(("  OK   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true
